//
//  File: LongPressGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct LongPressGesture : Gesture {
    public var minimumDuration: Double
    public var maximumDistance: CGFloat {
        get { _maximumDistance }
        set { _maximumDistance = newValue }
    }

    var _maximumDistance: CGFloat
    public init(minimumDuration: Double = 0.5, maximumDistance: CGFloat = 10) {
        self.minimumDuration = minimumDuration
        self._maximumDistance = maximumDistance
    }

    public static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Self.Value> {
        fatalError()
    }
    public typealias Value = Bool
    public typealias Body = Never
}

extension View {
    public func onLongPressGesture(minimumDuration: Double = 0.5,
                                   maximumDistance: CGFloat = 10,
                                   perform action: @escaping () -> Void,
                                   onPressingChanged: ((Bool) -> Void)? = nil) -> some View {
        self.gesture(
            ModifierGesture(
                content: LongPressGesture(minimumDuration: minimumDuration,
                                          maximumDistance: maximumDistance),
                modifier: CallbacksGesture(
                    callbacks: PressableGestureCallbacks(pressing: onPressingChanged,
                                                         pressed: action)
                )
            )
        )
    }
}
