//
//  File: ShapeStyledLeafView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol ShapeStyledLeafView: ContentResponder {
    associatedtype ShapeUpdateData

    static var animatesSize: Bool { get }

    func mustUpdate(
        data: ShapeUpdateData,
        position: Attribute<CGPoint>,
        environment: Attribute<EnvironmentValues>
    ) -> Bool

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect)

    static var hasBackground: Bool { get }

    func backgroundShape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect)

    func isClear(styles: _ShapeStyle_Pack) -> Bool
}

extension ShapeStyledLeafView {
    static var animatesSize: Bool { true }
    static var hasBackground: Bool { false }

    func backgroundShape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        (.empty, CGRect(origin: .zero, size: size))
    }

    func isClear(styles: _ShapeStyle_Pack) -> Bool {
        styles.isClear(name: .foreground) &&
            styles.isClear(name: .background)
    }

    func contains(
        points: UnsafeBufferPointer<CGPoint>,
        size: CGSize
    ) -> BitVector64 {
        let rendered: (
            shape: _ShapeStyle_RenderedShape.Shape,
            frame: CGRect
        )
        if Self.hasBackground {
            let background = backgroundShape(in: size)
            if case .empty = background.shape {
                rendered = shape(in: size)
            } else {
                rendered = background
            }
        } else {
            rendered = shape(in: size)
        }

        switch rendered.shape {
        case let .path(path, fillStyle):
            guard points.contains(where: rendered.frame.contains) else {
                return []
            }
            return path.contains(
                points: points,
                eoFill: fillStyle.isEOFilled,
                origin: rendered.frame.origin
            )
        case .text, .image, .empty:
            var result = BitVector64()
            for (index, point) in points.prefix(64).enumerated() {
                result[index] = rendered.frame.contains(point)
            }
            return result
        }
    }

    func contentPath(size: CGSize) -> Path {
        let rendered = shape(in: size)
        switch rendered.shape {
        case let .path(path, _):
            return path
        case .text, .image:
            return Path(rendered.frame)
        case .empty:
            return Path()
        }
    }

    static func makeLeafView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs,
        styles: Attribute<_ShapeStyle_Pack>,
        interpolatorGroup: _ShapeStyle_InterpolatorGroup?,
        data: ShapeUpdateData
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(self).makeLeafView called outside an active _AGGraph context."
            )
        }

        var outputs = _ViewOutputs()
        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value

        if inputs.preferences.keys.contains(DisplayList.Key.self) {
            let animatedSize = cachedEnvironment.animatedSize(for: inputs)
            let animatedPosition = cachedEnvironment.animatedPosition(for: inputs)
            cachedEnvironmentAttribute.value = cachedEnvironment

            var identityInputs = inputs
            let identity: _DisplayList_Identity
            if inputs.base.options.contains(.needsStableDisplayListIDs) {
                identity = identityInputs.pushIdentity()
            } else {
                identity = .none
            }

            let size = graph.subscriptNode(
                parent: inputs.size,
                keyPath: \ViewSize.value
            )
            let displayList = graph.makeStatefulRule(
                ShapeStyledDisplayList(
                    group: interpolatorGroup,
                    identity: identity,
                    _view: view._attribute,
                    _styles: styles,
                    _size: size,
                    _animatedSize: animatedSize,
                    _position: animatedPosition,
                    _containerPosition: inputs.containerPosition,
                    _transform: inputs.transform,
                    _environment: cachedEnvironment.environment,
                    _safeAreaInsets: inputs.safeAreaInsets,
                    options: inputs[DisplayList.Options.self],
                    data: data,
                    contentSeed: DisplayList.Seed()
                )
            )
            outputs.preferences.append(
                DisplayList.Key.self,
                node: displayList.identifier
            )
        }

        if inputs.preferences.keys.contains(ViewRespondersKey.self) {
            let size = cachedEnvironment.animatedSize(for: inputs)
            let position = cachedEnvironment.animatedPosition(for: inputs)
            cachedEnvironmentAttribute.value = cachedEnvironment
            let filter = ShapeStyledResponderFilter(
                _view: view._attribute,
                _styles: styles,
                _size: size,
                _position: position,
                _transform: inputs.transform,
                responder: LeafViewResponder()
            )
            let responders = graph.makeStatefulRule(filter)
            outputs.preferences.append(
                ViewRespondersKey.self,
                node: responders.identifier
            )
        }

        return outputs
    }
}

extension ShapeStyledLeafView where ShapeUpdateData == Void {
    func mustUpdate(
        data: Void,
        position: Attribute<CGPoint>,
        environment: Attribute<EnvironmentValues>
    ) -> Bool {
        false
    }

    static func makeLeafView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs,
        styles: Attribute<_ShapeStyle_Pack>,
        interpolatorGroup: _ShapeStyle_InterpolatorGroup?
    ) -> _ViewOutputs {
        makeLeafView(
            view: view,
            inputs: inputs,
            styles: styles,
            interpolatorGroup: interpolatorGroup,
            data: ()
        )
    }
}

private struct ShapeStyledDisplayList<Content: ShapeStyledLeafView>:
    StatefulRule {
    typealias Value = DisplayList

    var group: _ShapeStyle_InterpolatorGroup?
    var identity: _DisplayList_Identity
    var _view: Attribute<Content>
    var _styles: Attribute<_ShapeStyle_Pack>
    var _size: Attribute<CGSize>
    var _animatedSize: Attribute<ViewSize>
    var _position: Attribute<CGPoint>
    var _containerPosition: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    var _environment: Attribute<EnvironmentValues>
    var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>
    var options: DisplayList.Options
    var data: Content.ShapeUpdateData
    var contentSeed: DisplayList.Seed

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let viewChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_view.identifier)
        let positionChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_position.identifier)
        let containerPositionChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_containerPosition.identifier)

        let view = _view.value
        let mustUpdate = view.mustUpdate(
            data: data,
            position: _position,
            environment: _environment
        )
        let updateVersion = DisplayList.Version(forUpdate: ())
        if viewChanged || positionChanged || containerPositionChanged ||
            mustUpdate || contentSeed == DisplayList.Seed() {
            contentSeed = DisplayList.Seed(updateVersion)
        }

        let styles = _styles.value
        let size = Content.animatesSize
            ? _animatedSize.value.value
            : _size.value
        let position = _position.value
        let containerPosition = _containerPosition.value
        let origin = CGPoint(
            x: position.x - containerPosition.x,
            y: position.y - containerPosition.y
        )
        _ = _safeAreaInsets.attribute?.value

        var layers = _ShapeStyle_RenderedLayers(group: group)

        if Content.hasBackground {
            let background = view.backgroundShape(in: size)
            var renderedBackground = _ShapeStyle_RenderedShape(
                shape: background.shape.translated(by: origin),
                contentSeed: contentSeed,
                frame: background.frame.offsetBy(
                    dx: origin.x,
                    dy: origin.y
                ),
                identity: identity,
                version: updateVersion,
                options: options,
                environment: _environment
            )
            renderedBackground.renderItem(
                name: .background,
                styles: styles,
                layers: &layers
            )
        }

        let foreground = view.shape(in: size)
        var renderedForeground = _ShapeStyle_RenderedShape(
            shape: foreground.shape.translated(by: origin),
            contentSeed: contentSeed,
            frame: foreground.frame.offsetBy(
                dx: origin.x,
                dy: origin.y
            ),
            identity: identity,
            version: updateVersion,
            options: options,
            environment: _environment
        )
        renderedForeground.renderItem(
            name: .foreground,
            styles: styles,
            layers: &layers
        )
        _AGGraph.setStatefulOutput(
            layers.commit(shape: &renderedForeground)
        )
    }
}

struct _ShapeStyle_RenderedShape {
    struct LayerNeeds: OptionSet {
        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    enum Shape {
        case path(Path, FillStyle)
        case text(StyledTextContentView)
        case image(GraphicsContext.ResolvedImage, opacity: Double)
        case empty

        func translated(by offset: CGPoint) -> Self {
            guard offset != .zero else { return self }
            switch self {
            case let .path(path, fillStyle):
                return .path(
                    path.offsetBy(dx: offset.x, dy: offset.y),
                    fillStyle
                )
            case .text, .image, .empty:
                return self
            }
        }
    }

    var shape: Shape
    var contentSeed: DisplayList.Seed
    var frame: CGRect
    var interpolatorData: (
        group: DisplayList.InterpolatorGroup,
        serial: UInt32
    )?
    var item: DisplayList.Item
    var options: DisplayList.Options
    var _environment: Attribute<EnvironmentValues>
    var blendMode: GraphicsContext.BlendMode
    var opacity: Float
    var layerNeeds: LayerNeeds

    init(
        shape: Shape,
        contentSeed: DisplayList.Seed,
        frame: CGRect,
        identity: _DisplayList_Identity = .none,
        version: DisplayList.Version = DisplayList.Version(),
        options: DisplayList.Options,
        environment: Attribute<EnvironmentValues>
    ) {
        self.shape = shape
        self.contentSeed = contentSeed
        self.frame = frame
        self.interpolatorData = nil
        self.item = DisplayList.Item()
        self.item.identity = identity
        self.item.version = version
        self.options = options
        self._environment = environment
        self.blendMode = .normal
        self.opacity = 1
        self.layerNeeds = LayerNeeds()
    }

    mutating func renderItem(
        name: _ShapeStyle_Name,
        styles: _ShapeStyle_Pack,
        layers: inout _ShapeStyle_RenderedLayers
    ) {
        switch shape {
        case let .text(text):
            if text.text.needsStyledRendering {
                guard let style = styles.styles.first(where: {
                    $0.key.name == name && $0.key._level == 0
                })?.style else {
                    return
                }
                renderKeyedText(
                    text,
                    style: style,
                    name: name,
                    layers: &layers
                )
            } else {
                renderUnstyledText(text, layers: &layers)
            }
        case .image:
            renderUnstyledImage(layers: &layers)
        case .path:
            guard let style = styles.styles.first(where: {
                $0.key.name == name && $0.key._level == 0
            })?.style else {
                return
            }
            layers.beginLayer(
                id: .styled(name, 0),
                style: style,
                shape: &self
            )
            render(style: style)
            layers.endLayer(shape: &self)
        case .empty:
            break
        }
    }

    mutating func render(style: _ShapeStyle_Pack.Style) {
        precondition(
            style.effects.isEmpty,
            "Shape-style composited effects require their rendered-shape producer."
        )

        let shading: GraphicsContext.Shading
        switch style.fill {
        case let .color(color):
            shading = .color(Color(color))
        case let .paint(paint):
            if let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> {
                shading = .meshGradient(paint.paint.meshGradient)
            } else {
                shading = GraphicsContext.Shading(property: .resolvedPaint(
                    paint: paint, bounds: frame, opacity: 1
                ))
            }
        }

        var list = displayList(shading: shading)
        if style.opacity != 1 {
            var wrapped = DisplayList()
            wrapped.appendOpacityItem(
                bounds: list.interpolationBounds ?? frame,
                opacity: Double(style.opacity),
                contents: list
            )
            list = wrapped
        }
        if let blendMode = style._blend {
            guard let blendMode = BlendMode(graphicsContextMode: blendMode) else {
                preconditionFailure(
                    "The resolved shape style uses an unsupported blend mode."
                )
            }
            var wrapped = DisplayList()
            wrapped.appendBlendModeItem(
                bounds: list.interpolationBounds ?? frame,
                blendMode: blendMode,
                contents: list
            )
            list = wrapped
        }
        setItem(from: list)
    }

    mutating func commitItem() -> DisplayList.Item? {
        let hasItem: Bool
        if case .empty = item.value {
            hasItem = false
        } else {
            hasItem = true
        }

        let result: DisplayList.Item?
        if let interpolatorData {
            if hasItem {
                item.canonicalize(options: options)
                item.addEffect(.interpolatorLayer(
                    interpolatorData.group,
                    interpolatorData.serial
                ))
                item.canonicalize(options: options)
                result = item
            } else {
                result = DisplayList.Item(
                    effect: .interpolatorLayer(
                        interpolatorData.group,
                        interpolatorData.serial
                    ),
                    contents: DisplayList(),
                    frame: frame,
                    identity: item.identity,
                    version: item.version,
                    opacity: item.opacity
                )
            }
        } else {
            result = hasItem ? item : nil
        }

        self.interpolatorData = nil
        let identity = item.identity
        let version = item.version
        item = DisplayList.Item()
        item.identity = identity
        item.version = version
        blendMode = .normal
        opacity = 1
        layerNeeds = LayerNeeds()
        return result
    }

    func freshItemCopy() -> Self {
        var copy = self
        copy.interpolatorData = nil
        let identity = copy.item.identity
        let version = copy.item.version
        copy.item = DisplayList.Item()
        copy.item.identity = identity
        copy.item.version = version
        copy.blendMode = .normal
        copy.opacity = 1
        copy.layerNeeds = LayerNeeds()
        return copy
    }

    private mutating func renderUnstyledText(
        _ text: StyledTextContentView,
        layers: inout _ShapeStyle_RenderedLayers
    ) {
        layers.beginLayer(id: .unstyled, style: nil, shape: &self)

        if let resolvedText = text.text.resolvedText {
            let localFrame = text.text.frame(
                in: frame.size,
                renderer: text.renderer
            )
            let textFrame = localFrame.offsetBy(
                dx: frame.minX,
                dy: frame.minY
            )
            var list = DisplayList()
            list.appendTextItem(
                text,
                size: textFrame.size,
                foreground: resolvedText.shading,
                bounds: textFrame,
                displayBounds: frame,
                seed: contentSeed,
                version: item.version,
                environment: _environment.value.untrackedCopy()
            )
            setItem(from: list)
        }
        layers.endLayer(shape: &self)
    }

    private mutating func renderKeyedText(
        _ text: StyledTextContentView,
        style: _ShapeStyle_Pack.Style,
        name: _ShapeStyle_Name,
        layers: inout _ShapeStyle_RenderedLayers
    ) {
        layers.beginLayer(
            id: .styled(name, 0),
            style: style,
            shape: &self
        )
        render(style: style)
        layers.endLayer(shape: &self)
    }

    private mutating func renderUnstyledImage(
        layers: inout _ShapeStyle_RenderedLayers
    ) {
        guard case let .image(image, imageOpacity) = shape else {
            preconditionFailure("Unstyled image rendering requires image content.")
        }
        layers.beginLayer(id: .unstyled, style: nil, shape: &self)
        var list = DisplayList()
        list.appendImageItem(
            image,
            bounds: frame,
            opacity: Float(imageOpacity),
            version: item.version,
            environment: _environment.value.untrackedCopy()
        )
        setItem(from: list)
        layers.endLayer(shape: &self)
    }

    private func displayList(
        shading: GraphicsContext.Shading
    ) -> DisplayList {
        var list = DisplayList()
        switch shape {
        case let .path(path, fillStyle):
            list.appendShapeItem(
                path: path,
                role: .fill,
                style: AnyShapeStyle(shading),
                bounds: frame,
                fillStyle: fillStyle,
                environment: _environment.value.untrackedCopy()
            )
        case let .text(text):
            if let resolvedText = text.text.resolvedText {
                let localFrame = text.text.frame(
                    in: frame.size,
                    renderer: text.renderer
                )
                let textFrame = localFrame.offsetBy(
                    dx: frame.minX,
                    dy: frame.minY
                )
                list.appendTextItem(
                    text,
                    size: textFrame.size,
                    foreground: shading,
                    bounds: textFrame,
                    displayBounds: frame,
                    seed: contentSeed,
                    version: item.version,
                    environment: _environment.value.untrackedCopy()
                )
                _ = resolvedText
            }
        case .image(var image, let imageOpacity):
            image.shading = shading
            list.appendImageItem(
                image,
                bounds: frame,
                opacity: Float(imageOpacity),
                version: item.version,
                environment: _environment.value.untrackedCopy()
            )
        case .empty:
            break
        }
        return list
    }

    private mutating func setItem(from list: DisplayList) {
        let identity = item.identity
        let version = item.version
        switch list.items.count {
        case 0:
            item = DisplayList.Item()
        case 1:
            item = list.items[0]
        default:
            item = DisplayList.Item(
                effect: .identity,
                contents: list,
                frame: list.interpolationBounds ?? frame
            )
        }
        item.identity = identity
        item.version = version
    }
}

struct _ShapeStyle_RenderedLayers {
    enum Layers {
        case item(DisplayList.Item)
        case items([DisplayList.Item])
        case empty
    }

    var group: _ShapeStyle_InterpolatorGroup?
    var layers: Layers

    init(group: _ShapeStyle_InterpolatorGroup?) {
        self.group = group
        self.layers = .empty
    }

    mutating func beginLayer(
        id: _ShapeStyle_LayerID,
        style: _ShapeStyle_Pack.Style?,
        shape: inout _ShapeStyle_RenderedShape
    ) {
        guard let group else {
            return
        }

        while true {
            switch group.addLayer(id: id, style: style) {
            case let .direct(owner, serial):
                shape.interpolatorData = (owner, serial)
                return

            case let .replacement(retainedStyle, owner, serial):
                let requestedShape = shape
                shape = requestedShape.freshItemCopy()
                shape.interpolatorData = (owner, serial)
                if let retainedStyle {
                    shape.render(style: retainedStyle)
                }
                endLayer(shape: &shape)
                shape = requestedShape
            }
        }
    }

    mutating func endLayer(shape: inout _ShapeStyle_RenderedShape) {
        guard let item = shape.commitItem() else {
            return
        }
        switch layers {
        case .empty:
            layers = .item(item)
        case let .item(first):
            layers = .items([first, item])
        case var .items(items):
            items.append(item)
            layers = .items(items)
        }
    }

    mutating func commit(
        shape: inout _ShapeStyle_RenderedShape
    ) -> DisplayList {
        if let group {
            while let trailing = group.nextTrailingLayer() {
                var retired = shape.freshItemCopy()
                retired.interpolatorData = (
                    trailing.group,
                    trailing.serial
                )
                if let style = trailing.style {
                    retired.render(style: style)
                }
                endLayer(shape: &retired)
            }
            group.resetLayerCursor()
        }

        var result = DisplayList()
        switch layers {
        case let .item(item):
            result.items = [item]
            result.interpolationBounds = item.frame
        case let .items(items):
            result.items = items
            result.interpolationBounds = items.reduce(nil) { bounds, item in
                bounds.map { $0.union(item.frame) } ?? item.frame
            }
        case .empty:
            break
        }
        return result
    }
}

private extension AnyShapeStyle {
    init(_ shading: GraphicsContext.Shading) {
        self.init(_ShapeStyle_Shading(shading: shading))
    }
}

private struct _ShapeStyle_Shading: ShapeStyle, @unchecked Sendable {
    var shading: GraphicsContext.Shading

    func _apply(to shape: inout _ShapeStyle_Shape) {
        shape.resolvedShading = shading
    }
}

private extension BlendMode {
    init?(graphicsContextMode mode: GraphicsContext.BlendMode) {
        switch mode {
        case .normal: self = .normal
        case .multiply: self = .multiply
        case .screen: self = .screen
        case .overlay: self = .overlay
        case .darken: self = .darken
        case .lighten: self = .lighten
        case .colorDodge: self = .colorDodge
        case .colorBurn: self = .colorBurn
        case .softLight: self = .softLight
        case .hardLight: self = .hardLight
        case .difference: self = .difference
        case .exclusion: self = .exclusion
        case .hue: self = .hue
        case .saturation: self = .saturation
        case .color: self = .color
        case .luminosity: self = .luminosity
        case .sourceAtop: self = .sourceAtop
        case .destinationOver: self = .destinationOver
        case .destinationOut: self = .destinationOut
        case .plusDarker: self = .plusDarker
        case .plusLighter: self = .plusLighter
        default: return nil
        }
    }
}
