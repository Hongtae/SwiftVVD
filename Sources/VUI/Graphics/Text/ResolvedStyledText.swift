//
//  File: ResolvedStyledText.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

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

        struct FontMetrics {
            var capHeight: CGFloat = 0
            var ascender: CGFloat = 0
            var descender: CGFloat = 0
            var leading: CGFloat = 0
            var pointSize: CGFloat = 0
            var outsets = EdgeInsets()

            var resolvedMetrics: ResolvedFontMetrics {
                .init(capHeight: capHeight, ascender: ascender, descender: descender,
                      leading: leading, outsets: outsets)
            }
        }

        struct Fonts {
            struct FontPointer: Hashable, Sendable {
                var font: FontResource

                static func == (lhs: Self, rhs: Self) -> Bool { lhs.font === rhs.font }
                func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(font)) }
            }

            enum Storage: Sequence, Sendable {
                case font(FontResource), fonts(Set<FontPointer>), empty

                mutating func insert(_ font: FontResource) {
                    switch self {
                    case .empty:
                        self = .font(font)
                    case let .font(previous):
                        if previous !== font {
                            self = .fonts([FontPointer(font: previous), FontPointer(font: font)])
                        }
                    case var .fonts(fonts):
                        fonts.insert(FontPointer(font: font))
                        self = .fonts(fonts)
                    }
                }

                struct Iterator: IteratorProtocol {
                    enum Storage {
                        case font(FontResource), fonts(Set<FontPointer>.Iterator), empty
                    }
                    var storage: Storage

                    mutating func next() -> FontResource? {
                        switch storage {
                        case let .font(font):
                            storage = .empty
                            return font
                        case var .fonts(iterator):
                            let font = iterator.next()?.font
                            storage = .fonts(iterator)
                            return font
                        case .empty:
                            return nil
                        }
                    }
                }

                func makeIterator() -> Iterator {
                    switch self {
                    case let .font(font): .init(storage: .font(font))
                    case let .fonts(fonts): .init(storage: .fonts(fonts.makeIterator()))
                    case .empty: .init(storage: .empty)
                    }
                }
            }

            // Value copies share retention until mutation. Termination releases
            // references from every copy, including an externally retained source.
            private final class Resources: AppLifetimeResource, @unchecked Sendable {
                let state: Mutex<Storage>
                init(_ storage: Storage) { state = Mutex(storage) }
                override func purgeResources(reason: ResourcePurgeReason) {
                    if reason == .appTermination { state.withLock { $0 = .empty } }
                }
            }
            private var resources: Resources?

            var storage: Storage {
                get { resources?.state.withLock { $0 } ?? .empty }
                set {
                    if case .empty = newValue {
                        resources = nil
                    } else if isKnownUniquelyReferenced(&resources) {
                        resources!.state.withLock { $0 = newValue }
                    } else {
                        resources = Resources(newValue)
                    }
                }
            }

            init() {}

            init(_ text: NSAttributedString) {
                text.enumerateAttribute(.coreFont, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                    if let font = value as? Font,
                       let provider = font.provider as? FontBox<Font.PlatformFontProvider> {
                        storage.insert(provider.base.font)
                    }
                }
            }

            func purgeResources(reason: ResourcePurgeReason) {
                resources?.purgeResources(reason: reason)
            }

            func maxMetrics(for text: ResolvedTextSource) -> FontMetrics {
                var result = FontMetrics()
                var isFirst = true
                for font in storage {
                    guard let metrics = text.metrics(for: font) else { continue }
                    result.capHeight = max(result.capHeight, metrics.capHeight)
                    result.ascender = max(result.ascender, metrics.ascender)
                    result.descender = min(result.descender, metrics.descender)
                    result.leading = isFirst ? metrics.leading : max(result.leading, metrics.leading)
                    result.pointSize = max(result.pointSize, font.pointSize)
                    result.outsets.top = max(result.outsets.top, metrics.outsets.top)
                    result.outsets.leading = max(result.outsets.leading, metrics.outsets.leading)
                    result.outsets.bottom = max(result.outsets.bottom, metrics.outsets.bottom)
                    result.outsets.trailing = max(result.outsets.trailing, metrics.outsets.trailing)
                    isFirst = false
                }
                return result
            }

            func oversizedDrawingMargin(for text: ResolvedTextSource) -> EdgeInsets {
                guard text.hasOversizedLayoutScalars else { return .init() }
                var result = EdgeInsets()
                for font in storage {
                    guard let outsets = text.languageAwareOutsets(for: font) else { continue }
                    result.top = max(result.top, outsets.top)
                    result.leading = max(result.leading, outsets.leading)
                    result.bottom = max(result.bottom, outsets.bottom)
                    result.trailing = max(result.trailing, outsets.trailing)
                }
                return result
            }
        }

        struct LineHeightMetrics {
            var multiple: CGFloat?
            var exact: CGFloat?
            var leading: CGFloat?

            var isCustomized: Bool {
                multiple != nil || exact != nil || leading != nil
            }

            mutating func update(_ height: TextLineHeight) {
                switch height {
                case .variable:
                    break
                case let .multiple(factor):
                    multiple = min(CGFloat(factor), multiple ?? CGFloat(factor))
                case let .exact(points):
                    exact = min(CGFloat(points), exact ?? CGFloat(points))
                case let .leading(increase):
                    leading = min(CGFloat(increase), leading ?? CGFloat(increase))
                }
            }
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
        var fonts: Fonts
        var lineHeightMetrics: LineHeightMetrics

        mutating func addColor(_ color: Color.ResolvedHDR) {
            if color.base.linearRed == -1 && color.base.linearGreen == -1 {
                features.insert(.keyColor)
            }
        }

        mutating func addCustomStyle(_ style: _ShapeStyle_Pack.Style) -> Color.ResolvedHDR {
            if case var .color(color) = style.fill, style.effects.isEmpty,
               style._blend == nil || style._blend == .normal {
                color.opacity *= style.opacity
                return color
            }
            let index: Int
            if let existing = styles.firstIndex(of: style) {
                index = existing
            } else {
                index = styles.count
                styles.append(style)
                features.insert(.keyColor)
            }
            return Color.ResolvedHDR(.init(colorSpace: .sRGBLinear,
                red: -1, green: -1, blue: Float(index) / 1024, opacity: 1))
        }

        init(
            insets: EdgeInsets = EdgeInsets(),
            features: Features = [],
            styles: [_ShapeStyle_Pack.Style] = [],
            transitions: [Transition] = [],
            suffix: ResolvedTextSuffix = .none,
            customAttachments: CustomAttachments = CustomAttachments(),
            paragraph: Paragraph = Paragraph(),
            multilineTextAlignment: TextAlignment? = nil,
            fonts: Fonts = .init(),
            lineHeightMetrics: LineHeightMetrics = .init()
        ) {
            self.insets = insets
            self.features = features
            self.styles = styles
            self.transitions = transitions
            self.suffix = suffix
            self.customAttachments = customAttachments
            self.paragraph = paragraph
            self.multilineTextAlignment = multilineTextAlignment
            self.fonts = fonts
            self.lineHeightMetrics = lineHeightMetrics
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

    static func _makeInnerView(
        view: _GraphValue<Self>, inputs: _ViewInputs,
        styles: Attribute<_ShapeStyle_Pack>, interpolatorGroup: _ShapeStyle_InterpolatorGroup?
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("StyledTextContentView._makeInnerView requires an active AttributeGraph context.")
        }
        var outputs = makeLeafView(view: view, inputs: inputs,
            styles: styles, interpolatorGroup: interpolatorGroup)
        if inputs.preferences.keys.contains(Text.LayoutKey.self) {
            let query = graph.makeRule(TextLayoutQuery(
                _resolvedText: view[\.text]._attribute,
                _position: inputs.position,
                _size: _GraphValue(_attribute: inputs.size)[\.value]._attribute,
                _transform: inputs.transform
            ))
            outputs.preferences.append(Text.LayoutKey.self, node: query.identifier)
        }
        return outputs
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

class ResolvedStyledText: AppLifetimeResource, InterpolatableContent, @unchecked Sendable {
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
    let fonts: Text.ResolvedProperties.Fonts
    let maxFontMetrics: Text.ResolvedProperties.FontMetrics
    var lineHeightMetrics: Text.ResolvedProperties.LineHeightMetrics
    let resolvedText: ResolvedTextSource?
    var version: Int
    var transitionText: String?
    var needsDrawingGroup: Bool
    private var attributedStorage: NSAttributedString?
    private var didResolveAttributedStorage: Bool
    required init(
        storage: NSAttributedString? = nil,
        layoutProperties: TextLayoutProperties = TextLayoutProperties(),
        layoutMargins: EdgeInsets? = nil,
        scaleFactorOverride: CGFloat? = nil,
        stylePadding: EdgeInsets = EdgeInsets(),
        archiveOptions: ArchivedViewInput.Value = ArchivedViewInput.Value(),
        isCollapsible: Bool = false,
        features: Text.ResolvedProperties.Features = [],
        suffix: ResolvedTextSuffix = .none,
        attachments: Text.ResolvedProperties.CustomAttachments = .init(),
        styles: [_ShapeStyle_Pack.Style] = [],
        transitions: [Text.ResolvedProperties.Transition] = [],
        links: Text.ResolvedProperties.Links = Text.ResolvedProperties.Links(),
        fonts: Text.ResolvedProperties.Fonts? = nil,
        lineHeightMetrics: Text.ResolvedProperties.LineHeightMetrics = .init(),
        resolvedText: ResolvedTextSource? = nil,
        version: Int = 0,
        transitionText: String? = nil,
        needsDrawingGroup: Bool = false
    ) {
        self.layoutProperties = layoutProperties
        self.scaleFactorOverride = scaleFactorOverride
        self.stylePadding = stylePadding
        self.archiveOptions = archiveOptions
        self.isCollapsible = isCollapsible
        self.features = features
        self.styles = styles
        self.transitions = transitions
        self.links = links
        let fonts = fonts ?? resolvedText?.resolvedProperties?.fonts ?? storage.map(Text.ResolvedProperties.Fonts.init) ?? .init()
        self.fonts = fonts
        let maxFontMetrics: Text.ResolvedProperties.FontMetrics
        if let resolvedText {
            if case .empty = fonts.storage, let metrics = resolvedText.maximumFontMetrics {
                // Raw backend runs have no retained font request or point size.
                maxFontMetrics = .init(capHeight: metrics.capHeight, ascender: metrics.ascender,
                    descender: metrics.descender, leading: metrics.leading, outsets: metrics.outsets)
            } else {
                maxFontMetrics = fonts.maxMetrics(for: resolvedText)
            }
        } else {
            maxFontMetrics = .init()
        }
        self.maxFontMetrics = maxFontMetrics
        if let layoutMargins {
            self.layoutMargins = layoutMargins
        } else if storage != nil || resolvedText != nil {
            // Source-backed owners can defer materializing attributed storage.
            let pixelLength = layoutProperties.pixelLength
            let height = maxFontMetrics.ascender - maxFontMetrics.descender
            var margins = EdgeInsets()
            switch layoutProperties.textSizing.storage {
            case .standard:
                break
            case .uniformLineHeight:
                let leading = lineHeightMetrics.leading ?? maxFontMetrics.leading
                if leading != 0 {
                    let inset = (height - ceil(height / pixelLength) * pixelLength + leading) / 2
                    margins.top = inset
                    margins.bottom = inset
                }
            case .adjustsForOversizedCharacters:
                if let resolvedText {
                    let outsets = fonts.oversizedDrawingMargin(for: resolvedText)
                    margins = EdgeInsets(top: ceil(outsets.top / pixelLength) * pixelLength,
                        leading: ceil(outsets.leading / pixelLength) * pixelLength,
                        bottom: ceil(outsets.bottom / pixelLength) * pixelLength,
                        trailing: ceil(outsets.trailing / pixelLength) * pixelLength)
                }
            }
            if layoutProperties.writingMode == .verticalRightToLeft {
                margins = EdgeInsets(top: margins.leading, leading: margins.bottom,
                    bottom: margins.trailing, trailing: margins.top)
            }
            for modifier in layoutProperties.textSizing.modifiers.reversed() {
                modifier.updateLayoutMargins(&margins)
            }
            if layoutProperties.textBaseline == .balanced {
                var target = lineHeightMetrics.multiple.map { $0 * maxFontMetrics.pointSize }
                if let exact = lineHeightMetrics.exact { target = max(target ?? exact, exact) }
                if let leading = lineHeightMetrics.leading {
                    let value = maxFontMetrics.pointSize + leading
                    target = max(target ?? value, value)
                }
                if let target {
                    let delta = (height - target) / 2
                    if layoutProperties.writingMode == .verticalRightToLeft {
                        margins.leading += delta
                        margins.trailing -= delta
                    } else {
                        margins.top -= delta
                        margins.bottom += delta
                    }
                }
            }
            self.layoutMargins = margins
        } else {
            self.layoutMargins = .init()
        }
        self.lineHeightMetrics = lineHeightMetrics
        self.resolvedText = resolvedText
        self.version = version
        self.transitionText = transitionText
        self.needsDrawingGroup = needsDrawingGroup
        self.attributedStorage = storage
        self.didResolveAttributedStorage = storage != nil
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

    override func purgeResources(reason: ResourcePurgeReason) {
        guard reason == .appTermination else { return }
        fonts.purgeResources(reason: reason)
        resolvedText?.purgeResources(reason: reason)
        attributedStorage = nil
        didResolveAttributedStorage = true
    }

    var metricsCacheEntryCount: Int {
        0
    }

    func resetCache() {
        fatalError("ResolvedStyledText cache reset requires a concrete owner")
    }

    /// Drawing padding is independent of typographic height and baselines.
    var drawingMargins: EdgeInsets {
        let outsets = maxFontMetrics.outsets
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

    var needsRBDisplayList: Bool {
        guard storage?._isDynamicText != true else { return false }
        return features.contains(.customRenderer)
            || (archiveOptions.isArchived && archiveOptions.preciseTextLayout)
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
        // Spacing combines the unconstrained layout with the retained font metrics.
        let idealSize = CGSize(
            width: CGFloat.infinity,
            height: CGFloat.infinity
        )
        guard let idealMetrics = cachedLayoutMetrics(in: idealSize) else {
            return Spacing()
        }
        return Spacing.textSpacing(
            maxFontMetrics: maxFontMetrics.resolvedMetrics,
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

    func drawingGlyphs(in size: CGSize, layoutSize: CGSize? = nil,
                       containsResolvable: Bool = false)
        -> (source: ResolvedTextSource, lines: [ResolvedTextSource.LineGlyphs])? {
        guard let source = drawingSource(in: size) else { return nil }
        return (source, source.makeGlyphLayout(in: layoutSize ?? size, layoutProperties: layoutProperties).lines)
    }

    func prepareDrawing(in rect: CGRect, with size: CGSize,
                        applyingMarginOffsets: Bool, containsResolvable: Bool = false)
        -> (source: ResolvedTextSource, lines: [ResolvedTextSource.LineGlyphs], bounds: CGRect, layout: Text.Layout?)? {
        guard let prepared = drawingGlyphs(in: size, containsResolvable: containsResolvable) else { return nil }
        let margins = applyingMarginOffsets ? drawingMargins : EdgeInsets()
        return (prepared.source, prepared.lines,
                CGRect(x: rect.origin.x + margins.leading, y: rect.origin.y + margins.top,
                       width: size.width, height: size.height), nil)
    }

    func makeLayout(in rect: CGRect, with size: CGSize, shading: GraphicsContext.Shading,
                    layoutDirection: LayoutDirection) -> Text.Layout? {
        guard var source = drawingSource(in: size) else { return nil }
        source.shading = shading
        let margins = drawingMargins
        return source.makeLayout(in: size, layoutDirection: layoutDirection,
            layoutProperties: layoutProperties,
            origin: CGPoint(x: rect.origin.x + margins.leading, y: rect.origin.y + margins.top))
    }

    func layoutValue(in rect: CGRect, with size: CGSize,
                     applyingMarginOffsets: Bool = true) -> Text.Layout? {
        nil
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
    final class StringDrawing: ResolvedStyledText, @unchecked Sendable {
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

        override func drawingGlyphs(in size: CGSize, layoutSize: CGSize? = nil,
                                    containsResolvable: Bool = false)
            -> (source: ResolvedTextSource, lines: [ResolvedTextSource.LineGlyphs])? {
            guard let source = drawingSource(in: size) else { return nil }
            let prepared = drawingScale(size: size) == 1 && !containsResolvable ? preparedLayout : nil
            return (source, source.makeGlyphLayout(in: layoutSize ?? size, layoutProperties: layoutProperties,
                truncationTolerance: 0.0002,
                sourceLines: prepared?.lines, layoutScope: .document).lines)
        }

        func drawingBounds(in rect: CGRect, with size: CGSize, applyingMarginOffsets: Bool) -> CGRect {
            let metrics = cachedMetrics(in: size)
            var bounds = CGRect(x: rect.origin.x, y: rect.origin.y + metrics.baselineAdjustment,
                                width: metrics.size.width + layoutProperties.bodyHeadOutdent,
                                height: metrics.size.height)
            if applyingMarginOffsets {
                if !bounds.isNull {
                    bounds = bounds.standardized
                    bounds.origin.x += layoutMargins.leading
                    bounds.origin.y += layoutMargins.top
                    bounds.size.width -= layoutMargins.leading + layoutMargins.trailing
                    bounds.size.height -= layoutMargins.top + layoutMargins.bottom
                    if bounds.width < 0 || bounds.height < 0 { bounds = .null }
                }
                let margins = drawingMargins
                bounds.origin.x += margins.leading - layoutMargins.leading
                bounds.origin.y += margins.top - layoutMargins.top
            }
            if metrics.requestedWidth != .infinity {
                let adjustment = bounds.size.width - metrics.requestedWidth
                switch layoutProperties.multilineTextAlignment {
                case .center: bounds.origin.x += adjustment * 0.5
                case .leading:
                    if layoutProperties.layoutDirection == .rightToLeft { bounds.origin.x += adjustment }
                case .trailing:
                    if layoutProperties.layoutDirection == .leftToRight { bounds.origin.x += adjustment }
                }
                bounds.size.width = metrics.requestedWidth
            }
            return bounds
        }

        override func prepareDrawing(in rect: CGRect, with size: CGSize,
                                     applyingMarginOffsets: Bool, containsResolvable: Bool = false)
            -> (source: ResolvedTextSource, lines: [ResolvedTextSource.LineGlyphs], bounds: CGRect, layout: Text.Layout?)? {
            guard resolvedText != nil else { return nil }
            let bounds = drawingBounds(in: rect, with: size, applyingMarginOffsets: applyingMarginOffsets)
            // A zero drawing extent leaves that axis unconstrained. Measurement
            // keeps its separate narrow-proposal normalization and cached result.
            let layoutSize = CGSize(width: bounds.size.width == 0 ? .infinity : bounds.size.width,
                                    height: bounds.size.height == 0 ? .infinity : bounds.size.height)
            guard var prepared = drawingGlyphs(in: size, layoutSize: layoutSize,
                                               containsResolvable: containsResolvable) else { return nil }
            let width = bounds.size.width == 0
                ? prepared.lines.map(\.width).max() ?? 0
                : bounds.size.width * prepared.source.scaleFactor
            for index in prepared.lines.indices {
                let extra = width - prepared.lines[index].width
                switch layoutProperties.multilineTextAlignment {
                case .center: prepared.lines[index].originX = extra * 0.5
                case .leading:
                    prepared.lines[index].originX = layoutProperties.layoutDirection == .rightToLeft ? extra : 0
                case .trailing:
                    prepared.lines[index].originX = layoutProperties.layoutDirection == .leftToRight ? extra : 0
                }
            }
            return (prepared.source, prepared.lines, bounds, nil)
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
            guard minimum > 0, minimum < 1, source.fontResolutionContext != nil else { return nil }
            let font = source.uniformFont
            let string: String
            if let uniform = source.uniformString {
                string = uniform
            } else {
                // Mixed text runs share a fitting scale. LF starts a new paragraph owner.
                // Supported separators retain their paragraph ownership during fitting.
                guard layoutProperties.writingMode == .horizontalTopToBottom,
                      case let .styledText(_, _, _, first) = source.runs.first else { return nil }
                let allowsLineSeparators = (layoutProperties.lineLimit ?? 0) >= 1
                var paragraphStyle = first.paragraphStyle
                var startsParagraph = false
                var text = ""
                for run in source.runs {
                    let value: String
                    let attributes: _ResolvedTextRunAttributes
                    switch run {
                    case let .styledText(_, string, _, style):
                        value = string
                        attributes = style
                    case let .styledAttachment(_, _, _, style):
                        value = "\u{fffc}"
                        attributes = style
                    default:
                        return nil
                    }
                    guard attributes.customAttachment == nil,
                          attributes.fontResource?.requestedPointSize != nil,
                          startsParagraph || attributes.paragraphStyle == paragraphStyle,
                          (attributes.paragraphStyle?.firstLineHeadIndent ?? 0) == 0,
                          (attributes.paragraphStyle?.lineSpacing ?? 0) == 0,
                          attributes.paragraphStyle?.allowsTightening != true,
                          !value.unicodeScalars.contains(where: {
                              CharacterSet.newlines.contains($0) &&
                                  !(allowsLineSeparators && ($0 == "\n" || $0 == "\u{2028}"))
                          }) else { return nil }
                    text += value
                    paragraphStyle = attributes.paragraphStyle
                    if !value.isEmpty { startsParagraph = value.hasSuffix("\n") }
                }
                guard !text.isEmpty else { return nil }
                string = text
            }
            let limit = layoutProperties.lineLimit
            if limit == 1, string.unicodeScalars.contains(where: {
                CharacterSet.newlines.contains($0) && $0 != "\n" && $0 != "\u{2028}"
            }) {
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
                if let font {
                    return source.resizingUniformFont(to: (font.pointSize * scale * 4).rounded() * 0.25)
                }
                return source.scalingFonts(by: scale)
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
                let unchanged = zip(candidate.runs, source.runs).allSatisfy { candidate, original in
                    guard case let .styledText(_, _, _, a) = candidate,
                          case let .styledText(_, _, _, b) = original else { return false }
                    return a.fontResource?.pointSize == b.fontResource?.pointSize
                }
                if !unchanged, oversized(candidate) {
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
                truncationWidth: width,
                truncationTolerance: 0.0002 * source.scaleFactor,
                lineLimit: layoutProperties.lineLimit, truncationMode: layoutProperties.truncationMode,
                sourceLines: sources, layoutScope: .document)
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
                maximumHeight: .infinity, truncationWidth: pixelWidth,
                truncationTolerance: 0.0002 * resolvedText.scaleFactor, sourceLines: sources).lines
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

    final class TextLayoutManager: ResolvedStyledText, @unchecked Sendable {
        var suffix: ResolvedTextSuffix
        var attachments: Text.ResolvedProperties.CustomAttachments

        required init(
            storage: NSAttributedString? = nil,
            layoutProperties: TextLayoutProperties = TextLayoutProperties(),
            layoutMargins: EdgeInsets? = nil,
            scaleFactorOverride: CGFloat? = nil,
            stylePadding: EdgeInsets = EdgeInsets(),
            archiveOptions: ArchivedViewInput.Value = ArchivedViewInput.Value(),
            isCollapsible: Bool = false,
            features: Text.ResolvedProperties.Features = [],
            suffix: ResolvedTextSuffix = .none,
            attachments: Text.ResolvedProperties.CustomAttachments = .init(),
            styles: [_ShapeStyle_Pack.Style] = [],
            transitions: [Text.ResolvedProperties.Transition] = [],
            links: Text.ResolvedProperties.Links = .init(),
            fonts: Text.ResolvedProperties.Fonts? = nil,
            lineHeightMetrics: Text.ResolvedProperties.LineHeightMetrics = .init(),
            resolvedText: ResolvedTextSource? = nil,
            version: Int = 0,
            transitionText: String? = nil,
            needsDrawingGroup: Bool = false
        ) {
            self.suffix = suffix
            self.attachments = attachments
            super.init(storage: storage, layoutProperties: layoutProperties, layoutMargins: layoutMargins,
                scaleFactorOverride: scaleFactorOverride, stylePadding: stylePadding, archiveOptions: archiveOptions,
                isCollapsible: isCollapsible, features: features, suffix: suffix, attachments: attachments,
                styles: styles, transitions: transitions, links: links, fonts: fonts, lineHeightMetrics: lineHeightMetrics,
                resolvedText: resolvedText,
                version: version, transitionText: transitionText, needsDrawingGroup: needsDrawingGroup)
        }

        struct Size {
            struct Flags: OptionSet {
                var rawValue: UInt8

                static let minorAxisIsUnspecified = Flags(rawValue: 1)
            }

            var layoutWidth: CGFloat
            var layoutHeight: CGFloat
            var majorAxis: Axis
            var flags: Flags

            init(_ size: CGSize, majorAxis: Axis, flags: Flags = []) {
                layoutWidth = majorAxis == .vertical ? size.width : size.height
                layoutHeight = majorAxis == .vertical ? size.height : size.width
                self.majorAxis = majorAxis
                self.flags = flags
            }

            init(_ proposal: _ProposedSize, majorAxis: Axis) {
                let minor = majorAxis == .vertical ? proposal.width : proposal.height
                let major = majorAxis == .vertical ? proposal.height : proposal.width
                layoutWidth = minor ?? .infinity
                layoutHeight = major ?? .infinity
                self.majorAxis = majorAxis
                flags = minor == nil ? .minorAxisIsUnspecified : []
            }

            var physicalSize: CGSize {
                majorAxis == .vertical
                    ? CGSize(width: layoutWidth, height: layoutHeight)
                    : CGSize(width: layoutHeight, height: layoutWidth)
            }
        }

        struct Metrics {
            struct Flags: OptionSet {
                var rawValue: UInt8

                static let isTruncated = Flags(rawValue: 1)
            }

            var requestedSize: Size
            var base: NSAttributedString.Metrics
            var flags: Flags
            var layout: Text.Layout?
        }

        struct Cache {
            struct Entry {
                var request: CGSize
                var metrics: NSAttributedString.Metrics
            }

            var entries: [Entry] = []
            var ideal: NSAttributedString.Metrics?

            func find(measuredSize: CGSize) -> Entry? {
                entries.first {
                    $0.metrics.size.width == measuredSize.width &&
                        $0.metrics.size.height == measuredSize.height
                }
            }
        }

        private(set) var cache = Cache()

        /// Holds the current backend layout and last scaled source, independently of scalar measurements.
        final class GlyphLayoutCache: AppLifetimeResource, @unchecked Sendable {
            private struct Entry {
                var size: CGSize
                var scale: CGFloat
                var lineLimit: Int?
                var truncationMode: Text.TruncationMode
                var hasTextSuffix: Bool
                var layout: ResolvedTextSource.GlyphLayout
            }

            private struct State: @unchecked Sendable {
                var entry: Entry?
                var selectedScale: CGFloat = 1
                var scaledSource: (factor: CGFloat, source: ResolvedTextSource)?
                var terminated = false
            }

            private let state = Mutex(State())

            func source(at scale: CGFloat, original: ResolvedTextSource) -> ResolvedTextSource {
                var source = original
                state.withLock { state in
                    guard !state.terminated else { return }
                    if state.selectedScale != scale {
                        state.entry = nil
                        state.selectedScale = scale
                    }
                    guard scale != 1 else { return }
                    if state.scaledSource?.factor != scale {
                        // Rebuild from original font requests, retaining only the last scaled source.
                        state.scaledSource = (scale, original.scalingFonts(by: scale, toMultipleOf: nil))
                    }
                    source = state.scaledSource!.source
                }
                return source
            }

            func layout(in size: CGSize, scale: CGFloat = 1, lineLimit: Int?, truncationMode: Text.TruncationMode,
                        hasTextSuffix: Bool = false,
                        make: () -> ResolvedTextSource.GlyphLayout) -> ResolvedTextSource.GlyphLayout {
                // Serialize publication with resource purging, including a cold computation.
                state.withLock { state in
                    guard !state.terminated else {
                        return .init(lines: [], lineCount: 0, forcedClusterBreak: false,
                                     truncatedRanges: [], hasUnlaidText: false)
                    }
                    if let entry = state.entry, entry.size == size, entry.scale == scale,
                       entry.lineLimit == lineLimit, entry.truncationMode == truncationMode,
                       entry.hasTextSuffix == hasTextSuffix {
                        return entry.layout
                    }
                    let layout = make()
                    state.entry = Entry(size: size, scale: scale, lineLimit: lineLimit,
                                        truncationMode: truncationMode, hasTextSuffix: hasTextSuffix,
                                        layout: layout)
                    return layout
                }
            }

            override func purgeResources(reason: ResourcePurgeReason) {
                state.withLock { state in
                    state.entry = nil
                    state.scaledSource = nil
                    state.selectedScale = 1
                    if reason == .appTermination { state.terminated = true }
                }
            }
        }

        let glyphLayoutCache = GlyphLayoutCache()

        var majorAxis: Axis {
            layoutProperties.writingMode == .verticalRightToLeft ? .horizontal : .vertical
        }

        override var metricsCacheEntryCount: Int { cache.entries.count }

        override func resetCache() {}

        override func spacing() -> Spacing {
            guard resolvedText != nil else { return Spacing() }
            if cache.ideal == nil {
                // Spacing uses unit-scale unconstrained metrics independently of size requests.
                cache.ideal = computeMetrics(scale: 1,
                    requestedSize: Size(CGSize(width: CGFloat.infinity, height: CGFloat.infinity), majorAxis: majorAxis),
                    minorAxisIsFlexible: false).base
            }
            guard let ideal = cache.ideal else { return Spacing() }
            return Spacing.textSpacing(maxFontMetrics: maxFontMetrics.resolvedMetrics,
                idealMetrics: .init(size: ideal.size, firstBaseline: ideal.firstBaseline,
                                    lastBaseline: ideal.lastBaseline),
                layoutProperties: layoutProperties)
        }

        override func prepareDrawing(in rect: CGRect, with size: CGSize,
                                     applyingMarginOffsets: Bool, containsResolvable: Bool = false)
            -> (source: ResolvedTextSource, lines: [ResolvedTextSource.LineGlyphs], bounds: CGRect, layout: Text.Layout?)? {
            guard let prepared = prepareGlyphLayout(in: rect, with: size,
                applyingMarginOffsets: applyingMarginOffsets) else { return nil }
            return (prepared.source, prepared.layout.lines, prepared.bounds, prepared.metrics.layout)
        }

        override func makeLayout(in rect: CGRect, with size: CGSize, shading: GraphicsContext.Shading,
                                 layoutDirection: LayoutDirection) -> Text.Layout? {
            guard var prepared = prepareGlyphLayout(in: rect, with: size,
                applyingMarginOffsets: true) else { return nil }
            if let layout = prepared.metrics.layout {
                return layout.placed(at: prepared.bounds.origin, shading: shading)
            }
            prepared.source.shading = shading
            return prepared.source.makeLayout(lineGlyphs: prepared.layout.lines, layoutDirection: layoutDirection,
                isTruncated: !prepared.layout.truncatedRanges.isEmpty,
                origin: prepared.bounds.origin, usesLineStartAttributes: true)
        }

        override func layoutValue(in rect: CGRect, with size: CGSize,
                                  applyingMarginOffsets: Bool = true) -> Text.Layout? {
            guard let prepared = prepareGlyphLayout(in: .zero, with: size,
                applyingMarginOffsets: applyingMarginOffsets) else { return nil }
            if let layout = prepared.metrics.layout {
                return layout.placed(at: prepared.bounds.origin, shading: prepared.source.shading)
            }
            return prepared.source.makeLayout(lineGlyphs: prepared.layout.lines,
                layoutDirection: layoutProperties.layoutDirection,
                isTruncated: !prepared.layout.truncatedRanges.isEmpty,
                origin: prepared.bounds.origin, usesLineStartAttributes: true)
        }

        private func prepareGlyphLayout(in rect: CGRect, with size: CGSize, applyingMarginOffsets: Bool)
            -> (source: ResolvedTextSource, metrics: Metrics, layout: ResolvedTextSource.GlyphLayout, bounds: CGRect)? {
            guard let source = resolvedText else { return nil }
            var request = size
            if let entry = cache.find(measuredSize: size), entry.request.width.isFinite {
                request.width = entry.request.width
            }
            let metrics = fittingMetrics(in: Size(request, majorAxis: majorAxis))
            let drawingSource = glyphLayoutCache.source(at: metrics.base.scale, original: source)
            var layout = glyphLayout(drawingSource, in: metrics.requestedSize.physicalSize, scale: metrics.base.scale)
            let factor: CGFloat
            switch layoutProperties.multilineTextAlignment {
            case .center: factor = 0.5
            case .leading: factor = layoutProperties.layoutDirection == .rightToLeft ? 1 : 0
            case .trailing: factor = layoutProperties.layoutDirection == .leftToRight ? 1 : 0
            }
            let margins = applyingMarginOffsets ? drawingMargins : EdgeInsets()
            let displacement = factor == 0 ? 0 : (request.width - size.width) * factor
            let bounds = CGRect(
                x: rect.origin.x + margins.leading - displacement,
                y: rect.origin.y + margins.top + metrics.base.baselineAdjustment,
                width: request.width, height: request.height)
            let width = metrics.base.requestedWidth * drawingSource.scaleFactor
            for index in layout.lines.indices {
                layout.lines[index].originX = factor == 0 ? 0 :
                    (width - layout.lines[index].width) * factor
            }
            return (drawingSource, metrics, layout, bounds)
        }

        override func size(in size: CGSize) -> CGSize {
            cachedLayoutMetrics(in: size)?.size ?? .zero
        }

        override func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            guard proposal != .zero else { return .zero }
            guard resolvedText != nil else { return .zero }
            return metrics(in: Size(proposal, majorAxis: majorAxis), layoutMargins: nil).size
        }

        override func cachedLayoutMetrics(in size: CGSize) -> ResolvedTextSource.LayoutMetrics? {
            guard resolvedText != nil else { return nil }
            let value = metrics(in: size, layoutMargins: nil)
            return .init(size: value.size, firstBaseline: value.firstBaseline, lastBaseline: value.lastBaseline)
        }

        override func metrics(in size: CGSize, layoutMargins: EdgeInsets?) -> NSAttributedString.Metrics {
            metrics(in: Size(size, majorAxis: majorAxis), layoutMargins: layoutMargins)
        }

        func metrics(in requestedSize: Size, layoutMargins: EdgeInsets?) -> NSAttributedString.Metrics {
            guard resolvedText != nil else {
                fatalError("TextLayoutManager metrics require resolved text")
            }
            let size = requestedSize.physicalSize
            if let entry = cache.entries.first(where: { entry in
                size.width >= min(entry.metrics.size.width, entry.request.width) &&
                    size.width <= max(entry.metrics.size.width, entry.request.width) &&
                    size.height >= min(entry.metrics.size.height, entry.request.height) &&
                    size.height <= max(entry.metrics.size.height, entry.request.height)
            }) {
                return entry.metrics
            }
            let metrics = fittingMetrics(in: requestedSize).base
            cache.entries.append(Cache.Entry(request: size, metrics: metrics))
            return metrics
        }

        private func fittingMetrics(in requestedSize: Size) -> Metrics {
            guard let source = resolvedText else {
                fatalError("TextLayoutManager metrics require resolved text")
            }
            let minimum = max(layoutProperties.minScaleFactor, CGFloat.leastNonzeroMagnitude)
            guard minimum < 1 else {
                return computeMetrics(scale: 1, requestedSize: requestedSize, minorAxisIsFlexible: false)
            }
            // Font runs share one fitting scale. Attachments keep their fixed-scale producer.
            let canScaleTextRuns = layoutProperties.writingMode == .horizontalTopToBottom &&
                source.fontResolutionContext != nil && source.runs.allSatisfy { run in
                    let attributes: _ResolvedTextRunAttributes
                    switch run {
                    case let .styledText(_, _, _, style), let .styledAttachment(_, _, _, style):
                        attributes = style
                    default:
                        return false
                    }
                    guard let font = attributes.fontResource else { return false }
                    return font.requestedPointSize != nil
                }
            guard source.uniformFont != nil || storage?.length == 0 || canScaleTextRuns else {
                return computeMetrics(scale: 1, requestedSize: requestedSize, minorAxisIsFlexible: false)
            }
            let size = requestedSize.physicalSize
            var proposal = requestedSize
            proposal.layoutHeight = .infinity
            proposal.flags = []
            func fits(_ metrics: NSAttributedString.Metrics) -> Bool {
                !metrics.hasTruncatedRanges && metrics.size.width <= size.width && metrics.size.height <= size.height
            }
            var scale: CGFloat = 1
            if !fits(computeMetrics(scale: 1, requestedSize: proposal, minorAxisIsFlexible: false).base) {
                var low = minimum
                var high: CGFloat = 1
                if fits(computeMetrics(scale: low, requestedSize: proposal, minorAxisIsFlexible: false).base) {
                    repeat {
                        let candidate = high + (high - low) * -0.5
                        if fits(computeMetrics(scale: candidate, requestedSize: proposal, minorAxisIsFlexible: false).base) {
                            low = candidate
                        } else {
                            high = candidate
                        }
                    } while high - low >= 0.01
                }
                scale = low
            }
            // Publish the final constrained result even when the minimum still does not fit.
            return computeMetrics(scale: scale, requestedSize: requestedSize, minorAxisIsFlexible: false)
        }

        func computeMetrics(scale: CGFloat, requestedSize: Size, minorAxisIsFlexible: Bool) -> Metrics {
            guard let source = self.resolvedText else {
                fatalError("TextLayoutManager metrics require resolved text")
            }
            let resolvedText = glyphLayoutCache.source(at: scale, original: source)
            // The manager uses its retained margins for every measurement.
            let size = requestedSize.physicalSize
            let layoutMargins = self.layoutMargins
            let available = CGSize(width: max(size.width - layoutMargins.leading - layoutMargins.trailing, 0),
                                   height: max(size.height - layoutMargins.top - layoutMargins.bottom, 0))
            let availableSize = Size(available, majorAxis: requestedSize.majorAxis, flags: requestedSize.flags)
            let width = available.width > 0 ? available.width : CGFloat.leastNonzeroMagnitude
            let layout = glyphLayout(resolvedText, in: available, scale: scale)
            var raw = resolvedText.layoutMetrics(lineGlyphs: layout.lines)
            raw.size.width = layout.lines.reduce(CGFloat.zero) {
                max($0, $1.fragmentWidth ?? $1.width)
            } / resolvedText.scaleFactor
            let truncated = !layout.truncatedRanges.isEmpty || layout.hasUnlaidText
            var retainedLayout: Text.Layout?
            if truncated, var suffixLine = suffix.line {
                suffixLine.drawingOptions.insert(.init(rawValue: 2))
                var lines = layout.lines
                let factor: CGFloat
                switch layoutProperties.multilineTextAlignment {
                case .center: factor = 0.5
                case .leading: factor = layoutProperties.layoutDirection == .rightToLeft ? 1 : 0
                case .trailing: factor = layoutProperties.layoutDirection == .leftToRight ? 1 : 0
                }
                for index in lines.indices {
                    lines[index].originX = factor == 0 ? 0 :
                        (available.width * resolvedText.scaleFactor - lines[index].width) * factor
                }
                var value = resolvedText.makeLayout(lineGlyphs: lines,
                    layoutDirection: layoutProperties.layoutDirection,
                    isTruncated: !layout.truncatedRanges.isEmpty, usesLineStartAttributes: true)
                value.truncateLast(suffixLine, width: available.width)
                retainedLayout = value
                // Replacement changes the horizontal used extent, not the
                // original line count, vertical metrics or truncation ranges.
                let bounds = value.reduce(CGRect.null) { $0.union($1.typographicBounds.rect) }
                raw.size.width = bounds.isNull ? 0 : max(0, min(bounds.maxX, available.width) - max(bounds.minX, 0))
            }
            if layout.lines.isEmpty {
                raw.firstBaseline = 0
                raw.lastBaseline = 0
                if storage?.length == 0, available.height > 0 {
                    raw.size.height = ceil(min(raw.size.height, available.height) * resolvedText.displayScale)
                        / resolvedText.displayScale
                }
            }
            raw.size.width = min(raw.size.width, width)
            if minorAxisIsFlexible {
                if requestedSize.majorAxis == .vertical {
                    raw.size.width = max(raw.size.width, available.width)
                } else {
                    raw.size.height = max(raw.size.height, available.height)
                }
            }
            raw.size.width = ceil(raw.size.width * resolvedText.displayScale) / resolvedText.displayScale
            raw.size.height = ceil(raw.size.height * resolvedText.displayScale) / resolvedText.displayScale
            var metrics = NSAttributedString.Metrics(size: raw.size, scale: scale,
                firstBaseline: raw.firstBaseline, lastBaseline: raw.lastBaseline,
                baselineAdjustment: 0, requestedWidth: availableSize.layoutWidth,
                numberOfLines: UInt(layout.lines.count),
                hasTruncatedRanges: truncated)
            metrics.update(layoutMargins: layoutMargins, pixelLength: 1 / resolvedText.displayScale)
            return Metrics(requestedSize: availableSize,
                base: metrics, flags: truncated ? .isTruncated : [], layout: retainedLayout)
        }

        private func glyphLayout(_ source: ResolvedTextSource, in available: CGSize, scale: CGFloat)
            -> ResolvedTextSource.GlyphLayout {
            let width = available.width > 0 ? available.width : CGFloat.leastNonzeroMagnitude
            let pixelWidth = width * source.scaleFactor
            return glyphLayoutCache.layout(in: available, scale: scale, lineLimit: layoutProperties.lineLimit,
                truncationMode: layoutProperties.truncationMode, hasTextSuffix: suffix.line != nil) {
                source.makeGlyphLayout(
                    maxWidth: pixelWidth > CGFloat(Int.max) ? .max : Int(ceil(pixelWidth)),
                    maximumHeight: available.height * source.scaleFactor,
                    truncationWidth: pixelWidth,
                    truncationTolerance: 0.001 * source.scaleFactor,
                    lineLimit: layoutProperties.lineLimit, truncationMode: layoutProperties.truncationMode,
                    hasTextSuffix: suffix.line != nil)
            }
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
