//
//  File: RBDisplayListStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// The execution adapter supplies the existing backend filter from a recorded
// filter value. It does not own an encoder, texture or persistent resource cache.
protocol RecordedFilter {
    var executionFilter: GraphicsContext.Filter { get }
    var supportsColorOperations: Bool { get }
    func bounds(_ bounds: CGRect) -> CGRect
}

enum RBFilter {
    struct GaussianBlur: RecordedFilter {
        let radius: Float
        let options: GraphicsContext.BlurOptions

        var executionFilter: GraphicsContext.Filter {
            .blur(radius: CGFloat(radius), options: options)
        }
        var supportsColorOperations: Bool { radius.isFinite && radius >= 0 && options.isEmpty }

        func bounds(_ bounds: CGRect) -> CGRect {
            RBDisplayList.Style.outset(bounds, by: max(0, (radius * 2.8).rounded(.up)))
        }
    }
}

extension RBDisplayList {
    class Style {
        // A published chain is immutable. Selection mutates only fresh copies
        // before linking and publishing them through its operation owner.
        var next: Style?
        fileprivate(set) var transform: CGAffineTransform
        let hasClip: Bool
        let filterOptions: GraphicsContext.FilterOptions

        init(transform: CGAffineTransform, hasClip: Bool, filterOptions: GraphicsContext.FilterOptions) {
            self.transform = transform
            self.hasClip = hasClip
            self.filterOptions = filterOptions
        }

        var executionFilter: GraphicsContext.Filter { preconditionFailure("Abstract recorded style") }
        var supportsColorOperations: Bool { transform.isIdentity && !hasClip && filterOptions.isEmpty }
        func matches(_ predicate: RBDisplayListPredicate) -> UInt16 { 0 }
        func applyPredicate(styleOnly: Bool) {}
        func copy() -> Style { preconditionFailure("Abstract recorded style") }
        func applyBounds(_ bounds: CGRect) -> CGRect { bounds }

        func bounds(_ bounds: CGRect) -> CGRect {
            // Unsupported execution adapters retain their previous geometry
            // bounds; color operations reject those adapters before copying.
            let bounds = supportsColorOperations ? applyBounds(bounds) : bounds
            return next?.bounds(bounds) ?? bounds
        }

        var executionFilters: [(GraphicsContext.Filter, GraphicsContext.FilterOptions)] {
            var result: [(GraphicsContext.Filter, GraphicsContext.FilterOptions)] = []
            var style: Style? = self
            while let current = style {
                result.append((current.executionFilter, current.filterOptions))
                style = current.next
            }
            return result.reversed()
        }

        static func outset(_ bounds: CGRect, by amount: Float, offset: CGPoint = .zero) -> CGRect {
            guard !bounds.isNull, !bounds.isEmpty, !bounds.isInfinite else { return bounds }
            return CGRect(x: CGFloat(Float(bounds.minX) - amount + Float(offset.x)),
                          y: CGFloat(Float(bounds.minY) - amount + Float(offset.y)),
                          width: CGFloat(Float(bounds.width) + 2 * amount),
                          height: CGFloat(Float(bounds.height) + 2 * amount))
        }
    }

    final class ShadowStyle: Style {
        let color: RecordedColor
        let radius: Float
        let offset: CGPoint
        let blendMode: GraphicsContext.BlendMode
        var options: GraphicsContext.ShadowOptions

        init(color: RecordedColor, radius: Float, offset: CGPoint,
             blendMode: GraphicsContext.BlendMode, options: GraphicsContext.ShadowOptions,
             transform: CGAffineTransform, hasClip: Bool, filterOptions: GraphicsContext.FilterOptions) {
            self.color = color
            self.radius = radius
            self.offset = offset
            self.blendMode = blendMode
            self.options = options
            super.init(transform: transform, hasClip: hasClip, filterOptions: filterOptions)
        }

        override var executionFilter: GraphicsContext.Filter {
            .shadow(color: Color(color.resolved), radius: CGFloat(radius), x: offset.x, y: offset.y,
                    blendMode: blendMode, options: options)
        }
        override var supportsColorOperations: Bool {
            super.supportsColorOperations && radius.isFinite && radius >= 0 &&
                offset.x.isFinite && offset.y.isFinite && blendMode == .normal &&
                [UInt32(0), 1, 2, 3, 8, 10].contains(options.rawValue)
        }
        override func matches(_ predicate: RBDisplayListPredicate) -> UInt16 {
            0x100 | (predicate.matches(color) ? 1 : 0)
        }
        override func applyPredicate(styleOnly: Bool) {
            if styleOnly { options.insert(.shadowOnly) }
        }
        override func copy() -> Style {
            ShadowStyle(color: color, radius: radius, offset: offset, blendMode: blendMode,
                        options: options, transform: transform, hasClip: hasClip, filterOptions: filterOptions)
        }
        override func applyBounds(_ bounds: CGRect) -> CGRect {
            let shadow = Self.outset(bounds, by: max(0, radius * 2.8), offset: offset)
            return options.contains(.shadowOnly) ? shadow : bounds.union(shadow)
        }
    }

    final class FilterStyle<Filter: RecordedFilter>: Style {
        let filter: Filter

        init(filter: Filter, transform: CGAffineTransform, hasClip: Bool,
             filterOptions: GraphicsContext.FilterOptions) {
            self.filter = filter
            super.init(transform: transform, hasClip: hasClip, filterOptions: filterOptions)
        }
        override var executionFilter: GraphicsContext.Filter { filter.executionFilter }
        override var supportsColorOperations: Bool { super.supportsColorOperations && filter.supportsColorOperations }
        override func applyBounds(_ bounds: CGRect) -> CGRect { filter.bounds(bounds) }
        override func copy() -> Style {
            FilterStyle(filter: filter, transform: transform, hasClip: hasClip, filterOptions: filterOptions)
        }
    }

    // Retains existing replay for filter kinds whose recorded semantics are
    // still unavailable. Predicate and color replacement explicitly reject it.
    final class ExecutionFilterStyle: Style {
        let filter: GraphicsContext.Filter

        init(filter: GraphicsContext.Filter, transform: CGAffineTransform, hasClip: Bool,
             filterOptions: GraphicsContext.FilterOptions) {
            self.filter = filter
            super.init(transform: transform, hasClip: hasClip, filterOptions: filterOptions)
        }
        override var executionFilter: GraphicsContext.Filter { filter }
        override var supportsColorOperations: Bool { false }
        override func copy() -> Style {
            ExecutionFilterStyle(filter: filter, transform: transform, hasClip: hasClip, filterOptions: filterOptions)
        }
    }

    final class CachedTransform {
        private struct Key: Hashable {
            let source: ObjectIdentifier
            let clipOrStyleOnly: Bool
        }
        private struct CopiedStyle { let style: Style? }
        private var styles: [Key: CopiedStyle] = [:]
        let predicate: RBDisplayListPredicate?
        private let transform: CGAffineTransform
        private let outerStyle: Style?

        init(predicate: RBDisplayListPredicate? = nil, transform: CGAffineTransform = .identity,
             outerStyle: Style? = nil) {
            self.predicate = predicate
            self.transform = transform
            self.outerStyle = outerStyle
        }

        func transformStyle(_ source: Style?, clip: Bool = true, styleOnly: Bool = false) -> Style? {
            guard let source else { return outerStyle }
            // The two flags share one key bit. A chain first copied for a body
            // match can therefore be reused by a later style-only match.
            let key = Key(source: ObjectIdentifier(source), clipOrStyleOnly: clip || styleOnly)
            if let copy = styles[key] { return copy.style }
            var retained: [Style] = []
            var current: Style? = source
            while let style = current {
                if let predicate {
                    let match = style.matches(predicate)
                    if match & 0x100 != 0 && (match & 1 != 0) == predicate.invertsResult {
                        current = style.next
                        continue
                    }
                }
                retained.append(style)
                current = style.next
            }
            var head: Style?
            for style in retained.reversed() {
                let copy = style.copy()
                if predicate != nil { copy.applyPredicate(styleOnly: styleOnly) }
                // Effects keep the coordinates captured when they were added;
                // replay moves those coordinates with the receiving context.
                copy.transform = style.transform.concatenating(transform)
                copy.next = head
                head = copy
            }
            var outer: [Style] = []
            current = outerStyle
            while let style = current {
                outer.append(style)
                current = style.next
            }
            for style in outer.reversed() {
                let copy = style.copy()
                copy.next = head
                head = copy
            }
            styles[key] = CopiedStyle(style: head)
            return head
        }
    }
}
