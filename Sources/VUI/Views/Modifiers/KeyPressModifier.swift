//
//  File: KeyPressModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

public struct KeyPress: Sendable {
    public struct Phases: OptionSet, Sendable, CustomDebugStringConvertible {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let down = Phases(rawValue: 1 << 0)
        public static let `repeat` = Phases(rawValue: 1 << 1)
        public static let up = Phases(rawValue: 1 << 2)
        public static let all: Phases = [.down, .repeat, .up]

        public var debugDescription: String {
            if self == .down { return ".down" }
            if self == .repeat { return ".repeat" }
            if self == .up { return ".up" }
            if self == .all { return ".all" }

            var parts: [String] = []
            if contains(.down) { parts.append(".down") }
            if contains(.repeat) { parts.append(".repeat") }
            if contains(.up) { parts.append(".up") }
            if parts.isEmpty {
                return "[]"
            }
            return "[\(parts.joined(separator: ", "))]"
        }
    }

    public enum Result: Sendable, Hashable {
        case handled
        case ignored
    }

    public var key: KeyEquivalent
    public var characters: String
    public var modifiers: EventModifiers
    public var phase: Phases

    public init(
        key: KeyEquivalent,
        characters: String,
        modifiers: EventModifiers = [],
        phase: Phases
    ) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
        self.phase = phase
    }

    init?(_ event: KeyEvent) {
        guard let phase = Phases(event.phase) else { return nil }
        let key = (event.keyID.base as? KeyEquivalent)
            ?? event.keys.first.map { KeyEquivalent($0) }
        guard let key else { return nil }
        self.init(
            key: key,
            characters: event.stringValue,
            modifiers: event.modifiers,
            phase: phase
        )
    }
}

extension KeyPress: CustomDebugStringConvertible {
    public var debugDescription: String {
        "KeyPress(phase: \(phase.debugDescription), key: \(key), characters: \(characters), modifiers: \(modifiers.rawValue))"
    }
}

extension KeyPress.Phases {
    init?(_ eventPhase: EventPhase) {
        switch eventPhase {
        case .began:
            self = .down
        case .active:
            self = .repeat
        case .ended:
            self = .up
        case .failed:
            return nil
        }
    }
}

private let _keyPressResponderNextKey = Mutex<UInt32>(0xB0000000)

final class KeyPressResponder: MultiViewResponder {
    let hitTestKey: UInt32

    var phases: KeyPress.Phases
    var keys: Set<KeyEquivalent>?
    var characters: CharacterSet?
    var callback: (KeyPress) -> KeyPress.Result
    var snapshotIsEnabled: Bool

    init(
        phases: KeyPress.Phases,
        keys: Set<KeyEquivalent>?,
        characters: CharacterSet?,
        callback: @escaping (KeyPress) -> KeyPress.Result,
        isEnabled: Bool,
        innerResponders: [ViewResponder]
    ) {
        self.hitTestKey = _keyPressResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.phases = phases
        self.keys = keys
        self.characters = characters
        self.callback = callback
        self.snapshotIsEnabled = isEnabled
        super.init()
        updateInnerResponders(innerResponders)
    }

    func updateInnerResponders(_ innerResponders: [ViewResponder]) {
        children = innerResponders
    }

    override func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        .passthrough
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        ViewResponder.ContainsPointsResult(mask: [], priority: 0, children: children)
    }

    func handle(_ keyPress: KeyPress) -> KeyPress.Result {
        guard snapshotIsEnabled else { return .ignored }
        guard phases.contains(keyPress.phase) else { return .ignored }
        if let keys, !keys.contains(keyPress.key) { return .ignored }
        if let characters, !keyPress.characters.unicodeScalars.contains(where: { characters.contains($0) }) {
            return .ignored
        }
        return callback(keyPress)
    }
}

struct KeyEventDispatcher: ForwardedEventDispatcher {
    static var eventType: any EventType.Type { KeyEvent.self }

    @discardableResult
    mutating func receiveEvents(
        _ events: [EventID: any EventType],
        manager: EventBindingManager
    ) -> Set<EventID> {
        let rootResponder = manager.rootResponder as? MultiViewResponder
        guard let rootResponder else { return [] }
        let gestureGraph = manager.host as? GestureGraph
        let enqueueAction: (@escaping () -> Void) -> Void = { action in
            if let gestureGraph {
                gestureGraph.enqueueAction(action)
            } else {
                action()
            }
        }
        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            guard let keyEvent = event as? KeyEvent,
                  let keyPress = KeyPress(keyEvent) else { continue }
            if dispatch(
                keyPress,
                responders: rootResponder.children,
                enqueueAction: enqueueAction
            ) {
                consumed.insert(eventID)
            }
        }
        return consumed
    }

    private func dispatch(
        _ keyPress: KeyPress,
        responders: [ViewResponder],
        enqueueAction: (@escaping () -> Void) -> Void
    ) -> Bool {
        for responder in responders {
            if let keyResponder = responder as? KeyPressResponder {
                var result: KeyPress.Result = .ignored
                enqueueAction {
                    result = keyResponder.handle(keyPress)
                }
                if result == .handled {
                    return true
                }
            }
            if let multiResponder = responder as? MultiViewResponder,
               dispatch(
                   keyPress,
                   responders: multiResponder.children,
                   enqueueAction: enqueueAction
               ) {
                return true
            }
        }
        return false
    }
}

public struct _KeyPressModifier: ViewModifier, MultiViewModifier {
    public let phases: KeyPress.Phases
    public let keys: Set<KeyEquivalent>?
    public let characters: CharacterSet?
    public let callback: (KeyPress) -> KeyPress.Result

    public init(
        phases: KeyPress.Phases,
        keys: Set<KeyEquivalent>? = nil,
        characters: CharacterSet? = nil,
        callback: @escaping (KeyPress) -> KeyPress.Result
    ) {
        self.phases = phases
        self.keys = keys
        self.characters = characters
        self.callback = callback
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_KeyPressModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }

        let innerRespondersAttr: Attribute<[ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[ViewResponder]>(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let value = Attribute<[ViewResponder]>(nodeID).value
                    ViewRespondersKey.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let modifierValue = modifier._attribute.value
        let responder = KeyPressResponder(
            phases: modifierValue.phases,
            keys: modifierValue.keys,
            characters: modifierValue.characters,
            callback: modifierValue.callback,
            isEnabled: environmentAttr.value.isEnabled,
            innerResponders: innerRespondersAttr.value
        )
        graph.makeSideEffectRule { [weak responder] in
            guard let responder else { return }
            let modifierValue = modifier._attribute.value
            responder.phases = modifierValue.phases
            responder.keys = modifierValue.keys
            responder.characters = modifierValue.characters
            responder.callback = modifierValue.callback
            responder.snapshotIsEnabled = environmentAttr.value.isEnabled
            responder.updateInnerResponders(innerRespondersAttr.value)
        }

        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        let respondersAttr: Attribute<[ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }
}

extension _KeyPressModifier {
    public typealias Body = Never
}

extension View {
    public func onKeyPress(
        phases: KeyPress.Phases = [.down, .repeat],
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(phases: phases, callback: action))
    }

    public func onKeyPress(
        _ key: KeyEquivalent,
        action: @escaping () -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: [.down, .repeat]) { _ in action() }
    }

    public func onKeyPress(
        _ key: KeyEquivalent,
        phases: KeyPress.Phases,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: phases, action: action)
    }

    public func onKeyPress(
        _ key: KeyEquivalent,
        phases: KeyPress.Phases,
        action: @escaping () -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: phases) { _ in action() }
    }

    public func onKeyPress(
        keys: Set<KeyEquivalent>,
        phases: KeyPress.Phases = [.down, .repeat],
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(phases: phases, keys: keys, callback: action))
    }

    public func onKeyPress(
        characters: CharacterSet,
        phases: KeyPress.Phases = [.down, .repeat],
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(phases: phases, characters: characters, callback: action))
    }
}
