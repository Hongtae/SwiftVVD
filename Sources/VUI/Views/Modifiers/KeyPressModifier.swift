//
//  File: KeyPressModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

public struct KeyPress: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case down
        case `repeat`
        case up
    }

    public struct Phases: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let down = Phases(rawValue: 1 << 0)
        public static let `repeat` = Phases(rawValue: 1 << 1)
        public static let up = Phases(rawValue: 1 << 2)
        public static let all: Phases = [.down, .repeat, .up]

        func contains(_ phase: Phase) -> Bool {
            switch phase {
            case .down:
                return contains(Self.down)
            case .repeat:
                return contains(Self.repeat)
            case .up:
                return contains(Self.up)
            }
        }
    }

    public enum Result: Sendable, Hashable {
        case handled
        case ignored
    }

    public var key: KeyEquivalent
    public var characters: String
    public var modifiers: EventModifiers
    public var phase: Phase

    public init(
        key: KeyEquivalent,
        characters: String,
        modifiers: EventModifiers = [],
        phase: Phase
    ) {
        self.key = key
        self.characters = characters
        self.modifiers = modifiers
        self.phase = phase
    }

    init?(_ event: KeyEvent) {
        guard let phase = Phase(event.eventPhase) else { return nil }
        let key = event.key ?? event.characters.first.map { KeyEquivalent($0) }
        guard let key else { return nil }
        self.init(
            key: key,
            characters: event.characters,
            modifiers: event.modifiers,
            phase: phase
        )
    }
}

extension KeyPress.Phase {
    init?(_ eventPhase: EventPhase) {
        switch eventPhase {
        case .began:
            self = .down
        case .moved:
            self = .repeat
        case .ended:
            self = .up
        case .cancelled:
            return nil
        }
    }
}

private let _keyPressResponderNextKey = Mutex<UInt32>(0xB0000000)

final class KeyPressResponder: MultiViewResponder, ViewResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    var phases: KeyPress.Phases
    var keys: Set<KeyEquivalent>?
    var callback: (KeyPress) -> KeyPress.Result
    var snapshotIsEnabled: Bool

    init(
        phases: KeyPress.Phases,
        keys: Set<KeyEquivalent>?,
        callback: @escaping (KeyPress) -> KeyPress.Result,
        isEnabled: Bool,
        innerResponders: [any ViewResponder]
    ) {
        self.hitTestKey = _keyPressResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.phases = phases
        self.keys = keys
        self.callback = callback
        self.snapshotIsEnabled = isEnabled
        super.init()
        updateInnerResponders(innerResponders)
    }

    func updateInnerResponders(_ innerResponders: [any ViewResponder]) {
        responders = innerResponders
        for responder in responders {
            if responder.nextResponder == nil {
                responder.nextResponder = self
            }
        }
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .passthrough
    }

    func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ContainsPointsOptions
    ) -> ContainsPointsResult {
        ContainsPointsResult(mask: 0, priority: 0, children: responders)
    }

    func handle(_ keyPress: KeyPress) -> KeyPress.Result {
        guard snapshotIsEnabled else { return .ignored }
        guard phases.contains(keyPress.phase) else { return .ignored }
        if let keys, !keys.contains(keyPress.key) { return .ignored }
        return callback(keyPress)
    }
}

final class KeyEventDispatcher {
    @discardableResult
    func receiveEvents(
        _ events: [EventID: any EventType],
        rootResponder: MultiViewResponder?,
        enqueueAction: (@escaping () -> Void) -> Void
    ) -> Set<EventID> {
        guard let rootResponder else { return [] }
        var consumed: Set<EventID> = []
        for (eventID, event) in events {
            guard let keyEvent = event as? KeyEvent,
                  let keyPress = KeyPress(keyEvent) else { continue }
            if dispatch(
                keyPress,
                responders: rootResponder.responders,
                enqueueAction: enqueueAction
            ) {
                consumed.insert(eventID)
            }
        }
        return consumed
    }

    private func dispatch(
        _ keyPress: KeyPress,
        responders: [any ViewResponder],
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
                   responders: multiResponder.responders,
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
    public let callback: (KeyPress) -> KeyPress.Result

    public init(
        phases: KeyPress.Phases,
        keys: Set<KeyEquivalent>? = nil,
        callback: @escaping (KeyPress) -> KeyPress.Result
    ) {
        self.phases = phases
        self.keys = keys
        self.callback = callback
    }

    public static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("_KeyPressModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)

        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }

        let innerRespondersAttr: Attribute<[any ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[any ViewResponder]>(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let value = Attribute<[any ViewResponder]>(nodeID).value
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
            callback: modifierValue.callback,
            isEnabled: environmentAttr.value.isEnabled,
            innerResponders: innerRespondersAttr.value
        )
        graph.makeSideEffectRule { [weak responder] in
            guard let responder else { return }
            let modifierValue = modifier._attribute.value
            responder.phases = modifierValue.phases
            responder.keys = modifierValue.keys
            responder.callback = modifierValue.callback
            responder.snapshotIsEnabled = environmentAttr.value.isEnabled
            responder.updateInnerResponders(innerRespondersAttr.value)
        }

        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }
}

extension _KeyPressModifier {
    public typealias Body = Never
}

extension View {
    public func onKeyPress(
        phases: KeyPress.Phases = .down,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(phases: phases, callback: action))
    }

    public func onKeyPress(
        _ key: KeyEquivalent,
        phases: KeyPress.Phases = .down,
        action: @escaping () -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: phases) { _ in action() }
    }

    public func onKeyPress(
        keys: Set<KeyEquivalent>,
        phases: KeyPress.Phases = .down,
        action: @escaping (KeyPress) -> KeyPress.Result
    ) -> some View {
        modifier(_KeyPressModifier(phases: phases, keys: keys, callback: action))
    }
}
