//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

protocol ViewGenerator<Content> {
    associatedtype Content
    var graph: _GraphValue<Content> { get }
    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext?
    mutating func mergeInputs(_ inputs: _GraphInputs)
}

extension ViewGenerator {
    var anyGraph: _GraphValue<Any> {
        self.graph.unsafeCast(to: Any.self)
    }
}

protocol ViewListGenerator {
    func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator]
    mutating func mergeInputs(_ inputs: _GraphInputs)
}

struct StaticViewListGenerator : ViewListGenerator {
    var viewList: [any ViewGenerator]
    func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
        viewList
    }
    mutating func mergeInputs(_ inputs: _GraphInputs) {
        viewList.indices.forEach { viewList[$0].mergeInputs(inputs) }
    }
}

struct DynamicViewListGenerator : ViewListGenerator {
    var viewList: [any ViewListGenerator]
    var mergedInputs: [_GraphInputs] = []
    func makeViewList<T>(encloser: T, graph: _GraphValue<T>) -> [any ViewGenerator] {
        viewList.flatMap {
            var list = $0.makeViewList(encloser: encloser, graph: graph)
            list.indices.forEach { index in
                mergedInputs.forEach { inputs in
                    list[index].mergeInputs(inputs)
                }
            }
            return list
        }
    }
    mutating func mergeInputs(_ inputs: _GraphInputs) {
        mergedInputs.append(inputs)
    }
}

extension ViewListGenerator where Self == StaticViewListGenerator {
    static func staticList(_ list: [any ViewGenerator]) -> StaticViewListGenerator {
        .init(viewList: list)
    }
    static var empty: StaticViewListGenerator {
        .staticList([])
    }
}

extension ViewListGenerator where Self == DynamicViewListGenerator {
    static func dynamicList(_ list: [any ViewListGenerator]) -> DynamicViewListGenerator {
        .init(viewList: list)
    }
}

public struct _ViewContextDebugDraw : EnvironmentKey {
    public static var defaultValue: Bool { false }
}

public extension EnvironmentValues {
    var _viewContextDebugDraw: Bool {
        get { self[_ViewContextDebugDraw.self] }
        set { self[_ViewContextDebugDraw.self] = newValue }
    }
}

class ViewContext {
    let graph: _GraphValue<Any>
    var inputs: _GraphInputs
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues {
        inputs.environment
    }
    var sharedContext: SharedContext {
        inputs.sharedContext
    }
    var frame: CGRect
    var transform: AffineTransform = .identity
    var transformByRoot: AffineTransform = .identity
    var spacing: ViewSpacing

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    init<Content>(inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.graph = graph.unsafeCast(to: Any.self)
        self.traits = [:]
        self.frame = .zero
        self.spacing = .zero
        self.inputs = inputs.resolveMergedInputs()
    }

    var _validPath = false
    func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        _validPath = false
        return _validPath
    }

    func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
    }

    func merge(graphInputs inputs: _GraphInputs) {
        self.inputs.mergedInputs.append(inputs)
        self.inputs = self.inputs.resolveMergedInputs()
    }

    func update(transform t: AffineTransform) {
        let local = AffineTransform(translationX: self.frame.minX, y: self.frame.minY)
        self.transformByRoot = t.concatenating(local)
    }

    func resolveGraphInputs<T>(encloser: T, graph: _GraphValue<T>) {
        assert(self.inputs.mergedInputs.isEmpty)
        do {
            var modifiers = self.inputs.modifiers
            modifiers.indices.forEach { index in
                if modifiers[index].isResolved == false {
                    modifiers[index].resolve(encloser: encloser, graph: graph)
                }
            }
            modifiers.forEach { modifier in
                if modifier.isResolved {
                    modifier.apply(inputs: &self.inputs)
                }
            }
            self.inputs.modifiers = modifiers
        }
        do {
            var modifiers = self.inputs.viewStyleModifiers
            modifiers.indices.forEach { index in
                if modifiers[index].isResolved == false {
                    modifiers[index].resolve(encloser: encloser, graph: graph)
                }
            }
            self.inputs.viewStyleModifiers = modifiers
        }
    }

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
        inputs.environment.values.merge(environmentValues.values) { $1 }
        inputs.modifiers.forEach {
            $0.apply(inputs: &inputs)
        }
    }

    func loadResources(_ context: GraphicsContext) {
    }

    func trait<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
        traits[ObjectIdentifier(key)] as? Trait.Value ?? Trait.defaultValue
    }

    func viewStyles() -> ViewStyles {
        var styles = ViewStyles()
        self.inputs.viewStyleModifiers.forEach { modifier in
            if modifier.isResolved {
                modifier.apply(to: &styles)
            }
        }
        return styles
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        ViewDimensions(width: self.frame.width, height: self.frame.height)
    }

    func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize) {
        //let size = proposal.replacingUnspecifiedDimensions()
        let size = sizeThatFits(proposal)
        let offset = CGPoint(x: position.x - size.width * anchor.x,
                             y: position.y - size.height * anchor.y)

        self.frame = CGRect(origin: offset, size: size).standardized
        self.layoutSubviews()
    }

    func setLayoutProperties(_ properties: LayoutProperties) {
    }

    func layoutSubviews() {
    }

    func update(tick: UInt64, delta: Double, date: Date) {
        assert(self._validPath)
    }

    var _debugDraw = true
    var _debugDrawShading: GraphicsContext.Shading = .color(.blue.opacity(0.6))
    func draw(frame: CGRect, context: GraphicsContext) {
        if _debugDraw && self.environmentValues._viewContextDebugDraw {
            var path = Path()
            let frame = frame.insetBy(dx: 1, dy: 1).standardized
            path.addRect(frame)
            path.move(to: CGPoint(x: frame.minX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            path.move(to: CGPoint(x: frame.maxX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
            context.stroke(path, with: _debugDrawShading, lineWidth: 1.0)
        }
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext){
    }

    final func drawView(frame: CGRect, context: GraphicsContext) {
        var context = context
        context.environment = self.environmentValues

        self.drawBackground(frame: frame, context: context)
        self.draw(frame: frame, context: context)
        self.drawOverlay(frame: frame, context: context)
    }

    func gestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        fatalError()
    }

    final func makeGestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        return []
    }

    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        return false
    }

    func setFocus(for deviceID: Int) {
        let vp = self.sharedContext.focusedViews.updateValue(WeakObject(self),
                                                             forKey: deviceID)?.value
        if let vp, vp !== self {
            vp.onLostFocus(for: deviceID)
        }
    }

    func hitTest(_ location: CGPoint) -> ViewContext? {
        nil
    }

    @discardableResult
    func releaseFocus(for deviceID: Int) -> Bool {
        if self.sharedContext.focusedViews[deviceID]?.value === self {
            self.sharedContext.focusedViews[deviceID] = nil
            return true
        }
        return false
    }

    func hasFocus(for deviceID: Int) -> Bool {
        self.sharedContext.focusedViews[deviceID]?.value === self
    }

    func onLostFocus(for deviceID: Int) {
    }

    func processKeyboardEvent(type: KeyboardEventType,
                              deviceID: Int,
                              key: VirtualKey,
                              text: String) -> Bool {
        false
    }
}

class GenericViewContext<Content> : ViewContext where Content : View {
    var view: Content
    var body: ViewContext

    init(view: Content, body: ViewContext, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.view = view
        self.body = body
        super.init(inputs: inputs, graph: graph)
        self._debugDraw = false
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        self._validPath = false
        if let value = graph.value(atPath: self.graph, from: encloser) as? Content {
            self._validPath = true
            return body.validatePath(encloser: value, graph: self.graph)
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Content {
            self.view = view
            body.updateContent(encloser: self.view, graph: self.graph)
        } else {
            fatalError("Unable to recover View")
        }
    }

    override func resolveGraphInputs<T>(encloser: T, graph: _GraphValue<T>) {
        super.resolveGraphInputs(encloser: encloser, graph: graph)
        self.view = inputs.environment._resolve(view)
        self.body.resolveGraphInputs(encloser: self.view, graph: self.graph)
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.view = inputs.environment._resolve(view)
        self.body.updateEnvironment(environmentValues)
    }

    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        self.body.loadResources(context)
    }

    override func update(transform t: AffineTransform) {
        super.update(transform: t)
        self.body.update(transform: t)
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        self.body.update(tick: tick, delta: delta, date: date)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        let width = self.body.frame.width
        let height = self.body.frame.height
        guard width > 0 && height > 0 else {
            return
        }
        if frame.intersection(self.body.frame).isNull {
            return
        }
        let frame = self.body.frame
        self.body.drawView(frame: frame, context: context)
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if let view = self.body.hitTest(location) {
            return view
        }
        return super.hitTest(location)
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        self.body.setLayoutProperties(properties)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: self.frame.midX, y: self.frame.midY)
        let proposal = ProposedViewSize(width: self.frame.width, height: self.frame.height)
        self.body.place(at: center, anchor: .center, proposal: proposal)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        self.body.sizeThatFits(proposal)
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.contains(location) {
            let frame = self.body.frame
            if frame.contains(location) {
                let loc = location - frame.origin
                if self.body.handleMouseWheel(at: loc, delta: delta) {
                    return true
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }

    struct Generator : ViewGenerator {
        let graph: _GraphValue<Content>
        var body: any ViewGenerator
        var baseInputs: _GraphInputs
//        var preferences: PreferenceInputs
//        var traits: ViewTraitKeys = ViewTraitKeys()

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                if let body = self.body.makeView(encloser: view, graph: self.graph) {
                    return GenericViewContext(view: view, body: body, inputs: baseInputs, graph: self.graph)
                }
            } else {
                fatalError("Unable to recover view")
            }
            return nil
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            self.baseInputs.mergedInputs.append(inputs)
            self.body.mergeInputs(inputs)
        }
    }
}

struct PrimitiveViewGenerator<Content> : ViewGenerator where Content: View {
    let graph: _GraphValue<Content>
    var baseInputs: _GraphInputs

    func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
        ViewContext(inputs: baseInputs, graph: self.graph)
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        baseInputs.mergedInputs.append(inputs)
    }
}
