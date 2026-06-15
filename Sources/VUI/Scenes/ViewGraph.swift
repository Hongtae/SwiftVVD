//
//  File: ViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewGraphRootValues - dirty bitmask for which root values need updating.
// Member names are part of the host contract. Raw values use the current
// local bit mapping until the root-value mask is verified.
struct ViewGraphRootValues: OptionSet {
    let rawValue: UInt16

    // Raw values are provisional; keep bit order isolated here.
    static let rootView      = ViewGraphRootValues(rawValue: 1 << 0)
    static let environment   = ViewGraphRootValues(rawValue: 1 << 1)
    static let size          = ViewGraphRootValues(rawValue: 1 << 2)
    static let safeArea      = ViewGraphRootValues(rawValue: 1 << 3)
    static let transform     = ViewGraphRootValues(rawValue: 1 << 4)
    static let focusStore    = ViewGraphRootValues(rawValue: 1 << 5)
    static let focusedItem   = ViewGraphRootValues(rawValue: 1 << 6)
    static let focusedValues = ViewGraphRootValues(rawValue: 1 << 7)
    static let containerSize = ViewGraphRootValues(rawValue: 1 << 8)
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

// ViewRendererHost - extends ViewGraphOwner with a responder tree root and shared gesture graph.
// WindowController owns both graph objects and exposes the event state needed
// by generated responders through this protocol.
protocol ViewRendererHost: ViewGraphOwner {
    var responderNode: ResponderNode? { get }
    var gestureGraph: GestureGraph? { get }
}

// ViewGraphDelegate - update scheduling callbacks for the view graph.
// ViewGraph.delegate: Optional<ViewGraphDelegate>
protocol ViewGraphDelegate: AnyObject {
    func setNeedsUpdate()
    func requestUpdate(after: Double)
    func `as`<T>(_ type: T.Type) -> T?
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
protocol ViewGraphRootValueUpdater: AnyObject {
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

// ViewGraphHost - intermediate base class between GraphHost and ViewGraph.
// The backend currently drives updateOutputs from the render loop. The class
// keeps the shared host lifecycle surface so scheduling can be tightened later.
class ViewGraphHost: GraphHost, ViewGraphOwner {

    weak var delegate: (any ViewGraphHostDelegate)?
    weak var renderDelegate: (any ViewGraphRenderDelegate)?
    weak var updateDelegate: (any ViewGraphRootValueUpdater)?

    var accessibilityEnabled: Bool = false
    var mayDeferUpdate: Bool = false
    var parentPhase: Phase?

    // ViewGraphOwner
    var currentTimestamp: Time = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0
    var viewGraph: ViewGraph { self as! ViewGraph }

    // Pending parity: display/update timers are simplified.
    // The current backend calls updateOutputs directly from WindowController.
    func startDisplayLink() {}
    func clearDisplayLink() {}
    func startUpdateTimer(delay: Double) {}
    func clearUpdateTimer() {}

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
            data.graph.inbox.drain()
            data.graph.drainActions()

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

    override init() { super.init() }

    override init(graph: AttributeGraph) { super.init(graph: graph) }
}

// ViewGraph - view-level AG host.
// This keeps the GraphHost, ViewGraphHost, ViewGraph hierarchy while being
// owned directly by WindowController. The initializer builds the root view
// output rule and captures the requested output attributes.
//
// GestureGraph ownership is shared with the renderer host for event dispatch.
class ViewGraph: ViewGraphHost {

    // Update scheduling callback.
    weak var viewDelegate: (any ViewGraphDelegate)?

    // AG transaction lifecycle callback.
    weak var graphDelegate: (any GraphDelegate)?

    // Outputs requested at init time.
    var requestedOutputs: Outputs

    // Back-reference to the owning ViewRendererHost. Gesture responders use
    // this to reach the shared gesture graph during view construction.
    weak var rendererHost: (any ViewRendererHost)?

    // AG input attributes updated by WindowController's root-value updater.
    private(set) var sizeAttr: Attribute<ViewSize>?
    private(set) var envAttr: Attribute<EnvironmentValues>?
    private(set) var timeAttr: Attribute<Time>?
    private(set) var phaseAttr: Attribute<Phase>?

    // AG output attributes collected after V._makeView.
    private(set) var rootAnyViewContentInput: Attribute<AnyView>?
    private(set) var rootLayoutComputer: Attribute<LayoutComputer>?
    private(set) var rootFittedSize: Attribute<CGSize>?
    private(set) var rootDisplayList: Attribute<DisplayList>?
    private(set) var rootResourceList: Attribute<ResourceList>?

    var isValid: Bool { rootLayoutComputer != nil }

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
        var time: Double = .infinity
        var interval: Double = .infinity
        var reasons: Set<UInt32> = []

        mutating func at(_ t: Double) { time = t }
        mutating func interval(_ dt: Double, reason: UInt32? = nil) {
            self.interval = dt
            if let r = reason { reasons.insert(r) }
        }
        mutating func maxVelocity(_ v: Double) {}  // Scheduling velocity is not modeled yet.
    }

    // Backend init that takes a concrete view value to lift into the graph.
    convenience init<V: View>(rootViewType: V.Type, content: V, rendererHost: any ViewRendererHost, requestedOutputs: Outputs = .defaults) {
        self.init(rootViewType: V.self, rendererHost: rendererHost, requestedOutputs: requestedOutputs) { g in
            _GraphValue<V>(_attribute: g.makeInput(value: content))
        }
    }

    convenience init<Content: View>(replaceableContent content: Content,
                                    rendererHost: any ViewRendererHost,
                                    requestedOutputs: Outputs = .defaults) {
        var contentAttr: Attribute<AnyView>?
        let erasedContent = AnyView(content)
        self.init(rootViewType: AnyView.self, rendererHost: rendererHost, requestedOutputs: requestedOutputs) { g in
            let attr: Attribute<AnyView> = g.makeInput(value: erasedContent)
            contentAttr = attr
            return _GraphValue<AnyView>(_attribute: attr)
        }
        self.rootAnyViewContentInput = contentAttr
    }

    // Cross-graph variant: content lives in a parent AG and is mirrored via crossGraphRef.
    // When parent state changes, parent contentAttr re-evaluates, the child inbox
    // is notified, and the child updates on its next updateOutputs. Caller must evaluate contentAttr in sourceGraph
    // first (call `_ = contentAttr.value`) so the crossGraphRef finds a non-nil cached value.
    convenience init(crossGraphContentAttr: Attribute<AnyView>, sourceGraph: AttributeGraph,
                     rendererHost: any ViewRendererHost, requestedOutputs: Outputs = .defaults) {
        self.init(rootViewType: AnyView.self, rendererHost: rendererHost, requestedOutputs: requestedOutputs) { g in
            _GraphValue<AnyView>(_attribute: g.makeCrossGraphRef(source: crossGraphContentAttr, in: sourceGraph))
        }
    }

    // Common designated init: `makeContent` is called inside data.withCurrent to produce the
    // root _GraphValue. The AttributeGraph passed is self.data.graph (child graph, current).
    private init<V: View>(rootViewType: V.Type, rendererHost: any ViewRendererHost,
                          requestedOutputs: Outputs,
                          makeContent: (AttributeGraph) -> _GraphValue<V>) {
        self.requestedOutputs = requestedOutputs
        super.init()
        // Wire rendererHost before _makeView so GestureResponder.init can read rendererHost?.gestureGraph.
        self.rendererHost = rendererHost
        let time = Time(seconds: 0)

        var sizeAttrResult:  Attribute<ViewSize>?          = nil
        var envAttrResult:   Attribute<EnvironmentValues>? = nil
        var timeAttrResult:  Attribute<Time>?              = nil
        var phaseAttrResult: Attribute<Phase>?             = nil
        var rootLCResult:    Attribute<LayoutComputer>?    = nil
        var rootSizeResult:  Attribute<CGSize>?            = nil
        var rootDLResult:    Attribute<DisplayList>?       = nil
        var rootRLResult:    Attribute<ResourceList>?      = nil

        self.data.withCurrent {
            let g = self.data.graph
            let contentGV = makeContent(g)

            let timeAttr        = g.makeInput(value: time)
            let phaseAttr       = g.makeInput(value: Phase())
            let transactionAttr = g.makeInput(value: Transaction())
            let envAttr         = g.makeInput(value: EnvironmentValues())
            let graphInputs = _GraphInputs(
                customInputs: PropertyList(),
                time: timeAttr,
                cachedEnvironment: MutableBox(CachedEnvironment(environment: envAttr)),
                phase: phaseAttr,
                transaction: transactionAttr,
                changedDebugProperties: 0,
                options: 0,
                mergedInputs: []
            )
            var prefKeys = PreferenceKeys()
            prefKeys.insert(DisplayList.Key.self)
            prefKeys.insert(ResourceList.Key.self)
            prefKeys.insert(ViewRespondersKey.self)
            prefKeys.insert(SheetPreference.Key.self)
            prefKeys.insert(AlertStorage.PreferenceKey.self)
            prefKeys.insert(ConfirmationDialog.PreferenceKey.self)

            let hostKeysAttr = g.makeInput(value: prefKeys)
            let prefsInputs  = PreferencesInputs(keys: prefKeys, hostKeys: hostKeysAttr)

            let transformAttr    = g.makeInput(value: ViewTransform.identity)
            let positionAttr     = g.makeInput(value: CGPoint.zero)
            let containerPosAttr = g.makeInput(value: CGPoint.zero)
            let sizeAttr         = g.makeInput(value: ViewSize(.zero))
            let viewInputs = _ViewInputs(
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

            // GestureResponder.init reads the shared gesture graph from ViewGraph.
            let outputs: _ViewOutputs = V._makeView(view: contentGV, inputs: viewInputs)

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
                let rootRespondersAttr: Attribute<[any ViewResponder]> = g.makeRule {
                    var combined: [any ViewResponder] = ViewRespondersKey.defaultValue
                    for nodeID in responderNodes {
                        let list = Attribute<[any ViewResponder]>(nodeID).value
                        ViewRespondersKey.reduce(value: &combined) { list }
                    }
                    return combined
                }
                g.makeSideEffectRule { [weak self] in
                    self?.rendererHost?.gestureGraph?.updateResponders(rootRespondersAttr.value)
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
                    let transaction = AttributeGraph.current?.transaction(for: sheetAttr.identifier) ?? Transaction()
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
            phaseAttrResult = phaseAttr
        }

        self.sizeAttr           = sizeAttrResult
        self.envAttr            = envAttrResult
        self.timeAttr           = timeAttrResult
        self.phaseAttr          = phaseAttrResult
        self.rootLayoutComputer = rootLCResult
        self.rootFittedSize     = rootSizeResult
        self.rootDisplayList    = rootDLResult
        self.rootResourceList   = rootRLResult
    }

    /// Updates host outputs, then refreshes the time input every frame.
    override func updateOutputs(at time: Time) {
        super.updateOutputs(at: time)
        data.withCurrent {
            timeAttr?.setValue(time)
        }
    }

    // Returns the current display list from the AG graph.
    func displayList() -> DisplayList? { rootDisplayList?.value }

    // Pending parity: route input events through GestureGraph.
    func sendEvents(_ events: [Any], rootNode: ResponderNode, at time: Time) {}
}
