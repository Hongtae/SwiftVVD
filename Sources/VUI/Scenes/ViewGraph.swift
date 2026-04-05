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

// ViewRendererHost — extends ViewGraphOwner with a responder tree root.
protocol ViewRendererHost: ViewGraphOwner {
    var responderNode: ResponderNode? { get }
}

// ViewGraphDelegate — update scheduling callbacks for the view graph.
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

    func updateOutputs(at time: Time) {
        // TODO: trigger AG evaluation cycle (Phase 4)
    }

    override init() { super.init() }
}

// ViewGraph — view-level AG host.
//
// ViewGraph.init registers (AGAttribute, _ViewInputs) -> _ViewOutputs as AG rule
// containing V._makeView.
// init also takes `content: V` to lift the AppGraph-side view into ownGraph.
//
// GestureGraph owned here — equivalent of ViewGraph's event dispatch machinery.
class ViewGraph: ViewGraphHost {

    // viewDelegate — update scheduling callback.
    weak var viewDelegate: (any ViewGraphDelegate)?

    // graphDelegate — AG transaction lifecycle callback.
    weak var graphDelegate: (any GraphDelegate)?

    // requestedOutputs — outputs requested at init time.
    var requestedOutputs: Outputs

    // gestureGraph — gesture routing (replaces ViewGraph.sendEvents + EventBindingManager).
    let gestureGraph: GestureGraph

    // AG input attributes — updated by ViewGraphRootValueUpdater conformance on WindowController.
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
    // Uses GraphHost.data (AttributeGraph created by super.init()) as the owned graph.
    init<V: View>(rootViewType: V.Type, content: V, requestedOutputs: Outputs = .defaults) {
        self.requestedOutputs = requestedOutputs
        self.gestureGraph = GestureGraph()
        super.init()

        let gestureGraph = self.gestureGraph
        let time = Time(seconds: 0)

        var sizeAttrResult:  Attribute<ViewSize>?          = nil
        var envAttrResult:   Attribute<EnvironmentValues>? = nil
        var timeAttrResult:  Attribute<Time>?              = nil
        var phaseAttrResult: Attribute<Phase>?             = nil
        var rootLCResult:    Attribute<LayoutComputer>?    = nil
        var rootDLResult:    Attribute<DisplayList>?       = nil
        var rootRLResult:    Attribute<ResourceList>?      = nil

        AttributeGraph.$current.withValue(self.data) {
            // Lift the extracted content value into ownGraph as an input node.
            let contentAttr = self.data.makeInput(value: content)
            let contentGV   = _GraphValue<V>(_attribute: contentAttr)

            let timeAttr        = self.data.makeInput(value: time)
            let phaseAttr       = self.data.makeInput(value: Phase(value: 1))
            let transactionAttr = self.data.makeInput(value: Transaction())
            let envAttr         = self.data.makeInput(value: EnvironmentValues())
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

            let hostKeysAttr = self.data.makeInput(value: prefKeys)
            let prefsInputs  = PreferencesInputs(keys: prefKeys, hostKeys: hostKeysAttr)

            let transformAttr    = self.data.makeInput(value: ViewTransform.identity)
            let positionAttr     = self.data.makeInput(value: CGPoint.zero)
            let containerPosAttr = self.data.makeInput(value: CGPoint.zero)
            let sizeAttr         = self.data.makeInput(value: ViewSize(.zero))
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

            let outputs: _ViewOutputs = GestureGraph.$_current.withValue(gestureGraph) {
                V._makeView(view: contentGV, inputs: viewInputs)
            }

            // Collect DisplayList and ResourceList nodes from preferences.
            let resourceNodes = outputs.preferences.values(for: ResourceList.Key.self)
            let displayNodes  = outputs.preferences.values(for: DisplayList.Key.self)

            if !resourceNodes.isEmpty {
                rootRLResult = self.data.makeRule {
                    var combined = ResourceList.Key.defaultValue
                    for nodeID in resourceNodes {
                        let list = Attribute<ResourceList>(nodeID).value
                        ResourceList.Key.reduce(value: &combined) { list }
                    }
                    return combined
                }
            }
            if !displayNodes.isEmpty {
                rootDLResult = self.data.makeRule {
                    var combined = DisplayList.Key.defaultValue
                    for nodeID in displayNodes {
                        let list = Attribute<DisplayList>(nodeID).value
                        DisplayList.Key.reduce(value: &combined) { list }
                    }
                    return combined
                }
            }

            // Wire ViewRespondersKey to gestureGraph.
            let responderNodes = outputs.preferences.values(for: ViewRespondersKey.self)
            if !responderNodes.isEmpty {
                let rootRespondersAttr: Attribute<[any ViewResponder]> = self.data.makeRule {
                    var combined: [any ViewResponder] = ViewRespondersKey.defaultValue
                    for nodeID in responderNodes {
                        let list = Attribute<[any ViewResponder]>(nodeID).value
                        ViewRespondersKey.reduce(value: &combined) { list }
                    }
                    return combined
                }
                let gg = gestureGraph
                self.data.makeSideEffectRule {
                    gg.updateResponders(rootRespondersAttr.value)
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

    // displayList() — returns the current display list from the AG graph.
    func displayList() -> DisplayList? { rootDisplayList?.value }

    // sendEvents — dispatches input events through the responder tree.
    // TODO: implement proper event routing via GestureGraph
    func sendEvents(_ events: [Any], rootNode: ResponderNode, at time: Time) {}
}
