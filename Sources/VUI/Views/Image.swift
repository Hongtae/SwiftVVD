//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

class AnyImageProviderBox: @unchecked Sendable {
    func makeTexture(_ context: GraphicsContext) -> Texture? {
        nil
    }

    var scaleFactor: CGFloat { 1 }

    func isEqual(to other: AnyImageProviderBox) -> Bool {
        return self === other
    }

    @TaskLocal
    fileprivate static var _preferredBundle: Bundle?
}

final class NamedImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let name: String
    let value: Float?
    let location: Bundle?
    let label: Text?
    var scale: CGFloat = 1.0

    init(name: String, value: Float?, location: Bundle?, label: Text?) {
        self.name = name
        self.value = value
        self.location = location
        self.label = label
    }

    override var scaleFactor: CGFloat {
        self.scale
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        let bundles: [Bundle]
        if let location = self.location {
            bundles = [location]
        } else {
            bundles = [
                Self._preferredBundle,
                Image._mainNamedBundle,
                .main
            ].compactMap(\.self)
        }

        for bundle in bundles {
            if let url = bundle.url(forResource: self.name,
                                    withExtension: nil,
                                    subdirectory: nil) {

                let sceneResources = context.sceneResources
                if let texture = sceneResources.cachedTextures[url.absoluteString] as? Texture {
                    self.scale = sceneResources.contentScaleFactor
                    return texture
                }

                var image: VVD.Image?
                do {
                    Log.debug("url: \(url)")
                    let data = try Data(contentsOf: url, options: [])
                    image = data.withUnsafeBytes { ptr in
                        VVD.Image(data: ptr)
                    }
                } catch {
                    Log.error("Error on loading data: \(error)")
                }
                if let texture = image?.makeTexture(commandQueue: context.commandQueue) {
                    // cache
                    sceneResources.cachedTextures[url.absoluteString] = texture
                    self.scale = sceneResources.contentScaleFactor
                    return texture
                }
                Log.error("Failed to create texture from image at url: \(url)")
                return nil
            }
        }
        return nil
    }

    override func isEqual(to other: AnyImageProviderBox) -> Bool {
        if let other = other as? Self {
            return self.name == other.name &&
            self.value == other.value &&
            self.location == other.location &&
            self.label == other.label
        }
        return false
    }
}

final class RenderedImageProviderBox: AnyImageProviderBox, @unchecked Sendable {
    let size: CGSize
    let label: Text?
    let opaque: Bool
    let colorMode: ColorRenderingMode
    let renderer: (inout GraphicsContext)->Void
    init(size: CGSize, label: Text?, opaque: Bool, colorMode: ColorRenderingMode, renderer: @escaping (inout GraphicsContext) -> Void) {
        self.size = size
        self.label = label
        self.opaque = opaque
        self.colorMode = colorMode
        self.renderer = renderer
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        if var context = context.makeLayerContext(self.size) {
            renderer(&context)
            return context.backdrop
        }
        return nil
    }
}

final class TextureImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let texture: Texture
    let scale: CGFloat
    let orientation: Image.Orientation
    let label: Text?

    init(texture: Texture, scale: CGFloat, orientation: Image.Orientation, label: Text?) {
        self.texture = texture
        self.scale = scale
        self.orientation = orientation
        self.label = label
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        self.texture
    }

    override var scaleFactor: CGFloat {
        self.scale
    }

    override func isEqual(to: AnyImageProviderBox) -> Bool {
        if let other = to as? Self {
            return self.texture === other.texture &&
            self.scale == other.scale &&
            orientation == other.orientation &&
            label == other.label
        }
        return false
    }
}

final class SymbolImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let name: String
    let variableValue: Double?
    let bundle: Bundle?
    let label: Text?

    init(name: String, variableValue: Double?, bundle: Bundle?, label: Text?) {
        self.name = name
        self.variableValue = variableValue
        self.bundle = bundle
        self.label = label
    }
}

public struct Image: Equatable, Sendable {
    var provider: AnyImageProviderBox

    init(provider: AnyImageProviderBox) {
        self.provider = provider
    }

    public init(size: CGSize, label: Text? = nil, opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, renderer: @escaping (inout GraphicsContext) -> Void) {
        self.provider = RenderedImageProviderBox(size: size,
                                                 label: label,
                                                 opaque: opaque,
                                                 colorMode: colorMode,
                                                 renderer: renderer)
    }

    public init(_ name: String, bundle: Bundle? = nil) {
        self.provider = NamedImageProvider(name: name, value: nil, location: bundle, label: nil)
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self.provider = NamedImageProvider(name: name, value: nil, location: bundle, label: label)
    }

    public static func == (lhs: Image, rhs: Image) -> Bool {
        lhs.provider.isEqual(to: rhs.provider)
    }
}

extension Image {
    public struct DynamicRange: Hashable, Sendable {
        enum Storage: UInt8, Hashable, Sendable {
            case standard
            case constrainedHigh
            case high
        }

        var storage: Storage

        init(_ storage: Storage) {
            self.storage = storage
        }

        public static let standard = DynamicRange(.standard)
        public static let constrainedHigh = DynamicRange(.constrainedHigh)
        public static let high = DynamicRange(.high)
    }
}

extension Image {
    public enum Orientation: UInt8, CaseIterable, Hashable {
        case up
        case upMirrored
        case down
        case downMirrored
        case left
        case leftMirrored
        case right
        case rightMirrored
    }
}

extension Image {
    public init(_ texture: Texture, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) {
        self.provider = TextureImageProvider(texture: texture, scale: scale, orientation: orientation, label: label)
    }
    public init(decorative texture: Texture, scale: CGFloat, orientation: Image.Orientation = .up) {
        self.provider = TextureImageProvider(texture: texture, scale: scale, orientation: orientation, label: nil)
    }
}

extension Image {
    public init(systemName: String) {
        self.provider = SymbolImageProvider(name: systemName, variableValue: nil, bundle: nil, label: nil)
    }
    public init(systemName: String, variableValue: Double?) {
        self.provider = SymbolImageProvider(name: systemName, variableValue: variableValue, bundle: nil, label: nil)
    }
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.provider = SymbolImageProvider(name: name, variableValue: variableValue, bundle: bundle, label: nil)
    }
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil, label: Text) {
        self.provider = SymbolImageProvider(name: name, variableValue: variableValue, bundle: bundle, label: label)
    }
    public init(decorative name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.provider = SymbolImageProvider(name: name, variableValue: variableValue, bundle: bundle, label: nil)
    }
}

extension Image: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        // 1. Internal state nodes for communication between the resource and layout passes.
        // Caches the fully resolved image object (including GPU texture).
        let resolvedImageAttr = graph.makeInput(value: GraphicsContext.ResolvedImage?.none)

        let inbox = graph.inbox
        let sizeAttr = inputs.size
        let positionAttr = inputs.position
        let envAttr = inputs.base.cachedEnvironment.value.environment

        // 2. Resource pass (Resource Rule)
        // Evaluated before drawing (in updateView) to upload the image texture to the GPU.
        let resourceAttr: Attribute<ResourceList> = graph.makeRule {
            let image = view._attribute.value // Dependency: image provider changes

            // Optimization (Cache Hit): Return an empty list if the image is already cached.
            // Note: For a robust implementation, you might want to compare an image "version"
            // or use a caching mechanism within the ImageProvider.
            if resolvedImageAttr.value != nil {
                return ResourceList()
            }

            // If loading is required, create a new ResourceList(Task) to propagate upwards.
            let environment = envAttr.value
            let bundle = environment.resourceBundle  // Register AG dependency and capture for closure.
            let renderEnvironment = environment.untrackedCopy()
            var list = ResourceList()

            list.items.append { context in
                var context = context
                context.environment = renderEnvironment
                AnyImageProviderBox.$_preferredBundle.withValue(bundle) {
                    // 1. [Synchronous Loading] Resolve the image (loads data and creates texture).
                    let resolved = context.resolve(image)
                    let boxedResolved = UnsafeBox(resolved)

                    // 2. [State Invalidation] Notify completion and trigger a layout recomputation.
                    inbox.enqueue {
                        resolvedImageAttr.setValue(boxedResolved.value)
                    }
                } // withValue
            }

            return list
        }

        // 3. Layout pass (Layout Rule)
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            // Dependency: Re-evaluates when `inbox` updates these values from the Resource Rule.
            let resolved = resolvedImageAttr.value

            return LayoutComputer(
                sizeThatFits: { _ in resolved?.size ?? .zero }
            )
        }

        // 4. Drawing pass (DisplayList Rule)
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let _ = view._attribute.value // Dependency: image changes
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let resolved = resolvedImageAttr.value
            let environment = envAttr.value.untrackedCopy()

            var list = DisplayList()

            if let resolved = resolved {
                let frame = CGRect(origin: position, size: viewSize)
                list.appendImageItem(
                    resolved,
                    bounds: frame,
                    environment: environment
                )
            }
            return list
        }

        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(lcAttr)

        // 5. Propagate ResourceList and DisplayList upwards via the Preference channel!
        outputs.preferences.append(ResourceList.Key.self, node: resourceAttr.identifier)
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)

        return outputs
    }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }

    public typealias Body = Never
}

extension Image {
    static let _mainNamedBundle: Bundle? = .main
}

extension Image: PrimitiveView {
}
