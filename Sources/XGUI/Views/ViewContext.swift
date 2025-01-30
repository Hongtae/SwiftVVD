//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// Class hierarchy
//
// ViewContext
// - PrimitiveViewContext (Body = Never)
// - GenericViewContext (Body : View)
// - DynamicViewContext (Optional<Body>)

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
    var inputs: _GraphInputs
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues {
        inputs.environment
    }
    var sharedContext: SharedContext {
        inputs.sharedContext
    }
    var frame: CGRect
    var transform: AffineTransform = .identity          // local transform
    var transformToRoot: AffineTransform = .identity    // local to root
    var spacing: ViewSpacing

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    unowned var superview: ViewContext?

    var transformToContainer: AffineTransform {         // local to container (superview)
        let local = self.transform
        let offset = AffineTransform(translationX: self.frame.minX, y: self.frame.minY)
        return local.concatenating(offset)
    }

    init(inputs: _GraphInputs) {
        self.traits = [:]
        self.frame = .zero
        self.spacing = .zero
        self.inputs = inputs.resolveMergedInputs()
        self._resolveGraphInputs()
    }

    deinit {
        assert(self.superview == nil)
    }

    func updateContent() {
        fatalError("Subclasses must override this method")
    }

    func value<T>(atPath graph: _GraphValue<T>) -> T? {
        fatalError("Subclasses must override this method")
    }

    var isValid: Bool {
        return false
    }

    @discardableResult
    func validate() -> Bool {
        return false
    }

    func invalidate() {
    }

    func merge(graphInputs inputs: _GraphInputs) {
        self.inputs.mergedInputs.append(inputs)
        self.inputs = self.inputs.resolveMergedInputs()
        self._resolveGraphInputs()
    }

    func reloadInputModifiers() {
        self.inputs.resetModifiers()
        self._resolveGraphInputs()
    }

    private func _resolveGraphInputs() {
        assert(self.inputs.mergedInputs.isEmpty)
        do {
            var modifiers = self.inputs.modifiers
            modifiers.indices.forEach { index in
                if modifiers[index].isResolved == false {
                    modifiers[index].resolve(containerView: self)
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
                    modifiers[index].resolve(containerView: self)
                }
            }
            self.inputs.viewStyleModifiers = modifiers
        }
    }

    func update(transform t: AffineTransform) {
        self.transformToRoot = self.transformToContainer.concatenating(t)
    }

    func update(tick: UInt64, delta: Double, date: Date) {
        assert(self.isValid)
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

    func multiViewForLayout() -> [ViewContext] {
        return [self]
    }

    func updateFrame() {
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

    func draw(frame: CGRect, context: GraphicsContext) {
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext){
    }

    var _debugDraw = false
    var _debugDrawShading: GraphicsContext.Shading = .color(.blue.opacity(0.6))

    func drawDebugFrame(frame: CGRect, context: GraphicsContext) {
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

    final func drawView(frame: CGRect, context: GraphicsContext) {
        var context = context
        context.environment = self.environmentValues

        self.drawDebugFrame(frame: frame, context: context)
        self.drawBackground(frame: frame, context: context)
        self.draw(frame: frame, context: context)
        self.drawOverlay(frame: frame, context: context)
    }

    struct GestureHandlerOutputs {
        let gestures: [_GestureHandler]
        let simultaneousGestures: [_GestureHandler]
        let highPriorityGestures: [_GestureHandler]
        func merge(_ other: GestureHandlerOutputs) -> GestureHandlerOutputs {
            .init(gestures: gestures + other.gestures,
                  simultaneousGestures: simultaneousGestures + other.simultaneousGestures,
                  highPriorityGestures: highPriorityGestures + other.highPriorityGestures)
        }
    }

    func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        GestureHandlerOutputs(gestures: [], simultaneousGestures: [], highPriorityGestures: [])
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
        return nil
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

class PrimitiveViewContext<Content> : ViewContext {
    let graph: _GraphValue<Content>
    var view: Content?

    init(graph: _GraphValue<Content>, inputs: _GraphInputs) {
        self.graph = graph
        super.init(inputs: inputs)
    }

    override var isValid: Bool {
        self.view != nil
    }

    override func invalidate() {
        self.view = nil
    }

    override func validate() -> Bool {
        isValid
    }

    final override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let view {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: view)
            }
        }
        if let superview {
            return superview.value(atPath: graph)
        }
        if let root = self.sharedContext.viewContentRoot {
            return root.graph.value(atPath: graph, from: root.value)
        }
        return nil
    }

    func updateView(_ view: inout Content) {
    }

    override func updateContent() {
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.updateView(&view)
            self.view = view
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }
}

class GenericViewContext<Content> : ViewContext {
    let graph: _GraphValue<Content>
    let body: ViewContext
    var view: Content?

    init(graph: _GraphValue<Content>, inputs: _GraphInputs, body: ViewContext) {
        self.graph = graph
        self.body = body
        super.init(inputs: inputs)
        body.superview = self
    }

    deinit {
        body.superview = nil
    }

    override var isValid: Bool {
        self.view != nil && body.isValid
    }

    override func validate() -> Bool {
        if self.view == nil {
            if value(atPath: self.graph) == nil {
                Log.error("View: \(self.graph.debugDescription) validation failed")
                return false
            }
            assert(body.superview === self)
        }
        return body.validate()
    }

    override func invalidate() {
        self.view = nil
        self.body.invalidate()
    }

    final override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let view {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: view)
            }
        }
        if let superview {
            return superview.value(atPath: graph)
        }
        if let root = self.sharedContext.viewContentRoot {
            return root.graph.value(atPath: graph, from: root.value)
        }
        return nil
    }

    func updateView(_ view: inout Content) {
    }

    override func updateContent() {
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.updateView(&view)
            self.view = view
            self.body.updateContent()
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }

    override func updateFrame() {
        self.body.updateFrame()
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.body.updateEnvironment(environmentValues)
    }

    override func merge(graphInputs inputs: _GraphInputs) {
        super.merge(graphInputs: inputs)
        body.merge(graphInputs: inputs)
    }

    override func update(transform t: AffineTransform) {
        super.update(transform: t)
        body.update(transform: self.transformToRoot)
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        body.update(tick: tick, delta: delta, date: date)
    }

    override func loadResources(_ context: GraphicsContext) {
        body.loadResources(context)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        body.sizeThatFits(proposal)
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        body.setLayoutProperties(properties)
    }

    override func layoutSubviews() {
        let frame = self.bounds
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let proposal = ProposedViewSize(width: frame.width, height: frame.height)
        body.place(at: center, anchor: .center, proposal: proposal)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        let width = body.frame.width
        let height = body.frame.height
        guard width > .ulpOfOne && height > .ulpOfOne else {
            return
        }

        let drawingFrame = body.frame.offsetBy(dx: frame.minX,
                                               dy: frame.minY)
        if frame.intersection(drawingFrame).isNull {
            return
        }
        body.drawView(frame: drawingFrame, context: context)
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)
        let local = location.applying(body.transformToContainer.inverted())
        return outputs.merge(body.gestureHandlers(at: local))
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.bounds.contains(location) {
            let frame = body.frame
            if frame.contains(location) {
                let local = location.applying(body.transformToContainer.inverted())
                if body.handleMouseWheel(at: local, delta: delta) {
                    return true
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        let local = location.applying(body.transformToContainer.inverted())
        if let view = body.hitTest(local) {
            return view
        }
        return super.hitTest(location)
    }
}

class DynamicViewContext<Content> : ViewContext {
    let graph: _GraphValue<Content>
    var view: Content?
    var body: ViewContext? {
        willSet {
            if let body, body !== newValue {
                assert(body.superview === self)
                body.superview = nil
            }
        }
        didSet {
            if let body, body.superview != nil {
                assert(body.superview === self)
            }
            body?.superview = self
        }
    }

    init(graph: _GraphValue<Content>, inputs: _GraphInputs) {
        self.graph = graph
        super.init(inputs: inputs)

        if let body {
            assert(body.superview == nil)
            body.superview = self
        }
    }

    deinit {
        self.body?.superview = nil
    }

    override var isValid: Bool {
        if self.view != nil {
            if let body {
                return body.isValid
            }
        }
        return false
    }

    override func validate() -> Bool {
        if self.view == nil {
            if value(atPath: self.graph) == nil {
                Log.error("View: \(self.graph.debugDescription) validation failed")
                return false
            }
        }
        if let body {
            assert(body.superview === self)
            return body.validate()
        }
        Log.error("View: \(self.graph.debugDescription) validation failed")
        return false
    }

    override func invalidate() {
        self.view = nil
        self.body?.invalidate()
        self.body = nil
    }

    final override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let view {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: view)
            }
        }
        if let superview {
            return superview.value(atPath: graph)
        }
        if let root = self.sharedContext.viewContentRoot {
            return root.graph.value(atPath: graph, from: root.value)
        }
        return nil
    }

    func updateView(_ view: inout Content) {
    }

    override func updateContent() {
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.updateView(&view)
            self.view = view
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }

    override func merge(graphInputs inputs: _GraphInputs) {
        super.merge(graphInputs: inputs)
        body?.merge(graphInputs: inputs)
    }

    override func update(transform t: AffineTransform) {
        self.transformToRoot = self.transformToContainer.concatenating(t)
        body?.update(transform: self.transformToRoot)
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        body?.update(tick: tick, delta: delta, date: date)
    }

    override func updateFrame() {
        body?.updateFrame()
    }

    override func loadResources(_ context: GraphicsContext) {
        body?.loadResources(context)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        body?.sizeThatFits(proposal) ?? .zero
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        self.body?.setLayoutProperties(properties)
    }

    override func layoutSubviews() {
        if let body {
            let frame = self.bounds
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let proposal = ProposedViewSize(width: frame.width, height: frame.height)
            body.place(at: center, anchor: .center, proposal: proposal)
        }
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        if let body {
            let width = body.frame.width
            let height = body.frame.height
            guard width > .ulpOfOne && height > .ulpOfOne else {
                return
            }

            let drawingFrame = body.frame.offsetBy(dx: frame.minX,
                                                   dy: frame.minY)
            if frame.intersection(drawingFrame).isNull {
                return
            }
            body.drawView(frame: drawingFrame, context: context)
        }
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)
        if let body {
            let local = location.applying(body.transformToContainer.inverted())
            return outputs.merge(body.gestureHandlers(at: local))
        }
        return outputs
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if let body {
            if self.bounds.contains(location) {
                let frame = body.frame
                if frame.contains(location) {
                    let local = location.applying(body.transformToContainer.inverted())
                    if body.handleMouseWheel(at: local, delta: delta) {
                        return true
                    }
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if let body {
            let local = location.applying(body.transformToContainer.inverted())
            if let view = body.hitTest(local) {
                return view
            }
        }
        return nil
    }
}
