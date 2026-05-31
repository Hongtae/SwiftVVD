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

protocol HitTestableEventType: SpatialEventType {
    var hitTestLocation: CGPoint { get }
    var hitTestRadius: CGFloat { get }
}

extension HitTestableEventType {
    var hitTestLocation: CGPoint {
        location ?? globalLocation
    }

    var hitTestRadius: CGFloat {
        radius
    }
}

protocol PanEventType: SpatialEventType {
    var translation: CGSize { get set }
    var globalTranslation: CGSize { get set }
}

enum TouchType: UInt8, Sendable, Hashable {
    case direct = 0
    case indirect = 1
}

struct TouchEvent: EventType,
                   SpatialEventType,
                   TouchTypeProviding,
                   ModifiersEventType,
                   HitTestableEventType,
                   PanEventType,
                   Equatable {
    var location: CGPoint?
    var globalLocation: CGPoint
    var radius: CGFloat
    var eventPhase: EventPhase
    var modifiers: EventModifiers
    var touchType: TouchType
    var translation: CGSize
    var globalTranslation: CGSize
    var force: CGFloat
    var maximumPossibleForce: CGFloat
    var timestamp: Double
    var kind: SpatialEvent.Kind? { .touch }

    init(
        location: CGPoint?,
        globalLocation: CGPoint? = nil,
        phase: EventPhase,
        timestamp: Double = 0.0,
        touchType: TouchType = .direct,
        modifiers: EventModifiers = [],
        radius: CGFloat = 0.0,
        translation: CGSize = .zero,
        globalTranslation: CGSize = .zero,
        force: CGFloat = 0.0,
        maximumPossibleForce: CGFloat = 1.0
    ) {
        self.location = location
        self.globalLocation = globalLocation ?? location ?? .zero
        self.eventPhase = phase
        self.timestamp = timestamp
        self.touchType = touchType
        self.modifiers = modifiers
        self.radius = radius
        self.translation = translation
        self.globalTranslation = globalTranslation
        self.force = force
        self.maximumPossibleForce = maximumPossibleForce
    }
}
