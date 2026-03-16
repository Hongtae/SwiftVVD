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
struct ViewSize: Equatable, Sendable {
    var value: CGSize
    var proposal: ProposedViewSize

    var width:  CGFloat { get { value.width  } set { value.width  = newValue } }
    var height: CGFloat { get { value.height } set { value.height = newValue } }

    init(_ value: CGSize, proposal: ProposedViewSize = .unspecified) {
        self.value = value
        self.proposal = proposal
    }
    init(width: CGFloat, height: CGFloat, proposal: ProposedViewSize = .unspecified) {
        self.value = CGSize(width: width, height: height)
        self.proposal = proposal
    }

    static let zero = ViewSize(.zero)

    static func fixed(_ cgSize: CGSize) -> ViewSize {
        ViewSize(cgSize, proposal: ProposedViewSize(cgSize))
    }
}

/// The cumulative coordinate-space transform applied to a view.
/// Backed by `ProjectionTransform` to support both 2D affine and 3D projective
/// transforms (e.g., `.rotation3DEffect`).
struct ViewTransform: Equatable, Sendable {
    var matrix: ProjectionTransform

    init() { matrix = ProjectionTransform() }
    init(_ transform: ProjectionTransform) { matrix = transform }

    static let identity = ViewTransform()
}

/// The safe-area insets provided to a view by its nearest ancestor container.
/// Conceptually equivalent to `EdgeInsets` but kept as a distinct type so
/// the AG graph can distinguish safe-area changes from general padding changes.
struct SafeAreaInsets: Equatable, Sendable {
    var value: EdgeInsets

    init() { value = EdgeInsets() }
    init(_ insets: EdgeInsets) { value = insets }

    static let zero = SafeAreaInsets()
}
