//
//  File: TouchEvent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol TouchTypeProviding {
    var touchType: TouchType { get }
}

protocol HitTestableEventType: EventType {
    var hitTestLocation: CGPoint { get }
    var hitTestRadius: CGFloat { get }
}

extension HitTestableEventType where Self: SpatialEventType {
    var hitTestLocation: CGPoint {
        location
    }

    var hitTestRadius: CGFloat {
        radius
    }
}

protocol PanEventType: EventType, TouchTypeProviding {
    var translation: CGSize { get }
    var globalTranslation: CGSize { get }
}

protocol NonGestureEventType: EventType {}

enum TouchType: Sendable, Hashable {
    case direct
    case indirect
    case pencil
    case indirectPointer
}

struct TouchEvent: EventType,
                   SpatialEventType,
                   TouchTypeProviding,
                   ModifiersEventType,
                   HitTestableEventType,
                   PanEventType,
                   Equatable {
    var timestamp: Time
    var phase: EventPhase
    var binding: EventBinding?
    var location: CGPoint
    var globalLocation: CGPoint
    var radius: CGFloat
    var force: Double
    var maximumPossibleForce: Double
    var modifiers: EventModifiers
    var altitude: Angle
    var azimuth: Angle
    var touchType: TouchType

    var kind: SpatialEvent.Kind? { .touch }

    var translation: CGSize {
        CGSize(width: location.x, height: location.y)
    }

    var globalTranslation: CGSize {
        CGSize(width: globalLocation.x, height: globalLocation.y)
    }
}
