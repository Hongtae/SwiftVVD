//
//  File: DisplayList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Ordered collection of rendering commands produced by the view tree.
// Propagated to the scene root via the DisplayList.Key preference.
// TODO: Replace closure-backed draw bodies with backend commands as typed coverage is proven.
struct DisplayList {
    struct Version {
        let value: Int
    }

    // Compact change token used by interpolation groups to detect display-list content updates.
    struct Seed: Equatable, Hashable {
        private(set) var value: UInt16

        init() {
            self.value = 0
        }

        init(decodedValue: UInt16) {
            self.value = decodedValue
        }

        init(_ version: Version) {
            let bits = UInt(bitPattern: version.value)
            guard bits != 0 else {
                self.value = 0
                return
            }

            let high = UInt32(truncatingIfNeeded: bits >> 16)
            let low = UInt32(truncatingIfNeeded: bits)
            let mixed = (high &+ (high << 5)) ^ low
            self.value = UInt16(truncatingIfNeeded: (mixed << 1) | 1)
        }

        mutating func invalidate() {
            guard value != 0 else { return }
            value = (~value) | 1
        }

        static var undefined: Seed {
            Seed(decodedValue: 2)
        }
    }

    // Renderer-side metadata attached to a display list for state, content transitions, and
    // interpolator group routing.
    enum Effect {
        case state(StrongHash)
        case contentTransition(ContentTransition.State)
        case interpolatorRoot(InterpolatorGroup, CGPoint, CGSize)
        case interpolatorLayer(InterpolatorGroup, UInt32)
        case interpolatorAnimation(InterpolatorAnimation)
    }

    // Effect wrapper that keeps the original display-list contents with the effect marker.
    struct EffectItem {
        var effect: Effect
        var contents: DisplayList
    }

    // Backend-local style metadata recorded on the display list before exact private style
    // storage and renderer lowering exist.
    enum StyleCommand: Equatable {
        struct AnimationStyle: Equatable {
            static let defaultFlags: UInt32 = 0x111

            var animation: RBAnimation
            var id: UUID?
            var flags: UInt32

            init(
                animation: RBAnimation,
                id: UUID?,
                flags: UInt32
            ) {
                self.animation = animation.copy() as? RBAnimation ?? RBAnimation()
                self.id = id
                self.flags = flags
            }

            static func == (lhs: AnimationStyle, rhs: AnimationStyle) -> Bool {
                lhs.animation.isEqual(rhs.animation) &&
                    lhs.id == rhs.id &&
                    lhs.flags == rhs.flags
            }
        }

        case animation(AnimationStyle)
    }

    // Lightweight render-item summary used by interpolation before backend typed
    // commands replace closure-backed drawing.
    struct ItemRecord: Equatable {
        enum Kind: UInt8, Equatable {
            case closure
            case shapeFill
            case shapeStroke
            case shapeSeparator
            case image
            case text
            case custom
            case effect
            case debug
        }

        enum EffectKind: UInt8, Equatable {
            case generic
            case opacity
            case blur
            case geometry
            case crossFade
            case blendMode
            case shadow
            case colorFilter
        }

        enum ShapeStyleRecord: Equatable {
            case color(Color)
            case gradient(Gradient)
        }

        enum ShadingRecord: Equatable {
            case color(Color)
        }

        struct ImageRecord: Equatable {
            var baseline: CGFloat
            var textureID: ObjectIdentifier?
            var textureTransform: CGAffineTransform
            var scaleFactor: CGFloat
            var hasShading: Bool
            var shading: ShadingRecord?

            init(
                baseline: CGFloat,
                textureID: ObjectIdentifier?,
                textureTransform: CGAffineTransform,
                scaleFactor: CGFloat,
                hasShading: Bool,
                shading: ShadingRecord?
            ) {
                self.baseline = baseline
                self.textureID = textureID
                self.textureTransform = textureTransform
                self.scaleFactor = scaleFactor
                self.hasShading = hasShading
                self.shading = shading
            }

            init(
                _ image: GraphicsContext.ResolvedImage,
                shading: ShadingRecord?
            ) {
                baseline = image.baseline
                textureID = image.texture.map { ObjectIdentifier($0) }
                textureTransform = image.textureTransform
                scaleFactor = image.scaleFactor
                hasShading = image.shading != nil
                self.shading = shading
            }
        }

        struct TextRecord: Equatable {
            var foreground: ShadingRecord?
        }

        struct CustomRecord: Equatable {
            var isOpaque: Bool
            var colorMode: ColorRenderingMode
            var rendersAsynchronously: Bool
        }

        struct ShadowRecord: Equatable {
            var color: Color.Resolved
            var radius: CGFloat
            var offset: CGSize
            var blendModeRawValue: Int32
            var optionsRawValue: UInt32
        }

        enum ColorFilterKind: UInt8, Equatable {
            case colorMultiply
            case hueRotation
            case saturation
            case brightness
            case contrast
            case colorInvert
            case grayscale
            case luminanceToAlpha
            case colorMatrix
        }

        struct ColorFilterRecord: Equatable {
            var kind: ColorFilterKind
            var amount: Double
            var color: Color.Resolved?
            var matrix: ColorMatrix?

            init(
                kind: ColorFilterKind,
                amount: Double,
                color: Color.Resolved? = nil,
                matrix: ColorMatrix? = nil
            ) {
                self.kind = kind
                self.amount = amount
                self.color = color
                self.matrix = matrix
            }
        }

        var kind: Kind
        var effectKind: EffectKind?
        var bounds: CGRect?
        var shapeStyle: ShapeStyleRecord?
        var fillStyle: FillStyle?
        var strokeStyle: StrokeStyle?
        var image: ImageRecord?
        var text: TextRecord?
        var custom: CustomRecord?
        var opacity: Double?
        var blurRadius: CGFloat?
        var blurIsOpaque: Bool?
        var affineTransform: CGAffineTransform?
        var sourceFraction: Float?
        var targetFraction: Float?
        var blendMode: BlendMode?
        var shadow: ShadowRecord?
        var colorFilter: ColorFilterRecord?

        init(
            kind: Kind,
            bounds: CGRect? = nil,
            effectKind: EffectKind? = nil,
            shapeStyle: ShapeStyleRecord? = nil,
            fillStyle: FillStyle? = nil,
            strokeStyle: StrokeStyle? = nil,
            image: ImageRecord? = nil,
            text: TextRecord? = nil,
            custom: CustomRecord? = nil,
            opacity: Double? = nil,
            blurRadius: CGFloat? = nil,
            blurIsOpaque: Bool? = nil,
            affineTransform: CGAffineTransform? = nil,
            sourceFraction: Float? = nil,
            targetFraction: Float? = nil,
            blendMode: BlendMode? = nil,
            shadow: ShadowRecord? = nil,
            colorFilter: ColorFilterRecord? = nil
        ) {
            self.kind = kind
            self.effectKind = kind == .effect ? effectKind ?? .generic : nil
            self.bounds = bounds
            if kind == .shapeFill || kind == .shapeStroke || kind == .shapeSeparator {
                self.shapeStyle = shapeStyle
            } else {
                self.shapeStyle = nil
            }
            if kind == .shapeFill || kind == .shapeSeparator {
                self.fillStyle = fillStyle
            } else {
                self.fillStyle = nil
            }
            if kind == .shapeStroke {
                self.strokeStyle = strokeStyle
            } else {
                self.strokeStyle = nil
            }
            if kind == .image {
                self.image = image
            } else {
                self.image = nil
            }
            if kind == .text {
                self.text = text
            } else {
                self.text = nil
            }
            if kind == .custom {
                self.custom = custom
            } else {
                self.custom = nil
            }
            if kind == .effect && effectKind == .opacity {
                self.opacity = opacity
            } else {
                self.opacity = nil
            }
            if kind == .effect && effectKind == .blur {
                self.blurRadius = blurRadius
                self.blurIsOpaque = blurIsOpaque
            } else {
                self.blurRadius = nil
                self.blurIsOpaque = nil
            }
            if kind == .effect && effectKind == .geometry {
                self.affineTransform = affineTransform
            } else {
                self.affineTransform = nil
            }
            if kind == .effect && effectKind == .crossFade {
                self.sourceFraction = sourceFraction
                self.targetFraction = targetFraction
            } else {
                self.sourceFraction = nil
                self.targetFraction = nil
            }
            if kind == .effect && effectKind == .blendMode {
                self.blendMode = blendMode
            } else {
                self.blendMode = nil
            }
            if kind == .effect && effectKind == .shadow {
                self.shadow = shadow
            } else {
                self.shadow = nil
            }
            if kind == .effect && effectKind == .colorFilter {
                self.colorFilter = colorFilter
            } else {
                self.colorFilter = nil
            }
        }
    }

    enum ItemCommand: Equatable {
        enum EffectCommand: Equatable {
            case generic
            case opacity(Double)
            case blur(radius: CGFloat, isOpaque: Bool)
            case geometry(CGAffineTransform)
            case crossFade(sourceFraction: Float, targetFraction: Float)
            case blendMode(BlendMode)
            case shadow(ItemRecord.ShadowRecord)
            case colorFilter(ItemRecord.ColorFilterRecord)
        }

        case closure(bounds: CGRect?)
        case shape(
            role: ShapeRole,
            style: ItemRecord.ShapeStyleRecord?,
            fillStyle: FillStyle?,
            strokeStyle: StrokeStyle?,
            bounds: CGRect?
        )
        case image(ItemRecord.ImageRecord, bounds: CGRect?)
        case text(ItemRecord.TextRecord, bounds: CGRect?)
        case custom(ItemRecord.CustomRecord, bounds: CGRect?)
        case effect(EffectCommand, bounds: CGRect?)
        case debug(bounds: CGRect?)

        var record: ItemRecord {
            switch self {
            case let .closure(bounds):
                return ItemRecord(kind: .closure, bounds: bounds)
            case let .shape(role, style, fillStyle, strokeStyle, bounds):
                return ItemRecord(
                    kind: DisplayList.itemRecordKind(for: role),
                    bounds: bounds,
                    shapeStyle: style,
                    fillStyle: fillStyle,
                    strokeStyle: strokeStyle
                )
            case let .image(image, bounds):
                return ItemRecord(kind: .image, bounds: bounds, image: image)
            case let .text(text, bounds):
                return ItemRecord(kind: .text, bounds: bounds, text: text)
            case let .custom(custom, bounds):
                return ItemRecord(kind: .custom, bounds: bounds, custom: custom)
            case let .effect(effect, bounds):
                switch effect {
                case .generic:
                    return ItemRecord(kind: .effect, bounds: bounds, effectKind: .generic)
                case let .opacity(opacity):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .opacity,
                        opacity: opacity
                    )
                case let .blur(radius, isOpaque):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .blur,
                        blurRadius: radius,
                        blurIsOpaque: isOpaque
                    )
                case let .geometry(transform):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .geometry,
                        affineTransform: transform
                    )
                case let .crossFade(sourceFraction, targetFraction):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .crossFade,
                        sourceFraction: sourceFraction,
                        targetFraction: targetFraction
                    )
                case let .blendMode(blendMode):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .blendMode,
                        blendMode: blendMode
                    )
                case let .shadow(shadow):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .shadow,
                        shadow: shadow
                    )
                case let .colorFilter(filter):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .colorFilter,
                        colorFilter: filter
                    )
                }
            case let .debug(bounds):
                return ItemRecord(kind: .debug, bounds: bounds)
            }
        }

        var bounds: CGRect? {
            switch self {
            case let .closure(bounds),
                 let .shape(_, _, _, _, bounds),
                 let .image(_, bounds),
                 let .text(_, bounds),
                 let .custom(_, bounds),
                 let .effect(_, bounds),
                 let .debug(bounds):
                return bounds
            }
        }
    }

    struct Item {
        var command: ItemCommand
        private let body: (GraphicsContext) -> Void

        init(command: ItemCommand, _ body: @escaping (GraphicsContext) -> Void) {
            self.command = command
            self.body = body
        }

        var record: ItemRecord {
            command.record
        }

        func callAsFunction(_ context: GraphicsContext) {
            body(context)
        }
    }

    var items: [Item] = []
    var debugItems: [Item] = []
    var effects: [EffectItem] = []
    var styles: [StyleCommand] = []
    // Backend-local bounds used by display-list interpolation before exact private command storage exists.
    var interpolationBounds: CGRect?

    var itemRecords: [ItemRecord] {
        items.map(\.record)
    }

    var debugItemRecords: [ItemRecord] {
        debugItems.map(\.record)
    }

    var itemCommands: [ItemCommand] {
        items.map(\.command)
    }

    var debugItemCommands: [ItemCommand] {
        debugItems.map(\.command)
    }

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items)
        self.debugItems.append(contentsOf: other.debugItems)
        self.effects.append(contentsOf: other.effects)
        self.styles.append(contentsOf: other.styles)
        self.recordInterpolationBounds(other.interpolationBounds)
    }

    mutating func appendItem(
        kind: ItemRecord.Kind = .closure,
        bounds: CGRect? = nil,
        effectKind: ItemRecord.EffectKind? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = Self.itemCommand(
            kind: kind,
            bounds: bounds,
            effectKind: effectKind
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShapeItem(
        role: ShapeRole,
        bounds: CGRect? = nil,
        fillStyle: FillStyle? = nil,
        strokeStyle: StrokeStyle? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let isStroke = role == .stroke
        let command = ItemCommand.shape(
            role: role,
            style: nil,
            fillStyle: isStroke ? nil : fillStyle,
            strokeStyle: isStroke ? strokeStyle : nil,
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShapeItem<S: ShapeStyle>(
        role: ShapeRole,
        style: S,
        bounds: CGRect? = nil,
        fillStyle: FillStyle? = nil,
        strokeStyle: StrokeStyle? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let isStroke = role == .stroke
        let command = ItemCommand.shape(
            role: role,
            style: Self.shapeStyleRecord(for: style),
            fillStyle: isStroke ? nil : fillStyle,
            strokeStyle: isStroke ? strokeStyle : nil,
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendImageItem(
        _ image: GraphicsContext.ResolvedImage,
        bounds: CGRect? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.image(
            ItemRecord.ImageRecord(
                image,
                shading: image.shading.flatMap(Self.shadingRecord(for:))
            ),
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendTextItem(
        foreground: GraphicsContext.Shading,
        bounds: CGRect? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.text(
            ItemRecord.TextRecord(
                foreground: Self.shadingRecord(for: foreground)
            ),
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendCustomItem(
        bounds: CGRect? = nil,
        isOpaque: Bool,
        colorMode: ColorRenderingMode,
        rendersAsynchronously: Bool,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.custom(
            ItemRecord.CustomRecord(
                isOpaque: isOpaque,
                colorMode: colorMode,
                rendersAsynchronously: rendersAsynchronously
            ),
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendOpacityItem(
        bounds: CGRect? = nil,
        opacity: Double,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.opacity(opacity), bounds: bounds)
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendBlurItem(
        bounds: CGRect? = nil,
        radius: CGFloat,
        isOpaque: Bool,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .blur(radius: radius, isOpaque: isOpaque),
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendGeometryItem(
        bounds: CGRect? = nil,
        affineTransform: CGAffineTransform,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.geometry(affineTransform), bounds: bounds)
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendTransformedItem(
        _ item: Item,
        affineTransform: CGAffineTransform
    ) {
        let command = item.command.transformed(by: affineTransform)
        items.append(Item(command: command) { context in
            var context = context
            context.concatenate(affineTransform)
            item(context)
        })
        recordInterpolationBounds(command.bounds)
    }

    mutating func appendTransformedDebugItem(
        _ item: Item,
        affineTransform: CGAffineTransform
    ) {
        let command = item.command.transformed(by: affineTransform)
        debugItems.append(Item(command: command) { context in
            var context = context
            context.concatenate(affineTransform)
            item(context)
        })
        recordInterpolationBounds(command.bounds)
    }

    mutating func appendCrossFadeItem(
        bounds: CGRect? = nil,
        sourceFraction: Float,
        targetFraction: Float,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .crossFade(
                sourceFraction: sourceFraction,
                targetFraction: targetFraction
            ),
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendBlendModeItem(
        bounds: CGRect? = nil,
        blendMode: BlendMode,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.blendMode(blendMode), bounds: bounds)
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShadowItem(
        bounds: CGRect? = nil,
        color: Color.Resolved,
        radius: CGFloat,
        offset: CGSize,
        blendMode: GraphicsContext.BlendMode = .normal,
        options: GraphicsContext.ShadowOptions = GraphicsContext.ShadowOptions(),
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .shadow(ItemRecord.ShadowRecord(
                color: color,
                radius: radius,
                offset: offset,
                blendModeRawValue: blendMode.rawValue,
                optionsRawValue: options.rawValue
            )),
            bounds: bounds
        )
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendColorFilterItem(
        bounds: CGRect? = nil,
        filter: ItemRecord.ColorFilterRecord,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.colorFilter(filter), bounds: bounds)
        items.append(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendDebugItem(
        bounds: CGRect? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        debugItems.append(Item(command: .debug(bounds: bounds), item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendEffect(_ effect: Effect, contents: DisplayList) {
        effects.append(EffectItem(effect: effect, contents: contents))
        recordInterpolationBounds(contents.interpolationBounds)
    }

    mutating func appendAnimationStyle(
        _ animation: RBAnimation,
        id: UUID? = nil,
        flags: UInt32 = StyleCommand.AnimationStyle.defaultFlags
    ) {
        styles.append(.animation(StyleCommand.AnimationStyle(
            animation: animation,
            id: id,
            flags: flags
        )))
    }

    private static func itemRecordBounds(_ bounds: CGRect?) -> CGRect? {
        guard let bounds = bounds?.standardized,
              !bounds.isNull,
              bounds.width > 0,
              bounds.height > 0
        else { return nil }
        return bounds
    }

    private static func itemCommand(
        kind: ItemRecord.Kind,
        bounds: CGRect?,
        effectKind: ItemRecord.EffectKind?
    ) -> ItemCommand {
        switch kind {
        case .closure:
            return .closure(bounds: bounds)
        case .shapeFill:
            return .shape(role: .fill, style: nil, fillStyle: nil, strokeStyle: nil, bounds: bounds)
        case .shapeStroke:
            return .shape(role: .stroke, style: nil, fillStyle: nil, strokeStyle: nil, bounds: bounds)
        case .shapeSeparator:
            return .shape(role: .separator, style: nil, fillStyle: nil, strokeStyle: nil, bounds: bounds)
        case .image:
            return .image(
                ItemRecord.ImageRecord(
                    baseline: 0,
                    textureID: nil,
                    textureTransform: .identity,
                    scaleFactor: 1,
                    hasShading: false,
                    shading: nil
                ),
                bounds: bounds
            )
        case .text:
            return .text(ItemRecord.TextRecord(foreground: nil), bounds: bounds)
        case .custom:
            return .custom(
                ItemRecord.CustomRecord(
                    isOpaque: false,
                    colorMode: .nonLinear,
                    rendersAsynchronously: false
                ),
                bounds: bounds
            )
        case .effect:
            return .effect(effectCommand(for: effectKind), bounds: bounds)
        case .debug:
            return .debug(bounds: bounds)
        }
    }

    private static func effectCommand(
        for kind: ItemRecord.EffectKind?
    ) -> ItemCommand.EffectCommand {
        switch kind {
        case .opacity:
            return .opacity(1)
        case .blur:
            return .blur(radius: 0, isOpaque: false)
        case .geometry:
            return .geometry(.identity)
        case .crossFade:
            return .crossFade(sourceFraction: 0, targetFraction: 0)
        case .blendMode:
            return .blendMode(.normal)
        case .shadow:
            return .shadow(
                ItemRecord.ShadowRecord(
                    color: Color.Resolved(
                        colorSpace: .sRGBLinear,
                        red: 0,
                        green: 0,
                        blue: 0,
                        opacity: 0
                    ),
                    radius: 0,
                    offset: .zero,
                    blendModeRawValue: GraphicsContext.BlendMode.normal.rawValue,
                    optionsRawValue: 0
                )
            )
        case .colorFilter:
            return .colorFilter(
                ItemRecord.ColorFilterRecord(kind: .brightness, amount: 0)
            )
        case .generic, nil:
            return .generic
        }
    }

    private static func itemRecordKind(for role: ShapeRole) -> ItemRecord.Kind {
        switch role {
        case .fill:
            return .shapeFill
        case .stroke:
            return .shapeStroke
        case .separator:
            return .shapeSeparator
        }
    }

    private static func shapeStyleRecord<S: ShapeStyle>(
        for style: S
    ) -> ItemRecord.ShapeStyleRecord? {
        shapeStyleRecord(for: style as any ShapeStyle)
    }

    private static func shapeStyleRecord(
        for style: any ShapeStyle
    ) -> ItemRecord.ShapeStyleRecord? {
        if let color = style as? Color {
            return .color(color)
        }
        if let resolved = style as? Color.Resolved {
            return .color(Color(resolved))
        }
        if let gradient = style as? Gradient {
            return .gradient(gradient)
        }
        if let gradient = style as? AnyGradient {
            return .gradient(gradient.provider.gradient)
        }
        if let erased = style as? AnyShapeStyle {
            return shapeStyleRecord(for: erased.storage.box.style)
        }
        if let foreground = style as? ForegroundStyle {
            return shapeStyleRecord(resolving: foreground)
        }
        if let background = style as? BackgroundStyle {
            return shapeStyleRecord(resolving: background)
        }
        if let separator = style as? SeparatorShapeStyle {
            return shapeStyleRecord(resolving: separator)
        }
        if let hierarchical = style as? HierarchicalShapeStyle {
            return shapeStyleRecord(resolving: hierarchical)
        }
        return nil
    }

    private static func shapeStyleRecord<S: ShapeStyle>(
        resolving style: S
    ) -> ItemRecord.ShapeStyleRecord? {
        var shape = _ShapeStyle_Shape()
        style._apply(to: &shape)
        guard let shading = shape.shading else { return nil }
        if case let .color(color)? = shadingRecord(for: shading) {
            return .color(color)
        }
        return nil
    }

    private static func shadingRecord(
        for shading: GraphicsContext.Shading
    ) -> ItemRecord.ShadingRecord? {
        guard shading.properties.count == 1 else { return nil }
        if case let .color(color) = shading.properties[0] {
            return .color(color)
        }
        return nil
    }

    mutating func recordInterpolationBounds(_ rect: CGRect?) {
        guard let rect = Self.itemRecordBounds(rect) else { return }
        if let current = interpolationBounds {
            interpolationBounds = current.union(rect)
        } else {
            interpolationBounds = rect
        }
    }

    static func effect(_ effect: Effect, contents: DisplayList) -> DisplayList {
        var list = DisplayList()
        list.appendEffect(effect, contents: contents)
        return list
    }

    func forEachRenderItem(includeDebug: Bool = true, _ body: (Item) -> Void) {
        for item in items {
            body(item)
        }
        for effectItem in effects {
            effectItem.forEachRenderItem(includeDebug: includeDebug, body)
        }
        if includeDebug {
            for item in debugItems {
                body(item)
            }
        }
    }

    func draw(in context: GraphicsContext, includeDebug: Bool = true) {
        forEachRenderItem(includeDebug: includeDebug) { item in
            item(context)
        }
    }

    func hasSameInterpolationSurface(as other: DisplayList) -> Bool {
        itemSurfaceMatches(
            commands: itemCommands,
            otherCommands: other.itemCommands
        ) &&
        itemSurfaceMatches(
            commands: debugItemCommands,
            otherCommands: other.debugItemCommands
        ) &&
            styles == other.styles &&
            effectSurfaceMatches(effects, other.effects) &&
            interpolationBounds == other.interpolationBounds
    }

    private func itemSurfaceMatches(
        commands: [ItemCommand],
        otherCommands: [ItemCommand]
    ) -> Bool {
        commands == otherCommands
    }

    private func effectSurfaceMatches(
        _ effects: [EffectItem],
        _ otherEffects: [EffectItem]
    ) -> Bool {
        guard effects.count == otherEffects.count else { return false }
        return zip(effects, otherEffects).allSatisfy { lhs, rhs in
            lhs.effect.surfaceRecord == rhs.effect.surfaceRecord &&
                lhs.contents.hasSameInterpolationSurface(as: rhs.contents)
        }
    }
}

private struct DisplayListEffectSurfaceRecord: Equatable {
    enum Kind: UInt8, Equatable {
        case state
        case contentTransition
        case interpolatorRoot
        case interpolatorLayer
        case interpolatorAnimation
    }

    var kind: Kind
    var hash: StrongHash?
    var contentTransitionState: ContentTransition.State?
    var groupID: ObjectIdentifier?
    var origin: CGPoint?
    var size: CGSize?
    var layerID: UInt32?
    var animationValue: StrongHash?
    var animation: Animation?
}

private extension DisplayList.Effect {
    var surfaceRecord: DisplayListEffectSurfaceRecord {
        switch self {
        case let .state(hash):
            return DisplayListEffectSurfaceRecord(kind: .state, hash: hash)
        case let .contentTransition(state):
            return DisplayListEffectSurfaceRecord(
                kind: .contentTransition,
                contentTransitionState: state
            )
        case let .interpolatorRoot(group, origin, size):
            return DisplayListEffectSurfaceRecord(
                kind: .interpolatorRoot,
                groupID: ObjectIdentifier(group),
                origin: origin,
                size: size
            )
        case let .interpolatorLayer(group, layerID):
            return DisplayListEffectSurfaceRecord(
                kind: .interpolatorLayer,
                groupID: ObjectIdentifier(group),
                layerID: layerID
            )
        case let .interpolatorAnimation(animation):
            return DisplayListEffectSurfaceRecord(
                kind: .interpolatorAnimation,
                animationValue: animation.value,
                animation: animation.animation
            )
        }
    }
}

extension DisplayList.Effect {
    func hasSameSurface(as other: Self) -> Bool {
        surfaceRecord == other.surfaceRecord
    }
}

private extension DisplayList.ItemCommand {
    func transformed(by transform: CGAffineTransform) -> Self {
        let transformedBounds = bounds?.applying(transform).standardized
        switch self {
        case .closure:
            return .closure(bounds: transformedBounds)
        case let .shape(role, style, fillStyle, strokeStyle, _):
            return .shape(
                role: role,
                style: style,
                fillStyle: fillStyle,
                strokeStyle: strokeStyle,
                bounds: transformedBounds
            )
        case let .image(image, _):
            return .image(image, bounds: transformedBounds)
        case let .text(text, _):
            return .text(text, bounds: transformedBounds)
        case let .custom(custom, _):
            return .custom(custom, bounds: transformedBounds)
        case let .effect(effect, _):
            return .effect(effect.transformed(by: transform), bounds: transformedBounds)
        case .debug:
            return .debug(bounds: transformedBounds)
        }
    }
}

private extension DisplayList.ItemCommand.EffectCommand {
    func transformed(by transform: CGAffineTransform) -> Self {
        switch self {
        case let .geometry(affineTransform):
            return .geometry(affineTransform.concatenating(transform))
        case .generic,
             .opacity,
             .blur,
             .crossFade,
             .blendMode,
             .shadow,
             .colorFilter:
            return self
        }
    }
}

extension DisplayList.EffectItem {
    fileprivate func forEachRenderItem(
        includeDebug: Bool,
        _ body: (DisplayList.Item) -> Void
    ) {
        switch effect {
        case .contentTransition:
            contents.forEachRenderItem(includeDebug: includeDebug, body)
        case .state, .interpolatorRoot, .interpolatorLayer, .interpolatorAnimation:
            break
        }
    }
}

extension DisplayList {
    struct Key: PreferenceKey {
        typealias Value = DisplayList
        static var defaultValue: DisplayList { DisplayList() }

        static func reduce(value: inout DisplayList, nextValue: () -> DisplayList) {
            value.append(contentsOf: nextValue())
        }
    }
}

struct ResourceList {
    struct Version {
        let value: Int
    }

    typealias Task = (GraphicsContext) -> Void
    var items: [Task] = []

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items)
    }
}

extension ResourceList {
    struct Key: PreferenceKey {
        typealias Value = ResourceList
        static var defaultValue: ResourceList { ResourceList() }

        static func reduce(value: inout ResourceList, nextValue: () -> ResourceList) {
            value.append(contentsOf: nextValue())
        }
    }
}

private struct DisplayScaleEnvironmentKey: EnvironmentKey {
    static var defaultValue: CGFloat { return 1 }
}

extension EnvironmentValues {
    public var displayScale: CGFloat {
        set { self[DisplayScaleEnvironmentKey.self] = newValue }
        get { self[DisplayScaleEnvironmentKey.self] }
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
