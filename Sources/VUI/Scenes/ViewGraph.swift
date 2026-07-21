//
//  File: ViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewGraphRootValues - dirty bitmask for which root values need updating.
// Member names and raw bit order are part of the host contract.
struct ViewGraphRootValues: OptionSet {
    let rawValue: UInt16

    static let rootView      = ViewGraphRootValues(rawValue: 1 << 0)
    static let environment   = ViewGraphRootValues(rawValue: 1 << 1)
    static let transform     = ViewGraphRootValues(rawValue: 1 << 2)
    static let size          = ViewGraphRootValues(rawValue: 1 << 3)
    static let safeArea      = ViewGraphRootValues(rawValue: 1 << 4)
    static let containerSize = ViewGraphRootValues(rawValue: 1 << 5)
    static let focusStore    = ViewGraphRootValues(rawValue: 1 << 6)
    static let focusedItem   = ViewGraphRootValues(rawValue: 1 << 7)
    static let focusedValues = ViewGraphRootValues(rawValue: 1 << 8)
    static let all           = ViewGraphRootValues(rawValue: 0x01FF)
}

// ViewRenderingPhase - current rendering phase of ViewGraph.
// The phase is still represented as an opaque raw value until concrete cases
// are needed by the host scheduler.
struct ViewRenderingPhase: Equatable, Hashable {
    var rawValue: UInt8
    init(rawValue: UInt8 = 0) { self.rawValue = rawValue }
}

// ViewGraphRenderContext - rendering context passed to ViewGraphRenderDelegate.updateRenderContext.
struct ViewGraphRenderContext {
    var contentsScale: CGFloat
    var opaqueBackground: Bool
}

// ViewGraphOwner - owns a ViewGraph and tracks its update/render state.
// WindowController is the current platform host object for this contract.
protocol ViewGraphOwner: AnyObject {
    var viewGraph: ViewGraph { get }
    var currentTimestamp: Time { get set }
    var valuesNeedingUpdate: ViewGraphRootValues { get set }
    var renderingPhase: ViewRenderingPhase { get set }
    var externalUpdateCount: Int { get set }
}

// ViewRendererHost - extends root-value updating and graph ownership with a responder tree root.
protocol ViewRendererHost: ViewGraphOwner, ViewGraphRootValueUpdater {
    var responderNode: ResponderNode? { get }
}

// ViewGraphDelegate - update scheduling callbacks for the view graph.
// ViewGraph.delegate: Optional<ViewGraphDelegate>
protocol ViewGraphDelegate: GraphDelegate {
    func setNeedsUpdate()
    func requestUpdate(after: Double)
    func `as`<T>(_ type: T.Type) -> T?
}

extension ViewGraphDelegate {
    func setNeedsUpdate() {
        requestUpdate(after: 0)
    }
}

// ViewGraphHostDelegate - environment/input update hook for ViewGraphHost.
// ViewGraphHost.delegate: Optional<ViewGraphHostDelegate>
protocol ViewGraphHostDelegate: AnyObject {
    func updateGraphInputs(_ inputs: inout _GraphInputs)
}

// ViewGraphRenderDelegate - rendering callback delegate.
// ViewGraphHost.renderDelegate: Optional<ViewGraphRenderDelegate>
protocol ViewGraphRenderDelegate: AnyObject {
    // The root backend object being rendered.
    var renderingRootView: AnyObject { get }

    func updateRenderContext(_ context: inout ViewGraphRenderContext)

    // Host scheduling hooks.
    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time
    func renderIntervalForDisplayLink(timestamp: Time) -> Double
}

// ViewGraphRootValueUpdater - notifies ViewGraph when root input values change.
// Current host code implements no-op stubs for transform, focus, and
// accessibility paths until those root inputs are wired.
// ViewGraphHost.updateDelegate: Optional<ViewGraphRootValueUpdater>
// WindowController conforms as the host object that updates root input attributes.
protocol ViewGraphRootValueUpdater: ViewGraphDelegate {
    func updateRootView()
    func updateEnvironment()
    func updateSize()
    func updateSafeArea()
    func updateContainerSize()

    func updateTransform()
    func updateFocusStore()
    func updateFocusedItem()
    func updateFocusedValues()
    func updateAccessibilityEnvironment()
}

extension ViewGraphRootValueUpdater {
    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let owner = self as? any ViewGraphOwner else {
            fatalError("ViewGraphRootValueUpdater requires a ViewGraphOwner")
        }
        return body(owner.viewGraph)
    }

    func graphDidChange() {
        setNeedsUpdate()
    }

    func preferencesDidChange() {}

    func updateTransform() {}
    func updateFocusStore() {}
    func updateFocusedItem() {}
    func updateFocusedValues() {}
    func updateAccessibilityEnvironment() {}

    func invalidateProperties(_ values: ViewGraphRootValues, mayDeferUpdate: Bool) {
        guard !values.isEmpty,
              let owner = self as? any ViewGraphOwner else {
            return
        }

        Update.withLock {
            let currentValues = owner.valuesNeedingUpdate
            guard !values.subtracting(currentValues).isEmpty else {
                return
            }

            let updatedValues = currentValues.union(values)
            owner.valuesNeedingUpdate = updatedValues
            owner.viewGraph.setNeedsUpdate(
                mayDeferUpdate: mayDeferUpdate,
                values: updatedValues
            )
        }
    }
}

// ViewGraphFeature - optional per-graph hooks for auxiliary graph behavior.
// Features can adjust inputs/outputs, join lifecycle transitions, and request
// update participation without becoming part of the core ViewGraph state.
protocol ViewGraphFeature {
    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph)
    func modifyViewOutputs(outputs: inout _ViewOutputs, inputs: _ViewInputs, graph: ViewGraph)
    func uninstantiate(graph: ViewGraph)
    func isHiddenForReuseDidChange(graph: ViewGraph)
    func allowsAsyncUpdate(graph: ViewGraph) -> Bool?
    func needsUpdate(graph: ViewGraph) -> Bool
    func outputsDidChange(graph: ViewGraph)
    func update(graph: ViewGraph)
}

// Default feature hooks are intentionally inert. Individual features only
// override the lifecycle points they need.
extension ViewGraphFeature {
    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {}
    func modifyViewOutputs(outputs: inout _ViewOutputs, inputs: _ViewInputs, graph: ViewGraph) {}
    func uninstantiate(graph: ViewGraph) {}
    func isHiddenForReuseDidChange(graph: ViewGraph) {}
    func allowsAsyncUpdate(graph: ViewGraph) -> Bool? { true }
    func needsUpdate(graph: ViewGraph) -> Bool { false }
    func outputsDidChange(graph: ViewGraph) {}
    func update(graph: ViewGraph) {}
}

// Small ordered feature list owned by ViewGraph. Keeping dispatch centralized
// makes host lifecycle fan-out explicit at the call site.
struct ViewGraphFeatureBuffer {
    private var features: [any ViewGraphFeature] = []

    var count: Int {
        features.count
    }

    mutating func append(_ feature: any ViewGraphFeature) {
        features.append(feature)
    }

    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        for feature in features {
            feature.modifyViewInputs(inputs: &inputs, graph: graph)
        }
    }

    func modifyViewOutputs(outputs: inout _ViewOutputs, inputs: _ViewInputs, graph: ViewGraph) {
        for feature in features {
            feature.modifyViewOutputs(outputs: &outputs, inputs: inputs, graph: graph)
        }
    }

    func isHiddenForReuseDidChange(graph: ViewGraph) {
        for feature in features {
            feature.isHiddenForReuseDidChange(graph: graph)
        }
    }
}

struct ImageRendererHostViewGraph: ViewGraphFeature {
    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        inputs[UsingGraphicsRenderer.self] = true
        inputs.base.options.insert(.animationsDisabled)
    }
}

// ViewGraphHost - intermediate base class between GraphHost and ViewGraph.
// The backend currently drives updateOutputs from the render loop. The class
// keeps the shared host lifecycle surface so scheduling can be tightened later.
class ViewGraphHost: GraphHost, ViewGraphOwner {

    weak var delegate: (any ViewGraphHostDelegate)?
    weak var renderDelegate: (any ViewGraphRenderDelegate)?
    weak var updateDelegate: (any ViewGraphRootValueUpdater)?

    var accessibilityEnabled: Bool = false
    var parentPhase: _GraphInputs.Phase?

    // ViewGraphOwner
    var currentTimestamp: Time = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0
    var viewGraph: ViewGraph { self as! ViewGraph }

    private static let updateTimerDelayFloor: Double = 0.1

    private var displayLink: ViewGraphDisplayLink?
    private var updateTimerDelay: Double?
    private var updateTimerNextUpdate: Time = .infinity
    private var canStartUpdateTimer: Bool = true

    var scheduledDisplayLinkTime: Time {
        displayLink?.scheduledNextUpdate ?? .infinity
    }

    var hasScheduledUpdateTimer: Bool {
        updateTimerDelay != nil
    }

    var scheduledUpdateTimerTime: Time {
        updateTimerNextUpdate
    }

    var isUpdateTimerGateOpen: Bool {
        canStartUpdateTimer
    }

    var scheduledUpdateTimerDelay: Double? {
        updateTimerDelay
    }

    override var mayDeferUpdate: Bool {
        guard super.mayDeferUpdate,
              let displayLink else {
            return false
        }
        return displayLink.hasScheduledNextUpdate
    }

    func updateRemovedState(isUnattached: Bool, isHiddenForReuse: Bool) {
        var state: RemovedState = []
        if isUnattached {
            state.insert(.unattached)
        }
        if isHiddenForReuse {
            state.insert(.hiddenForReuse)
        }

        Update.withLock {
            Update.begin()
            defer { Update.end() }
            removedState = state
        }
    }

    // Pending parity: the current backend does not own an AppKit/CoreDisplayLink
    // object, but the host still keeps the same scheduling state boundary used
    // by the may-defer gate.
    func startDisplayLink(delay: Double = 0) {
        let link = displayLink ?? ViewGraphDisplayLink()
        displayLink = link
        link.setNextUpdate(
            delay: delay,
            interval: (self as? ViewGraph)?.nextUpdateInterval ?? .infinity,
            reasons: (self as? ViewGraph)?.nextUpdateReasons ?? []
        )
        clearUpdateTimer()
    }

    func clearDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func startUpdateTimer(delay: Double) {
        displayLink?.setNextThread(.main)

        let effectiveDelay = delay < Self.updateTimerDelayFloor
            ? Self.updateTimerDelayFloor
            : delay
        let scheduledTime = currentTimestamp + effectiveDelay
        guard scheduledTime.seconds.isFinite else {
            return
        }

        if canStartUpdateTimer || scheduledTime < updateTimerNextUpdate {
            updateTimerDelay = effectiveDelay
            updateTimerNextUpdate = scheduledTime
            canStartUpdateTimer = false
        }
    }

    func clearUpdateTimer() {
        updateTimerDelay = nil
        updateTimerNextUpdate = .infinity
        canStartUpdateTimer = true
    }

    /// Central AG evaluation entry point for host-driven output updates.
    ///
    /// Current flow:
    ///   display/update trigger
    ///   dirty root values applied through updateDelegate
    ///   graph inbox and queued actions flushed in the current graph context
    func updateOutputs(at time: Time) {
        currentTimestamp = time

        let dirty = valuesNeedingUpdate
        valuesNeedingUpdate = []

        data.withCurrent {
            // Flush async invalidations before applying root-value changes.
            var inboxTransaction: Transaction?
            while data.graph.inbox.hasPendingWork {
                let pendingTransaction = data.graph.inbox.nextTransaction
                if let viewGraph = self as? ViewGraph {
                    viewGraph.setCurrentUpdateTransaction(pendingTransaction)
                    viewGraph.beginNextUpdate(at: time)
                }
                inboxTransaction = data.graph.inbox.drainOne()
            }
            data.graph.drainActions()
            if let viewGraph = self as? ViewGraph {
                viewGraph.setCurrentUpdateTransaction(inboxTransaction)
            }

            // Apply dirty root values through the host updater.
            if dirty.contains(.rootView)      { updateDelegate?.updateRootView() }
            if dirty.contains(.environment)   { updateDelegate?.updateEnvironment() }
            if dirty.contains(.size)          { updateDelegate?.updateSize() }
            if dirty.contains(.safeArea)      { updateDelegate?.updateSafeArea() }
            if dirty.contains(.transform)     { updateDelegate?.updateTransform() }
            if dirty.contains(.focusStore)    { updateDelegate?.updateFocusStore() }
            if dirty.contains(.focusedItem)   { updateDelegate?.updateFocusedItem() }
            if dirty.contains(.focusedValues) { updateDelegate?.updateFocusedValues() }
            if dirty.contains(.containerSize) { updateDelegate?.updateContainerSize() }

            // Pending parity: ViewGraphHostDelegate.updateGraphInputs is not
            // wired here. WindowController updates root input attributes directly.
        }
    }

}

private final class ViewGraphDisplayLink {
    private static let immediateDelayThreshold: Double = 0.001

    enum ThreadName: UInt8 {
        case main = 0
        case async = 1
    }

    private(set) var nextUpdate: Time = .infinity
    private var currentUpdate: Time?
    private var interval: Double = .infinity
    private var reasons: Set<UInt32> = []
    private var currentThread: ThreadName = .main
    private var nextThread: ThreadName = .main

    var scheduledNextUpdate: Time {
        nextUpdate
    }

    var hasScheduledNextUpdate: Bool {
        !(nextUpdate == .infinity)
    }

    func setNextUpdate(
        delay: Double,
        interval: Double,
        reasons: Set<UInt32>
    ) {
        let candidate = delay < Self.immediateDelayThreshold
            ? .zero
            : (currentUpdate ?? .zero) + delay
        if candidate < nextUpdate {
            nextUpdate = candidate
            self.interval = interval
            self.reasons = reasons
        }
    }

    func setNextThread(_ thread: ThreadName) {
        nextThread = thread
    }

    func invalidate() {
        nextUpdate = .infinity
        currentUpdate = nil
        interval = .infinity
        reasons = []
        currentThread = .main
        nextThread = .main
    }
}

// ViewGraph - view-level AG host.
// This keeps the GraphHost, ViewGraphHost, ViewGraph hierarchy while being
// owned directly by WindowController. The initializer builds the root view
// output rule and captures the requested output attributes.
//
// GestureGraph ownership is shared with the renderer host for event dispatch.
class ViewGraph: ViewGraphHost {

    override func hostKind() -> CustomEventTrace.InstantiationEventType.Kind {
        .view
    }

    // Update scheduling callback.
    weak var viewDelegate: (any ViewGraphDelegate)?

    // AG transaction lifecycle callback.
    private weak var graphDelegateStorage: (any GraphDelegate)?

    override var graphDelegate: (any GraphDelegate)? {
        get { graphDelegateStorage }
        set { graphDelegateStorage = newValue }
    }

    // Outputs requested at init time.
    var requestedOutputs: Outputs
    private var featureBuffer = ViewGraphFeatureBuffer()
    var preferenceBridge: PreferenceBridge?
    private(set) var preferenceValueOutlets: [(key: any PreferenceKey.Type, value: AGAttribute)] = []
    private(set) var hostPreferenceKeys: Attribute<PreferenceKeys>?
    private var hostPreferenceOutletKeys: Attribute<PreferenceKeys>?

    var nextUpdate: (views: NextUpdate, gestures: NextUpdate) = (NextUpdate(), NextUpdate())

    // Back-reference to the owning ViewRendererHost. Gesture responders use
    // this to reach the shared gesture graph during view construction.
    weak var rendererHost: (any ViewRendererHost)?

    override var parentHost: GraphHost? {
        (rendererHost as? WindowController)?.parentWindow?.viewGraph
    }

    // AG input attributes updated by WindowController's root-value updater.
    private(set) var sizeAttr: Attribute<ViewSize>?
    private(set) var envAttr: Attribute<EnvironmentValues>?
    private(set) var timeAttr: Attribute<Time>?
    private(set) var transactionAttr: Attribute<Transaction>?
    private(set) var phaseAttr: Attribute<_GraphInputs.Phase>?
    private var currentUpdateTransaction = Transaction()
    private var hasCurrentUpdateTransaction = false
    private var transactionAttrNeedsClear = false

    // AG output attributes collected after V._makeView.
    private(set) var rootAnyViewContentInput: Attribute<AnyView>?
    private(set) var rootLayoutComputer: Attribute<LayoutComputer>?
    private(set) var rootFittedSize: Attribute<CGSize>?
    private(set) var rootDisplayList: Attribute<DisplayList>?
    private(set) var rootResourceList: Attribute<ResourceList>?

    override var isValid: Bool { rootLayoutComputer != nil }

    // Requested output bitmask.
    // defaults = displayList | viewResponders | layout | focus.
    struct Outputs: OptionSet {
        let rawValue: UInt8
        static let displayList      = Outputs(rawValue: 0x01)  // bit 0
        static let platformItemList = Outputs(rawValue: 0x02)  // bit 1
        static let viewResponders   = Outputs(rawValue: 0x04)  // bit 2
        // 0x08: unknown member (unused)
        static let layout           = Outputs(rawValue: 0x10)  // bit 4
        static let focus            = Outputs(rawValue: 0x20)  // bit 5
        static let defaults         = Outputs(rawValue: 0x35)  // displayList | viewResponders | layout | focus
        static let all              = Outputs(rawValue: 0xFF)
    }

    // Update scheduling value type.
    // Stored as a tuple: nextUpdate: (views: NextUpdate, gestures: NextUpdate)
    struct NextUpdate {
        var time: Time = .infinity
        var interval: Double = .infinity
        var hasZeroInterval: Bool = false
        var reasons: Set<UInt32> = []
        private static let highFrameRateReason: UInt32 = 2_555_904

        mutating func at(_ t: Time) {
            if t < time {
                time = t
            }
        }

        mutating func interval(_ dt: Double, reason: UInt32? = nil) {
            if dt == 0 {
                hasZeroInterval = true
            } else {
                interval = Swift.min(interval, dt)
            }
            normalizeIntervalAfterZeroRequest()
            if let r = reason { reasons.insert(r) }
        }

        mutating func maxVelocity(_ velocity: Double) {
            let interval: Double
            if velocity >= 320 {
                interval = 1.0 / 120.0
            } else if velocity >= 160 {
                interval = 1.0 / 80.0
            } else {
                return
            }
            self.interval = Swift.min(self.interval, interval)
            normalizeIntervalAfterZeroRequest()
            reasons.insert(Self.highFrameRateReason)
        }

        private mutating func normalizeIntervalAfterZeroRequest() {
            if hasZeroInterval && interval > (1.0 / 60.0) {
                interval = .infinity
            }
        }
    }

    var nextUpdateInterval: Double {
        let interval = Swift.min(
            nextUpdate.views.interval,
            nextUpdate.gestures.interval
        )
        return interval.isFinite ? interval : 0.0
    }

    var nextUpdateReasons: Set<UInt32> {
        nextUpdate.views.reasons.union(nextUpdate.gestures.reasons)
    }

    var hasScheduledViewUpdate: Bool {
        func isScheduled(_ update: NextUpdate) -> Bool {
            !(update.time == .infinity) ||
                update.interval.isFinite ||
                update.hasZeroInterval ||
                !update.reasons.isEmpty
        }
        return isScheduled(nextUpdate.views) || isScheduled(nextUpdate.gestures)
    }

    var viewGraphFeatureCount: Int {
        featureBuffer.count
    }

    func addFeature(_ feature: any ViewGraphFeature) {
        featureBuffer.append(feature)
    }

    override func isHiddenForReuseDidChange() {
        updatePreferenceOutletsForHiddenReuse()
        featureBuffer.isHiddenForReuseDidChange(graph: self)
    }

    func updatePreferenceBridge(environment: EnvironmentValues, deferredUpdate: @escaping () -> Void) {
        guard let bridge = environment.preferenceBridge else {
            return
        }
        guard bridge !== preferenceBridge else {
            return
        }

        if shouldDeferPreferenceBridgeUpdate {
            Update.enqueueAction(reason: 0x11, deferredUpdate)
        } else {
            setPreferenceBridge(to: bridge, isInvalidating: false)
        }
    }

    func invalidatePreferenceBridge() {
        setPreferenceBridge(to: nil, isInvalidating: true)
    }

    func setPreferenceBridge(to bridge: PreferenceBridge?, isInvalidating: Bool) {
        guard bridge !== preferenceBridge else {
            return
        }

        data.withCurrent {
            removePreferenceOutlets(isInvalidating: isInvalidating)
            preferenceBridge = bridge
            bridge?.viewGraph = self
            bridge?.addChild(self)
            updateRemovedState()
        }
    }

    func makePreferenceOutlets(outputs: _ViewOutputs) {
        guard let bridge = preferenceBridge else {
            return
        }

        for key in bridge.requestedPreferences.keys {
            guard key != HostPreferencesKey.self,
                  let value = outputs.preferences.value(for: key) else {
                continue
            }
            preferenceValueOutlets.append((key: key, value: value))
            if !data.isHiddenForReuse {
                bridge.addValue(value, for: key)
            }
        }

        guard let hostValues = outputs.preferences.value(for: HostPreferencesKey.self),
              let graph = _AGGraph.current,
              let weakHostValues = graph.weakAttributeIfValid(for: hostValues) else {
            return
        }

        let outletKeys = resolvedHostPreferenceKeys(for: bridge, in: graph)
        let hostWeak = WeakAttribute<PreferenceValues>(base: weakHostValues)
        hostPreferenceOutletKeys = outletKeys
        hostPreferenceValues = hostWeak
        if let outletKeys, !data.isHiddenForReuse {
            bridge.addHostValues(hostWeak, for: outletKeys)
        }
    }

    func removePreferenceOutlets(isInvalidating: Bool) {
        guard let bridge = preferenceBridge else {
            preferenceValueOutlets.removeAll()
            hostPreferenceValues = WeakAttribute()
            hostPreferenceOutletKeys = nil
            return
        }

        for outlet in preferenceValueOutlets {
            bridge.removeValue(
                outlet.value,
                for: outlet.key,
                isInvalidating: isInvalidating
            )
        }
        preferenceValueOutlets.removeAll()

        if let hostPreferenceOutletKeys {
            bridge.removeHostValues(
                for: hostPreferenceOutletKeys,
                isInvalidating: isInvalidating
            )
        }
        hostPreferenceValues = WeakAttribute()
        hostPreferenceOutletKeys = nil
        bridge.removeChild(self)
    }

    private func updatePreferenceOutletsForHiddenReuse() {
        guard let bridge = preferenceBridge else {
            return
        }

        data.withCurrent {
            if data.isHiddenForReuse {
                for outlet in preferenceValueOutlets {
                    bridge.removeValue(
                        outlet.value,
                        for: outlet.key,
                        isInvalidating: true
                    )
                }
                if let hostPreferenceOutletKeys {
                    bridge.removeHostValues(
                        for: hostPreferenceOutletKeys,
                        isInvalidating: true
                    )
                }
            } else {
                for outlet in preferenceValueOutlets {
                    bridge.addValue(outlet.value, for: outlet.key)
                }
                if let hostPreferenceOutletKeys,
                   hostPreferenceValues.isValid(in: data.graph) {
                    bridge.addHostValues(hostPreferenceValues, for: hostPreferenceOutletKeys)
                }
            }
        }
    }

    private func resolvedHostPreferenceKeys(
        for bridge: PreferenceBridge,
        in graph: _AGGraph
    ) -> Attribute<PreferenceKeys>? {
        if let hostPreferenceKeys,
           containsRequestedPreference(in: hostPreferenceKeys.value, bridge: bridge) {
            return hostPreferenceKeys
        }
        guard bridge._hostPreferenceKeys.isValid(in: graph) else {
            return hostPreferenceKeys
        }
        return bridge._hostPreferenceKeys.toStrong()
    }

    private func containsRequestedPreference(
        in keys: PreferenceKeys,
        bridge: PreferenceBridge
    ) -> Bool {
        bridge.requestedPreferences.keys.contains { requestedKey in
            requestedKey != HostPreferencesKey.self && keys.contains(requestedKey)
        }
    }

    private var shouldDeferPreferenceBridgeUpdate: Bool {
        isUpdating
    }

    func updateGraphPhase(
        oldParentPhase: _GraphInputs.Phase?,
        newParentPhase: _GraphInputs.Phase
    ) {
        defer { parentPhase = newParentPhase }

        guard let oldParentPhase else {
            setPhase(newParentPhase)
            return
        }

        let delta = oldParentPhase.rawValue ^ newParentPhase.rawValue
        if delta >= 0x2 {
            incrementPhase()
        } else if (delta & 0x1) != 0 {
            data.withCurrent {
                var phase = data._phase.value
                phase.isBeingRemoved = newParentPhase.isBeingRemoved
                data._phase.setValue(phase)
            }
        }
    }

    // Backend init that takes a concrete view value to lift into the graph.
    convenience init<V: View>(
        rootViewType: V.Type,
        content: V,
        rendererHost: any ViewRendererHost,
        initialEnvironment: EnvironmentValues = .tracking(),
        requestedOutputs: Outputs = .defaults,
        features: [any ViewGraphFeature] = []
    ) {
        self.init(rootViewType: V.self, rendererHost: rendererHost,
                  initialEnvironment: initialEnvironment,
                  requestedOutputs: requestedOutputs, features: features) { g in
            _GraphValue<V>(_attribute: g.makeInput(value: content))
        }
    }

    convenience init<Content: View>(replaceableContent content: Content,
                                    rendererHost: any ViewRendererHost,
                                    initialEnvironment: EnvironmentValues = .tracking(),
                                    requestedOutputs: Outputs = .defaults,
                                    features: [any ViewGraphFeature] = []) {
        var contentAttr: Attribute<AnyView>?
        let erasedContent = AnyView(content)
        self.init(rootViewType: AnyView.self, rendererHost: rendererHost,
                  initialEnvironment: initialEnvironment,
                  requestedOutputs: requestedOutputs, features: features) { g in
            let attr: Attribute<AnyView> = g.makeInput(value: erasedContent)
            contentAttr = attr
            return _GraphValue<AnyView>(_attribute: attr)
        }
        self.rootAnyViewContentInput = contentAttr
    }

    // Cross-graph variant: content lives in a parent graph and is observed through a proxy node.
    // When parent state changes, parent contentAttr re-evaluates, the child inbox
    // is notified, and the child updates on its next updateOutputs. Caller must evaluate contentAttr in sourceGraph
    // first (call `_ = contentAttr.value`) so the crossGraphRef finds a non-nil cached value.
    convenience init(crossGraphContentAttr: Attribute<AnyView>, sourceGraph: _AGGraph,
                     rendererHost: any ViewRendererHost,
                     initialEnvironment: EnvironmentValues = .tracking(),
                     requestedOutputs: Outputs = .defaults,
                     features: [any ViewGraphFeature] = []) {
        self.init(rootViewType: AnyView.self, rendererHost: rendererHost,
                  initialEnvironment: initialEnvironment,
                  requestedOutputs: requestedOutputs, features: features) { g in
            _GraphValue<AnyView>(_attribute: g.makeCrossGraphRef(source: crossGraphContentAttr, in: sourceGraph))
        }
    }

    // Common designated init: `makeContent` is called inside data.withCurrent to produce the
    // root _GraphValue. The _AGGraph passed is self.data.graph (child graph, current).
    private init<V: View>(rootViewType: V.Type, rendererHost: any ViewRendererHost,
                          initialEnvironment: EnvironmentValues,
                          requestedOutputs: Outputs,
                          features: [any ViewGraphFeature],
                          makeContent: (_AGGraph) -> _GraphValue<V>) {
        self.requestedOutputs = requestedOutputs
        super.init(data: GraphHost.Data())
        // Wire rendererHost before building the root view.
        self.rendererHost = rendererHost
        for feature in features {
            featureBuffer.append(feature)
        }
        let time = Time(seconds: 0)

        var sizeAttrResult:  Attribute<ViewSize>?          = nil
        var envAttrResult:   Attribute<EnvironmentValues>? = nil
        var timeAttrResult:  Attribute<Time>?              = nil
        var transactionAttrResult: Attribute<Transaction>? = nil
        var phaseAttrResult: Attribute<_GraphInputs.Phase>? = nil
        var rootLCResult:    Attribute<LayoutComputer>?    = nil
        var rootSizeResult:  Attribute<CGSize>?            = nil
        var rootDLResult:    Attribute<DisplayList>?       = nil
        var rootRLResult:    Attribute<ResourceList>?      = nil

        self.data.withCurrent {
            // Root construction inherits the host's root subgraph so every
            // node and nested responder has a stable lifecycle owner.
            AGSubgraph.withCurrent(self.rootSubgraph) {
            let g = self.graph
            let contentGV = makeContent(g)

            let timeAttr        = g.makeInput(value: time)
            let phaseAttr       = self.data._phase
            let transactionAttr = g.makeInput(value: Transaction())
            let envAttr         = g.makeInput(value: initialEnvironment)
            let graphInputs = _GraphInputs(
                time: timeAttr,
                phase: phaseAttr,
                environment: envAttr,
                transaction: transactionAttr
            )
            var prefKeys = PreferenceKeys()
            prefKeys.add(DisplayList.Key.self)
            prefKeys.add(ResourceList.Key.self)
            prefKeys.add(ViewRespondersKey.self)
            prefKeys.add(SheetPreference.Key.self)
            prefKeys.add(AlertStorage.PreferenceKey.self)
            prefKeys.add(ConfirmationDialog.PreferenceKey.self)

            let hostKeysAttr = g.makeInput(value: prefKeys)
            let prefsInputs  = PreferencesInputs(keys: prefKeys, hostKeys: hostKeysAttr)
            hostPreferenceKeys = hostKeysAttr

            let transformAttr    = g.makeInput(value: ViewTransform.identity)
            let positionAttr     = g.makeInput(value: CGPoint.zero)
            let containerPosAttr = g.makeInput(value: CGPoint.zero)
            let sizeAttr         = g.makeInput(value: ViewSize(.zero))
            var viewInputs = _ViewInputs(
                base: graphInputs,
                customInputs: PropertyList(),
                preferences: prefsInputs,
                transform: transformAttr,
                position: positionAttr,
                containerPosition: containerPosAttr,
                size: sizeAttr,
                safeAreaInsets: OptionalAttribute(),
                containerSize: OptionalAttribute(),
                stackOrientation: nil
            )
            viewInputs.requestsLayoutComputer = true
            viewInputs.needsGeometry = true
            featureBuffer.modifyViewInputs(inputs: &viewInputs, graph: self)
            viewInputs.makeRootMatchedGeometryScope()

            // GestureResponder.init reads the shared gesture graph from ViewGraph.
            var outputs: _ViewOutputs = V._makeView(view: contentGV, inputs: viewInputs)
            featureBuffer.modifyViewOutputs(outputs: &outputs, inputs: viewInputs, graph: self)
            makePreferenceOutlets(outputs: outputs)

            let resourceNodes = outputs.preferences.values(for: ResourceList.Key.self)
            let displayNodes  = outputs.preferences.values(for: DisplayList.Key.self)
            if !resourceNodes.isEmpty {
                rootRLResult = g.makeRule {
                    var combined = ResourceList.Key.defaultValue
                    for nodeID in resourceNodes {
                        let list = Attribute<ResourceList>(nodeID).value
                        ResourceList.Key.reduce(value: &combined) { list }
                    }
                    return combined
                }
            }
            if !displayNodes.isEmpty {
                rootDLResult = g.makeRule {
                    var combined = DisplayList.Key.defaultValue
                    for nodeID in displayNodes {
                        let list = Attribute<DisplayList>(nodeID).value
                        DisplayList.Key.reduce(value: &combined) { list }
                    }
                    return combined
                }
            }

            let responderNodes = outputs.preferences.values(for: ViewRespondersKey.self)
            if !responderNodes.isEmpty {
                let rootRespondersAttr: Attribute<[ViewResponder]> = g.makeRule {
                    var combined: [ViewResponder] = ViewRespondersKey.defaultValue
                    for nodeID in responderNodes {
                        let list = Attribute<[ViewResponder]>(nodeID).value
                        ViewRespondersKey.reduce(value: &combined) { list }
                    }
                    return combined
                }
                g.makeSideEffectRule { [weak self] in
                    (self?.rendererHost as? WindowController)?
                        .gestureGraph?
                        .updateResponders(rootRespondersAttr.value)
                }
            }

            let sheetNodes = outputs.preferences.values(for: SheetPreference.Key.self)
            if !sheetNodes.isEmpty {
                let sheetAttr: Attribute<SheetPreference.Value> = g.makeRule {
                    var combined = SheetPreference.Key.defaultValue
                    for nodeID in sheetNodes {
                        let val = Attribute<SheetPreference.Value>(nodeID).value
                        SheetPreference.Key.reduce(value: &combined) { val }
                    }
                    return combined
                }
                g.makeSideEffectRule { [weak self] in
                    guard let host = self?.rendererHost as? WindowController else { return }
                    let value = sheetAttr.value
                    let transaction = _AGGraph.current?.transaction(for: sheetAttr.identifier) ?? Transaction()
                    host.updateSheetPresentation(value, transaction: transaction)
                }
            }

            let alertNodes = outputs.preferences.values(for: AlertStorage.PreferenceKey.self)
            if !alertNodes.isEmpty {
                let alertAttr: Attribute<AlertStorage.PreferenceKey.Value> = g.makeRule {
                    var combined = AlertStorage.PreferenceKey.defaultValue
                    for nodeID in alertNodes {
                        let val = Attribute<AlertStorage.PreferenceKey.Value>(nodeID).value
                        AlertStorage.PreferenceKey.reduce(value: &combined) { val }
                    }
                    return combined
                }
                g.makeSideEffectRule { [weak self] in
                    guard let host = self?.rendererHost as? WindowController else { return }
                    host.updateAlertPresentation(Array(alertAttr.value.values.map { $0.preference }))
                }
            }

            let dialogNodes = outputs.preferences.values(for: ConfirmationDialog.PreferenceKey.self)
            if !dialogNodes.isEmpty {
                let dialogAttr: Attribute<ConfirmationDialog.PreferenceKey.Value> = g.makeRule {
                    var combined = ConfirmationDialog.PreferenceKey.defaultValue
                    for nodeID in dialogNodes {
                        let val = Attribute<ConfirmationDialog.PreferenceKey.Value>(nodeID).value
                        ConfirmationDialog.PreferenceKey.reduce(value: &combined) { val }
                    }
                    return combined
                }
                g.makeSideEffectRule { [weak self] in
                    guard let host = self?.rendererHost as? WindowController else { return }
                    host.updateConfirmationDialogPresentation(
                        Array(dialogAttr.value.values.map { $0.preference }))
                }
            }

            if let rootLC = outputs._layoutComputer.attribute {
                rootLCResult = rootLC
                // Modal/aux platform windows need the root view's natural
                // size, not the host window's proposed sizeAttr. This rule
                // registers dependencies through LayoutComputer.sizeThatFits
                // and is only read by child controllers that auto-fit.
                rootSizeResult = g.makeRule {
                    rootLC.value.sizeThatFits(.unspecified)
                }
            }

            sizeAttrResult  = sizeAttr
            envAttrResult   = envAttr
            timeAttrResult  = timeAttr
            transactionAttrResult = transactionAttr
            phaseAttrResult = phaseAttr
            }
        }

        self.sizeAttr           = sizeAttrResult
        self.envAttr            = envAttrResult
        self.timeAttr           = timeAttrResult
        self.transactionAttr    = transactionAttrResult
        self.phaseAttr          = phaseAttrResult
        self.rootLayoutComputer = rootLCResult
        self.rootFittedSize     = rootSizeResult
        self.rootDisplayList    = rootDLResult
        self.rootResourceList   = rootRLResult
    }

    /// Flushes queued graph transactions around host output evaluation.
    override func updateOutputs(at time: Time) {
        beginNextUpdate(at: time)
        flushTransactions()
        runTransaction(nil, do: {
            super.updateOutputs(at: time)
        }, id: nil)
        flushTransactions()
        updatePreferences()
    }

    func setCurrentUpdateTransaction(_ transaction: Transaction?) {
        if let transaction, !transaction.isEmpty {
            currentUpdateTransaction = transaction
            hasCurrentUpdateTransaction = true
        } else {
            currentUpdateTransaction = Transaction()
            hasCurrentUpdateTransaction = false
        }
    }

    func beginNextUpdate(at time: Time) {
        data.withCurrent {
            guard let timeAttr else {
                nextUpdate = (NextUpdate(), NextUpdate())
                return
            }
            if !(timeAttr.value == time) {
                timeAttr.setValue(time)
                nextUpdate = (NextUpdate(), NextUpdate())
            }
            if let transactionAttr {
                if hasCurrentUpdateTransaction {
                    transactionAttr.setValue(currentUpdateTransaction)
                    transactionAttrNeedsClear = true
                } else if transactionAttrNeedsClear {
                    transactionAttr.setValue(Transaction())
                    transactionAttrNeedsClear = false
                }
            }
            data.updateSeed &+= 1
        }
    }

    // Returns the current display list from the AG graph.
    func displayList() -> DisplayList? { rootDisplayList?.value }

    // Pending parity: route input events through GestureGraph.
    func sendEvents(_ events: [Any], rootNode: ResponderNode, at time: Time) {}
}
