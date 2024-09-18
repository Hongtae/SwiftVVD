//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

class AnyImageProviderBox {
    func makeTexture(_ context: GraphicsContext) -> Texture? {
        nil
    }

    var scaleFactor: CGFloat { 1 }

    func isEqual(to other: AnyImageProviderBox) -> Bool {
        return self === other
    }
}

class NamedImageProvider: AnyImageProviderBox {
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
        let bundle = self.location ?? .main
        if let url = bundle.url(forResource: self.name,
                                withExtension: nil,
                                subdirectory: nil) {

            let sharedContext = context.sharedContext
            if let texture = sharedContext.resourceObjects[url.absoluteString] as? Texture {
                self.scale = sharedContext.contentScaleFactor
                return texture
            }

            var image: DKGame.Image?
            do {
                Log.debug("url: \(url)")
                let data = try Data(contentsOf: url, options: [])
                image = data.withUnsafeBytes { ptr in
                    DKGame.Image(data: ptr)
                }
            } catch {
                Log.error("Error on loading data: \(error)")
            }
            if let texture = image?.makeTexture(commandQueue: context.commandQueue) {
                // cache
                sharedContext.resourceObjects[url.absoluteString] = texture
                self.scale = sharedContext.contentScaleFactor
                return texture
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

class RenderedImageProviderBox: AnyImageProviderBox {
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

class TextureImageProvider: AnyImageProviderBox {
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

class SymbolImageProvider: AnyImageProviderBox {
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

public struct Image: Equatable {
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
        let bundle = bundle ?? Image._mainNamedBundle ?? .main
        self.provider = NamedImageProvider(name: name, value: nil, location: bundle, label: nil)
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        let bundle = bundle ?? Image._mainNamedBundle ?? .main
        self.provider = NamedImageProvider(name: name, value: nil, location: bundle, label: label)
    }

    public static func == (lhs: Image, rhs: Image) -> Bool {
        lhs.provider.isEqual(to: rhs.provider)
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
        let generator = ImageViewContext.Generator(graph: view, baseInputs: inputs.base)
        return _ViewOutputs(view: generator)
    }

    public typealias Body = Never
}

extension Image {
    public static var _mainNamedBundle: Bundle?
}

extension Image: _PrimitiveView {
}

class ImageViewContext : ViewContext {
    var image: Image
    var resolvedImage: GraphicsContext.ResolvedImage?

    struct Generator : ViewGenerator {
        let graph: _GraphValue<Image>
        var baseInputs: _GraphInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                return ImageViewContext(view: view, inputs: baseInputs, graph: self.graph)
            }
            fatalError("Unable to recover view")
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            baseInputs.mergedInputs.append(inputs)
        }
    }

    init(view: Image, inputs: _GraphInputs, graph: _GraphValue<Image>) {
        self.image = view
        super.init(inputs: inputs, graph: graph)
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        self._validPath = false
        if graph.value(atPath: self.graph, from: encloser) is Image {
            self._validPath = true
            return true
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Image {
            self.image = view
        } else {
            fatalError("Unable to recover Image")
        }
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if let resolvedImage {
            return resolvedImage.size
        }
        return super.sizeThatFits(proposal)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        if self.frame.width > 0 && self.frame.height > 0 {
            if self.resolvedImage == nil {
                self.resolvedImage = context.resolve(self.image)
                self.sharedContext.needsLayout = true
            }
            if let resolvedImage {
                context.draw(resolvedImage, in: frame)
            }
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if self.frame.contains(location) {
            return self
        }
        return super.hitTest(location)
    }
}
