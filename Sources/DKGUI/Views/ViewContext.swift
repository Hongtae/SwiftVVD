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
    func makeView(view: Content) -> ViewContext
}

struct AnyViewGenerator {
    let generator: any ViewGenerator
    init(_ generator: any ViewGenerator) {
        self.generator = generator
    }
    func makeView(view: some View) -> ViewContext {
        func make<T: ViewGenerator>(_ g: T, _ v: some View) -> ViewContext {
            g.makeView(view: v as! T.Content)
        }
        return make(generator, view)
    }
}

class ViewContext {
    let keyPath: any _GraphPath
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

    var gestures: [any Gesture]
    var simultaneousGestures: [any Gesture]
    var highPriorityGestures: [any Gesture]

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
    }

    init(inputs: _GraphInputs, path: any _GraphPath) {
        self.keyPath = path

        fatalError()
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

        self.frame = CGRect(origin: offset, size: size)
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

    func draw(frame: CGRect, context: GraphicsContext) {
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
        fatalError()
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
        self.view = view
        self.body = body
        super.init(inputs: inputs, path: path)
    }

    struct Generator : ViewGenerator {
        let view: _GraphValue<Content>
        let body: any ViewGenerator
        var baseInputs: _GraphInputs
        var preferences: PreferenceInputs
        var traits: ViewTraitKeys = ViewTraitKeys()

        func makeView(view: Content) -> ViewContext {
            func makeBody<T: ViewGenerator>(_ gen: T) -> ViewContext? {
                var body: Any? = view
                let b = self.view.trackRelativePaths(to: gen.view) {
                    body = body[keyPath: $0]
                }
                if (b) {
                    if let body = body as? T.Content {
                        return gen.makeView(view: body)
                    }
                }
                return nil
            }
            guard let body = makeBody(self.body) else {
                fatalError()
            }
            return GenericViewContext(view: view, body: body, inputs: baseInputs, path: self.view)
        }
    }
}

struct PrimitiveViewGenerator<Content> : ViewGenerator where Content: View {
    let view: _GraphValue<Content>
    var baseInputs: _GraphInputs
    var preferences: PreferenceInputs
    var traits: ViewTraitKeys = ViewTraitKeys()

    func makeView(view _: Content) -> ViewContext {
        ViewContext(inputs: baseInputs, path: self.view)
    }
}
