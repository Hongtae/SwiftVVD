//
//  File: ContextMenuRecognizer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private struct ContextMenuLongPressConfiguration {
    var minimumDuration: TimeInterval
    var allowableMovement: CGFloat
}

private func contextMenuLongPressConfiguration(
    for device: MouseEventDevice
) -> ContextMenuLongPressConfiguration {
    switch device {
    case .touch, .stylus:
        ContextMenuLongPressConfiguration(
            minimumDuration: 0.15,
            allowableMovement: 10
        )
    case .genericMouse, .unknown:
        ContextMenuLongPressConfiguration(
            minimumDuration: 0.15,
            allowableMovement: 3
        )
    }
}

struct ContextMenuRecognizer {
    private struct PendingSession {
        var id: UInt64
        var deviceID: Int
        var buttonID: Int
        var startLocation: CGPoint
        var currentLocation: CGPoint
        var currentTimestamp: Time
        var responder: ContextMenuResponder
        var policy: ContextMenuTriggerPolicy
        var allowableMovement: CGFloat
        var didOpen: Bool = false
    }

    private var pending: PendingSession?
    private var nextSessionID: UInt64 = 1
    private var modifierKeys: [VirtualKey] = []

    mutating func reset() {
        pending = nil
    }

    mutating func handleKeyboardEvent(_ event: KeyboardEvent) {
        switch event.type {
        case .keyDown:
            if isContextMenuModifier(event.key),
               !modifierKeys.contains(event.key) {
                modifierKeys.append(event.key)
            }
        case .keyUp:
            if isContextMenuModifier(event.key) {
                modifierKeys.removeAll { $0 == event.key }
            }
        default:
            break
        }
    }

    @discardableResult
    mutating func handleMouseEvent(_ event: PlatformMouseEvent,
                                   viewGraph: ViewGraph,
                                   rootResponder: MultiViewResponder,
                                   scheduleLongPress: (UInt64, TimeInterval) -> Void,
                                   open: (ContextMenuResponder, CGPoint) -> Void) -> Bool {
        guard event.type != .wheel else { return false }

        if pending != nil {
            return handlePendingMouseEvent(event,
                                           viewGraph: viewGraph,
                                           rootResponder: rootResponder,
                                           open: open)
        }

        guard event.type == .buttonDown else {
            return false
        }

        var consumed = false
        viewGraph.data.withCurrent {
            guard let responder = hitResponder(at: event.location,
                                               timestamp: Time(seconds: event.timestamp),
                                               rootResponder: rootResponder) else {
                return
            }
            let policy = responder.resolvedTriggerPolicy(
                for: event.device,
                buttonID: event.buttonID
            )
            guard canStartContextMenuSession(event, policy: policy) else {
                return
            }
            switch policy {
            case .automatic:
                fatalError("ContextMenuRecognizer received unresolved automatic policy")

            case .secondaryDown:
                open(responder, event.location)
                consumed = true

            case .secondaryUpInside, .longPress:
                let sessionID = makeSessionID()
                let longPressConfiguration = contextMenuLongPressConfiguration(
                    for: event.device
                )
                pending = PendingSession(id: sessionID,
                                         deviceID: event.deviceID,
                                         buttonID: event.buttonID,
                                         startLocation: event.location,
                                         currentLocation: event.location,
                                         currentTimestamp: Time(seconds: event.timestamp),
                                         responder: responder,
                                         policy: policy,
                                         allowableMovement: longPressConfiguration.allowableMovement)
                if policy == .longPress {
                    scheduleLongPress(
                        sessionID,
                        longPressConfiguration.minimumDuration
                    )
                }
                consumed = true
            }
        }
        return consumed
    }

    @discardableResult
    mutating func fireLongPress(sessionID: UInt64,
                                viewGraph: ViewGraph,
                                rootResponder: MultiViewResponder,
                                open: (ContextMenuResponder, CGPoint) -> Void) -> Bool {
        guard var session = pending,
              session.id == sessionID,
              session.policy == .longPress,
              !session.didOpen else {
            return false
        }

        var opened = false
        viewGraph.data.withCurrent {
            guard hitResponder(at: session.currentLocation,
                               timestamp: session.currentTimestamp,
                               rootResponder: rootResponder) === session.responder else {
                pending = nil
                return
            }
            open(session.responder, session.currentLocation)
            session.didOpen = true
            pending = session
            opened = true
        }
        return opened
    }

    private mutating func handlePendingMouseEvent(_ event: PlatformMouseEvent,
                                                  viewGraph: ViewGraph,
                                                  rootResponder: MultiViewResponder,
                                                  open: (ContextMenuResponder, CGPoint) -> Void) -> Bool {
        guard var session = pending else { return false }
        guard event.deviceID == session.deviceID,
              event.buttonID == session.buttonID else {
            return true
        }

        switch event.type {
        case .move, .pointing:
            session.currentLocation = event.location
            session.currentTimestamp = Time(seconds: event.timestamp)
            if session.policy == .longPress,
               movedBeyondLongPressTolerance(from: session.startLocation,
                                             to: event.location,
                                             allowableMovement: session.allowableMovement) {
                pending = nil
                return true
            }
            pending = session
            return true

        case .buttonUp:
            defer { pending = nil }
            guard !session.didOpen else { return true }
            guard session.policy == .secondaryUpInside else {
                return true
            }

            var shouldOpen = false
            viewGraph.data.withCurrent {
                shouldOpen = hitResponder(at: event.location,
                                          timestamp: Time(seconds: event.timestamp),
                                          rootResponder: rootResponder) === session.responder
                if shouldOpen {
                    open(session.responder, event.location)
                }
            }
            return shouldOpen

        case .cancelled:
            pending = nil
            return true

        default:
            pending = nil
            return false
        }
    }

    private mutating func makeSessionID() -> UInt64 {
        let id = nextSessionID
        nextSessionID &+= 1
        return id
    }

    private func movedBeyondLongPressTolerance(
        from start: CGPoint,
        to current: CGPoint,
        allowableMovement: CGFloat
    ) -> Bool {
        let dx = current.x - start.x
        let dy = current.y - start.y
        let squaredDistance = dx * dx + dy * dy
        return squaredDistance > allowableMovement * allowableMovement
    }

    private func canStartContextMenuSession(_ event: PlatformMouseEvent,
                                            policy: ContextMenuTriggerPolicy) -> Bool {
        switch policy {
        case .automatic:
            fatalError("ContextMenuRecognizer received unresolved automatic policy")

        case .secondaryDown, .secondaryUpInside:
            switch event.device {
            case .genericMouse, .unknown:
                return event.buttonID == 1 || (event.buttonID == 0 && isControlPressed)
            case .stylus:
                return event.buttonID == 0 || event.buttonID == 1
            case .touch:
                return event.buttonID == 0
            }

        case .longPress:
            switch event.device {
            case .genericMouse, .unknown:
                return event.buttonID == 0 || event.buttonID == 1
            case .touch, .stylus:
                return event.buttonID == 0
            }
        }
    }

    private var isControlPressed: Bool {
        modifierKeys.contains(.leftControl) || modifierKeys.contains(.rightControl)
    }

    private func isContextMenuModifier(_ key: VirtualKey) -> Bool {
        key == .leftControl || key == .rightControl
    }

    private func hitResponder(at location: CGPoint,
                              timestamp: Time,
                              rootResponder: MultiViewResponder) -> ContextMenuResponder? {
        let event = ContextMenuEvent(
            timestamp: timestamp,
            binding: nil,
            location: .zero,
            globalLocation: location
        )
        return rootResponder
            .bindEvent(event)?
            .firstAncestor(ofType: ContextMenuResponder.self)
    }
}
