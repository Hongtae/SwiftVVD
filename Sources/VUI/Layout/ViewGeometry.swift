//
//  File: ViewGeometry.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// The concrete size of a view as resolved by the layout pass.
/// { value: CGSize (16 bytes), proposal: ProposedViewSize (16 bytes) }, total 32 bytes.
/// `width`/`height` are computed accessors into `value`.
/// `proposal` stores the proposal that was used to compute this size, which is needed by the
/// animation system to interpolate between layout frames.
public struct ViewSize: Equatable, Sendable {
    public var value: CGSize
    public var proposal: ProposedViewSize

    public var width:  CGFloat { get { value.width  } set { value.width  = newValue } }
    public var height: CGFloat { get { value.height } set { value.height = newValue } }

    public init(_ value: CGSize, proposal: ProposedViewSize = .unspecified) {
        self.value = value
        self.proposal = proposal
    }
    public init(width: CGFloat, height: CGFloat, proposal: ProposedViewSize = .unspecified) {
        self.value = CGSize(width: width, height: height)
        self.proposal = proposal
    }

    public static let zero = ViewSize(.zero)

    public static func fixed(_ cgSize: CGSize) -> ViewSize {
        ViewSize(cgSize, proposal: ProposedViewSize(cgSize))
    }
}

/// The cumulative coordinate-space transform applied to a view.
/// Backed by `ProjectionTransform` to support both 2D affine and 3D projective
/// transforms (e.g., `.rotation3DEffect`).
public struct ViewTransform: Equatable, Sendable {
    public var matrix: ProjectionTransform

    public init() { matrix = ProjectionTransform() }
    public init(_ transform: ProjectionTransform) { matrix = transform }

    public static let identity = ViewTransform()
}

/// The safe-area insets provided to a view by its nearest ancestor container.
/// Conceptually equivalent to `EdgeInsets` but kept as a distinct type so
/// the AG graph can distinguish safe-area changes from general padding changes.
public struct SafeAreaInsets: Equatable, @unchecked Sendable {
    public var value: EdgeInsets

    public init() { value = EdgeInsets() }
    public init(_ insets: EdgeInsets) { value = insets }

    public static let zero = SafeAreaInsets()
}
