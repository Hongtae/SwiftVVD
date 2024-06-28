//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

protocol ViewLayer {
    func loadResources(_ context: GraphicsContext)
    func layout(frame: CGRect)
    func draw(frame: CGRect, context: GraphicsContext)
}

protocol ViewGenerator<Content> where Content : View {
    associatedtype Content
    var view: _GraphValue<Content> { get }
    func makeView(view: Content) -> ViewContext?
}

struct AnyViewGenerator {
    let generator: any ViewGenerator
    init(_ generator: any ViewGenerator) {
        self.generator = generator
    }
    func makeView(view: some View) -> ViewContext? {
        func make<T: ViewGenerator>(_ g: T, _ v: some View) -> ViewContext? {
            g.makeView(view: v as! T.Content)
        }
        return make(generator, view)
    }
}

class ViewContext {
    let keyPath: _GraphValue<Any>
    var modifiers: [any ViewModifier]
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var frame: CGRect
    var transform: AffineTransform = .identity
    var transformByRoot: AffineTransform = .identity
    var spacing: ViewSpacing

    var backgroundLayers: [ViewLayer]
    var overlayLayers: [ViewLayer]

    var foregroundStyle: (primary: AnyShapeStyle?,
                          secondary: AnyShapeStyle?,
                          tertiary: AnyShapeStyle?)

    var gestures: [_GraphValue<any Gesture>]
    var simultaneousGestures: [_GraphValue<any Gesture>]
    var highPriorityGestures: [_GraphValue<any Gesture>]

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    init<Content>(inputs: _GraphInputs, path: _GraphValue<Content>) where Content : View {
        self.keyPath = path.unsafeCast(to: Any.self)
        self.modifiers = []
        self.traits = [:]
        self.environmentValues = inputs.environment
        self.sharedContext = inputs.sharedContext

        self.frame = .zero
        self.spacing = .zero
        self.backgroundLayers = []
        self.overlayLayers = []

        self.gestures = []
        self.simultaneousGestures = []
        self.highPriorityGestures = []
    }

    func update(transform t: AffineTransform) {
        let local = AffineTransform(translationX: self.frame.minX, y: self.frame.minY)
        self.transformByRoot = t.concatenating(local)
    }

    func loadResources(_ context: GraphicsContext) {
        self.overlayLayers.forEach {
            $0.loadResources(context)
        }
        self.backgroundLayers.forEach {
            $0.loadResources(context)
        }
    }

    func trait<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
        traits[ObjectIdentifier(key)] as? Trait.Value ?? Trait.defaultValue
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
        self.overlayLayers.forEach { $0.layout(frame: self.frame) }
        self.backgroundLayers.forEach { $0.layout(frame: self.frame) }
    }

    func setLayoutProperties(_ properties: LayoutProperties) {
    }

    func layoutSubviews() {
    }

    func update(tick: UInt64, delta: Double, date: Date) {
    }

    var debugDraw = true
    func draw(frame: CGRect, context: GraphicsContext) {
        if debugDraw {
            var path = Path()
            let frame = frame.insetBy(dx: 1, dy: 1).standardized
            path.addRect(frame)
            path.move(to: CGPoint(x: frame.minX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            path.move(to: CGPoint(x: frame.maxX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
            context.stroke(path, with: .color(.blue.opacity(0.6)), lineWidth: 1.0)
        }
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
        self.backgroundLayers.reversed().forEach { layer in
            layer.draw(frame: frame, context: context)
        }
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext){
        self.overlayLayers.forEach { layer in
            layer.draw(frame: frame, context: context)
        }
    }

    final func drawView(frame: CGRect, context: GraphicsContext) {
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

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
        self.environmentValues = environmentValues._resolve(modifiers: modifiers)
    }
}

class GenericViewContext<Content> : ViewContext where Content : View {
    var view: Content
    var body: ViewContext

    init(view: Content, body: ViewContext, inputs: _GraphInputs, path: _GraphValue<Content>) {
        self.view = inputs.environment._resolve(view)
        self.body = body
        super.init(inputs: inputs, path: path)
        self.debugDraw = false
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

        var context = context
        context.environment = self.body.environmentValues
        self.body.drawView(frame: self.body.frame.standardized, context: context)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: self.frame.midX, y: self.frame.midY)
        let proposal = ProposedViewSize(width: self.frame.width, height: self.frame.height)
        self.body.place(at: center, anchor: .center, proposal: proposal)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let s1 = super.sizeThatFits(proposal)
        let s2 = self.body.sizeThatFits(proposal)
        return CGSize(width: max(s1.width, s2.width),
                      height: max(s1.height, s2.height))
    }

    struct Generator : ViewGenerator {
        let view: _GraphValue<Content>
        let body: any ViewGenerator
        var baseInputs: _GraphInputs
        var preferences: PreferenceInputs
        var traits: ViewTraitKeys = ViewTraitKeys()

        func makeView(view: Content) -> ViewContext? {
            func makeBody<T: ViewGenerator>(_ gen: T) -> ViewContext? {
                if let body = self.view.value(atPath: gen.view, from: view) {
                    return gen.makeView(view: body)
                }
                return nil
            }
            if let body = makeBody(self.body) {
                return GenericViewContext(view: view, body: body, inputs: baseInputs, path: self.view)
            }
            return nil
        }
    }
}

struct PrimitiveViewGenerator<Content> : ViewGenerator where Content: View {
    let view: _GraphValue<Content>
    var baseInputs: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()

    func makeView(view _: Content) -> ViewContext? {
        ViewContext(inputs: baseInputs, path: self.view)
    }
}
