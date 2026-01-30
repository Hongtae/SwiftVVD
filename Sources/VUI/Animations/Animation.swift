//
//  File: Animation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
class AnimationBoxBase: @unchecked Sendable {
}


public struct Animation: Equatable, Sendable {
    var box: AnimationBoxBase

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        lhs.box === rhs.box
    }
}

extension Animation: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "Animation"
    }
    public var debugDescription: String {
        "Animatino"
    }
    public var customMirror: Mirror {
        fatalError()
    }
}

extension Animation {
    public static let `default`: Animation = .init(box: AnimationBoxBase())
}

extension Transaction {
    public init(animation: Animation?) {
        fatalError()
    }

    public var animation: Animation? {
        get { fatalError() }
        set { fatalError() }
    }
    public var disablesAnimations: Bool {
        get { fatalError() }
        set { fatalError() }
    }
}
