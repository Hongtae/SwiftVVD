//
//  File: DragGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct DragGesture : Gesture {
    public struct Value : Equatable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize {
            fatalError()
        }

        public var velocity: CGSize {
            get {
                let predicted = predictedEndLocation
                return CGSize(
                    width: 4.0 * (predicted.x - location.x),
                    height: 4.0 * (predicted.y - location.y))
            }
        }
        public var predictedEndLocation: CGPoint {
            fatalError()
        }
        public var predictedEndTranslation: CGSize {
            fatalError()
        }
    }
    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
    }
    public static func _makeGesture(gesture: _GraphValue<DragGesture>, inputs: _GestureInputs) -> _GestureOutputs<DragGesture.Value> {
        fatalError()
    }
    public typealias Body = Never
}
