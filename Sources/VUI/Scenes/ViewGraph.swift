//
//  File: ViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewGraphRootValues is the dirty bitmask for root values that need updating.
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

// ViewRenderingPhase is the current rendering phase of ViewGraph.
struct ViewRenderingPhase: Equatable, Hashable {
    var rawValue: UInt8
    init(rawValue: UInt8 = 0) { self.rawValue = rawValue }
}

// ViewGraphRenderContext is passed to ViewGraphRenderDelegate.updateRenderContext.
struct ViewGraphRenderContext {
    var contentsScale: CGFloat
    var opaqueBackground: Bool
}

// ViewGraphOwner owns a ViewGraph and tracks its update/render state.
protocol ViewGraphOwner: AnyObject {
    var viewGraph: ViewGraph { get }
    var currentTimestamp: Time { get set }
    var valuesNeedingUpdate: ViewGraphRootValues { get set }
    var renderingPhase: ViewRenderingPhase { get set }
    var externalUpdateCount: Int { get set }
}

// ViewRendererHost extends ViewGraphOwner with a responder tree root and gesture graph.
// WindowController conforms.
protocol ViewRendererHost: ViewGraphOwner {
    var responderNode: ResponderNode? { get }
    var gestureGraph: GestureGraph? { get }
}

// ViewGraphDelegate provides update scheduling callbacks for the view graph.
protocol ViewGraphDelegate: AnyObject {
    func setNeedsUpdate()
    func requestUpdate(after: Double)
    func `as`<T>(_ type: T.Type) -> T?
}

// ViewGraphHostDelegate provides the environment/inputs update hook for ViewGraphHost.
protocol ViewGraphHostDelegate: AnyObject {
    func updateGraphInputs(_ inputs: inout _GraphInputs)
}

// ViewGraphRenderDelegate is the rendering callback delegate.
protocol ViewGraphRenderDelegate: AnyObject {
    // The root object being rendered.
    var renderingRootView: AnyObject { get }

    func updateRenderContext(_ context: inout ViewGraphRenderContext)

    func withMainThreadRender(wasAsync: Bool, _ body: () -> Time) -> Time
    func renderIntervalForDisplayLink(timestamp: Time) -> Double
}

// ViewGraphRootValueUpdater notifies ViewGraph when root input values change.
protocol ViewGraphRootValueUpdater: AnyObject {
    // Pure required, no default implementation:
    func updateRootView()
    func updateEnvironment()
    func updateSize()
    func updateSafeArea()
    func updateContainerSize()

    // Required with default implementations:
    func updateTransform()
    func updateFocusStore()
    func updateFocusedItem()
    func updateFocusedValues()
    func updateAccessibilityEnvironment()
}

// ViewGraphHost is the intermediate base class between GraphHost and ViewGraph.
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

    // CADisplayLink will be used once implemented and is not used currently.
    func startDisplayLink() {}
    func clearDisplayLink() {}
    func startUpdateTimer(delay: Double) {}
    func clearUpdateTimer() {}

    /// Central entry point for the AG evaluation cycle.
    ///
    /// Flow:
    /// render loop -> WindowController.updateFrame -> viewGraph.updateOutputs
    func updateOutputs(at time: Time) {
        currentTimestamp = time

        let dirty = valuesNeedingUpdate
        valuesNeedingUpdate = []

        data.withCurrent {
            // Flush asynchronous invalidations from @State, @Observable, and similar sources.
            data.graph.inbox.drain()
            data.graph.drainActions()

            // Call updateDelegate methods according to the dirty bitmask.
            // Each method updates the corresponding ViewGraph input attribute with setValue.
            if dirty.contains(.rootView)      { updateDelegate?.updateRootView() }
            if dirty.contains(.environment)   { updateDelegate?.updateEnvironment() }
            if dirty.contains(.size)          { updateDelegate?.updateSize() }
            if dirty.contains(.safeArea)      { updateDelegate?.updateSafeArea() }
            if dirty.contains(.transform)     { updateDelegate?.updateTransform() }
            if dirty.contains(.focusStore)    { updateDelegate?.updateFocusStore() }
            if dirty.contains(.focusedItem)   { updateDelegate?.updateFocusedItem() }
            if dirty.contains(.focusedValues) { updateDelegate?.updateFocusedValues() }
            if dirty.contains(.containerSize) { updateDelegate?.updateContainerSize() }

            // ViewGraphHostDelegate.updateGraphInputs is called inside the AG rule update().
        }
    }

    override init() { super.init() }

    override init(graph: AttributeGraph) { super.init(graph: graph) }
}

// ViewGraph is the view-level AG host.
//
// ViewGraph.init registers (AGAttribute, _ViewInputs) -> _ViewOutputs as AG rule
// containing V._makeView.
// init also takes `content: V` to lift the AppGraph-side view into ownGraph.
//
// GestureGraph is owned here as part of the view graph event dispatch machinery.
class ViewGraph: ViewGraphHost {

    // viewDelegate is the update scheduling callback.
    weak var viewDelegate: (any ViewGraphDelegate)?

    // graphDelegate is the AG transaction lifecycle callback.
    weak var graphDelegate: (any GraphDelegate)?

    // requestedOutputs are the outputs requested at init time.
    var requestedOutputs: Outputs

    // rendererHost is a back-reference to the owning ViewRendererHost (WindowController).
    // GestureResponder.init uses viewGraph.rendererHost?.gestureGraph.
    weak var rendererHost: (any ViewRendererHost)?

    // AG input attributes updated by ViewGraphRootValueUpdater conformance on WindowController.
    private(set) var sizeAttr: Attribute<ViewSize>?
    private(set) var envAttr: Attribute<EnvironmentValues>?
    private(set) var timeAttr: Attribute<Time>?
    private(set) var phaseAttr: Attribute<Phase>?

    // AG output attributes collected after V._makeView.
    private(set) var rootLayoutComputer: Attribute<LayoutComputer>?
    private(set) var rootDisplayList: Attribute<DisplayList>?
    private(set) var rootResourceList: Attribute<ResourceList>?

    var isValid: Bool { rootLayoutComputer != nil }

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

    // NextUpdate is the update scheduling value type.
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

    // init: takes a concrete view value to lift into ownGraph.
    // AG wiring moved from WindowController.init.
    // GestureGraph owns an independent AG (NOT shared). GestureFilter nodes live in ViewGraph's AG.
    // GestureResponder.init gets gestureGraph from ViewGraph.rendererHost?.gestureGraph (via currentHost),
    // rendererHost must be set by caller (WindowController) before ViewGraph.init is called,
    // since _makeView may create GestureResponder nodes during the init body.
    init<V: View>(rootViewType: V.Type, content: V, rendererHost: any ViewRendererHost, requestedOutputs: Outputs = .defaults) {
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
        var rootDLResult:    Attribute<DisplayList>?       = nil
        var rootRLResult:    Attribute<ResourceList>?      = nil

        self.data.withCurrent {
            let g = self.data.graph
            // Lift the extracted content value into ownGraph as an input node.
            let contentAttr = g.makeInput(value: content)
            let contentGV   = _GraphValue<V>(_attribute: contentAttr)

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
            var prefKeys     = PreferenceKeys()
            prefKeys.insert(DisplayList.Key.self)
            prefKeys.insert(ResourceList.Key.self)
            prefKeys.insert(ViewRespondersKey.self)
            prefKeys.insert(SheetPreference.Key.self)

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

            // Run _makeView in ViewGraph's own AG context.
            // GestureResponder.init reads gestureGraph from ViewGraph (via currentHost cast),
            // not from AttributeGraphRef.current?.context. GestureFilter nodes are created in
            // ViewGraph's AG subgraph.
            let outputs: _ViewOutputs = V._makeView(view: contentGV, inputs: viewInputs)

            // Collect DisplayList and ResourceList nodes from preferences.
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

            // Wire ViewRespondersKey -> rendererHost?.gestureGraph.updateResponders.
            // Side-effect rule fires in ViewGraph AG context; gestureGraph is owned by rendererHost.
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

            // Wire SheetPreference.Key -> rendererHost.updateSheetPresentation.
            // Same side-effect rule pattern as ViewRespondersKey above.
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

            sizeAttrResult  = sizeAttr
            envAttrResult   = envAttr
            timeAttrResult  = timeAttr
            phaseAttrResult = phaseAttr
            rootLCResult    = outputs._layoutComputer.attribute
        }

        self.sizeAttr           = sizeAttrResult
        self.envAttr            = envAttrResult
        self.timeAttr           = timeAttrResult
        self.phaseAttr          = phaseAttrResult
        self.rootLayoutComputer = rootLCResult
        self.rootDisplayList    = rootDLResult
        self.rootResourceList   = rootRLResult
    }

    /// ViewGraph-level updateOutputs override: parent implementation plus timeAttr update.
    /// Time changes every frame, so it is always updated without a dirty bit.
    override func updateOutputs(at time: Time) {
        super.updateOutputs(at: time)
        data.withCurrent {
            timeAttr?.setValue(time)
        }
    }

    // displayList() returns the current display list from the AG graph.
    func displayList() -> DisplayList? { rootDisplayList?.value }

    // sendEvents dispatches input events through the responder tree.
    // TODO: implement proper event routing via GestureGraph
    func sendEvents(_ events: [Any], rootNode: ResponderNode, at time: Time) {}
}
