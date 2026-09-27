//
//  File: WindowGestureEnvironment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Receives raw window events at a mounted platform-host responder without
/// materializing a view gesture around that host boundary.
protocol ResponderEventConsumer: AnyObject {
    func acceptsEventType(_ eventType: Any.Type) -> Bool
    func consumeEvents(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> GesturePhase<Void>
    func resetEventSession()
}

extension ResponderEventConsumer {
    func resetEventSession() {
    }
}

/// Owns an accepted event serial at the mounted control boundary. Common
/// gesture responders must not observe any phase of that serial.
protocol ExclusiveResponderEventConsumer: ResponderEventConsumer
where Self: ViewResponder {
    func exclusivelyConsumes(_ event: any EventType) -> Bool
}

/// Adapts platform-host recognition competition to responder decisions while
/// the window backend owns the raw event session.
protocol GestureArbitratingEventConsumer: ResponderEventConsumer
where Self: ViewResponder {
    func isPrevented(by responder: any AnyGestureResponder) -> Bool
    func preventRecognition(for events: [EventID: any EventType])
    func cancels(_ responder: any AnyGestureResponder) -> Bool
}

/// Carries common event-consumption results across the raw-window adapter.
/// A mounted platform consumer reports handling through its aggregate phase;
/// recognizer-owned graphs retain their exact consumed event identifiers.
struct WindowGestureDispatchResult {
    var phase: GesturePhase<Void>
    var consumedEventIDs: Set<EventID>

    var handlesPlatformEvent: Bool {
        if !consumedEventIDs.isEmpty {
            return true
        }
        return phase.isActive || phase.isEnded
    }

    static var possible: WindowGestureDispatchResult {
        WindowGestureDispatchResult(
            phase: .possible(nil),
            consumedEventIDs: []
        )
    }
}

/// Bridges a responder-owned gesture graph to the raw event producer used by
/// the window backend. Platform recognizer state and callback buffering remain
/// outside the common gesture graph.
final class WindowEventBindingBridge:
    EventBindingBridge,
    EventBindingBridgeFactory,
    GestureGraphDelegate
{
    private weak var responder: (any AnyGestureResponder)?
    private lazy var gestureRecognizer: WindowGestureRecognizer? = {
        guard GestureContainerFeature.isEnabled,
              let responder,
              let host = (responder as? ViewResponder)?.host as? WindowController else {
            return nil
        }
        return WindowGestureRecognizer(
            eventBridge: self,
            responder: responder,
            environment: host.gestureEnvironment
        )
    }()
    private var pendingActions: [() -> Void] = []

    private init(
        eventBindingManager: EventBindingManager,
        responder: any AnyGestureResponder
    ) {
        self.responder = responder
        super.init(eventBindingManager: eventBindingManager)
        eventBindingManager.delegate = self
    }

    static func makeEventBindingBridge(
        bindingManager: EventBindingManager,
        responder: any AnyGestureResponder
    ) -> EventBindingBridge & GestureGraphDelegate {
        WindowEventBindingBridge(
            eventBindingManager: bindingManager,
            responder: responder
        )
    }

    override var eventSources: [any EventBindingSource] {
        gestureRecognizer.map { [$0] } ?? []
    }

    func enqueueAction(_ action: @escaping () -> Void) {
        pendingActions.append(action)
    }

    func flushActions() {
        guard !pendingActions.isEmpty else { return }
        let actions = pendingActions
        pendingActions.removeAll()
        Update.enqueueAction {
            for action in actions {
                action()
            }
        }
    }

    func discardActions() {
        pendingActions.removeAll()
    }

    override func reset(
        eventSource: any EventBindingSource,
        resetForwardedEventDispatchers: Bool = false
    ) {
        super.reset(
            eventSource: eventSource,
            resetForwardedEventDispatchers: resetForwardedEventDispatchers
        )
        pendingActions.removeAll()
    }
}

/// Responder-specific recognizer source selected by the window gesture
/// environment. It mirrors the platform recognizer's ownership boundary while
/// leaving raw window-event conversion to `WindowController`.
final class WindowGestureRecognizer: EventBindingSource {
    private weak var eventBridge: WindowEventBindingBridge?
    private weak var responder: (any AnyGestureResponder)?
    private weak var environment: WindowGestureEnvironment?
    private(set) var phase: GesturePhase<Void> = .possible(nil)
    private(set) var gestureCategory: GestureCategory = []
    private(set) var bindings: [EventID: EventBinding] = [:]

    init(
        eventBridge: WindowEventBindingBridge,
        responder: any AnyGestureResponder,
        environment: WindowGestureEnvironment
    ) {
        self.eventBridge = eventBridge
        self.responder = responder
        self.environment = environment
    }

    func attach(to bridge: EventBindingBridge) {
        guard let bridge = bridge as? WindowEventBindingBridge else {
            fatalError("Window gesture recognizer requires its window event bridge")
        }
        eventBridge = bridge
    }

    @discardableResult
    func send(
        _ events: [EventID: any EventType]
    ) -> WindowGestureDispatchResult {
        guard let eventBridge else { return .possible }
        let consumedEventIDs = eventBridge.send(events, source: self)
        return WindowGestureDispatchResult(
            phase: phase,
            consumedEventIDs: consumedEventIDs
        )
    }

    func reset(resetForwardedEventDispatchers: Bool = false) {
        eventBridge?.reset(
            eventSource: self,
            resetForwardedEventDispatchers: resetForwardedEventDispatchers
        )
        phase = .possible(nil)
        gestureCategory = []
        bindings.removeAll()
    }

    var nextUpdateTime: Time {
        eventBridge?.eventBindingManager?.scheduledEventUpdateTime ?? .infinity
    }

    var hasPendingGraphWork: Bool {
        guard let graph = responder?.gestureGraph else { return false }
        return graph.data.graph.inbox.hasPendingWork ||
            !graph.data.graph.pendingActions.isEmpty ||
            !graph.data.graph.actionOutbox.isEmpty
    }

    @discardableResult
    func updateTimedGesture(at time: Time) -> Bool {
        eventBridge?.eventBindingManager?.sendScheduledEventUpdate(at: time)
            ?? false
    }

    func deliverPendingActions() {
        eventBridge?.flushActions()
    }

    func discardPendingActions() {
        eventBridge?.discardActions()
    }

    func drainGraphActions() -> Bool {
        guard let graph = responder?.gestureGraph else { return false }
        let actions = graph.data.graph.actionOutbox
        guard !actions.isEmpty else { return false }
        graph.data.graph.actionOutbox.removeAll()
        actions.forEach { $0() }
        return true
    }

    func didUpdate(
        phase: GesturePhase<Void>,
        in bridge: EventBindingBridge
    ) {
        self.phase = phase
    }

    func didUpdate(
        gestureCategory: GestureCategory,
        in bridge: EventBindingBridge
    ) {
        self.gestureCategory = gestureCategory
    }

    func didBind(
        to binding: EventBinding,
        id: EventID,
        in bridge: EventBindingBridge
    ) {
        bindings[id] = binding
    }

    func didRequestHoverUpdate(in bridge: EventBindingBridge) {
        environment?.requestHoverUpdate()
    }
}

/// Owns recognizer admission and competition for a window backend that exposes
/// raw pointer and gesture events instead of a platform recognizer hierarchy.
final class WindowGestureEnvironment {
    private enum RecognitionDisposition: Equatable {
        case possible
        case waiting
        case admitted
        case rejected
        case completed

        var isTerminal: Bool {
            switch self {
            case .rejected, .completed:
                return true
            case .possible, .waiting, .admitted:
                return false
            }
        }

        var wasAdmitted: Bool {
            switch self {
            case .admitted, .completed:
                return true
            case .possible, .waiting, .rejected:
                return false
            }
        }
    }

    private final class RecognitionMember {
        weak var responder: (any AnyGestureResponder)?
        let recognizer: WindowGestureRecognizer
        var disposition: RecognitionDisposition = .possible
        var didReset = false

        init(
            responder: any AnyGestureResponder,
            recognizer: WindowGestureRecognizer
        ) {
            self.responder = responder
            self.recognizer = recognizer
        }
    }

    private final class RecognitionCohort {
        var members: [ObjectIdentifier: RecognitionMember] = [:]
    }

    private weak var host: WindowController?
    private var retainedRootResponder: MultiViewResponder?
    private var retainedEventBindingManager: EventBindingManager?
    private var activeGestureResponders:
        [Int: [any AnyGestureResponder]] = [:]
    private var cancelledGestureResponders:
        [Int: Set<ObjectIdentifier>] = [:]
    private var recognitionCohorts: [Int: RecognitionCohort] = [:]
    private var recognizerCohortIDs: [ObjectIdentifier: Int] = [:]
    private var nextRecognitionCohortID = 1

    init(host: WindowController) {
        self.host = host
    }

    init(
        rootResponder: MultiViewResponder,
        eventBindingManager: EventBindingManager
    ) {
        self.retainedRootResponder = rootResponder
        self.retainedEventBindingManager = eventBindingManager
    }

    func requestHoverUpdate() {
        host?.eventBindingManager.enqueueHoverUpdateIfNeeded()
    }

    private var rootResponder: MultiViewResponder? {
        retainedRootResponder ?? host?.responderNode as? MultiViewResponder
    }

    private var eventBindingManager: EventBindingManager? {
        retainedEventBindingManager ?? host?.eventBindingManager
    }

    var nextGestureUpdateTime: Time {
        recognizers.reduce(.infinity) { current, recognizer in
            let next = recognizer.nextUpdateTime
            return next < current ? next : current
        }
    }

    var hasPendingGraphWork: Bool {
        recognizers.contains(where: \.hasPendingGraphWork)
    }

    func eventBinding(
        at location: CGPoint,
        accepting eventType: Any.Type
    ) -> EventBinding? {
        if let consumer = hitTestEventConsumer(
            at: location,
            accepting: eventType
        ), let responder = consumer as? ResponderNode {
            return EventBinding(responder: responder)
        }
        guard let responder = hitTestResponders(at: location).first else {
            return nil
        }
        return EventBinding(responder: responder)
    }

    @discardableResult
    func send(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> WindowGestureDispatchResult {
        guard rootResponder != nil else { return .possible }
        return Update.ensure {
            sendBody(events, at: time)
        }
    }

    @discardableResult
    func updateTimedGestures(at time: Time) -> Bool {
        var updated = false
        var affectedCohortIDs: Set<Int> = []
        for recognizer in recognizers
        where !(time < recognizer.nextUpdateTime) {
            if recognizer.updateTimedGesture(at: time) {
                updated = true
                if let cohortID = recognizerCohortIDs[
                    ObjectIdentifier(recognizer)
                ] {
                    affectedCohortIDs.insert(cohortID)
                }
            }
        }
        for cohortID in affectedCohortIDs {
            resolveRecognition(in: cohortID)
            finalizeTerminalMembers(in: cohortID)
        }
        return updated
    }

    func drainGestureActions() -> Bool {
        var drained = false
        for recognizer in recognizers {
            drained = recognizer.drainGraphActions() || drained
        }
        return drained
    }

    func reset() {
        if let rootResponder {
            resetEventConsumers(in: rootResponder)
        }
        for recognizer in recognizers {
            recognizer.reset(resetForwardedEventDispatchers: true)
        }
        activeGestureResponders.removeAll()
        cancelledGestureResponders.removeAll()
        recognitionCohorts.removeAll()
        recognizerCohortIDs.removeAll()
    }

    private func resetEventConsumers(in responder: ViewResponder) {
        (responder as? any ResponderEventConsumer)?.resetEventSession()
        for child in responder.children {
            resetEventConsumers(in: child)
        }
    }

    private var recognizers: [WindowGestureRecognizer] {
        var result: [WindowGestureRecognizer] = []
        var seen: Set<ObjectIdentifier> = []
        for cohort in recognitionCohorts.values {
            for member in cohort.members.values where !member.didReset {
                let identifier = ObjectIdentifier(member.recognizer)
                if seen.insert(identifier).inserted {
                    result.append(member.recognizer)
                }
            }
        }
        return result
    }

    private struct GestureResponderDispatch {
        var responder: any AnyGestureResponder
        var recognizer: WindowGestureRecognizer
        var phase: GesturePhase<Void>
        var consumedEventIDs: Set<EventID>
        var wasAdmitted: Bool
    }

    private func sendBody(
        _ events: [EventID: any EventType],
        at time: Time
    ) -> WindowGestureDispatchResult {
        let eventSerials = Set(events.keys.map(\.serial))
        let candidates = gestureCandidates(for: events)
        let activeCandidates = candidates.filter { responder in
            let identifier = ObjectIdentifier(responder as AnyObject)
            return !eventSerials.contains { serial in
                cancelledGestureResponders[serial]?.contains(identifier) == true
            }
        }
        let cohortID = registerRecognitionCohort(responders: activeCandidates)
        var gestureDispatches: [GestureResponderDispatch] =
            activeCandidates.compactMap { responder in
            guard let recognizer = windowRecognizer(for: responder) else {
                return nil
            }
            if let cohortID,
               let member = recognitionMember(for: recognizer, in: cohortID),
               member.disposition.isTerminal ||
                (member.disposition == .waiting && recognizer.phase.isTerminal) {
                return nil
            }
            let result = recognizer.send(events)
            return GestureResponderDispatch(
                responder: responder,
                recognizer: recognizer,
                phase: result.phase,
                consumedEventIDs: result.consumedEventIDs,
                wasAdmitted: false
            )
        }
        if let cohortID {
            resolveRecognition(in: cohortID)
            for index in gestureDispatches.indices {
                gestureDispatches[index].wasAdmitted = recognitionMember(
                    for: gestureDispatches[index].recognizer,
                    in: cohortID
                )?.disposition.wasAdmitted == true
            }
        }
        let consumerResult = dispatchToEventConsumers(
            events,
            at: time,
            gestureDispatches: gestureDispatches
        )
        if let cohortID,
           let cohort = recognitionCohorts[cohortID] {
            for identifier in consumerResult.cancelledRecognizerIDs {
                guard let member = cohort.members[identifier] else { continue }
                member.disposition = .rejected
                member.didReset = true
            }
            finalizeTerminalMembers(in: cohortID)
        }

        var phases: [GesturePhase<Void>] = gestureDispatches.map {
            $0.phase
        }
        phases.append(contentsOf: consumerResult.phases)
        let consumedEventIDs = gestureDispatches.reduce(
            into: Set<EventID>()
        ) { result, dispatch in
            result.formUnion(dispatch.consumedEventIDs)
        }

        var phasesBySerial: [Int: [EventPhase]] = [:]
        for (eventID, event) in events {
            phasesBySerial[eventID.serial, default: []].append(event.phase)
        }
        for (serial, eventPhases) in phasesBySerial
        where eventPhases.allSatisfy(\.isTerminal) {
            activeGestureResponders.removeValue(forKey: serial)
            cancelledGestureResponders.removeValue(forKey: serial)
        }

        if !events.isEmpty,
           events.values.allSatisfy({ $0.phase.isTerminal }),
           let cohortID,
           let cohort = recognitionCohorts[cohortID] {
            // A responder can combine recognizers for disjoint event types,
            // such as mouse and touch taps. Recognizers that did not accept
            // this completed event stream remain possible, but there can be
            // no later sample that resolves them. Retire those members with
            // the completed stream so a later interaction can form a fresh
            // recognition cohort for the same responder.
            for member in cohort.members.values
            where !member.disposition.isTerminal {
                reject(member)
            }
            finalizeTerminalMembers(in: cohortID)
        }

        let phase: GesturePhase<Void>
        if phases.contains(where: { $0.isActive }) {
            phase = .active(())
        } else if phases.contains(where: { $0.isEnded }) {
            phase = .ended(())
        } else if !phases.isEmpty && phases.allSatisfy({ $0.isFailed }) {
            phase = .failed
        } else {
            phase = .possible(nil)
        }
        return WindowGestureDispatchResult(
            phase: phase,
            consumedEventIDs: consumedEventIDs
        )
    }

    private func registerRecognitionCohort(
        responders: [any AnyGestureResponder]
    ) -> Int? {
        let entries = responders.compactMap { responder -> (
            responder: any AnyGestureResponder,
            recognizer: WindowGestureRecognizer
        )? in
            guard let recognizer = windowRecognizer(for: responder) else {
                return nil
            }
            return (responder, recognizer)
        }
        guard !entries.isEmpty else { return nil }

        let existingIDs = Set(entries.compactMap { entry in
            recognizerCohortIDs[ObjectIdentifier(entry.recognizer)]
        })
        let cohortID: Int
        if let existingID = existingIDs.min() {
            cohortID = existingID
            for sourceID in existingIDs where sourceID != existingID {
                mergeRecognitionCohort(sourceID, into: existingID)
            }
        } else {
            cohortID = nextRecognitionCohortID
            nextRecognitionCohortID &+= 1
            recognitionCohorts[cohortID] = RecognitionCohort()
        }

        guard let cohort = recognitionCohorts[cohortID] else {
            fatalError("Recognition cohort must exist after registration")
        }
        for entry in entries {
            let identifier = ObjectIdentifier(entry.recognizer)
            if let member = cohort.members[identifier] {
                if member.responder == nil {
                    member.responder = entry.responder
                }
            } else {
                cohort.members[identifier] = RecognitionMember(
                    responder: entry.responder,
                    recognizer: entry.recognizer
                )
            }
            recognizerCohortIDs[identifier] = cohortID
        }
        return cohortID
    }

    private func mergeRecognitionCohort(_ sourceID: Int, into targetID: Int) {
        guard sourceID != targetID,
              let source = recognitionCohorts.removeValue(forKey: sourceID),
              let target = recognitionCohorts[targetID] else {
            return
        }
        for (identifier, member) in source.members {
            if target.members[identifier] == nil {
                target.members[identifier] = member
            }
            recognizerCohortIDs[identifier] = targetID
        }
    }

    private func recognitionMember(
        for recognizer: WindowGestureRecognizer,
        in cohortID: Int
    ) -> RecognitionMember? {
        recognitionCohorts[cohortID]?.members[ObjectIdentifier(recognizer)]
    }

    private func resolveRecognition(in cohortID: Int) {
        guard let cohort = recognitionCohorts[cohortID] else { return }

        for member in cohort.members.values {
            guard let responder = member.responder,
                  responder.viewSubgraph.isValid else {
                reject(member)
                continue
            }
            switch member.recognizer.phase {
            case .failed:
                // An admitted stream terminates by cancellation. Only a failure
                // that precedes admission is rejected without delivering actions.
                if member.disposition.wasAdmitted {
                    member.recognizer.deliverPendingActions()
                    member.disposition = .completed
                } else {
                    reject(member)
                }
            case .possible:
                break
            case .active, .ended:
                switch member.disposition {
                case .possible:
                    member.disposition = .waiting
                case .admitted:
                    member.recognizer.deliverPendingActions()
                    if member.recognizer.phase.isEnded {
                        member.disposition = .completed
                    }
                case .waiting, .rejected, .completed:
                    break
                }
            }
        }

        var madeProgress = true
        while madeProgress {
            madeProgress = false

            for member in cohort.members.values
            where member.disposition == .waiting {
                guard let responder = member.responder else {
                    reject(member)
                    madeProgress = true
                    continue
                }
                let requiredMembers = cohort.members.values.filter { other in
                    guard other !== member,
                          let otherResponder = other.responder else {
                        return false
                    }
                    return responder.shouldRequireFailure(of: otherResponder)
                }
                if requiredMembers.contains(where: {
                    $0.disposition.wasAdmitted
                }) {
                    reject(member)
                    madeProgress = true
                }
            }

            let ready = cohort.members.values.filter { member in
                guard member.disposition == .waiting,
                      member.recognizer.phase.isActive,
                      let responder = member.responder else {
                    return false
                }
                return cohort.members.values.allSatisfy { other in
                    guard other !== member,
                          let otherResponder = other.responder,
                          responder.shouldRequireFailure(of: otherResponder) else {
                        return true
                    }
                    return other.disposition == .rejected
                }
            }
            let winners = ready.filter { candidate in
                !ready.contains { other in
                    other !== candidate && canPrevent(other, candidate)
                }
            }
            guard !winners.isEmpty else { continue }

            for winner in winners {
                winner.disposition = .admitted
                winner.recognizer.deliverPendingActions()
                if winner.recognizer.phase.isEnded {
                    winner.disposition = .completed
                }
                madeProgress = true
            }
            for winner in winners {
                for member in cohort.members.values
                where member !== winner && !member.disposition.isTerminal {
                    if requiresFailure(member, of: winner) ||
                        canPrevent(winner, member) {
                        reject(member)
                        madeProgress = true
                    }
                }
            }
        }
    }

    private func requiresFailure(
        _ member: RecognitionMember,
        of other: RecognitionMember
    ) -> Bool {
        guard let responder = member.responder,
              let otherResponder = other.responder else {
            return false
        }
        return responder.shouldRequireFailure(of: otherResponder)
    }

    private func canPrevent(
        _ member: RecognitionMember,
        _ other: RecognitionMember
    ) -> Bool {
        guard let responder = member.responder,
              let otherResponder = other.responder as? ViewResponder else {
            return false
        }
        return responder.canPrevent(
            otherResponder,
            otherExclusionPolicy: other.responder?.exclusionPolicy ?? .default
        )
    }

    private func reject(_ member: RecognitionMember) {
        guard !member.disposition.isTerminal else { return }
        member.disposition = .rejected
        member.recognizer.discardPendingActions()
    }

    private func finalizeTerminalMembers(in cohortID: Int) {
        guard let cohort = recognitionCohorts[cohortID] else { return }
        for member in cohort.members.values
        where member.disposition.isTerminal && !member.didReset {
            member.recognizer.reset()
            member.didReset = true
        }
        guard cohort.members.values.allSatisfy(\.disposition.isTerminal) else {
            return
        }
        recognitionCohorts.removeValue(forKey: cohortID)
        for identifier in cohort.members.keys {
            recognizerCohortIDs.removeValue(forKey: identifier)
        }
    }

    private func windowRecognizer(
        for responder: any AnyGestureResponder
    ) -> WindowGestureRecognizer? {
        for source in responder.eventSources {
            if let recognizer = source.as(WindowGestureRecognizer.self) {
                return recognizer
            }
        }
        return nil
    }

    private func gestureCandidates(
        for events: [EventID: any EventType]
    ) -> [any AnyGestureResponder] {
        var result: [any AnyGestureResponder] = []
        var seen: Set<ObjectIdentifier> = []

        for serial in Set(events.keys.map(\.serial)).sorted() {
            let serialEvents = events.filter { $0.key.serial == serial }
            let candidates: [any AnyGestureResponder]
            if serialEvents.values.contains(where: { $0.phase == .began }) {
                cancelledGestureResponders.removeValue(forKey: serial)
                candidates = initialGestureCandidates(for: serialEvents)
                activeGestureResponders[serial] = candidates
            } else if let active = activeGestureResponders[serial] {
                candidates = active
            } else {
                candidates = initialGestureCandidates(for: serialEvents)
            }

            for candidate in candidates {
                let identifier = ObjectIdentifier(candidate as AnyObject)
                if seen.insert(identifier).inserted {
                    result.append(candidate)
                }
            }
        }
        return result
    }

    private func initialGestureCandidates(
        for events: [EventID: any EventType]
    ) -> [any AnyGestureResponder] {
        if events.contains(where: { eventID, event in
            hasExclusiveEventConsumer(for: eventID, event: event)
        }) {
            return []
        }

        var boundResponders: [any AnyGestureResponder] = []
        var seen: Set<ObjectIdentifier> = []
        for event in events.values {
            guard let boundNode = event.binding?.responder else { continue }
            for responder in boundNode.sequence.compactMap({
                $0 as? any AnyGestureResponder
            }) where responder.mask.contains(.gesture) {
                let identifier = ObjectIdentifier(responder as AnyObject)
                if seen.insert(identifier).inserted {
                    boundResponders.append(responder)
                }
            }
        }
        if !boundResponders.isEmpty {
            return boundResponders
        }

        guard let location = events.values.compactMap({ event in
            (event as? any HitTestableEventType)?.hitTestLocation
        }).first else {
            return []
        }
        return hitTestCandidateResponders(at: location)
    }

    private func hasExclusiveEventConsumer(
        for eventID: EventID,
        event: any EventType
    ) -> Bool {
        if let responder = event.binding?.responder,
           let consumer = responder as? any ExclusiveResponderEventConsumer {
            return consumer.exclusivelyConsumes(event)
        }
        if let responder = eventBindingManager?.eventBindings[eventID]?.responder,
           let consumer = responder as? any ExclusiveResponderEventConsumer {
            return consumer.exclusivelyConsumes(event)
        }
        guard let hitTestable = event as? any HitTestableEventType else {
            return false
        }
        guard let consumer = hitTestEventConsumer(
            at: hitTestable.hitTestLocation,
            accepting: type(of: event)
        ) as? any ExclusiveResponderEventConsumer else {
            return false
        }
        return consumer.exclusivelyConsumes(event)
    }

    private func dispatchToEventConsumers(
        _ events: [EventID: any EventType],
        at time: Time,
        gestureDispatches: [GestureResponderDispatch]
    ) -> (
        phases: [GesturePhase<Void>],
        cancelledRecognizerIDs: Set<ObjectIdentifier>
    ) {
        struct Dispatch {
            var consumer: any ResponderEventConsumer
            var responder: ResponderNode
            var events: [EventID: any EventType]
            var terminalIDs: [EventID]
        }

        guard let eventBindingManager else { return ([], []) }
        let exclusiveSerials = Set(events.compactMap { eventID, event in
            hasExclusiveEventConsumer(for: eventID, event: event)
                ? eventID.serial
                : nil
        })
        var dispatches: [ObjectIdentifier: Dispatch] = [:]
        for (eventID, event) in events {
            let eventType = type(of: event)
            let consumerAndResponder: (
                consumer: any ResponderEventConsumer,
                responder: ResponderNode
            )?

            if let responder = event.binding?.responder,
               let consumer = responder as? any ResponderEventConsumer {
                consumerAndResponder = (consumer, responder)
            } else if let responder = eventBindingManager.eventBindings[eventID]?.responder,
                      let consumer = responder as? any ResponderEventConsumer {
                consumerAndResponder = (consumer, responder)
            } else if let hitTestable = event as? any HitTestableEventType,
                      let consumer = hitTestEventConsumer(
                        at: hitTestable.hitTestLocation,
                        accepting: eventType
                      ),
                      let responder = consumer as? ResponderNode {
                consumerAndResponder = (consumer, responder)
            } else {
                consumerAndResponder = nil
            }

            guard let consumerAndResponder else { continue }
            if exclusiveSerials.contains(eventID.serial) {
                guard let exclusiveConsumer = consumerAndResponder.consumer as?
                    any ExclusiveResponderEventConsumer,
                      exclusiveConsumer.exclusivelyConsumes(event) else {
                    continue
                }
            }
            if event.phase == .began {
                eventBindingManager.rebindEvent(
                    eventID,
                    to: consumerAndResponder.responder
                )
            }
            let identifier = ObjectIdentifier(
                consumerAndResponder.consumer as AnyObject
            )
            var dispatch = dispatches[identifier] ?? Dispatch(
                consumer: consumerAndResponder.consumer,
                responder: consumerAndResponder.responder,
                events: [:],
                terminalIDs: []
            )
            dispatch.events[eventID] = event
            if event.phase.isTerminal {
                dispatch.terminalIDs.append(eventID)
            }
            dispatches[identifier] = dispatch
        }

        var phases: [GesturePhase<Void>] = []
        var cancelledRecognizers:
            [ObjectIdentifier: WindowGestureRecognizer] = [:]
        for dispatch in dispatches.values {
            let arbitrator = dispatch.consumer as?
                any GestureArbitratingEventConsumer
            if let arbitrator {
                for gestureDispatch in gestureDispatches
                where gestureDispatch.wasAdmitted &&
                    gestureDispatch.phase.isActive &&
                    arbitrator.isPrevented(by: gestureDispatch.responder) {
                    arbitrator.preventRecognition(for: dispatch.events)
                }
            }
            let phase = dispatch.consumer.consumeEvents(
                dispatch.events,
                at: time
            )
            if phase.isActive, let arbitrator {
                for gestureDispatch in gestureDispatches
                where gestureDispatch.wasAdmitted &&
                    !gestureDispatch.phase.isTerminal &&
                    arbitrator.cancels(gestureDispatch.responder) {
                    let responderID = ObjectIdentifier(
                        gestureDispatch.responder as AnyObject
                    )
                    for eventID in dispatch.events.keys {
                        cancelledGestureResponders[eventID.serial, default: []]
                            .insert(responderID)
                    }
                    let recognizerID = ObjectIdentifier(
                        gestureDispatch.recognizer
                    )
                    cancelledRecognizers[recognizerID] =
                        gestureDispatch.recognizer
                }
            }
            for eventID in dispatch.terminalIDs {
                eventBindingManager.rebindEvent(eventID, to: nil)
            }
            phases.append(phase)
        }
        for recognizer in cancelledRecognizers.values {
            recognizer.reset()
        }
        return (phases, Set(cancelledRecognizers.keys))
    }

    private func hitTestEventConsumer(
        at location: CGPoint,
        accepting eventType: Any.Type
    ) -> (any ResponderEventConsumer)? {
        guard let rootResponder else { return nil }

        func firstConsumer(
            in responders: [ViewResponder]
        ) -> (any ResponderEventConsumer)? {
            for responder in responders.reversed() {
                guard responder.features.isSuperset(of: .platformViews) else {
                    continue
                }
                let options = ViewResponder.ContainsPointsOptions.platformDefault
                guard responder.hitTestPolicy(options: options) != .exclude else {
                    continue
                }
                let result = responder.containsGlobalPoints(
                    [location],
                    cacheKey: nil,
                    options: options
                )
                guard result.mask[0] else { continue }
                if let descendant = firstConsumer(in: result.children) {
                    return descendant
                }
                if let consumer = responder as? any ResponderEventConsumer,
                   consumer.acceptsEventType(eventType) {
                    return consumer
                }
            }
            return nil
        }

        return firstConsumer(in: rootResponder.children)
    }

    private func hitTestCandidateResponders(
        at location: CGPoint
    ) -> [any AnyGestureResponder] {
        guard let rootResponder else { return [] }
        return rootResponder.respondersContaining(point: location)
            .compactMap { $0 as? any AnyGestureResponder }
            .filter { $0.mask.contains(.gesture) }
    }

    private func hitTestResponders(
        at location: CGPoint
    ) -> [any AnyGestureResponder] {
        hitTestCandidateResponders(at: location)
    }
}
