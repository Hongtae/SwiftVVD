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
private let contextMenuRecognizerDebugLog = true

private func logContextMenuRecognizer(_ message: @autoclosure () -> String) {
    if contextMenuRecognizerDebugLog {
        Log.debug("[ContextMenuRecognizer] \(message())")
    }
}

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
        if let pending {
            logContextMenuRecognizer("reset clears pending id=\(pending.id) policy=\(pending.policy) didOpen=\(pending.didOpen)")
        }
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
                logContextMenuRecognizer("buttonDown no responder location=\(event.location) button=\(event.buttonID) device=\(event.device)")
                return
            }
            let policy = responder.resolvedTriggerPolicy(for: event.device)
            logContextMenuRecognizer("buttonDown responder=\(responder.hitTestKey) policy=\(policy) location=\(event.location) button=\(event.buttonID) device=\(event.device)")
            guard canStartContextMenuSession(event, policy: policy) else {
                logContextMenuRecognizer("buttonDown rejected policy=\(policy) button=\(event.buttonID) control=\(isControlPressed)")
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
                logContextMenuRecognizer("pending start id=\(sessionID) policy=\(policy) location=\(event.location)")
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
            logContextMenuRecognizer("fire ignored id=\(sessionID) pending=\(pending?.id.description ?? "nil")")
            return false
        }

        var opened = false
        viewGraph.data.withCurrent {
            guard hitResponder(at: session.currentLocation,
                               rootResponder: rootResponder) === session.responder else {
                logContextMenuRecognizer("fire cancelled id=\(sessionID) hit-test changed location=\(session.currentLocation)")
                pending = nil
                return
            }
            logContextMenuRecognizer("fire open id=\(sessionID) location=\(session.currentLocation)")
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
            if event.type == .pointing {
                logContextMenuRecognizer("pending pointing id=\(session.id) pressure=\(event.pressure) location=\(event.location)")
            }
            if session.policy == .longPress,
               movedBeyondLongPressTolerance(from: session.startLocation,
                                             to: event.location) {
                logContextMenuRecognizer("pending cancel moved id=\(session.id) start=\(session.startLocation) current=\(event.location)")
                pending = nil
                return true
            }
            pending = session
            return true

        case .buttonUp:
            defer { pending = nil }
            logContextMenuRecognizer("pending buttonUp id=\(session.id) didOpen=\(session.didOpen) policy=\(session.policy)")
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
            logContextMenuRecognizer("pending cancel event id=\(session.id) type=\(event.type) button=\(event.buttonID) device=\(event.device)")
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
        // FIXME: Tune context-menu long-press movement tolerance if touch/stylus
        // behavior becomes visually mismatched.
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
