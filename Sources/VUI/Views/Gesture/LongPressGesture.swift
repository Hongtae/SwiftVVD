//
//  File: LongPressGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// LongPressGesture
//
// _makeGesture -> create SingleLongPressGesture<TappableEvent> -> run body chain
//
public struct LongPressGesture: Gesture {
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

    public typealias Value = Bool
    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<Self>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<Bool> {
        guard let graph = AttributeGraph.current else {
            fatalError("LongPressGesture._makeGesture requires AG context")
        }
        // create SingleLongPressGesture<TappableEvent> -> run body chain
        // maximumDistance will be handled at EventFilter level, currently unimplemented
        let minimumDuration = gesture._attribute.value.minimumDuration
        let singleLongPress = SingleLongPressGesture<TappableEvent>(minimumDuration: minimumDuration)
        let attr: Attribute<SingleLongPressGesture<TappableEvent>> = graph.makeInput(value: singleLongPress)
        return SingleLongPressGesture<TappableEvent>._makeGesture(
            gesture: _GraphValue(_attribute: attr),
            inputs: inputs
        )
    }
}

extension View {
    public func onLongPressGesture(
        minimumDuration: Double = 0.5,
        maximumDistance: CGFloat = 10,
        perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        self.gesture(
            ModifierGesture(
                modifier: CallbacksGesture(
                    callbacks: PressableGestureCallbacks(pressing: onPressingChanged,
                                                         pressed: action)
                ),
                body: LongPressGesture(minimumDuration: minimumDuration,
                                       maximumDistance: maximumDistance)
            )
        )
    }
}
