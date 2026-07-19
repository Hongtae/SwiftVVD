//
//  File: ProposedViewSize.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ProposedViewSize: Equatable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    // The zero proposal - the view responds with its minimum size.
    public static let zero = ProposedViewSize(width: 0, height: 0)
    // The unspecified proposal - the view responds with its ideal size.
    public static let unspecified = ProposedViewSize(width: nil, height: nil)
    // The infinity proposal - the view responds with its maximum size.
    public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)

    @inlinable public init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }

    @inlinable public init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    init(_ size: _ProposedSize) {
        self.width = size.width
        self.height = size.height
    }

    @inlinable public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: self.width ?? size.width, height: self.height ?? size.height)
    }
}

public struct _ProposedSize: Hashable, Sendable {
    var width: CGFloat?
    var height: CGFloat?

    static var zero: _ProposedSize {
        _ProposedSize(width: 0, height: 0)
    }

    static var unspecified: _ProposedSize {
        _ProposedSize()
    }

    static var infinity: _ProposedSize {
        _ProposedSize(width: .infinity, height: .infinity)
    }

    init(width: CGFloat? = nil, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }

    init(_ size: CGSize) {
        self.width = size.width
        self.height = size.height
    }

    init(_ size: ProposedViewSize) {
        self.width = size.width
        self.height = size.height
    }

    init(_ length: CGFloat?, in axis: Axis, by breadth: CGFloat?) {
        switch axis {
        case .horizontal:
            self.init(width: length, height: breadth)
        case .vertical:
            self.init(width: breadth, height: length)
        }
    }

    func fixingUnspecifiedDimensions(
        at size: CGSize = CGSize(width: 10, height: 10)
    ) -> CGSize {
        CGSize(width: width ?? size.width, height: height ?? size.height)
    }

    func scaled(by scale: CGFloat) -> _ProposedSize {
        _ProposedSize(
            width: width.map { $0 * scale },
            height: height.map { $0 * scale }
        )
    }

    func inset(by insets: EdgeInsets) -> _ProposedSize {
        _ProposedSize(
            width: width.map { max(0, $0 - insets.leading - insets.trailing) },
            height: height.map { max(0, $0 - insets.top - insets.bottom) }
        )
    }

    subscript(axis: Axis) -> CGFloat? {
        get {
            switch axis {
            case .horizontal: width
            case .vertical: height
            }
        }
        set {
            switch axis {
            case .horizontal: width = newValue
            case .vertical: height = newValue
            }
        }
    }
}

extension CGSize {
    init?(_ proposal: _ProposedSize) {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }
        self.init(width: width, height: height)
    }
}
