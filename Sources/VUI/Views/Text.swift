//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

final class _TextResourceResolutionState {
    private(set) var pendingVersion: Int?
    private var pendingTransaction = Transaction()

    func transaction(for version: Int, candidate: Transaction) -> Transaction {
        guard pendingVersion != version else {
            return pendingTransaction
        }
        pendingVersion = version
        pendingTransaction = candidate
        return candidate
    }

    func didResolve(version: Int) {
        guard pendingVersion == version else { return }
        pendingVersion = nil
        pendingTransaction = Transaction()
    }

    static func publicationTransaction(
        candidate: Transaction,
        hasResolvedContent: Bool
    ) -> Transaction {
        guard !hasResolvedContent else { return candidate }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }
}

final class _TextDisplayListContentState {
    private var resolvedVersion: Int?
    private var size: CGSize?
    private var needsDrawingGroup: Bool?
    private var rendererID: ObjectIdentifier?
    private var seed = DisplayList.Seed()

    func contentSeed(
        resolvedVersion: Int,
        size: CGSize,
        needsDrawingGroup: Bool,
        renderer: TextRendererBoxBase? = nil
    ) -> DisplayList.Seed {
        let rendererID = renderer.map(ObjectIdentifier.init)
        if seed.value == 0 ||
            self.resolvedVersion != resolvedVersion ||
            self.size != size ||
            self.needsDrawingGroup != needsDrawingGroup ||
            self.rendererID != rendererID {
            seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
            self.resolvedVersion = resolvedVersion
            self.size = size
            self.needsDrawingGroup = needsDrawingGroup
            self.rendererID = rendererID
        }
        return seed
    }
}

func _textTransitionRenderFrame(
    position: CGPoint,
    viewSize: CGSize,
    targetSize: CGSize,
    idealSize: CGSize,
    pixelLength: CGFloat,
    activeSourceBounds: CGRect?
) -> CGRect {
    var renderSize = viewSize
    let targetAccommodatesIdealWidth =
        targetSize.width + max(pixelLength, 0) >= idealSize.width
    if targetAccommodatesIdealWidth, viewSize.width < idealSize.width {
        renderSize.width = idealSize.width
    }
    if let activeSourceBounds {
        let sourceWidth = activeSourceBounds.width
        let isExpanding = idealSize.width > sourceWidth && viewSize.width > sourceWidth
        let isContracting = idealSize.width < sourceWidth && viewSize.width < sourceWidth
        if isExpanding || isContracting {
            renderSize.width = max(viewSize.width, idealSize.width)
        }
    }
    return CGRect(
        x: position.x + (viewSize.width - renderSize.width) * 0.5,
        y: position.y,
        width: renderSize.width,
        height: renderSize.height
    )
}

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
    func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveText(in environment: EnvironmentValues) -> String {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        resolveText(in: environment)
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

    override func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        //let text = String(localized: self.key)
        let text = self.key
        return .init(runs: [.text(typefaces, text)], scaleFactor: context.contentScaleFactor)
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

    override func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let first = first._resolve(context: context)
        let second = second._resolve(context: context)
        return .init(runs: first.runs + second.runs, scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        first._resolveText(in: environment) + second._resolveText(in: environment)
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        guard let first = first._resolveTransitionText(in: environment),
              let second = second._resolveTransitionText(in: environment) else {
            return nil
        }
        return first + second
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

    override func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let image = context.resolve(self.image)
        return .init(runs: [.attachment(typefaces, image)], scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String()
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        nil
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
        case customAttribute(_AnyTextAttribute)
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

    func _resolveTransitionText(in environment: EnvironmentValues) -> String? {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveTransitionText(in: environment)
        }
        return nil
    }

    func _resolve(context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let displayScale = context.sceneResources.contentScaleFactor
        var font = self.font ?? context.environment.font
        if font == nil {
            font = .system(.body)
        }
        font = font?.resolved(in: context.environment)
        font = font?.displayScale(displayScale)
        let defaultFace = font?.typeface(forContext: context.sceneResources)
        let fallbackFaces = font?.fallbackTypefaces ?? []
        let faces = ([defaultFace] + fallbackFaces).compactMap {$0 }

        if faces.isEmpty == false {
            var runs: [GraphicsContext.ResolvedText.Run] = []
            if case let .verbatim(text) = self.storage {
                runs = [.text(faces, text)]
                return GraphicsContext.ResolvedText(
                    runs: runs.map { $0.applying(customAttributes) },
                    scaleFactor: context.contentScaleFactor
                )
            }
            else if case let .anyTextStorage(text) = self.storage {
                let resolved = text.resolve(typefaces: faces, context: context)
                guard !customAttributes.isEmpty else { return resolved }
                return GraphicsContext.ResolvedText(
                    runs: resolved.runs.map { $0.applying(customAttributes) },
                    scaleFactor: context.contentScaleFactor
                )
            }
        }
        return .init(runs: [], scaleFactor: context.contentScaleFactor)
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
    public func customAttribute<T>(_ value: T) -> Text where T: TextAttribute {
        let attribute = _AnyTextAttribute(value)
        var modifiers = modifiers.filter {
            guard case let .customAttribute(existing) = $0 else { return true }
            return existing.type != attribute.type
        }
        modifiers.append(.customAttribute(attribute))
        return Text(storage: storage, modifiers: modifiers)
    }

    var customAttributes: _TextAttributeValues {
        var attributes = _TextAttributeValues()
        for modifier in modifiers {
            guard case let .customAttribute(attribute) = modifier else { continue }
            attributes.set(attribute)
        }
        return attributes
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        .init(storage: .anyTextStorage(ConcatenatedTextStorage(first: lhs,
                                                               second: rhs)),
              modifiers: [])
    }
}

extension Text: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        // 1. Internal state nodes for communication between the resource and layout passes.
        // Caches the fully resolved styled text object (including glyphs/metrics).
        let resolvedStyledTextAttr = graph.makeInput(value: ResolvedStyledText())
        let resolvedStyledTextTransactionAttr = graph.makeInput(value: Transaction())
        let resourceResolutionState = _TextResourceResolutionState()
        let displayListContentState = _TextDisplayListContentState()

        // Extract inputs to avoid capturing the entire `inputs` struct
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let animatedFrame = cachedEnvironmentAttr.value.animatedFrame
        let inbox = graph.inbox
        let sizeAttr = animatedFrame?._animatedSize ?? inputs.size
        let targetSizeAttr = animatedFrame?.size ?? inputs.size
        let pixelLengthAttr = animatedFrame?.pixelLength
        let positionAttr = animatedFrame?._animatedPosition ?? inputs.position
        let textRendererAttr = inputs[TextRendererInput.self]
        let archiveOptions = inputs[ArchivedViewInput.self]

        let debugLayoutAttr: Attribute<Bool> = graph.makeRule {
            cachedEnvironmentAttr.value.environment.value._debugLayout
        }

        // 2. Resource pass (Resource Rule)
        // Evaluated before drawing (in updateView) to upload resources to the GPU.
        let resourceAttr: Attribute<ResourceList> = graph.makeRule {
            let text = view._attribute.value // Dependency 1: Text content and modifiers
            let environment = cachedEnvironmentAttr.value.environment.value // Dependency 2: Environment (scale, theme, font)
            let renderEnvironment = environment.untrackedCopy()
            let transitionText = text._resolveTransitionText(in: environment)
            let layoutProperties = TextLayoutProperties(environment)

            // Generate a unique hash (version) combining text content and environment factors.
            var hasher = Hasher()
            hasher.combine(text._resolveText(in: environment))
            hasher.combine(environment.font?.hashValue ?? 0)
            hasher.combine(environment.defaultFontRenderingMode)
            hasher.combine(environment.displayScale)
            text.customAttributes.hash(into: &hasher)
            let currentVersion = hasher.finalize()

            // Optimization (Cache Hit): Return an empty list if the resolved version matches and the text is already cached.
            let resolvedStyledText = resolvedStyledTextAttr.value
            if resolvedStyledText.version == currentVersion, resolvedStyledText.resolvedText != nil {
                resourceResolutionState.didResolve(version: currentVersion)
                return ResourceList()
            }

            let candidateTransaction = _AGGraph.currentRuleContextAttribute
                .flatMap { graph.transaction(for: $0) } ?? Transaction()
            let resourceTransaction = resourceResolutionState.transaction(
                for: currentVersion,
                candidate: candidateTransaction
            )
            let publicationTransaction = _TextResourceResolutionState.publicationTransaction(
                candidate: resourceTransaction,
                hasResolvedContent: resolvedStyledText.resolvedText != nil
            )

            // If loading is required, create a new ResourceList(Task) to propagate upwards.
            var list = ResourceList()

            list.items.append { context in
                var context = context
                context.environment = renderEnvironment
                // 1. [Synchronous Loading] Parse the text and generate glyphs using the provided context.
                let resolved = text._resolve(context: context)
                let boxedResolved = UnsafeBox(resolved)
                let boxedTransaction = UnsafeBox(publicationTransaction)
                let boxedLayoutProperties = UnsafeBox(layoutProperties)

                // 2. [State Invalidation] Notify completion and trigger a layout recomputation.
                let publish: @Sendable () -> Void = {
                    resolvedStyledTextTransactionAttr.setValue(boxedTransaction.value)
                    resolvedStyledTextAttr.setValue(
                        ResolvedStyledText(
                            layoutProperties: boxedLayoutProperties.value,
                            archiveOptions: archiveOptions,
                            features: boxedResolved.value.resolvedFeatures,
                            resolvedText: boxedResolved.value,
                            version: currentVersion,
                            transitionText: transitionText
                        ),
                        transaction: boxedTransaction.value
                    )
                }
                if _AGGraph.current === graph {
                    publish()
                } else {
                    inbox.enqueue(transaction: publicationTransaction, publish)
                }
            }

            return list
        }

        // 3. Layout pass (Layout Rule)
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            // Dependency: Re-evaluates when `inbox` updates these values from the Resource Rule.
            let resolved = resolvedStyledTextAttr.value.resolvedText
            let renderer = textRendererAttr?.value

            func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
                guard let r = resolved else { return .zero } // Return zero size before loading completes
                if let renderer {
                    return renderer.sizeThatFits(proposal: proposal, text: TextProxy(r))
                }
                if proposal == .zero {
                    return .zero
                }
                // Keep Text width at zero for zero-width proposals while still
                // reporting the measured height when height is non-zero or unspecified.
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

        let interpolatorGroup = DisplayList.UnaryInterpolatorGroup()
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let text = view._attribute.value // Dependency: text modifiers/colors
            let environment = cachedEnvironmentAttr.value.environment.value
            let viewSize = sizeAttr.value.value
            let targetSize = targetSizeAttr.value.value
            let position = positionAttr.value
            let styledText = resolvedStyledTextAttr.value
            let resolved = styledText.resolvedText
            let debugLayout = debugLayoutAttr.value
            let foreground = text.foregroundShading(in: environment)
            let renderer = textRendererAttr?.value

            var list = DisplayList()

            if let resolved = resolved {
                let idealSize = renderer?.sizeThatFits(
                    proposal: .unspecified,
                    text: TextProxy(resolved)
                ) ?? resolved.measure()
                var frame = _textTransitionRenderFrame(
                    position: position,
                    viewSize: viewSize,
                    targetSize: targetSize,
                    idealSize: idealSize,
                    pixelLength: pixelLengthAttr?.value ?? environment.animationPixelLength,
                    activeSourceBounds: interpolatorGroup.activeSourceBounds
                )
                let measuredSize = renderer?.sizeThatFits(
                    proposal: ProposedViewSize(frame.size),
                    text: TextProxy(resolved)
                ) ?? resolved.measure(maxWidth: frame.width, maxHeight: frame.height)

                if measuredSize.height < frame.height {
                    let offset = frame.height - measuredSize.height
                    frame = frame.offsetBy(dx: 0, dy: offset * 0.5)
                    frame.size.height = measuredSize.height
                }
                let styledTextContent = StyledTextContentView(
                    text: styledText,
                    renderer: renderer,
                    needsDrawingGroup: styledText.needsDrawingGroup
                )
                let contentSeed = displayListContentState.contentSeed(
                    resolvedVersion: styledText.version,
                    size: frame.size,
                    needsDrawingGroup: styledText.needsDrawingGroup,
                    renderer: renderer
                )
                let padding = renderer?.displayPadding ?? EdgeInsets()
                let displayBounds = CGRect(
                    x: frame.minX - padding.leading,
                    y: frame.minY - padding.top,
                    width: frame.width + padding.leading + padding.trailing,
                    height: frame.height + padding.top + padding.bottom
                )
                list.appendTextItem(
                    styledTextContent,
                    size: frame.size,
                    foreground: foreground,
                    bounds: frame,
                    displayBounds: displayBounds,
                    seed: contentSeed,
                    environment: environment.untrackedCopy()
                )
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
        var interpolatorInputs = inputs
        interpolatorInputs.base.transaction = resolvedStyledTextTransactionAttr
        interpolatorInputs.size = animatedFrame?.size ?? inputs.size
        outputs.applyInterpolatorGroup(
            interpolatorGroup,
            content: resolvedStyledTextAttr,
            inputs: interpolatorInputs,
            animatesSize: false,
            defersRender: false
        )
        if platformItemListShouldCollectStaticItemContributors(inputs) {
            // Plain Text under MenuStyleContext contributes a disabled platform item.
            let textAttr = view._attribute
            let itemID = PlatformItemList.stableID(textAttr.identifier)
            let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
                var list = PlatformItemList()
                list.append(PlatformItemList.Item(
                    id: itemID,
                    label: AnyView(textAttr.value),
                    action: nil,
                    role: nil,
                    isEnabled: false
                ))
                return list
            }
            outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
        }

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
}

extension Text: PrimitiveView {
}
