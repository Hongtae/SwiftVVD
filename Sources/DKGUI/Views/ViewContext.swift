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

    var resourceData: [String: Data] = [:]
    var resourceObjects: [String: AnyObject] = [:]
    var cachedTypeFaces: [Font: TypeFace] = [:]

    init(appContext: AppContext) {
        self.appContext = appContext
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
    var modifiers: [any ViewModifier] { get }
    var environmentValues: EnvironmentValues { get }
    var sharedContext: SharedContext { get }

    var layoutOffset: CGPoint { get }
    var layoutSize: CGSize { get }
    var contentScaleFactor: CGFloat { get }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
    func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat)
    func update(tick: UInt64, delta: Double, date: Date)
    func draw(frame: CGRect, context: GraphicsContext)
    func updateEnvironment(_ environmentValues: EnvironmentValues)
}

extension ViewProxy {
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: self.layoutSize)
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

extension ViewProxy {
    func trait<Trait>(_ key: Trait.Type) -> Trait.Value where Trait: _ViewTraitKey {
        for modifier in modifiers {
            if let trait = modifier as? _TraitWritingModifier<Trait> {
                return trait.value
            }
        }
        return Trait.defaultValue
    }
}

class ViewContext<Content>: ViewProxy where Content: View {
    var view: _GraphValue<Content>
    var subviews: [any ViewProxy]
    var modifiers: [any ViewModifier]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext

    var layoutOffset: CGPoint = .zero
    var layoutSize: CGSize = .zero
    var contentScaleFactor: CGFloat = 1

    init(view: _GraphValue<Content>, inputs: _ViewInputs, listOutputs: _ViewListOutputs) {
        let modifiers = inputs.modifiers
        self.environmentValues = inputs.environmentValues._resolve(modifiers: modifiers)
        self.view = self.environmentValues._resolve(view)
        self.modifiers = modifiers
        self.sharedContext = inputs.sharedContext

        self.subviews = []
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext) {
    }

    func draw(frame: CGRect, context: GraphicsContext) {
        self.drawBackground(frame: frame, context: context)

//        let drawSubview = true
//        if drawSubview {
//            let subviewFrame = CGRect(origin: subview.layoutOffset, size: subview.layoutSize)
//                .offsetBy(dx: frame.minX, dy: frame.minY)
//            var subviewContext = context
//            subviewContext.environment = subview.environmentValues
//            subviewContext.contentOffset += subview.layoutOffset
//            subview.draw(frame: subviewFrame, context: subviewContext)
//        }
        self.drawOverlay(frame: frame, context: context)
    }

    func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat) {
        self.layoutOffset = offset
        self.layoutSize = size
        self.contentScaleFactor = scaleFactor
//        self.subview.layout(offset: self.layoutOffset,
//                            size: self.layoutSize,
//                            scaleFactor: self.contentScaleFactor)
    }

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
        self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        self.subviews.forEach { $0.updateEnvironment(self.environmentValues) }
    }
}