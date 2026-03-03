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

