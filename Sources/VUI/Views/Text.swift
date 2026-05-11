//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// TextAlignment: horizontal alignment for multi-line text.
public enum TextAlignment: Hashable {
    case leading
    case center
    case trailing
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    static var defaultValue: TextAlignment { .leading }
}

extension EnvironmentValues {
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

extension View {
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}


class AnyTextStorage {
    func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveText(in environment: EnvironmentValues) -> String {
        fatalError("This method should be overridden by subclasses.")
    }
    func isEqual(to other: AnyTextStorage) -> Bool {
        self === other
    }
}

// NOTE: No String.LocalizationValue for non-Apple platforms.
//typealias LocalizedStringKey = String.LocalizationValue
public typealias LocalizedStringKey = String

class LocalizedTextStorage: AnyTextStorage {
    let key: LocalizedStringKey
    let table: String?
    let bundle: Bundle?
    init(key: LocalizedStringKey, table: String?, bundle: Bundle?) {
        self.key = key
        self.table = table
        self.bundle = bundle
    }

    override func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        //let text = String(localized: self.key)
        let text = self.key
        return .init(storage: [.text(typeFaces, text)], scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        //String(localized: key)
        self.key
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.key == other.key && self.table == other.table && self.bundle == other.bundle
        }
        return false
    }
}

class ConcatenatedTextStorage: AnyTextStorage {
    let first: Text
    let second: Text
    init(first: Text, second: Text) {
        self.first = first
        self.second = second
    }

    override func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let first = first._resolve(context: context)
        let second = second._resolve(context: context)
        return .init(storage: first.storage + second.storage, scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        first._resolveText(in: environment) + second._resolveText(in: environment)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.first == other.first && self.second == other.second
        }
        return false
    }
}

class AttachmentTextStorage: AnyTextStorage {
    let image: Image
    init(_ image: Image) {
        self.image = image
    }

    override func resolve(typeFaces: [TypeFace], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let image = context.resolve(self.image)
        return .init(storage: [.attachment(typeFaces, image)], scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String()
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.image == other.image
        }
        return false
    }
}

public struct Text: Equatable {
    enum Storage: Equatable {
        case verbatim(String)
        case anyTextStorage(AnyTextStorage)

        static func == (lhs: Text.Storage, rhs: Text.Storage) -> Bool {
            if case let .verbatim(s1) = lhs, case let .verbatim(s2) = rhs {
                return s1 == s2
            }
            if case let .anyTextStorage(s1) = lhs, case let .anyTextStorage(s2) = rhs {
                return s1.isEqual(to: s2)
            }
            return false
        }
    }

    let storage: Storage

    public enum Case: Hashable {
        case lowercase
        case uppercase
    }

    public struct LineStyle: Hashable {
        public struct Pattern: Equatable, Sendable {
            enum UnderlineStyle {
                case solid
                case dot
                case dash
                case dashDot
                case dashDotDot
            }
            let underlineStyle: UnderlineStyle
            let color: Color?

            init(_ underlineStyle: UnderlineStyle) {
                self.underlineStyle = underlineStyle
                self.color = nil
            }

            public static let solid = Pattern(.solid)
            public static let dot = Pattern(.dot)
            public static let dash = Pattern(.dash)
            public static let dashDot = Pattern(.dashDot)
            public static let dashDotDot = Pattern(.dashDotDot)

            public init(pattern: Text.LineStyle.Pattern = .solid,
                        color: Color? = nil) {
                self.underlineStyle = pattern.underlineStyle
                self.color = color
            }
        }
    }

    enum Modifier: Equatable {
        case font(Font)
        case fontWeight(Font.Weight)
        case foregroundColor(Color)
        case bold(Bool)
        case italic(Bool)
        case strikethrough(Bool, LineStyle.Pattern, Color?)
        case underline(Bool, LineStyle.Pattern, Color?)
        case monospacedDigit
        case kerning(CGFloat)
        case tracking(CGFloat)
        case baselineOffset(CGFloat)
        case textCase(Case)
    }

    let modifiers: [Modifier]

    public init<S>(_ content: S) where S: StringProtocol {
        let key = LocalizedStringKey(String(content))
        self.storage = .anyTextStorage(LocalizedTextStorage(key: key, table: nil, bundle: nil))
        self.modifiers = []
    }

    public init(verbatim content: String) {
        self.storage = .verbatim(content)
        self.modifiers = []
    }

    public init(_ image: Image) {
        self.storage = .anyTextStorage(AttachmentTextStorage(image))
        self.modifiers = []
    }

    init(storage: Storage, modifiers: [Modifier]) {
        self.storage = storage
        self.modifiers = modifiers
    }

    public func _resolveText(in environment: EnvironmentValues) -> String {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveText(in: environment)
        }
        return String()
    }

    func _resolve(context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let displayScale = context.sceneResources.contentScaleFactor
        var font = self.font ?? context.environment.font
        if font == nil {
            font = .system(.body)
        }
        font = font?.displayScale(displayScale)
        let defaultFace = font?.typeFace(forContext: context.sceneResources)
        let fallbackFaces = font?.fallbackTypeFaces ?? []
        let faces = ([defaultFace] + fallbackFaces).compactMap {$0 }

        if faces.isEmpty == false {
            var storage: [GraphicsContext.ResolvedText.Storage] = []
            if case let .verbatim(text) = self.storage {
                storage = [.text(faces, text)]
                return GraphicsContext.ResolvedText(storage: storage, scaleFactor: context.contentScaleFactor)
            }
            else if case let .anyTextStorage(text) = self.storage {
                return text.resolve(typeFaces: faces, context: context)
            }
        }
        return .init(storage: [], scaleFactor: context.contentScaleFactor)
    }
}

extension Text {
    public func foregroundColor(_ color: Color?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .foregroundColor(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let color {
            modifiers.append(.foregroundColor(color))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var foregroundColor: Color? {
        self.modifiers.compactMap {
            if case let .foregroundColor(color) = $0 { return color }
            return nil
        }.first
    }

    func foregroundShading(in environment: EnvironmentValues) -> GraphicsContext.Shading {
        if let foregroundColor {
            return .color(foregroundColor)
        }
        if let styles = environment.foregroundStyleLevels {
            var shape = _ShapeStyle_Shape()
            shape.foregroundStyle = (
                primary: styles.primary,
                secondary: styles.secondary,
                tertiary: styles.tertiary
            )
            styles.primary._apply(to: &shape)
            if let shading = shape.shading {
                return shading
            }
        }
        return .foreground
    }

    public func font(_ font: Font?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .font(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let font {
            modifiers.append(.font(font))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var font: Font? {
        self.modifiers.compactMap {
            if case let .font(font) = $0 { return font }
            return nil
        }.first
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .fontWeight(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let weight {
            modifiers.append(.fontWeight(weight))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var fontWeight: Font.Weight? {
        self.modifiers.compactMap {
            if case let .fontWeight(weight) = $0 { return weight }
            return nil
        }.first
    }
}

extension Text {
    public static func + (lhs: Text, rhs: Text) -> Text {
        .init(storage: .anyTextStorage(ConcatenatedTextStorage(first: lhs,
                                                               second: rhs)),
              modifiers: [])
    }
}

extension Text: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        // 1. Internal state nodes for communication between the resource and layout passes.
        // Caches the fully resolved text object (including glyphs/metrics).
        let resolvedTextAttr = graph.makeInput(value: GraphicsContext.ResolvedText?.none)
        // Tracks the hash of the text content and environment to detect changes.
        let resolvedEnvVersionAttr = graph.makeInput(value: 0)

        // Extract inputs to avoid capturing the entire `inputs` struct
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let inbox = graph.inbox
        let sizeAttr = inputs.size
        let positionAttr = inputs.position

        let debugLayoutAttr: Attribute<Bool> = graph.makeRule {
            cachedEnvironmentAttr.value.environment.value._debugLayout
        }

        // 2. Resource pass (Resource Rule)
        // Evaluated before drawing (in updateView) to upload resources to the GPU.
        let resourceAttr: Attribute<ResourceList> = graph.makeRule {
            let text = view._attribute.value // Dependency 1: Text content and modifiers
            let environment = cachedEnvironmentAttr.value.environment.value // Dependency 2: Environment (scale, theme, font)

            // Generate a unique hash (version) combining text content and environment factors.
            var hasher = Hasher()
            hasher.combine(text._resolveText(in: environment))
            hasher.combine(environment.font?.hashValue ?? 0)
            hasher.combine(environment.displayScale)
            let currentVersion = hasher.finalize()

            // Optimization (Cache Hit): Return an empty list if the resolved version matches and the text is already cached.
            if resolvedEnvVersionAttr.value == currentVersion, resolvedTextAttr.value != nil {
                return ResourceList() 
            }

            // If loading is required, create a new ResourceList(Task) to propagate upwards.
            var list = ResourceList()

            list.items.append { context in
                // 1. [Synchronous Loading] Parse the text and generate glyphs using the provided context.
                let resolved = text._resolve(context: context)
                let boxedResolved = UnsafeBox(resolved)

                // 2. [State Invalidation] Notify completion and trigger a layout recomputation.
                inbox.enqueue {
                    resolvedTextAttr.setValue(boxedResolved.value)
                    resolvedEnvVersionAttr.setValue(currentVersion) // Update cached version
                }
            }

            return list
        }

        // 3. Layout pass (Layout Rule)
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            // Dependency: Re-evaluates when `inbox` updates these values from the Resource Rule.
            let resolved = resolvedTextAttr.value

            func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
                guard let r = resolved else { return .zero } // Return zero size before loading completes
                if proposal == .zero {
                    return .zero
                }
                // Keep Text width at zero for zero-width proposals while still
                // reporting measured height when height is non-zero or unspecified.
                if proposal.width == 0 {
                    let measured = r.measure(maxWidth: 0, maxHeight: proposal.height)
                    return CGSize(width: 0, height: measured.height)
                }
                if proposal == .infinity {
                    return r.measure()
                }
                return r.measure(maxWidth: proposal.width, maxHeight: proposal.height)
            }

            return LayoutComputer(
                sizeThatFits: { sizeThatFits($0) },
                // Text contributes text-specific spacing for adjacent text runs.
                spacing: .text,
                explicitAlignment: { key, size in
                    guard let r = resolved else { return nil }
                    let cgSize = CGSize(width: size.width, height: size.height)
                    if key == VerticalAlignment.firstTextBaseline.key {
                        return r.firstBaseline(in: cgSize)
                    }
                    if key == VerticalAlignment.lastTextBaseline.key {
                        return r.lastBaseline(in: cgSize)
                    }
                    return nil
                }
            )
        }

        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let text = view._attribute.value // Dependency: text modifiers/colors
            let environment = cachedEnvironmentAttr.value.environment.value
            let viewSize = sizeAttr.value.value
            let position = positionAttr.value
            let resolved = resolvedTextAttr.value
            let debugLayout = debugLayoutAttr.value
            let foreground = text.foregroundShading(in: environment)

            var list = DisplayList()

            if let resolved = resolved {
                list.items.append { context in
                    // 1. Local rendering frame (origin is the position assigned by the parent)
                    var frame = CGRect(origin: position, size: viewSize)

                    // 2. Measure actual text size for vertical centering
                    let measuredSize = resolved.measure(maxWidth: frame.width, maxHeight: frame.height)

                    if measuredSize.height < frame.height {
                        let offset = frame.height - measuredSize.height
                        frame = frame.offsetBy(dx: 0, dy: offset * 0.5)
                        frame.size.height = measuredSize.height
                    }

                    // 3. Draw to the screen
                    if frame.width > 0 && frame.height > 0 {
                        context.draw(resolved, in: frame, shading: foreground)
                    }
                }
            }
            if debugLayout {
                appendDebugOverlay(to: &list, frame: CGRect(origin: position, size: viewSize),
                                   category: .primitiveView)
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
}

extension Text: _PrimitiveView {
}
