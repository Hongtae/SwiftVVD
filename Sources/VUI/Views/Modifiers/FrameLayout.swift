//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FrameLayout: ViewModifier, Animatable, Sendable {
    let width: CGFloat?
    let height: CGFloat?
    let alignment: Alignment

    @usableFromInline
    init(width: CGFloat?, height: CGFloat?, alignment: Alignment) {
        self.width = width
        self.height = height
        self.alignment = alignment
    }

    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

extension View {
    @inlinable nonisolated
    public func frame(width: CGFloat? = nil,
                      height: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        return modifier(
            _FrameLayout(width: width, height: height, alignment: alignment))
    }
}

public struct _FlexFrameLayout: ViewModifier, Animatable, Sendable {
    let minWidth: CGFloat?
    let idealWidth: CGFloat?
    let maxWidth: CGFloat?
    let minHeight: CGFloat?
    let idealHeight: CGFloat?
    let maxHeight: CGFloat?
    let alignment: Alignment

    @usableFromInline
    init(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil,
         maxWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
         idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, 
         alignment: Alignment) {
        self.minWidth = minWidth
        self.idealWidth = idealWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.idealHeight = idealHeight
        self.maxHeight = maxHeight
        self.alignment = alignment
    }
  
    public typealias AnimatableData = EmptyAnimatableData
    public typealias Body = Never
}

@usableFromInline
func log_error(_ message: String) {
    Log.error(message)
}

extension View {
    @inlinable nonisolated
    public func frame(minWidth: CGFloat? = nil,
                      idealWidth: CGFloat? = nil,
                      maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, 
                      idealHeight: CGFloat? = nil,
                      maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        func areInNondecreasingOrder(
            _ min: CGFloat?, _ ideal: CGFloat?, _ max: CGFloat?
        ) -> Bool {
            let min = min ?? -.infinity
            let ideal = ideal ?? min
            let max = max ?? ideal
            return min <= ideal && ideal <= max
        }

        if !areInNondecreasingOrder(minWidth, idealWidth, maxWidth)
            || !areInNondecreasingOrder(minHeight, idealHeight, maxHeight)
        {
            log_error("Contradictory frame constraints specified.")
        }

        return modifier(
            _FlexFrameLayout(
                minWidth: minWidth,
                idealWidth: idealWidth, maxWidth: maxWidth,
                minHeight: minHeight,
                idealHeight: idealHeight, maxHeight: maxHeight,
                alignment: alignment))
    }
}

extension _FrameLayout: _ViewLayoutModifier {
    private class LayoutViewContext: ViewModifierContext<_FrameLayout> {
        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            guard let modifier else { fatalError("Invalid view modifier") }

            var size = self.body.sizeThatFits(proposal)
            if let w = modifier.width { size.width = w }
            if let h = modifier.height { size.height = h }
            return size
        }

        override func layoutSubviews() {
            guard let modifier else { fatalError("Invalid view modifier") }

            let frame = self.bounds

            var anchor: UnitPoint
            switch modifier.alignment {
            case .leading:          anchor = .leading
            case .trailing:         anchor = .trailing
            case .top:              anchor = .top
            case .bottom:           anchor = .bottom
            case .topLeading:       anchor = .topLeading
            case .topTrailing:      anchor = .topTrailing
            case .bottomLeading:    anchor = .bottomLeading
            case .bottomTrailing:   anchor = .bottomTrailing
            default:                anchor = .center
            }

            let position = CGPoint(
                x: frame.minX + frame.width * anchor.x,
                y: frame.minY + frame.height * anchor.y)
            let proposal = ProposedViewSize(width: frame.width, height: frame.height)
            self.body.place(at: position, anchor: anchor, proposal: proposal)
        }
    }

    static func _makeLayoutView(modifier: _GraphValue<Self>, inputs: _ViewInputs, content: any ViewGenerator) -> any ViewGenerator {
        UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
            let body = content.makeView()
            return LayoutViewContext(graph: graph, body: body, inputs: inputs)
        }
    }
}

extension _FlexFrameLayout: _ViewLayoutModifier {
    private class LayoutViewContext: ViewModifierContext<_FlexFrameLayout> {
        override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            guard let modifier else { fatalError("Invalid view modifier") }

            // Clamp proposed size to [min, max] and offer to child.
            // When proposed is nil (unspecified), use idealWidth/idealHeight.
            let childProposedWidth: CGFloat? = {
                guard let w = proposal.width else { return modifier.idealWidth }
                let minW = modifier.minWidth ?? 0
                let maxW = modifier.maxWidth ?? w
                return max(minW, min(maxW, w))
            }()
            let childProposedHeight: CGFloat? = {
                guard let h = proposal.height else { return modifier.idealHeight }
                let minH = modifier.minHeight ?? 0
                let maxH = modifier.maxHeight ?? h
                return max(minH, min(maxH, h))
            }()

            let childSize = self.body.sizeThatFits(
                ProposedViewSize(width: childProposedWidth, height: childProposedHeight))

            // Reported size: clamp child result to [min, max].
            // When maxWidth == .infinity, expand to fill the proposed space.
            let reportedWidth: CGFloat = {
                let minW = modifier.minWidth ?? 0
                if let maxW = modifier.maxWidth, maxW == .infinity {
                    return max(minW, proposal.width ?? childSize.width)
                }
                return max(minW, min(modifier.maxWidth ?? .infinity, childSize.width))
            }()
            let reportedHeight: CGFloat = {
                let minH = modifier.minHeight ?? 0
                if let maxH = modifier.maxHeight, maxH == .infinity {
                    return max(minH, proposal.height ?? childSize.height)
                }
                return max(minH, min(modifier.maxHeight ?? .infinity, childSize.height))
            }()

            return CGSize(width: reportedWidth, height: reportedHeight)
        }

        override func layoutSubviews() {
            guard let modifier else { fatalError("Invalid view modifier") }

            let frame = self.bounds

            var anchor: UnitPoint
            switch modifier.alignment {
            case .leading:          anchor = .leading
            case .trailing:         anchor = .trailing
            case .top:              anchor = .top
            case .bottom:           anchor = .bottom
            case .topLeading:       anchor = .topLeading
            case .topTrailing:      anchor = .topTrailing
            case .bottomLeading:    anchor = .bottomLeading
            case .bottomTrailing:   anchor = .bottomTrailing
            default:                anchor = .center
            }

            let position = CGPoint(
                x: frame.minX + frame.width * anchor.x,
                y: frame.minY + frame.height * anchor.y)
            let proposal = ProposedViewSize(width: frame.width, height: frame.height)
            self.body.place(at: position, anchor: anchor, proposal: proposal)
        }
    }

    static func _makeLayoutView(modifier: _GraphValue<Self>, inputs: _ViewInputs, content: any ViewGenerator) -> any ViewGenerator {
        UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
            let body = content.makeView()
            return LayoutViewContext(graph: graph, body: body, inputs: inputs)
        }
    }
}
