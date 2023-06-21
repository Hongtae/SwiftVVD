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

protocol ViewProxy: AnyObject {
    associatedtype Content: View
    var view: _GraphValue<Content> { get }

    func modifier<K>(key: K.Type) -> K? where K: ViewModifier
    func trait<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey

    var environmentValues: EnvironmentValues { get }
    var sharedContext: SharedContext { get }

    var frame: CGRect { get set }
    var spacing: ViewSpacing { get }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
    func dimensions(in proposal: ProposedViewSize) -> ViewDimensions
    func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize)
    func layoutSubviews()

    func update(tick: UInt64, delta: Double, date: Date)
    func draw(frame: CGRect, context: GraphicsContext)

    func updateEnvironment(_ environmentValues: EnvironmentValues)
}

extension ViewProxy {
    var spacing: ViewSpacing { .init() }

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

    func layoutSubviews() {
    }

    func update(tick: UInt64, delta: Double, date: Date) {
    }

    func draw(frame: CGRect, context: GraphicsContext) {
        // Log.err("Existential types must implement the draw() method themselves.")
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

class ViewContext<Content>: ViewProxy where Content: View {
    var view: _GraphValue<Content>
    var subviews: [any ViewProxy]
    var modifiers: [ObjectIdentifier: any ViewModifier]
    var traits: [ObjectIdentifier: Any]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext

    var frame: CGRect

    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?

    init(view: _GraphValue<Content>, inputs: _ViewInputs, outputs: _ViewListOutputs? = nil, layout: (any Layout)? = nil) {
        let modifiers = inputs.modifiers
        self.environmentValues = inputs.environmentValues
        self.view = self.environmentValues._resolve(view)
        self.modifiers = modifiers
        self.traits = inputs.traits
        self.sharedContext = inputs.sharedContext

        if let outputs {
            let viewOutputs = outputs.views.map {
                $0.view.makeView(graph: _Graph(), inputs: $0.inputs)
            }
            self.subviews = viewOutputs.compactMap {
                if case let .view(view) = $0.item { return view }
                return nil
            }
        } else {
            self.subviews = []
        }

        if let layout {
            self.layout = AnyLayout(layout)
        } else {
            self.layout = AnyLayout(_VStackLayout())
        }
        self.layoutCache = nil
        self.frame = .zero
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext) {
    }

    func draw(frame: CGRect, context: GraphicsContext) {
        self.drawBackground(frame: frame, context: context)

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
            view.draw(frame: view.frame, context: graphicsContext)
        }
        self.drawOverlay(frame: frame, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
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

    func layoutSubviews() {
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

    func modifier<K>(key: K.Type) -> K? where K: ViewModifier {
        modifiers[ObjectIdentifier(key)] as? K
    }

    func trait<Trait>(key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
        traits[ObjectIdentifier(key)] as? Trait.Value ?? Trait.defaultValue
    }

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
        //self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        self.subviews.forEach { $0.updateEnvironment(self.environmentValues) }
    }
}
