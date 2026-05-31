//
//  File: ContextMenuRecognizer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private let contextMenuLongPressDelay: TimeInterval = 0.5
private let contextMenuLongPressMovementTolerance: CGFloat = 10

struct ContextMenuRecognizer {
    private struct PendingSession {
        var id: UInt64
        var deviceID: Int
        var buttonID: Int
        var startLocation: CGPoint
        var currentLocation: CGPoint
        var responder: ContextMenuResponder
        var policy: ContextMenuTriggerPolicy
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
    mutating func handleMouseEvent(_ event: MouseEvent,
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
                                               rootResponder: rootResponder) else {
                return
            }
            let policy = responder.resolvedTriggerPolicy(for: event.device)
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
                pending = PendingSession(id: sessionID,
                                         deviceID: event.deviceID,
                                         buttonID: event.buttonID,
                                         startLocation: event.location,
                                         currentLocation: event.location,
                                         responder: responder,
                                         policy: policy)
                if policy == .longPress {
                    scheduleLongPress(sessionID, contextMenuLongPressDelay)
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

    private mutating func handlePendingMouseEvent(_ event: MouseEvent,
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
            if session.policy == .longPress,
               movedBeyondLongPressTolerance(from: session.startLocation,
                                             to: event.location) {
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
                                          rootResponder: rootResponder) === session.responder
                if shouldOpen {
                    open(session.responder, event.location)
                }
            }
            return shouldOpen

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

    private func movedBeyondLongPressTolerance(from start: CGPoint, to current: CGPoint) -> Bool {
        // Refine the long-press movement tolerance if touch/stylus behavior
        // becomes visually mismatched.
        let dx = current.x - start.x
        let dy = current.y - start.y
        let squaredDistance = dx * dx + dy * dy
        let tolerance = contextMenuLongPressMovementTolerance
        return squaredDistance > tolerance * tolerance
    }

    private func canStartContextMenuSession(_ event: MouseEvent,
                                            policy: ContextMenuTriggerPolicy) -> Bool {
        switch policy {
        case .automatic:
            fatalError("ContextMenuRecognizer received unresolved automatic policy")

        case .secondaryDown, .secondaryUpInside:
            switch event.device {
            case .genericMouse, .unknown:
                return event.buttonID == 1 || (event.buttonID == 0 && isControlPressed)
            case .touch, .stylus:
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
                              rootResponder: MultiViewResponder) -> ContextMenuResponder? {
        let hits = rootResponder.respondersContaining(point: location)
        let contextHits = hits.compactMap { $0 as? ContextMenuResponder }
        return contextHits.first
    }
}
