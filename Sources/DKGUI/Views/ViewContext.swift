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
            WeakWrapper(value: $0)
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
    var resourceBundle: Bundle? {
        get { self[ResourceBundleKey.self] }
        set { self[ResourceBundleKey.self] = newValue }
    }
}

class ViewProxy {
    var modifiers: [ObjectIdentifier: any ViewModifier]
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var frame: CGRect
    var spacing: ViewSpacing
    var subviews: [ViewProxy]

    init(inputs: _ViewInputs, subviews: [ViewProxy] = []) {
        self.subviews = subviews
        self.modifiers = inputs.modifiers
        self.traits = inputs.traits
        self.environmentValues = inputs.environmentValues
        self.sharedContext = inputs.sharedContext
        self.frame = .zero
        self.spacing = .init()
    }

    func loadView(context: GraphicsContext) {
        self.subviews.forEach {
            var context = context
            context.environment = $0.environmentValues
            $0.loadView(context: context)
        }
    }

    func modifier<K>(key: K.Type) -> K? where K: ViewModifier {
        modifiers[ObjectIdentifier(key)] as? K
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
        let size = sizeThatFits(proposal)
        let offset = CGPoint(x: position.x - size.width * anchor.x,
                             y: position.y - size.height * anchor.y)

        self.frame = CGRect(origin: offset, size: size)
        self.layoutSubviews()
    }

    func setLayoutProperties(_: LayoutProperties) {
    }

    func layoutSubviews() {
        let proposal = ProposedViewSize(width: self.frame.width,
                                        height: self.frame.height)
        self.subviews.first?.place(at: .zero,
                                   anchor: .topLeading,
                                   proposal: proposal)
    }

    func update(tick: UInt64, delta: Double, date: Date) {
    }

    func draw(frame: CGRect, context: GraphicsContext) {
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext){
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
            var graphicsContext = context
            graphicsContext.environment = view.environmentValues
            view.drawView(frame: view.frame, context: graphicsContext)
        }
        self.drawOverlay(frame: frame, context: context)
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

// View must provide its own proxy instance.
protocol ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy
}

extension ViewProxyProvider {
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

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if self.subviews.count > 1 {

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
        } else if let first = self.subviews.first {
            return first.sizeThatFits(proposal)
        }
        return proposal.replacingUnspecifiedDimensions()
    }

    override func layoutSubviews() {
        let frame = self.frame.standardized
        guard frame.width > 0 && frame.height > 0 else { return }

        if self.subviews.count > 1 {
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
        } else if let first = self.subviews.first {
            first.place(at: .zero,
                        anchor: .topLeading,
                        proposal: ProposedViewSize(width: self.frame.width,
                                                   height: self.frame.height))
        }
    }
}
