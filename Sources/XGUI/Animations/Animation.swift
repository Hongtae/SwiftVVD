//
//  File: Animation.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
class AnimationBoxBase {
}

public struct Animation: Equatable {
    var box: AnimationBoxBase

    public static func == (lhs: Animation, rhs: Animation) -> Bool {
        false
    }
}

extension Animation : CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
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
