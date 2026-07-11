//
//  File: ResolvedStyledText.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension NSAttributedString.Key {
    static let resolvedTextAttachment = NSAttributedString.Key(
        "org.swiftvvd.resolvedText.attachment"
    )
}

struct _ResolvedAttributedStringArchive: Codable, Equatable {
    struct Run: Codable, Equatable {
        var text: String
        var isAttachment: Bool
    }

    var runs: [Run]

    init(_ value: NSAttributedString) {
        var runs: [Run] = []
        value.enumerateAttributes(
            in: NSRange(location: 0, length: value.length)
        ) { attributes, range, _ in
            runs.append(Run(
                text: value.attributedSubstring(from: range).string,
                isAttachment: attributes[.resolvedTextAttachment] as? Bool == true
            ))
        }
        self.runs = runs
    }

    var attributedString: NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            let attributes: [NSAttributedString.Key: Any] = run.isAttachment
                ? [.resolvedTextAttachment: true]
                : [:]
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }
}

struct _ShapeStyle_Pack {
    enum Fill: Equatable, Sendable {
        case color(Color.Resolved)
    }

    enum Effect: Equatable, Sendable {
    }

    struct Style: Equatable, Sendable {
        var fill: Fill
        var opacity: Float
        var blendMode: GraphicsContext.BlendMode?
        var effects: [Effect]

        init(_ fill: Fill) {
            self.fill = fill
            self.opacity = 1
            self.blendMode = nil
            self.effects = []
        }
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

        struct Paragraph: Codable, Equatable, Sendable {
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

final class ResolvedStyledText: InterpolatableContent {
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

    var maxFontMetrics: ResolvedFontMetrics? {
        if !didComputeMaxFontMetrics {
            _computedMaxFontMetrics = resolvedText?.maximumFontMetrics
            didComputeMaxFontMetrics = true
        }
        return _computedMaxFontMetrics
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
        state.transition = .text
    }
}
