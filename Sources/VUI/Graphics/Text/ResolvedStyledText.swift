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

        mutating func addColor(_ color: Color.ResolvedHDR) {
            if color.base.linearRed == -1 && color.base.linearGreen == -1 {
                features.insert(.keyColor)
            }
        }

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

class ResolvedStyledText: InterpolatableContent {
    fileprivate struct MeasurementEntry {
        var requestedSize: CGSize
        var metrics: ResolvedTextSource.LayoutMetrics

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
    var scaleFactorOverride: CGFloat? {
        didSet { resetCache() }
    }
    var stylePadding: EdgeInsets
    var archiveOptions: ArchivedViewInput.Value
    var isCollapsible: Bool
    var features: Text.ResolvedProperties.Features
    var styles: [_ShapeStyle_Pack.Style]
    var transitions: [Text.ResolvedProperties.Transition]
    var links: Text.ResolvedProperties.Links
    let resolvedText: ResolvedTextSource?
    var version: Int
    var transitionText: String?
    var needsDrawingGroup: Bool
    private var attributedStorage: NSAttributedString?
    private var didResolveAttributedStorage: Bool
    private var _computedMaxFontMetrics: ResolvedFontMetrics?
    private var didComputeMaxFontMetrics: Bool
    required init(
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
        resolvedText: ResolvedTextSource? = nil,
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
        0
    }

    func resetCache() {
        fatalError("ResolvedStyledText cache reset requires a concrete owner")
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
        guard resolvedText != nil else { return .zero }
        fatalError("ResolvedStyledText sizing requires a concrete owner")
    }

    func size(in size: CGSize) -> CGSize {
        fatalError("ResolvedStyledText measurement requires a concrete owner")
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

    func cachedLayoutMetrics(
        in requestedSize: CGSize
    ) -> ResolvedTextSource.LayoutMetrics? {
        guard resolvedText != nil else { return nil }
        fatalError("ResolvedStyledText measurement requires a concrete owner")
    }

    func metrics(in size: CGSize, layoutMargins: EdgeInsets?) -> NSAttributedString.Metrics {
        fatalError("ResolvedStyledText metrics require a concrete producer")
    }

    func textSizeCacheMetrics(in size: CGSize) -> (UInt?, CGSize) {
        let value = metrics(in: size, layoutMargins: nil)
        return (value.numberOfLines, value.size)
    }

    func drawingSource(in size: CGSize) -> ResolvedTextSource? {
        resolvedText
    }

    func drawingGlyphs(in size: CGSize) -> (source: ResolvedTextSource,
                                          lines: [ResolvedTextSource.LineGlyphs])? {
        guard let source = drawingSource(in: size) else { return nil }
        return (source, source.makeGlyphLayout(in: size, layoutProperties: layoutProperties).lines)
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

extension ResolvedStyledText {
    final class StringDrawing: ResolvedStyledText {
        /// Retains prepared source lines across constraint changes. The arrays
        /// share immutable glyph data with the resource's existing storage.
        final class PreparedLayout {
            let source: ResolvedTextSource
            let lines: [ResolvedTextSource.LineGlyphs]

            init(source: ResolvedTextSource, lines: [ResolvedTextSource.LineGlyphs]) {
                self.source = source
                self.lines = lines
            }
        }

        private struct Fragment {
            var lineRect: CGRect
            var usedRect: CGRect
            var glyphRange: Range<Int>
            var baselineOffset: CGFloat

            var baseline: CGFloat { lineRect.minY + baselineOffset }
        }

        // Retained proxies and the host share this owner's measurement entries.
        private var measurements: [(requestedSize: CGSize, metrics: NSAttributedString.Metrics)] = []
        private var measurementSource: ResolvedTextSource?
        private(set) var preparedLayout: PreparedLayout?

        override var metricsCacheEntryCount: Int { measurements.count }

        override func resetCache() {
            measurementSource = resolvedText?.scalingFonts(by: scaleFactorOverride ?? 1)
            preparedLayout = nil
            measurements.removeAll()
        }

        override func drawingSource(in size: CGSize) -> ResolvedTextSource? {
            guard let resolvedText else { return nil }
            _ = cachedMetrics(in: size)
            let scale = drawingScale(size: size)
            if scale == 1, let preparedLayout { return preparedLayout.source }
            return resolvedText.scalingFonts(by: scale)
        }

        func drawingScale(size: CGSize) -> CGFloat {
            scaleFactorOverride ?? (layoutProperties.minScaleFactor == 1 ? 1 : cachedMetrics(in: size).scale)
        }

        override func drawingGlyphs(in size: CGSize) -> (source: ResolvedTextSource,
                                                        lines: [ResolvedTextSource.LineGlyphs])? {
            guard let source = drawingSource(in: size) else { return nil }
            let prepared = drawingScale(size: size) == 1 ? preparedLayout : nil
            return (source, source.makeGlyphLayout(in: size, layoutProperties: layoutProperties,
                                                   sourceLines: prepared?.lines).lines)
        }

        override func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            guard proposal != .zero else { return .zero }
            return cachedLayoutMetrics(in: CGSize(
                width: proposal.width ?? .infinity,
                height: proposal.height ?? .infinity
            ))?.size ?? .zero
        }

        override func cachedLayoutMetrics(in size: CGSize) -> ResolvedTextSource.LayoutMetrics? {
            guard resolvedText != nil else { return nil }
            let metrics = cachedMetrics(in: size)
            return .init(size: metrics.size, firstBaseline: metrics.firstBaseline, lastBaseline: metrics.lastBaseline)
        }

        override func size(in size: CGSize) -> CGSize {
            cachedMetrics(in: size).size
        }

        override func metrics(in size: CGSize, layoutMargins: EdgeInsets?) -> NSAttributedString.Metrics {
            cachedMetrics(in: size, layoutMargins: layoutMargins, wantsNumberOfLineFragments: true)
        }

        func cachedMetrics(in size: CGSize, layoutMargins: EdgeInsets? = nil,
                           wantsNumberOfLineFragments: Bool = false) -> NSAttributedString.Metrics {
            if measurementSource == nil {
                measurementSource = resolvedText?.scalingFonts(by: scaleFactorOverride ?? 1)
            }
            guard let resolvedText = measurementSource else {
                fatalError("StringDrawing metrics require resolved text")
            }
            if let entry = measurements.first(where: { entry in
                (!wantsNumberOfLineFragments || entry.metrics.numberOfLines != nil)
                    && size.width >= min(entry.requestedSize.width, entry.metrics.size.width)
                    && size.width <= max(entry.requestedSize.width, entry.metrics.size.width)
                    && size.height >= min(entry.requestedSize.height, entry.metrics.size.height)
                    && size.height <= max(entry.requestedSize.height, entry.metrics.size.height)
            }) {
                return entry.metrics
            }
            let layoutMargins = layoutMargins ?? self.layoutMargins
            let available = CGSize(width: max(size.width - layoutMargins.leading - layoutMargins.trailing, 0),
                                   height: max(size.height - layoutMargins.top - layoutMargins.bottom, 0))
            func drawingDimension(_ value: CGFloat) -> CGFloat {
                if value <= 0 { return .leastNonzeroMagnitude }
                return value == .infinity ? .greatestFiniteMagnitude : value
            }
            let requestedWidth = available.width + layoutProperties.bodyHeadOutdent
            let normalizedWidth = drawingDimension(requestedWidth)
            let normalizedHeight = drawingDimension(available.height)
            let drawingSize = CGSize(width: normalizedWidth, height: normalizedHeight)
            let fitted = scaleFactorOverride == nil ? fontFittingMetrics(in: drawingSize, source: resolvedText) : nil
            let measurement: FittingMeasurement
            if let fitted {
                // Font fitting measures independent candidates with layout
                // retention disabled, including a natural-size early return.
                preparedLayout = nil
                measurement = fitted.measurement
            } else {
                let sources = preparedLayout?.lines ?? resolvedText.unwrappedGlyphLines()
                if preparedLayout == nil, !resolvedText.hasAttachments,
                   sources.contains(where: { !$0.glyphs.isEmpty }) {
                    preparedLayout = PreparedLayout(source: resolvedText, lines: sources)
                }
                measurement = fittingMeasurement(in: drawingSize, source: resolvedText,
                    layoutProperties: layoutProperties, sourceLines: sources)
            }
            var metrics = measurement.metrics
            let clippedWidth = fitted == nil ? min(metrics.size.width, normalizedWidth) : metrics.size.width
            let width = clippedWidth == CGFloat.leastNonzeroMagnitude ? 0 : clippedWidth
            let height = metrics.size.height == .leastNonzeroMagnitude ? 0 : metrics.size.height
            let pixelLength = 1 / resolvedText.displayScale
            metrics.size.width = (layoutMargins.leading + layoutMargins.trailing)
                + ceil(width / pixelLength) * pixelLength
            metrics.size.height = (layoutMargins.top + layoutMargins.bottom)
                + ceil(height / pixelLength) * pixelLength
            // Retain raw baselines through margin application. The first
            // baseline's rounding adjustment also affects the last baseline.
            let firstBaseline = layoutMargins.top + metrics.firstBaseline
            metrics.firstBaseline = (firstBaseline / pixelLength).rounded() * pixelLength
            let adjustment = metrics.firstBaseline - firstBaseline
            metrics.lastBaseline = ceil((layoutMargins.top + metrics.lastBaseline + adjustment)
                / pixelLength) * pixelLength
            let result = NSAttributedString.Metrics(size: metrics.size, scale: fitted?.scale ?? 1,
                firstBaseline: metrics.firstBaseline, lastBaseline: metrics.lastBaseline,
                baselineAdjustment: adjustment, requestedWidth: requestedWidth,
                numberOfLines: wantsNumberOfLineFragments || layoutProperties.bodyHeadOutdent > 0
                    ? UInt(measurement.lineCount) : nil,
                hasTruncatedRanges: !measurement.truncatedRanges.isEmpty)
            measurements.append((requestedSize: size, metrics: result))
            return result
        }

        private func fontFittingMetrics(
            in size: CGSize, source: ResolvedTextSource
        ) -> (measurement: FittingMeasurement, scale: CGFloat)? {
            let minimum = layoutProperties.minScaleFactor
            guard minimum > 0, minimum < 1, let font = source.uniformFont,
                  let string = source.uniformString, source.fontResolutionContext != nil else { return nil }
            let limit = layoutProperties.lineLimit
            // Explicit separators in a one-line request retain their ordinary
            // paragraph path until that path supplies its own fitting producer.
            if limit == 1, string.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) }) {
                return nil
            }
            let naturalSize = CGSize(width: limit == 1 ? 9_000_000 : size.width, height: 9_000_000)
            var fittingProperties = layoutProperties
            var original = fittingMeasurement(in: naturalSize, source: source, layoutProperties: fittingProperties)
            if let limit, limit > 1, limit < Int.max {
                fittingProperties.lineLimit = limit + 1
                original = fittingMeasurement(in: naturalSize, source: source, layoutProperties: fittingProperties)
            }
            var ratio = size.height / original.metrics.size.height
            if limit == 1 {
                ratio = size.width / original.metrics.size.width
                if ratio > 1 { ratio = size.height / original.metrics.size.height }
            }
            let countOverflow = limit.map { $0 > 1 && original.lineCount > $0 } ?? false
            if (max(minimum, min(1, ratio)) >= 1 && !countOverflow)
                || abs(1 - minimum) < CGFloat(Float.ulpOfOne) {
                return (original, 1)
            }
            func resized(_ scale: CGFloat) -> ResolvedTextSource? {
                source.resizingUniformFont(to: (font.pointSize * scale * 4).rounded() * 0.25)
            }
            func oversized(_ candidate: ResolvedTextSource) -> Bool {
                let measured = fittingMeasurement(in: naturalSize, source: candidate, layoutProperties: fittingProperties)
                if limit == 1 {
                    return measured.metrics.size.width > size.width || measured.metrics.size.height > size.height
                }
                return measured.metrics.size.height > size.height
                    || limit.map { measured.lineCount > $0 } == true
                    || (string.utf16.count <= 512 && measured.forcedClusterBreak)
            }
            func finish(_ candidate: ResolvedTextSource, scale: CGFloat)
                -> (FittingMeasurement, CGFloat) {
                var measured = fittingMeasurement(in: size, source: candidate, layoutProperties: layoutProperties)
                // Restore the logical constraint after backend pixel quantization.
                measured.metrics.size.width = min(measured.metrics.size.width, size.width)
                return (measured, scale)
            }
            var low = minimum
            var high: CGFloat = 1
            if minimum > 0.01 {
                guard let candidate = resized(minimum) else { return nil }
                if candidate.uniformFont?.pointSize != font.pointSize, oversized(candidate) {
                    return finish(candidate, scale: minimum)
                }
            }
            var sawFit = false
            var lastScale = minimum
            var lastCandidate = source
            for attempt in 0..<20 {
                let mid = high + (high - low) * -0.5
                guard let candidate = resized(mid) else { return nil }
                lastScale = mid
                lastCandidate = candidate
                if oversized(candidate) {
                    high = mid
                } else {
                    low = mid
                    sawFit = true
                }
                if attempt == 19 || (sawFit && high - low < 0.01) { break }
            }
            if lastScale != low {
                guard let accepted = resized(low) else { return nil }
                lastCandidate = accepted
            }
            return finish(lastCandidate, scale: low)
        }

        private struct FittingMeasurement {
            var metrics: ResolvedTextSource.LayoutMetrics
            var lineCount: Int
            var forcedClusterBreak: Bool
            var truncatedRanges: [Range<Int>]
        }

        private func fittingMeasurement(
            in size: CGSize, source: ResolvedTextSource, layoutProperties: TextLayoutProperties,
            sourceLines: [ResolvedTextSource.LineGlyphs]? = nil
        ) -> FittingMeasurement {
            let sources = sourceLines ?? source.unwrappedGlyphLines()
            if let measured = separatorMeasurement(in: size, source: source, sources: sources,
                                                    layoutProperties: layoutProperties)
                ?? trailingParagraphMeasurement(in: size, source: source, sources: sources,
                                                layoutProperties: layoutProperties) {
                return measured
            }
            let width = size.width * source.scaleFactor
            let layout = source.makeGlyphLayout(
                maxWidth: width >= CGFloat(Int.max) ? .max : Int(ceil(width)),
                maximumHeight: size.height * source.scaleFactor,
                lineLimit: layoutProperties.lineLimit, truncationMode: layoutProperties.truncationMode,
                sourceLines: sources)
            return .init(metrics: source.unroundedLayoutMetrics(lineGlyphs: layout.lines), lineCount: layout.lineCount,
                         forcedClusterBreak: layout.forcedClusterBreak, truncatedRanges: layout.truncatedRanges)
        }

        private func separatorMeasurement(
            in size: CGSize,
            source resolvedText: ResolvedTextSource,
            sources: [ResolvedTextSource.LineGlyphs],
            layoutProperties: TextLayoutProperties
        ) -> FittingMeasurement? {
            guard let extra = sources.last,
                  case .extra = extra.kind, sources.count > 1,
                  layoutProperties.truncationMode == .tail else { return nil }
            let paragraphs = sources.dropLast()
            guard let firstInput = paragraphs.first?.paragraphInput,
                  let font = firstInput.fontLineMetrics, font.leading == 0 else { return nil }
            let spacing = firstInput.style.paragraphStyle?.lineSpacing ?? 0
            guard spacing.isFinite, spacing >= 0 else { return nil }
            // This fragment path handles uniform separator paragraphs. Other
            // paragraph attributes continue through the existing layout producer.
            for line in paragraphs {
                guard line.glyphs.isEmpty, let boundary = line.trailingBoundary,
                      let input = line.paragraphInput,
                      boundary.sourceRange != nil,
                      [0x0a, 0x0d, 0x2028, 0x2029].contains(boundary.scalar.value),
                      boundary.fontLineMetrics == font, input.fontLineMetrics == font,
                      boundary.baselineOffset == 0, input.baselineOffset == 0,
                      (boundary.style.paragraphStyle?.lineSpacing ?? 0) == spacing,
                      (input.style.paragraphStyle?.lineSpacing ?? 0) == spacing else { return nil }
            }
            let height = font.height / resolvedText.scaleFactor
            let baseline = font.ascent / resolvedText.scaleFactor
            let limit = layoutProperties.lineLimit.map { max($0, 1) } ?? .max
            var fragments: [Fragment] = []
            var usedExtent = CGSize.zero
            var invalidUsage = false
            var nextParagraph = paragraphs.startIndex
            var retriedEnd: Int?

            func publish(_ fragment: Fragment) {
                fragments.append(fragment)
                if !invalidUsage {
                    usedExtent.width = max(usedExtent.width, fragment.usedRect.maxX)
                    usedExtent.height = max(usedExtent.height, fragment.usedRect.maxY)
                }
            }

            while nextParagraph < paragraphs.endIndex {
                let origin = fragments.last?.lineRect.maxY ?? 0
                if !fragments.isEmpty,
                   fragments.count >= limit || origin + height > size.height {
                    // Empty paragraphs backtrack to the first adjacent pair.
                    // The merged content range occupies one ordinary fragment;
                    // later separators are laid out again from that range's end.
                    let first = fragments[0]
                    let end = fragments.dropFirst().first?.glyphRange.upperBound ?? first.glyphRange.upperBound
                    guard retriedEnd != end else { break }
                    retriedEnd = end
                    let invalidatesUsage = fragments.count > 1
                    fragments.removeAll(keepingCapacity: true)
                    let lineRect = CGRect(x: 0, y: 0, width: size.width, height: height)
                    var usedRect = CGRect(x: 0, y: 0, width: 0, height: height)
                    if usedRect.intersection(lineRect).isEmpty, usedRect.width == 0 {
                        usedRect.size.width = 1
                    }
                    publish(Fragment(lineRect: lineRect, usedRect: usedRect,
                        glyphRange: first.glyphRange.lowerBound..<end, baselineOffset: baseline))
                    // A single-fragment replacement accumulates usage. A range
                    // spanning multiple fragments invalidates it for reduction.
                    invalidUsage = invalidUsage || invalidatesUsage
                    nextParagraph = paragraphs.firstIndex {
                        $0.trailingBoundary!.sourceRange!.upperBound == end
                    }! + 1
                    continue
                }
                let lineHeight: CGFloat
                if fragments.isEmpty {
                    lineHeight = min(height + spacing, size.height)
                } else {
                    // When the complete spacing does not fit, retain the font
                    // rectangle without spacing rather than clipping the spacing.
                    lineHeight = origin + height + spacing <= size.height ? height + spacing : height
                }
                let lineRect = CGRect(x: 0, y: origin, width: size.width, height: lineHeight)
                let usedRect = CGRect(x: 0, y: origin, width: 0, height: lineHeight)
                publish(Fragment(lineRect: lineRect, usedRect: usedRect,
                    glyphRange: paragraphs[nextParagraph].trailingBoundary!.sourceRange!,
                    baselineOffset: usedRect.maxY - lineRect.minY))
                nextParagraph += 1
            }
            let first = fragments[0]
            let last = fragments.last!
            let contentEnd = paragraphs.last!.trailingBoundary!.sourceRange!.upperBound
            let firstBaseline = first.glyphRange.upperBound == contentEnd ? first.baseline : baseline
            let lastBaseline = last.baseline
            let end = last.glyphRange.upperBound
            if nextParagraph == paragraphs.endIndex, last.lineRect.maxY + height <= size.height {
                let lineRect = CGRect(x: 0, y: last.lineRect.maxY, width: size.width, height: height)
                publish(Fragment(lineRect: lineRect,
                    usedRect: CGRect(x: 0, y: lineRect.minY, width: 0, height: height),
                    glyphRange: end..<end, baselineOffset: 0))
            }
            if invalidUsage {
                usedExtent = fragments.reduce(CGSize.zero) {
                    CGSize(width: max($0.width, $1.usedRect.maxX), height: max($0.height, $1.usedRect.maxY))
                }
            }
            let count = fragments.lazy.filter { !$0.glyphRange.isEmpty }.count
            return .init(metrics: .init(size: usedExtent, firstBaseline: firstBaseline, lastBaseline: lastBaseline),
                         lineCount: count, forcedClusterBreak: false, truncatedRanges: [])
        }

        private func trailingParagraphMeasurement(
            in size: CGSize,
            source resolvedText: ResolvedTextSource,
            sources: [ResolvedTextSource.LineGlyphs],
            layoutProperties: TextLayoutProperties
        ) -> FittingMeasurement? {
            guard sources.count == 2,
                  !sources[0].glyphs.isEmpty, sources[0].trailingBoundary != nil,
                  case .extra = sources[1].kind,
                  layoutProperties.truncationMode == .tail,
                  layoutProperties.lineLimit.map({ $0 >= 2 }) ?? true else { return nil }
            let pixelWidth = size.width * resolvedText.scaleFactor
            let lines = resolvedText.makeGlyphLayout(
                maxWidth: pixelWidth > CGFloat(Int.max) ? .max : Int(ceil(pixelWidth)),
                maximumHeight: .infinity, sourceLines: sources).lines
            // A completed single content line admits its trailing fragment only
            // when that complete rectangle fits. It does not truncate the line
            // merely because the final empty fragment failed the height check.
            guard lines.count == 2, case .extra = lines[1].kind else { return nil }
            let admitsExtra = lines[1].maxY / resolvedText.scaleFactor <= size.height
            let admitted = admitsExtra ? lines : [lines[0]]
            return .init(metrics: resolvedText.unroundedLayoutMetrics(lineGlyphs: admitted),
                         lineCount: admitsExtra ? 2 : 1, forcedClusterBreak: false, truncatedRanges: [])
        }
    }

    final class TextLayoutManager: ResolvedStyledText {
        private var measurements: [MeasurementEntry] = []

        override var metricsCacheEntryCount: Int { measurements.count }

        override func resetCache() {}

        override func size(in size: CGSize) -> CGSize {
            cachedLayoutMetrics(in: size)?.size ?? .zero
        }

        override func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            guard proposal != .zero else { return .zero }
            return cachedLayoutMetrics(in: CGSize(
                width: proposal.width ?? .infinity,
                height: proposal.height ?? .infinity
            ))?.size ?? .zero
        }

        override func cachedLayoutMetrics(in size: CGSize) -> ResolvedTextSource.LayoutMetrics? {
            guard let resolvedText else { return nil }
            if let entry = measurements.first(where: { $0.canReuse(for: size) }) {
                return entry.metrics
            }
            let available = CGSize(width: max(size.width - layoutMargins.leading - layoutMargins.trailing, 0),
                                   height: max(size.height - layoutMargins.top - layoutMargins.bottom, 0))
            let width = available.width > 0 ? available.width : CGFloat.leastNonzeroMagnitude
            let pixelWidth = width * resolvedText.scaleFactor
            let lines = resolvedText.makeGlyphs(
                maxWidth: pixelWidth > CGFloat(Int.max) ? .max : Int(ceil(pixelWidth)),
                maximumHeight: available.height * resolvedText.scaleFactor,
                lineLimit: layoutProperties.lineLimit, truncationMode: layoutProperties.truncationMode)
            var metrics = resolvedText.layoutMetrics(lineGlyphs: lines)
            if lines.isEmpty {
                metrics.firstBaseline = 0
                metrics.lastBaseline = 0
            }
            metrics.size.width = ceil(min(metrics.size.width, width) * resolvedText.displayScale) / resolvedText.displayScale
            measurements.append(MeasurementEntry(requestedSize: size, metrics: metrics))
            return metrics
        }
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
