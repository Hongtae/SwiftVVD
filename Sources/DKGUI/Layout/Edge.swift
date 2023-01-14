//
//  File: Edge.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public enum Edge : Int8, CaseIterable, Equatable, Hashable, RawRepresentable {
    case top
    case leading
    case bottom
    case trailing
}

extension Edge {
    public struct Set: OptionSet {
        public let rawValue: Int8
        public init(rawValue: Int8) {self.rawValue = rawValue }

        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)

        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]

        public init(_ e: Edge) {
            switch e {
            case .top:      self = .top
            case .leading:  self = .leading
            case .bottom:   self = .bottom
            case .trailing: self = .trailing
            }
        }
    }
}

public struct EdgeInsets : Equatable, Sendable, Animatable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public init() {
        self.top = 0
        self.leading = 0
        self.bottom = 0
        self.trailing = 0
    }

    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    public var animatableData: AnimatableData {
        get { .init(top, .init(leading, .init(bottom, trailing))) }
        set {
            top = newValue.first
            leading = newValue.second.first
            bottom = newValue.second.second.first
            trailing = newValue.second.second.second
        }
    }
}
