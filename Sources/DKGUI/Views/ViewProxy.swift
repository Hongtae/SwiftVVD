//
//  File: ViewProxy.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

protocol ViewLayer {
    func load(context: GraphicsContext)
    func layout(frame: CGRect)
    func draw(frame: CGRect, context: GraphicsContext)
}

// _ViewProxyProvider is a View type that provides its own proxy instance.
protocol _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy
}

extension _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        fatalError("ViewProxy for \(Self.self) must be provided.")
    }
}

class ViewProxy {
    var modifiers: [any ViewModifier]
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var frame: CGRect
    var spacing: ViewSpacing
    weak var superview: ViewProxy?

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

    init(inputs: _ViewInputs) {
        self.superview = nil
        self.modifiers = inputs.modifiers
        self.traits = inputs.traits
        self.environmentValues = inputs.environmentValues
        self.sharedContext = inputs.sharedContext
        self.frame = .zero
        self.spacing = .init()

        self.backgroundLayers = inputs.backgroundLayers
        self.overlayLayers = inputs.overlayLayers

        self.foregroundStyle.primary = inputs.foregroundStyle.primary
        self.foregroundStyle.secondary = inputs.foregroundStyle.secondary
        self.foregroundStyle.tertiary = inputs.foregroundStyle.tertiary

        self.gestures = inputs.gestures
        self.simultaneousGestures = inputs.simultaneousGestures
        self.highPriorityGestures = inputs.highPriorityGestures

        Log.debug("ViewProxy initialized with modifiers: \(self.modifiers), traits: \(self.traits)")
    }

    var transformByRoot: AffineTransform {
        var t = AffineTransform(translationX: self.frame.minX, y: self.frame.minY)
        if let t2 = superview?.transformByRoot {
            t = t2.concatenating(t)
        }
        return t
    }

    func loadView(context: GraphicsContext) {
        self.overlayLayers.forEach {
            $0.load(context: context)
        }
        self.backgroundLayers.forEach {
            $0.load(context: context)
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
        self.gestures.compactMap {
            let handler = _makeGestureHandler($0, inputs: _GestureInputs(viewProxy: self))
            if handler.isValid { return handler }
            return nil
        }
    }

    final func makeGestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        let hpGestures = self.highPriorityGestures.compactMap {
            let handler = _makeGestureHandler($0, inputs: _GestureInputs(viewProxy: self))
            if handler.isValid { return handler }
            return nil
        }
        let simGestures = self.simultaneousGestures.compactMap {
            let handler = _makeGestureHandler($0, inputs: _GestureInputs(viewProxy: self))
            if handler.isValid { return handler }
            return nil
        }

        let viewGestures = self.gestureHandlers(at: location)

        var outputs: [_GestureHandler] = []
        var filter: _PrimitiveGestureTypes = .all

        hpGestures.forEach {
            filter = $0.setTypeFilter(filter)
            if $0.isValid { outputs.append($0) }
        }
        viewGestures.forEach {
            filter = $0.setTypeFilter(filter)
            if $0.isValid { outputs.append($0) }
        }
        outputs.append(contentsOf: simGestures)
        outputs.forEach { $0.viewProxy = self }
        return outputs
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

    func loadResourceData(name: String, cache: Bool) -> Data? {
        if let bundle = self.environmentValues.resourceBundle {
            if let data = self.sharedContext.loadResourceData(name: name, bundle: bundle, cache: cache) {
                return data
            }
        }
        return self.sharedContext.loadResourceData(name: name, bundle: nil, cache: cache)
    }
}

class GenericViewProxy : ViewProxy {
    var body: ViewProxy?

    init(inputs: _ViewInputs, body: ViewProxy?) {
        self.body = body
        super.init(inputs: inputs)

        self.body?.superview = self
    }

    override func loadView(context: GraphicsContext) {
        super.loadView(context: context)

        if let body {
            var context = context
            context.environment = body.environmentValues
            body.loadView(context: context)
        }
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.body?.updateEnvironment(self.environmentValues)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        if let body {
            let width = body.frame.width
            let height = body.frame.height
            guard width > 0 && height > 0 else {
                return
            }

            if frame.intersection(body.frame).isNull {
                return
            }
            var context = context
            context.environment = body.environmentValues
            body.drawView(frame: body.frame.standardized, context: context)
        }
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        self.body?.setLayoutProperties(properties)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = super.sizeThatFits(proposal)
        if let body {
            let s = body.sizeThatFits(proposal)
            return CGSize(width: max(size.width, s.width),
                          height: max(size.height, s.height))
        }
        return size
    }

    override func layoutSubviews() {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let proposal = ProposedViewSize(width: frame.width,
                                        height: frame.height)
        self.body?.place(at: center, anchor: .center, proposal: proposal)
    }

    override func gestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        var gestures: [_GestureHandler] = []
        if let body {
            let frame = body.frame.standardized
            if frame.contains(location) {
                let locationInView = location - frame.origin
                gestures = body.gestureHandlers(at: locationInView)
            }
        }
        gestures.append(contentsOf: super.gestureHandlers(at: location))
        return gestures
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.standardized.contains(location) {
            if let body {
                let frame = body.frame.standardized
                if frame.contains(location) {
                    let loc = location - frame.origin
                    if body.handleMouseWheel(at: loc, delta: delta) {
                        return true
                    }
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }
}

class TypedViewProxy<Content> : GenericViewProxy where Content: View {
    var view: Content

    init(view: Content, inputs: _ViewInputs, body: ViewProxy?) {
        self.view = view
        super.init(inputs: inputs, body: body)

        self.body?.superview = self
        self.installStateLocations()
    }

    func installStateLocations() {
        // install StoredLocation to all @State
        Log.debug("Install StoredLocation to all @State properties")
    }

    func reloadContent() {
        Log.debug("Reload-Content: View.body")
    }
}

class ViewGroupProxy<Content>: ViewProxy where Content: View {
    var view: Content
    var subviews: [ViewProxy]
    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?
    let layoutProperties: LayoutProperties

    init<L: Layout>(view: Content, inputs: _ViewInputs, subviews: [ViewProxy] = [], layout: L) {
        self.view = inputs.environmentValues._resolve(view)
        self.subviews = subviews
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = L.layoutProperties
        super.init(inputs: inputs)

        defer {
            self.subviews.forEach {
                $0.superview = self
                $0.setLayoutProperties(self.layoutProperties)
            }
        }
    }

    override func loadView(context: GraphicsContext) {
        super.loadView(context: context)

        self.subviews.forEach {
            var context = context
            context.environment = $0.environmentValues
            $0.loadView(context: context)
        }
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.subviews.forEach { $0.updateEnvironment(self.environmentValues) }
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if self.subviews.isEmpty == false {
            let subviews: [LayoutSubview] = self.subviews.map {
                LayoutSubview(view: $0)
            }
            let layoutSubviews = AnyLayout.Subviews(subviews: subviews, layoutDirection: .leftToRight)

            if var cache = self.layoutCache {
                self.layout.updateCache(&cache, subviews: layoutSubviews)
                self.layoutCache = cache
            } else {
                self.layoutCache = self.layout.makeCache(subviews: layoutSubviews)
            }
            if var cache = self.layoutCache {
                let ret = self.layout.sizeThatFits(proposal: proposal,
                                                   subviews: layoutSubviews,
                                                   cache: &cache)
                self.layoutCache = cache
                return ret
            }
        }
        return proposal.replacingUnspecifiedDimensions()
    }

    override func layoutSubviews() {
        let frame = self.frame.standardized
        guard frame.width > 0 && frame.height > 0 else { return }

        if self.subviews.isEmpty == false {
            let subviews: [LayoutSubview] = self.subviews.map {
                LayoutSubview(view: $0)
            }
            let layoutSubviews = AnyLayout.Subviews(subviews: subviews, layoutDirection: .leftToRight)

            if var cache = self.layoutCache {
                self.layout.updateCache(&cache, subviews: layoutSubviews)
                self.layoutCache = cache
            } else {
                self.layoutCache = self.layout.makeCache(subviews: layoutSubviews)
            }
            if var cache = self.layoutCache {
                let proposal = ProposedViewSize(frame.size)
                let size = self.layout.sizeThatFits(proposal: proposal,
                                                    subviews: layoutSubviews,
                                                    cache: &cache)
                let halign = self.layout.explicitAlignment(of: HorizontalAlignment.center,
                                                           in: frame,
                                                           proposal: proposal,
                                                           subviews: layoutSubviews,
                                                           cache: &cache)
                let valign = self.layout.explicitAlignment(of: VerticalAlignment.center,
                                                           in: frame,
                                                           proposal: proposal,
                                                           subviews: layoutSubviews,
                                                           cache: &cache)
                // TODO: calcuate alignment guide.
                self.layout.placeSubviews(in: frame,
                                          proposal: proposal,
                                          subviews: layoutSubviews,
                                          cache: &cache)
                self.layoutCache = cache
            } else {
                Log.error("Invalid layout cache")
            }
        }
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        self.subviews.forEach { view in
            let width = view.frame.width
            let height = view.frame.height
            guard width > 0 && height > 0 else {
                return
            }

            if frame.intersection(view.frame).isNull {
                return
            }
            var context = context
            context.environment = view.environmentValues
            view.drawView(frame: view.frame.standardized, context: context)
        }
    }

    override func gestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        var gestures = subviews.flatMap {
            let frame = $0.frame.standardized
            if frame.contains(location) {
                let locationInView = location - frame.origin
                return $0.gestureHandlers(at: locationInView)
            }
            return []
        }
        gestures.append(contentsOf: super.gestureHandlers(at: location))
        return gestures
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.standardized.contains(location) {
            for subview in subviews {
                let frame = subview.frame.standardized
                if frame.contains(location) {
                    let loc = location - frame.origin
                    if subview.handleMouseWheel(at: loc, delta: delta) {
                        return true
                    }
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }
}
