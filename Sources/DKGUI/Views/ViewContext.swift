//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

enum DisplayScaleEnvironmentKey: EnvironmentKey {
    static var defaultValue: CGFloat { return 1 }
}

extension EnvironmentValues {
    public var displayScale: CGFloat {
        set { self[DisplayScaleEnvironmentKey.self] = newValue }
        get { self[DisplayScaleEnvironmentKey.self] }
    }
}

struct WeakObject<T: AnyObject> : Equatable {
    weak var value: T?
    static func == (a: Self, b: Self) -> Bool { a.value === b.value }

    init(_ value: T?) {
        self.value = value
    }
}

class SharedContext {
    var appContext: AppContext

    var window: Window?
    var commandQueue: CommandQueue? // render queue for window swap-chain

    var contentBounds: CGRect
    var contentScaleFactor: CGFloat
    var needsLayout: Bool

    var resourceData: [String: Data] = [:]
    var resourceObjects: [String: AnyObject] = [:]
    var cachedTypeFaces: [Font: TypeFace] = [:]

    var focusedViews: [Int: WeakObject<ViewProxy>] = [:]

    init(appContext: AppContext) {
        self.appContext = appContext
        self.contentBounds = .zero
        self.contentScaleFactor = 1
        self.needsLayout = true
    }

    func updateReferencedResourceObjects() {
        struct WeakWrapper {
            weak var value: AnyObject?
        }
        let weakMap = resourceObjects.mapValues {
            WeakObject<AnyObject>($0)
        }
        resourceObjects.removeAll()
        resourceObjects = weakMap.compactMapValues {
            $0.value
        }
    }

    func loadResourceData(name: String, bundle: Bundle?, cache: Bool) -> Data? {
        Log.debug("Loading resource: \(name)...")
        let bundle = bundle ?? Bundle.module
        var url: URL? = nil
        //TODO: check for Bundle.module crashes on Windows,Linux after Swift 5.8
#if os(macOS) || os(iOS)
        url = bundle.url(forResource: name, withExtension: nil)
#else
        url = bundle.bundleURL.appendingPathComponent(name)
#endif
        if let url {
            if let data = self.resourceData[url.path] {
                return data
            }
            do {
                Log.debug("Loading resource: \(url)")
                let data = try Data(contentsOf: url, options: [])
                if cache {
                    self.resourceData[url.path] = data
                }
                return data
            } catch {
                Log.error("Error on loading data: \(error)")
            }
        }
        Log.error("cannot load resource.")
        return nil
    }
}

private struct ResourceBundleKey: EnvironmentKey {
    static let defaultValue: Bundle? = nil
}

extension EnvironmentValues {
    public var resourceBundle: Bundle? {
        get { self[ResourceBundleKey.self] }
        set { self[ResourceBundleKey.self] = newValue }
    }
}

protocol ViewLayer {
    func load(context: GraphicsContext)
    func layout(frame: CGRect)
    func draw(frame: CGRect, context: GraphicsContext)
}

class ViewProxy {
    var modifiers: [any ViewModifier]
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var frame: CGRect
    var spacing: ViewSpacing
    var subviews: [ViewProxy]
    weak var superview: ViewProxy?

    var backgroundLayers: [ViewLayer]
    var overlayLayers: [ViewLayer]

    var foregroundStyle: (primary: AnyShapeStyle?,
                          secondary: AnyShapeStyle?,
                          tertiary: AnyShapeStyle?)

    var gestures: [any Gesture]
    var simultaneousGestures: [any Gesture]
    var highPriorityGestures: [any Gesture]

    init(inputs: _ViewInputs, subviews: [ViewProxy] = []) {
        self.subviews = subviews
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
        self.subviews.forEach { $0.superview = self }
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
        self.subviews.forEach {
            var context = context
            context.environment = $0.environmentValues
            $0.loadView(context: context)
        }
    }

    func trait<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
        traits[ObjectIdentifier(key)] as? Trait.Value ?? Trait.defaultValue
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let proposed =  proposal.replacingUnspecifiedDimensions()
        return subviews.reduce(proposed) {
            let size = $1.sizeThatFits(proposal)
            return CGSize(width: max($0.width, size.width),
                          height: max($0.height, size.height))
        }
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
        self.subviews.forEach {
            $0.setLayoutProperties(properties)
        }
    }

    func layoutSubviews() {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let proposal = ProposedViewSize(width: frame.width,
                                        height: frame.height)
        self.subviews.forEach {
            $0.place(at: center,
                     anchor: .center,
                     proposal: proposal)
        }
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

    func drawView(frame: CGRect, context: GraphicsContext) {
        self.drawBackground(frame: frame, context: context)
        self.draw(frame: frame, context: context)

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
            view.drawView(frame: view.frame, context: context)
        }
        self.drawOverlay(frame: frame, context: context)
    }

    func gestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        func makeHandler<T: Gesture>(_ gesture: T, inputs: _GestureInputs) -> _GestureHandler {
            T._makeGesture(gesture: _GraphValue(gesture), inputs: inputs).recognizer
        }

        let hpGestures = self.highPriorityGestures.compactMap {
            let handler = makeHandler($0, inputs: _GestureInputs())
            if handler.isValid { return handler }
            return nil
        }

        let viewGestures = self.gestures.compactMap {
            let handler = makeHandler($0, inputs: _GestureInputs())
            if handler.isValid { return handler }
            return nil
        }

        let simGestures = self.simultaneousGestures.compactMap {
            let handler = makeHandler($0, inputs: _GestureInputs())
            if handler.isValid { return handler }
            return nil
        }

        let subviewGestures = subviews.flatMap {
            let frame = $0.frame.standardized
            if frame.contains(location) {
                let locationInView = location - frame.origin
                return $0.gestureHandlers(at: locationInView)
            }
            return []
        }

        var outputs: [_GestureHandler] = []
        let isAcceptable = { type in
            for g in outputs {
                if g.shouldRequireFailure(of: type) == false {
                    return false
                }
            }
            return true
        }

        hpGestures.forEach {
            if isAcceptable($0.type) {
                outputs.append($0)
            }
        }
        subviewGestures.forEach {
            if isAcceptable($0.type) {
                outputs.append($0)
            }
        }
        viewGestures.forEach {
            if isAcceptable($0.type) {
                outputs.append($0)
            }
        }
        outputs.append(contentsOf: simGestures)
        outputs.forEach { $0.viewProxy = self }
        return outputs
    }

    func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
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
        //self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        self.subviews.forEach { $0.updateEnvironment(self.environmentValues) }
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

// _ViewProxyProvider is a View type that provides its own proxy instance.
protocol _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy
}

extension _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        fatalError("ViewProxy for \(Self.self) must be provided.")
    }
}

class ViewGroupProxy<Content>: ViewProxy where Content: View {
    var view: Content
    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?
    let layoutProperties: LayoutProperties

    init<L: Layout>(view: Content, inputs: _ViewInputs, subviews: [ViewProxy] = [], layout: L) {
        self.view = inputs.environmentValues._resolve(view)
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = L.layoutProperties
        super.init(inputs: inputs, subviews: subviews)

        defer {
            self.subviews.forEach {
                $0.setLayoutProperties(self.layoutProperties)
            }
        }
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
}
