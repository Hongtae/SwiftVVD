//
//  File: ViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Dirty bitmask for root values that need updating.
struct ViewGraphRootValues: OptionSet {
    let rawValue: UInt16

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

// Current rendering phase of ViewGraph.
struct ViewRenderingPhase: Equatable, Hashable {
    var rawValue: UInt8
    init(rawValue: UInt8 = 0) { self.rawValue = rawValue }
}

// Rendering context passed to ViewGraphRenderDelegate.updateRenderContext.
struct ViewGraphRenderContext {
    var contentsScale: CGFloat
    var opaqueBackground: Bool
}

// Owns a ViewGraph and tracks its update/render state.
protocol ViewGraphOwner: AnyObject {
    var viewGraph: ViewGraph { get }
    var currentTimestamp: Time { get set }
    var valuesNeedingUpdate: ViewGraphRootValues { get set }
    var renderingPhase: ViewRenderingPhase { get set }
    var externalUpdateCount: Int { get set }
}

// Extends ViewGraphOwner with a responder tree root and gesture graph.
protocol ViewRendererHost: ViewGraphOwner {
    var responderNode: ResponderNode? { get }
    var gestureGraph: GestureGraph? { get }
}

// Update scheduling callbacks for the view graph.
protocol ViewGraphDelegate: AnyObject {
    func setNeedsUpdate()
    func requestUpdate(after: Double)
    func `as`<T>(_ type: T.Type) -> T?
}

// Environment and inputs update hook for ViewGraphHost.
protocol ViewGraphHostDelegate: AnyObject {
    func updateGraphInputs(_ inputs: inout _GraphInputs)
}

// Rendering callback delegate.
protocol ViewGraphRenderDelegate: AnyObject {
    // The root object being rendered.
    var renderingRootView: AnyObject { get }

    func updateRenderContext(_ context: inout ViewGraphRenderContext)

    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time
    func renderIntervalForDisplayLink(timestamp: Time) -> Double
}

// Notifies ViewGraph when root input values change.
protocol ViewGraphRootValueUpdater: AnyObject {
    // Required values.
    func updateRootView()
    func updateEnvironment()
    func updateSize()
    func updateSafeArea()
    func updateContainerSize()

    // Optional values implemented by hosts as needed.
    func updateTransform()
    func updateFocusStore()
    func updateFocusedItem()
    func updateFocusedValues()
    func updateAccessibilityEnvironment()
}

// Intermediate base class between GraphHost and ViewGraph.
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

    // CADisplayLink will be used once implemented. It is not used currently.
    func startDisplayLink() {}
    func clearDisplayLink() {}
    func startUpdateTimer(delay: Double) {}
    func clearUpdateTimer() {}

    /// Central entry point for the AG evaluation cycle.
    ///
    /// Flow: render loop -> WindowController.updateFrame -> viewGraph.updateOutputs.
    func updateOutputs(at time: Time) {
        currentTimestamp = time

        let dirty = valuesNeedingUpdate
        valuesNeedingUpdate = []

        data.withCurrent {
            // Flush async invalidations from @State and @Observable.
            data.graph.inbox.drain()
            data.graph.drainActions()

            // Call updateDelegate methods for dirty root values.
            // Each method updates the corresponding ViewGraph input attribute.
            if dirty.contains(.rootView)      { updateDelegate?.updateRootView() }
            if dirty.contains(.environment)   { updateDelegate?.updateEnvironment() }
            if dirty.contains(.size)          { updateDelegate?.updateSize() }
            if dirty.contains(.safeArea)      { updateDelegate?.updateSafeArea() }
            if dirty.contains(.transform)     { updateDelegate?.updateTransform() }
            if dirty.contains(.focusStore)    { updateDelegate?.updateFocusStore() }
            if dirty.contains(.focusedItem)   { updateDelegate?.updateFocusedItem() }
            if dirty.contains(.focusedValues) { updateDelegate?.updateFocusedValues() }
            if dirty.contains(.containerSize) { updateDelegate?.updateContainerSize() }

            // ViewGraphHostDelegate.updateGraphInputs is called from the AG rule update path.
        }
    }

    override init() { super.init() }

    override init(graph: AttributeGraph) { super.init(graph: graph) }
}

// View-level AG host owned by WindowController.
class ViewGraph: ViewGraphHost {

    // Update scheduling callback.
    weak var viewDelegate: (any ViewGraphDelegate)?

    // AG transaction lifecycle callback.
    weak var graphDelegate: (any GraphDelegate)?

    // Outputs requested at init time.
    var requestedOutputs: Outputs

    // Back-reference to the owning ViewRendererHost.
    weak var rendererHost: (any ViewRendererHost)?

    // AG input attributes updated by ViewGraphRootValueUpdater.
    private(set) var sizeAttr: Attribute<ViewSize>?
    private(set) var envAttr: Attribute<EnvironmentValues>?
    private(set) var timeAttr: Attribute<Time>?
    private(set) var phaseAttr: Attribute<Phase>?

    // AG output attributes collected after V._makeView.
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
        mutating func maxVelocity(_ v: Double) {}  // TODO: implement
    }

    // Takes a concrete view value to lift into this graph.
    convenience init<V: View>(rootViewType: V.Type, content: V, rendererHost: any ViewRendererHost, requestedOutputs: Outputs = .defaults) {
        self.init(rootViewType: V.self, rendererHost: rendererHost, requestedOutputs: requestedOutputs) { g in
            _GraphValue<V>(_attribute: g.makeInput(value: content))
        }
    }

    // Cross-graph variant: content lives in a parent AG and is mirrored via crossGraphRef.
    // When parent @State changes, the parent contentAttr re-evaluates and notifies the child inbox.
    // The child then updates on its next updateOutputs pass. Caller must evaluate contentAttr in
    // sourceGraph first so the crossGraphRef finds a non-nil cached value.
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
            let phaseAttr       = g.makeInput(value: Phase(value: 1))
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
                containerSize: OptionalAttribute()
            )

            // GestureResponder.init reads gestureGraph from ViewGraph.
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
                    host.updateSheetPresentation(sheetAttr.value)
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

    /// ViewGraph-level updateOutputs override.
    /// time changes every frame, so it is updated without a dirty bit.
    override func updateOutputs(at time: Time) {
        super.updateOutputs(at: time)
        data.withCurrent {
            timeAttr?.setValue(time)
        }
    }

    // Returns the current display list from the AG graph.
    func displayList() -> DisplayList? { rootDisplayList?.value }

    // Dispatches input events through the responder tree.
    // TODO: implement proper event routing via GestureGraph (Phase 4)
    func sendEvents(_ events: [Any], rootNode: ResponderNode, at time: Time) {}
}
