//
//  File: DragGesture.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// DragGesture
//
// _makeGesture -> create SpatialDragGesture -> run body chain
//
public struct DragGesture: Gesture {
    public struct Value: Equatable {
        public var time: Date
        public var location: CGPoint
        public var startLocation: CGPoint

        var _velocity: _Velocity<CGSize>

        public var translation: CGSize {
            CGSize(width: location.x - startLocation.x,
                   height: location.y - startLocation.y)
        }

        public var velocity: CGSize {
            let predicted = predictedEndLocation
            return CGSize(
                width: 4.0 * (predicted.x - location.x),
                height: 4.0 * (predicted.y - location.y))
        }

        public var predictedEndLocation: CGPoint {
            let x = location.x + _velocity.valuePerSecond.width * 0.25
            let y = location.y + _velocity.valuePerSecond.height * 0.25
            return CGPoint(x: x, y: y)
        }

        public var predictedEndTranslation: CGSize {
            let loc = predictedEndLocation
            return CGSize(width: loc.x - startLocation.x,
                          height: loc.y - startLocation.y)
        }
    }

    public var minimumDistance: CGFloat
    public var coordinateSpace: CoordinateSpace

    public init(minimumDistance: CGFloat = 10, coordinateSpace: some CoordinateSpaceProtocol = .local) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace.coordinateSpace
    }

    public typealias Body = Never

    public static func _makeGesture(
        gesture: _GraphValue<DragGesture>,
        inputs: _GestureInputs
    ) -> _GestureOutputs<DragGesture.Value> {
        guard let graph = AttributeGraph.current else {
            fatalError("DragGesture._makeGesture requires AG context")
        }
        // create SpatialDragGesture and run the body chain.
        let self_ = gesture._attribute.value
        let spatial = SpatialDragGesture(
            minimumDistance: self_.minimumDistance,
            coordinateSpace: self_.coordinateSpace
        )
        let attr: Attribute<SpatialDragGesture> = graph.makeInput(value: spatial)
        return SpatialDragGesture._makeGesture(
            gesture: _GraphValue(_attribute: attr),
            inputs: inputs
        )
    }
}

extension DragGesture.Value: Sendable {}
