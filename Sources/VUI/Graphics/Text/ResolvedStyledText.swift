//
//  File: ResolvedStyledText.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension NSAttributedString.Key {
    static let resolvedTextAttachment = NSAttributedString.Key(
        "VUI.resolvedText.attachment"
    )
    static let updateSchedule = NSAttributedString.Key("VUI.updateSchedule")
}

struct _ResolvedAttributedStringArchive: Codable, Equatable {
    struct Run: Codable, Equatable {
        var text: String
        var isAttachment: Bool
        var isDynamic: Bool

        init(text: String, isAttachment: Bool, isDynamic: Bool = false) {
            self.text = text
            self.isAttachment = isAttachment
            self.isDynamic = isDynamic
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case isAttachment
            case isDynamic
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            isAttachment = try container.decode(Bool.self, forKey: .isAttachment)
            isDynamic = try container.decodeIfPresent(Bool.self, forKey: .isDynamic) ?? false
        }
    }

    var runs: [Run]

    init(_ value: NSAttributedString) {
        var runs: [Run] = []
        value.enumerateAttributes(
            in: NSRange(location: 0, length: value.length)
        ) { attributes, range, _ in
            runs.append(Run(
                text: value.attributedSubstring(from: range).string,
                isAttachment: attributes[.resolvedTextAttachment] as? Bool == true,
                isDynamic: attributes[.updateSchedule] != nil
            ))
        }
        self.runs = runs
    }

    var attributedString: NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if run.isAttachment {
                attributes[.resolvedTextAttachment] = true
            }
            if run.isDynamic {
                attributes[.updateSchedule] = true
            }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }
}

private extension NSAttributedString {
    var _isDynamicText: Bool {
        guard length > 0 else { return false }
        return attribute(.updateSchedule, at: 0, effectiveRange: nil) != nil
    }
}

struct CodableAttributedString: ProtobufEncodableMessage {
    var base: NSAttributedString

    init(_ base: NSAttributedString) {
        self.base = base
    }

    func encode(to encoder: inout ProtobufEncoder) throws {
        if !base.string.isEmpty {
            encoder.encodeStringField(1, base.string)
        }
        guard base.length > 0 else { return }
        var ranges: [KnownAttributeRange] = []
        base.enumerateAttributes(
            in: NSRange(location: 0, length: base.length)
        ) { attributes, range, _ in
            var flags: UInt = 0
            if attributes[.resolvedTextAttachment] as? Bool == true {
                flags |= 1
            }
            if attributes[.updateSchedule] != nil {
                flags |= 2
            }
            guard flags != 0 else { return }
            ranges.append(KnownAttributeRange(extent: range, flags: flags))
        }
        for range in ranges {
            try encoder.encodeMessageField(2, range)
        }
    }
}

private struct KnownAttributeRange: ProtobufEncodableMessage {
    var extent: NSRange
    var flags: UInt

    func encode(to encoder: inout ProtobufEncoder) throws {
        if extent.location != 0 {
            encoder.encodeVarint(1 << 3)
            encoder.encodeVarint(UInt(extent.location))
        }
        if extent.length != 0 {
            encoder.encodeVarint(2 << 3)
            encoder.encodeVarint(UInt(extent.length))
        }
        encoder.encodeVarint(127 << 3)
        encoder.encodeVarint(flags)
    }
}

enum ResolvedTextSuffix: Equatable {
    case truncated(Text.Layout.Line, [_ShapeStyle_Pack.Style])
    case alwaysVisible(Text.Layout.Line, [_ShapeStyle_Pack.Style])
    case none

    var line: Text.Layout.Line? {
        switch self {
        case let .truncated(line, _), let .alwaysVisible(line, _):
            line
        case .none:
            nil
        }
    }

    var styles: [_ShapeStyle_Pack.Style] {
        switch self {
        case let .truncated(_, styles), let .alwaysVisible(_, styles):
            styles
        case .none:
            []
        }
    }
}

extension Text {
    struct ResolvedProperties {
        struct CustomAttachments: Equatable, Sendable {
            var characterIndices: [Int]

            init(characterIndices: [Int] = []) {
                self.characterIndices = characterIndices
            }

            var isEmpty: Bool {
                characterIndices.isEmpty
            }
        }

        struct Features: OptionSet, Equatable, Sendable {
            let rawValue: UInt16

            init(rawValue: UInt16) {
                self.rawValue = rawValue
            }

            static let keyColor = Features(rawValue: 1 << 0)
            static let attachments = Features(rawValue: 1 << 1)
            static let sensitive = Features(rawValue: 1 << 2)
            static let customRenderer = Features(rawValue: 1 << 3)
            static let useTextLayoutManager = Features(rawValue: 1 << 4)
            static let useTextSuffix = Features(rawValue: 1 << 5)
            static let produceTextLayout = Features(rawValue: 1 << 6)
            static let checkInterpolationStrategy = Features(rawValue: 1 << 7)
            static let isUniqueSizeVariant = Features(rawValue: 1 << 8)
            static let isStandaloneSizeVariant = Features(rawValue: 1 << 9)
        }

        struct Transition: Equatable, Sendable {
            var transition: ContentTransition

            init(transition: ContentTransition) {
                self.transition = transition
            }
        }

        struct Links: Equatable, Sendable {
        }

        /// Tracks the current paragraph's UTF-16 start, languages, and shared style.
        /// Boundary finalization releases the cache while completed runs retain it.
        struct Paragraph: Codable, Equatable {
            var compositionLanguage: Int = 0
            var cachedStyle: TextParagraphStyle?
            var languageIdentifiers: Set<String>
            var startIndex: Int

            init(
                languageIdentifiers: Set<String> = [],
                startIndex: Int = 0
            ) {
                self.languageIdentifiers = languageIdentifiers
                self.startIndex = startIndex
            }

            mutating func markParagraphBoundary(at characterIndex: Int) {
                cachedStyle = nil
                languageIdentifiers.removeAll()
                startIndex = characterIndex
            }
        }

        var insets: EdgeInsets
        var features: Features
        var styles: [_ShapeStyle_Pack.Style]
        var transitions: [Transition]
        var suffix: ResolvedTextSuffix
        var customAttachments: CustomAttachments
        var paragraph: Paragraph
        var multilineTextAlignment: TextAlignment?

        init(
            insets: EdgeInsets = EdgeInsets(),
            features: Features = [],
            styles: [_ShapeStyle_Pack.Style] = [],
            transitions: [Transition] = [],
            suffix: ResolvedTextSuffix = .none,
            customAttachments: CustomAttachments = CustomAttachments(),
            paragraph: Paragraph = Paragraph(),
            multilineTextAlignment: TextAlignment? = nil
        ) {
            self.insets = insets
            self.features = features
            self.styles = styles
            self.transitions = transitions
            self.suffix = suffix
            self.customAttachments = customAttachments
            self.paragraph = paragraph
            self.multilineTextAlignment = multilineTextAlignment
        }

        mutating func registerCustomAttachment(at characterIndex: Int) {
            customAttachments.characterIndices.append(characterIndex)
        }

        var links: Links {
            Links()
        }
    }
}

private final class _ResolvedStyledTextWeakReference {
    weak var value: ResolvedStyledText?

    init(_ value: ResolvedStyledText) {
        self.value = value
    }
}

private enum _ResolvedStyledTextVariantReference {
    case strong(ResolvedStyledText)
    case weak(_ResolvedStyledTextWeakReference)

    var value: ResolvedStyledText? {
        switch self {
        case let .strong(value):
            return value
        case let .weak(reference):
            return reference.value
        }
    }
}

private final class _ResolvedStyledTextVariantEntry {
    weak var owner: ResolvedStyledText?
    var smaller: _ResolvedStyledTextVariantReference?
    var larger: _ResolvedStyledTextVariantReference?
    var candidateTail: [ResolvedStyledText] = []

    init(owner: ResolvedStyledText) {
        self.owner = owner
    }
}

private final class _ResolvedStyledTextVariantStorage: @unchecked Sendable {
    private enum Direction {
        case smaller
        case larger

        var opposite: Direction {
            switch self {
            case .smaller: .larger
            case .larger: .smaller
            }
        }
    }

    static let shared = _ResolvedStyledTextVariantStorage()

    private let lock = NSRecursiveLock()
    private var entries: [ObjectIdentifier: _ResolvedStyledTextVariantEntry] = [:]

    func smaller(for owner: ResolvedStyledText) -> ResolvedStyledText? {
        value(for: owner, direction: .smaller)
    }

    func larger(for owner: ResolvedStyledText) -> ResolvedStyledText? {
        value(for: owner, direction: .larger)
    }

    func setSmaller(_ value: ResolvedStyledText?, for owner: ResolvedStyledText) {
        set(value, for: owner, direction: .smaller)
    }

    func setLarger(_ value: ResolvedStyledText?, for owner: ResolvedStyledText) {
        set(value, for: owner, direction: .larger)
    }

    func candidates(for owner: ResolvedStyledText) -> [ResolvedStyledText] {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[ObjectIdentifier(owner)] else {
            return [owner]
        }
        return [owner] + entry.candidateTail
    }

    func setCandidates(
        _ candidates: [ResolvedStyledText],
        for owner: ResolvedStyledText
    ) {
        precondition(candidates.first === owner)
        lock.lock()
        defer { lock.unlock() }
        entry(for: owner).candidateTail = Array(candidates.dropFirst())
    }

    func remove(_ owner: ResolvedStyledText) {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries.removeValue(forKey: ObjectIdentifier(owner)) else {
            return
        }
        detachReciprocal(of: owner, target: entry.smaller?.value, direction: .smaller)
        detachReciprocal(of: owner, target: entry.larger?.value, direction: .larger)
    }

    private func value(
        for owner: ResolvedStyledText,
        direction: Direction
    ) -> ResolvedStyledText? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[ObjectIdentifier(owner)] else {
            return nil
        }
        let reference = reference(in: entry, direction: direction)
        if reference?.value == nil {
            setReference(nil, in: entry, direction: direction)
        }
        return reference?.value
    }

    private func set(
        _ value: ResolvedStyledText?,
        for owner: ResolvedStyledText,
        direction: Direction
    ) {
        lock.lock()
        defer { lock.unlock() }

        let ownerEntry = entry(for: owner)
        let previous = reference(in: ownerEntry, direction: direction)?.value
        detachReciprocal(of: owner, target: previous, direction: direction)

        if let value {
            setReference(.strong(value), in: ownerEntry, direction: direction)
            let targetEntry = entry(for: value)
            setReference(
                .weak(_ResolvedStyledTextWeakReference(owner)),
                in: targetEntry,
                direction: direction.opposite
            )
        } else {
            setReference(nil, in: ownerEntry, direction: direction)
        }
    }

    private func detachReciprocal(
        of owner: ResolvedStyledText,
        target: ResolvedStyledText?,
        direction: Direction
    ) {
        guard let target,
              let targetEntry = entries[ObjectIdentifier(target)],
              reference(in: targetEntry, direction: direction.opposite)?.value === owner else {
            return
        }
        setReference(nil, in: targetEntry, direction: direction.opposite)
    }

    private func entry(for owner: ResolvedStyledText) -> _ResolvedStyledTextVariantEntry {
        let identifier = ObjectIdentifier(owner)
        if let entry = entries[identifier], entry.owner != nil {
            return entry
        }
        let entry = _ResolvedStyledTextVariantEntry(owner: owner)
        entries[identifier] = entry
        return entry
    }

    private func reference(
        in entry: _ResolvedStyledTextVariantEntry,
        direction: Direction
    ) -> _ResolvedStyledTextVariantReference? {
        switch direction {
        case .smaller: entry.smaller
        case .larger: entry.larger
        }
    }

    private func setReference(
        _ reference: _ResolvedStyledTextVariantReference?,
        in entry: _ResolvedStyledTextVariantEntry,
        direction: Direction
    ) {
        switch direction {
        case .smaller:
            entry.smaller = reference
        case .larger:
            entry.larger = reference
        }
    }
}

struct StyledTextContentView {
    var text: ResolvedStyledText
    var renderer: TextRendererBoxBase?
    var needsDrawingGroup: Bool

    init(
        text: ResolvedStyledText,
        renderer: TextRendererBoxBase?,
        needsDrawingGroup: Bool = false
    ) {
        self.text = text
        self.renderer = renderer
        self.needsDrawingGroup = needsDrawingGroup
    }

    static var animatesSize: Bool {
        false
    }
}

extension StyledTextContentView: ShapeStyledLeafView {
    typealias ShapeUpdateData = Void

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        let frame = renderer.map { renderer in
            let padding = renderer.displayPadding
            return CGRect(
                x: -padding.leading,
                y: -padding.top,
                width: size.width + padding.leading + padding.trailing,
                height: size.height + padding.top + padding.bottom
            )
        } ?? CGRect(origin: .zero, size: size)
        return (.text(self), frame)
    }
}

final class ResolvedStyledText: InterpolatableContent {
    private struct MetricsCacheEntry {
        var requestedSize: CGSize
        var metrics: GraphicsContext.ResolvedText.LayoutMetrics

        func canReuse(for size: CGSize) -> Bool {
            let minimumWidth = min(metrics.size.width, requestedSize.width)
            let maximumWidth = max(metrics.size.width, requestedSize.width)
            let minimumHeight = min(metrics.size.height, requestedSize.height)
            let maximumHeight = max(metrics.size.height, requestedSize.height)
            return size.width >= minimumWidth &&
                size.width <= maximumWidth &&
                size.height >= minimumHeight &&
                size.height <= maximumHeight
        }
    }

    var layoutProperties: TextLayoutProperties
    var layoutMargins: EdgeInsets
    var scaleFactorOverride: CGFloat?
    var stylePadding: EdgeInsets
    var archiveOptions: ArchivedViewInput.Value
    var isCollapsible: Bool
    var features: Text.ResolvedProperties.Features
    var styles: [_ShapeStyle_Pack.Style]
    var transitions: [Text.ResolvedProperties.Transition]
    var links: Text.ResolvedProperties.Links
    let resolvedText: GraphicsContext.ResolvedText?
    var version: Int
    var transitionText: String?
    var needsDrawingGroup: Bool
    private var attributedStorage: NSAttributedString?
    private var didResolveAttributedStorage: Bool
    private var _computedMaxFontMetrics: ResolvedFontMetrics?
    private var didComputeMaxFontMetrics: Bool
    // Each instance belongs to one scene graph. Layout and renderer measurement
    // on its serialized update task share this cache through retained proxies.
    private var metricsCache: [MetricsCacheEntry]

    init(
        storage: NSAttributedString? = nil,
        layoutProperties: TextLayoutProperties = TextLayoutProperties(),
        layoutMargins: EdgeInsets = EdgeInsets(),
        scaleFactorOverride: CGFloat? = nil,
        stylePadding: EdgeInsets = EdgeInsets(),
        archiveOptions: ArchivedViewInput.Value = ArchivedViewInput.Value(),
        isCollapsible: Bool = false,
        features: Text.ResolvedProperties.Features = [],
        styles: [_ShapeStyle_Pack.Style] = [],
        transitions: [Text.ResolvedProperties.Transition] = [],
        links: Text.ResolvedProperties.Links = Text.ResolvedProperties.Links(),
        resolvedText: GraphicsContext.ResolvedText? = nil,
        version: Int = 0,
        transitionText: String? = nil,
        needsDrawingGroup: Bool = false
    ) {
        self.layoutProperties = layoutProperties
        self.layoutMargins = layoutMargins
        self.scaleFactorOverride = scaleFactorOverride
        self.stylePadding = stylePadding
        self.archiveOptions = archiveOptions
        self.isCollapsible = isCollapsible
        self.features = features
        self.styles = styles
        self.transitions = transitions
        self.links = links
        self.resolvedText = resolvedText
        self.version = version
        self.transitionText = transitionText
        self.needsDrawingGroup = needsDrawingGroup
        self.attributedStorage = storage
        self.didResolveAttributedStorage = storage != nil
        self._computedMaxFontMetrics = nil
        self.didComputeMaxFontMetrics = false
        self.metricsCache = []
    }

    deinit {
        _ResolvedStyledTextVariantStorage.shared.remove(self)
    }

    var smallerSizeVariant: ResolvedStyledText? {
        get { _ResolvedStyledTextVariantStorage.shared.smaller(for: self) }
        set { _ResolvedStyledTextVariantStorage.shared.setSmaller(newValue, for: self) }
    }

    var largerSizeVariant: ResolvedStyledText? {
        get { _ResolvedStyledTextVariantStorage.shared.larger(for: self) }
        set { _ResolvedStyledTextVariantStorage.shared.setLarger(newValue, for: self) }
    }

    var sizeVariantCandidates: [ResolvedStyledText] {
        _ResolvedStyledTextVariantStorage.shared.candidates(for: self)
    }

    func setSizeVariantCandidates(_ candidates: [ResolvedStyledText]) {
        _ResolvedStyledTextVariantStorage.shared.setCandidates(candidates, for: self)
    }

    var storage: NSAttributedString? {
        get {
            if !didResolveAttributedStorage {
                attributedStorage = resolvedText?.attributedStorage
                didResolveAttributedStorage = true
            }
            return attributedStorage
        }
        set {
            attributedStorage = newValue
            didResolveAttributedStorage = true
        }
    }

    func resolvedContent(
        in context: ResolvableStringResolutionContext
    ) -> NSAttributedString? {
        _ = context
        return storage
    }

    var maxFontMetrics: ResolvedFontMetrics? {
        if !didComputeMaxFontMetrics {
            _computedMaxFontMetrics = resolvedText?.maximumFontMetrics
            didComputeMaxFontMetrics = true
        }
        return _computedMaxFontMetrics
    }

    var metricsCacheEntryCount: Int {
        metricsCache.count
    }

    /// Drawing padding is independent of typographic height and baselines.
    var drawingMargins: EdgeInsets {
        let outsets = maxFontMetrics?.outsets ?? EdgeInsets()
        let scale = resolvedText?.displayScale ?? 1
        return EdgeInsets(
            top: ceil((outsets.top + stylePadding.top) * scale) / scale,
            leading: ceil((outsets.leading + stylePadding.leading) * scale) / scale,
            bottom: ceil((outsets.bottom + stylePadding.bottom) * scale) / scale,
            trailing: ceil((outsets.trailing + stylePadding.trailing) * scale) / scale
        )
    }

    var needsStyledRendering: Bool {
        if features.contains(.keyColor) {
            return true
        }
        guard features.contains(.attachments),
              archiveOptions.isArchived else {
            return false
        }
        guard let storage else {
            return true
        }
        return !storage._isDynamicText
    }

    func frame(
        in size: CGSize,
        renderer: TextRendererBoxBase?
    ) -> CGRect {
        guard resolvedText != nil else {
            return CGRect(origin: .zero, size: size)
        }
        let measured = renderer?.sizeThatFits(
            proposal: ProposedViewSize(size),
            text: TextProxy(self)
        ) ?? sizeThatFits(_ProposedSize(size))
        var frame = CGRect(origin: .zero, size: measured)
        if measured.height < size.height {
            frame.origin.y = (size.height - measured.height) * 0.5
        }
        let margins = drawingMargins
        let top = layoutMargins.top - margins.top
        let leading = layoutMargins.leading - margins.leading
        let bottom = layoutMargins.bottom - margins.bottom
        let trailing = layoutMargins.trailing - margins.trailing
        frame.origin.x += leading
        frame.origin.y += top
        frame.size.width -= leading + trailing
        frame.size.height -= top + bottom
        return frame
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        let requestedSize = CGSize(
            width: proposal.width ?? .infinity,
            height: proposal.height ?? .infinity
        )
        if proposal == .zero {
            return .zero
        }
        guard let measured = cachedLayoutMetrics(in: requestedSize)?.size else {
            return .zero
        }
        let result: CGSize
        if proposal.width == 0 {
            result = CGSize(width: 0, height: measured.height)
        } else {
            result = measured
        }
        return result
    }

    func firstBaseline(in size: CGSize) -> CGFloat {
        cachedLayoutMetrics(in: size)?.firstBaseline ?? .zero
    }

    func lastBaseline(in size: CGSize) -> CGFloat {
        cachedLayoutMetrics(in: size)?.lastBaseline ?? .zero
    }

    func spacing() -> Spacing {
        // Measure the unconstrained text before aggregating font metrics.
        // Missing either carrier means there are no text-spacing categories.
        let idealSize = CGSize(
            width: CGFloat.infinity,
            height: CGFloat.infinity
        )
        guard let idealMetrics = cachedLayoutMetrics(in: idealSize),
              let maxFontMetrics else {
            return Spacing()
        }
        return Spacing.textSpacing(
            maxFontMetrics: maxFontMetrics,
            idealMetrics: idealMetrics,
            layoutProperties: layoutProperties
        )
    }

    private func cachedLayoutMetrics(
        in requestedSize: CGSize
    ) -> GraphicsContext.ResolvedText.LayoutMetrics? {
        guard let resolvedText else { return nil }
        if let cached = metricsCache.first(where: {
            $0.canReuse(for: requestedSize)
        }) {
            return cached.metrics
        }

        let measured = resolvedText.layoutMetrics(
            in: requestedSize,
            layoutProperties: layoutProperties
        )
        metricsCache.append(MetricsCacheEntry(
            requestedSize: requestedSize,
            metrics: measured
        ))
        return measured
    }

    var needsDynamicRenderingInArchive: Bool {
        if storage?._isDynamicText == true {
            return true
        }
        guard features.contains(.attachments), let largerSizeVariant else {
            return false
        }
        return largerSizeVariant.needsDynamicRenderingInArchive
    }

    static var defaultTransition: ContentTransition {
        _SemanticFeature<Semantics_v4>.isEnabled ? .interpolate : .identity
    }

    func requiresTransition(to target: ResolvedStyledText) -> Bool {
        if self === target { return false }
        if version == target.version { return false }
        guard let sourceText = transitionText, let targetText = target.transitionText else {
            return true
        }
        return sourceText != targetText
    }

    var appliesTransitionsForSizeChanges: Bool {
        true
    }

    var addsDrawingGroup: Bool {
        needsDrawingGroup
    }

    func modifyTransition(state: inout ContentTransition.State, to target: ResolvedStyledText) {
        guard !state.options.contains(.animatesDifferentContent) else { return }
        guard requiresTransition(to: target) else { return }
        guard !state.transition.isNumericText else { return }
        state.transition = .text
    }
}

struct CodableResolvedStyledText: ProtobufEncodableMessage {
    var base: ResolvedStyledText

    func encode(to encoder: inout ProtobufEncoder) throws {
        try Node(
            base: base,
            candidateTail: Array(base.sizeVariantCandidates.dropFirst()),
            ancestors: []
        ).encode(to: &encoder)
    }

    private struct Node: ProtobufEncodableMessage {
        var base: ResolvedStyledText
        var candidateTail: [ResolvedStyledText]
        var ancestors: Set<ObjectIdentifier>

        func encode(to encoder: inout ProtobufEncoder) throws {
            let identifier = ObjectIdentifier(base)
            guard !ancestors.contains(identifier) else { return }
            var descendants = ancestors
            descendants.insert(identifier)

            if let storage = base.storage {
                try encoder.encodeMessageField(1, CodableAttributedString(storage))
            }
            let stylePadding = Self.rect(base.stylePadding)
            if stylePadding != .zero {
                try encoder.encodeMessageField(2, stylePadding)
            }
            let layoutMargins = Self.rect(base.layoutMargins)
            if layoutMargins != .zero {
                try encoder.encodeMessageField(3, layoutMargins)
            }
            try encoder.encodeMessageField(5, base.layoutProperties)
            if base.features.rawValue != 0 {
                encoder.encodeVarint(7 << 3)
                encoder.encodeVarint(UInt(base.features.rawValue))
            }

            let smaller = base.smallerSizeVariant ?? candidateTail.first
            if let smaller, !descendants.contains(ObjectIdentifier(smaller)) {
                let remainingTail: [ResolvedStyledText]
                if base.smallerSizeVariant == nil {
                    remainingTail = Array(candidateTail.dropFirst())
                } else {
                    remainingTail = Array(smaller.sizeVariantCandidates.dropFirst())
                }
                try encoder.encodeMessageField(
                    8,
                    Node(
                        base: smaller,
                        candidateTail: remainingTail,
                        ancestors: descendants
                    )
                )
            }
            if let larger = base.largerSizeVariant,
               !descendants.contains(ObjectIdentifier(larger)) {
                try encoder.encodeMessageField(
                    9,
                    Node(
                        base: larger,
                        candidateTail: Array(larger.sizeVariantCandidates.dropFirst()),
                        ancestors: descendants
                    )
                )
            }
        }

        private static func rect(_ insets: EdgeInsets) -> CGRect {
            CGRect(
                x: insets.top,
                y: insets.leading,
                width: insets.bottom,
                height: insets.trailing
            )
        }
    }
}

final class DynamicTextPlaceholder: NSObject {
    let text: ResolvedStyledText
    let size: CGSize

    init(text: ResolvedStyledText, size: CGSize) {
        self.text = text
        self.size = size
        super.init()
    }

    var identifier: String {
        "VUI.DynamicText"
    }

    var boundingRect: CGRect {
        CGRect(origin: .zero, size: size)
    }

    func encodedData(delegate: AnyObject? = nil) throws -> Data {
        _ = delegate
        return try ProtobufEncoder.encoding(Archive(text: text, size: size))
    }

    func draw(in context: GraphicsContext) {
        _ = context
    }

    private struct Archive: ProtobufEncodableMessage {
        var text: ResolvedStyledText
        var size: CGSize

        func encode(to encoder: inout ProtobufEncoder) throws {
            try encoder.encodeMessageField(1, CodableResolvedStyledText(base: text))
            try encoder.encodeMessageField(2, size)
        }
    }
}
