//
//  File: SizeFittingText.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct TextSizeVariant: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    var rawValue: Int

    static let regular = TextSizeVariant(rawValue: 0)
    static let compact = TextSizeVariant(rawValue: 1)
    static let small = TextSizeVariant(rawValue: 2)
    static let tiny = TextSizeVariant(rawValue: 3)

    var nextUp: TextSizeVariant? {
        guard rawValue > Self.regular.rawValue else { return nil }
        return TextSizeVariant(rawValue: rawValue - 1)
    }

    var nextDown: TextSizeVariant {
        TextSizeVariant(rawValue: rawValue + 1)
    }

    static func < (lhs: TextSizeVariant, rhs: TextSizeVariant) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

protocol TextSizeFittingLogic {
    mutating func suggestedVariant(for proposal: ProposedViewSize) -> TextSizeVariant?
    mutating func onInvalidation(of variant: TextSizeVariant)
}

struct StickyTextSizeFittingLogic: TextSizeFittingLogic {
    var stickOnHorizontalGrowth: Bool
    var stickOnVerticalGrowth: Bool
    var committedValue: (sizeVariant: TextSizeVariant, proposal: ProposedViewSize)?

    init(
        stickOnHorizontalGrowth: Bool = false,
        stickOnVerticalGrowth: Bool = true,
        committedValue: (sizeVariant: TextSizeVariant, proposal: ProposedViewSize)? = nil
    ) {
        self.stickOnHorizontalGrowth = stickOnHorizontalGrowth
        self.stickOnVerticalGrowth = stickOnVerticalGrowth
        self.committedValue = committedValue
    }

    mutating func suggestedVariant(for proposal: ProposedViewSize) -> TextSizeVariant? {
        guard let committedValue else { return nil }
        if !stickOnHorizontalGrowth,
           Self.dimension(proposal.width, growsBeyond: committedValue.proposal.width) {
            return nil
        }
        if !stickOnVerticalGrowth,
           Self.dimension(proposal.height, growsBeyond: committedValue.proposal.height) {
            return nil
        }
        return committedValue.sizeVariant
    }

    mutating func onInvalidation(of variant: TextSizeVariant) {
        guard committedValue?.sizeVariant == variant else { return }
        committedValue = nil
    }

    mutating func commit(_ variant: TextSizeVariant, for proposal: ProposedViewSize) {
        committedValue = (variant, proposal)
    }

    private static func dimension(_ value: CGFloat?, growsBeyond committed: CGFloat?) -> Bool {
        let value = value ?? .infinity
        let committed = committed ?? .infinity
        return value > committed
    }
}

struct ClosestFitCache<Value: Equatable> {
    struct Entry {
        var proposal: ProposedViewSize
        var value: Value
    }

    var capacity: Int
    private(set) var entries: [Entry]

    init(capacity: Int = 10) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.entries = []
    }

    mutating func callAsFunction(
        for proposal: ProposedViewSize,
        makeValue: (Value?) -> Value
    ) -> Value {
        let requestedWidth = proposal.width ?? .infinity
        let requestedHeight = proposal.height ?? .infinity
        var closestIndex: Int?
        var closestDistance = CGFloat.infinity

        for index in entries.indices {
            let cachedProposal = entries[index].proposal
            let cachedWidth = cachedProposal.width ?? .infinity
            let cachedHeight = cachedProposal.height ?? .infinity

            guard !cachedWidth.isNaN,
                  !cachedHeight.isNaN,
                  cachedWidth <= requestedWidth,
                  cachedHeight <= requestedHeight else {
                continue
            }

            let distance: CGFloat
            if cachedWidth == .infinity && cachedHeight == .infinity {
                distance = 0
            } else {
                let widthDistance = requestedWidth - cachedWidth
                let heightDistance = requestedHeight - cachedHeight
                distance = heightDistance < widthDistance
                    ? heightDistance
                    : widthDistance
            }
            guard distance < closestDistance else { continue }
            closestIndex = index
            closestDistance = distance
            if cachedProposal == proposal {
                break
            }
        }

        let suggestedValue = closestIndex.map { entries[$0].value }
        let value = makeValue(suggestedValue)
        if let closestIndex, value == entries[closestIndex].value {
            if closestIndex > entries.startIndex {
                entries.swapAt(closestIndex, closestIndex - 1)
            }
            return value
        }

        let entry = Entry(proposal: proposal, value: value)
        if entries.count < capacity {
            entries.append(entry)
        } else {
            entries[entries.index(before: entries.endIndex)] = entry
        }
        return value
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
    }
}

protocol SizeFittingTextResolver {
    associatedtype Input
    associatedtype Engine: LayoutEngine

    var sizeVariant: TextSizeVariant { get }
    var narrowerVariant: Self { get }
    func value(for input: Input) -> SizeFittingTextCacheValue<Engine>
}

struct SizeFittingTextCacheValue<Engine: LayoutEngine> {
    var text: ResolvedStyledText
    var engine: Engine
    var renderer: TextRendererBoxBase?

    mutating func truncates(in proposal: ProposedViewSize) -> Bool {
        guard let resolved = text.resolvedText else { return false }
        if renderer != nil {
            let ideal = engine.sizeThatFits(.unspecified)
            return proposal.width.map { ideal.width > $0 } == true ||
                proposal.height.map { ideal.height > $0 } == true
        }
        if proposal.width == nil, proposal.height == nil {
            return false
        }
        let layout = resolved.makeLayout(
            in: CGSize(
                width: proposal.width ?? .infinity,
                height: proposal.height ?? .infinity
            ),
            layoutDirection: .leftToRight
        )
        if layout.isTruncated {
            return true
        }
        if let lineLimit = text.layoutProperties.lineLimit,
           layout.count > lineLimit {
            return true
        }
        return false
    }

    mutating func fits(_ proposal: ProposedViewSize) -> Bool {
        !truncates(in: proposal)
    }
}

final class SizeFittingTextCache<Resolver, Logic>
where Resolver: SizeFittingTextResolver, Logic: TextSizeFittingLogic {
    struct CacheEntry {
        var resolver: Resolver
        var lastValue: SizeFittingTextCacheValue<Resolver.Engine>?
        var inputChanged: Bool

        init(resolver: Resolver) {
            self.resolver = resolver
            self.lastValue = nil
            self.inputChanged = true
        }
    }

    private(set) var sizeVariantCache: ClosestFitCache<TextSizeVariant>
    private(set) var exhaustedWidthVariants: Bool
    private(set) var resultCache: [CacheEntry]
    private(set) var logic: Logic
    private var _input: Resolver.Input

    init(resolver: Resolver, logic: Logic, input: Resolver.Input) {
        self.sizeVariantCache = ClosestFitCache(capacity: 10)
        self.exhaustedWidthVariants = false
        self.resultCache = [CacheEntry(resolver: resolver)]
        self.logic = logic
        self._input = input
    }

    func setInput(_ input: Resolver.Input, changed: Bool) {
        _input = input
        guard changed else { return }
        sizeVariantCache.removeAll()
        exhaustedWidthVariants = false
        for index in resultCache.indices {
            resultCache[index].inputChanged = true
        }
    }

    func updateInput(changed: Bool, _ body: (inout Resolver.Input) -> Void) {
        body(&_input)
        guard changed else { return }
        sizeVariantCache.removeAll()
        exhaustedWidthVariants = false
        for index in resultCache.indices {
            resultCache[index].inputChanged = true
        }
    }

    func sizeVariant(for proposal: ProposedViewSize) -> TextSizeVariant {
        let suggestion = logic.suggestedVariant(for: proposal)
        let result = sizeVariantCache(for: proposal) { _ in
            var index = suggestion.map(index(for:)) ?? 0

            while true {
                let fits = withValue(at: index) { $0.fits(proposal) }
                guard !fits else { break }
                guard appendNarrowerVariant(after: index) else {
                    exhaustedWidthVariants = proposal.width != nil
                    break
                }
                index += 1
            }
            return resultCache[index].resolver.sizeVariant
        }
        if var sticky = logic as? StickyTextSizeFittingLogic {
            sticky.commit(result, for: proposal)
            // The conditional cast proves this assignment has the same
            // concrete type. Other fitting policies do not use sticky state.
            logic = sticky as! Logic
        }
        return result
    }

    func withValue<Result>(
        for proposal: ProposedViewSize,
        _ body: (inout SizeFittingTextCacheValue<Resolver.Engine>) -> Result
    ) -> Result {
        withValue(for: sizeVariant(for: proposal), body)
    }

    func withValue<Result>(
        for variant: TextSizeVariant,
        _ body: (inout SizeFittingTextCacheValue<Resolver.Engine>) -> Result
    ) -> Result {
        let index = index(for: variant)
        if resultCache[index].lastValue == nil || resultCache[index].inputChanged {
            resultCache[index].lastValue = resultCache[index].resolver.value(for: _input)
            resultCache[index].inputChanged = false
        }
        return body(&resultCache[index].lastValue!)
    }

    func invalidate(_ variant: TextSizeVariant) {
        let index = index(for: variant)
        resultCache[index].inputChanged = true
        sizeVariantCache.removeAll()
        exhaustedWidthVariants = false
        logic.onInvalidation(of: variant)
    }

    private func index(for variant: TextSizeVariant) -> Int {
        if let index = resultCache.firstIndex(where: { $0.resolver.sizeVariant == variant }) {
            return index
        }

        while let last = resultCache.indices.last,
              resultCache[last].resolver.sizeVariant.rawValue < variant.rawValue,
              appendNarrowerVariant(after: last) {
            if resultCache.last?.resolver.sizeVariant == variant {
                return resultCache.count - 1
            }
        }
        return resultCache.indices.last ?? 0
    }

    private func withValue<Result>(
        at index: Int,
        _ body: (inout SizeFittingTextCacheValue<Resolver.Engine>) -> Result
    ) -> Result {
        if resultCache[index].lastValue == nil || resultCache[index].inputChanged {
            resultCache[index].lastValue = resultCache[index].resolver.value(for: _input)
            resultCache[index].inputChanged = false
        }
        return body(&resultCache[index].lastValue!)
    }

    private func appendNarrowerVariant(after index: Int) -> Bool {
        precondition(resultCache.indices.contains(index))
        if resultCache.indices.contains(index + 1) {
            return true
        }
        guard !exhaustedWidthVariants else { return false }
        let currentIsUnique = withValue(at: index) {
            $0.text.features.contains(.isUniqueSizeVariant)
        }
        guard currentIsUnique else {
            exhaustedWidthVariants = true
            return false
        }
        resultCache.append(CacheEntry(resolver: resultCache[index].resolver.narrowerVariant))
        let addedIndex = resultCache.count - 1
        let isUnique = withValue(at: addedIndex) {
            $0.text.features.contains(.isUniqueSizeVariant)
        }
        if !isUnique {
            exhaustedWidthVariants = true
        }
        return true
    }
}

struct ResolvedTextHelper: SizeFittingTextResolver {
    struct Input {
        var text: ResolvedStyledText
        var renderer: TextRendererBoxBase?
    }

    var sizeVariant: TextSizeVariant

    init(sizeVariant: TextSizeVariant = .regular) {
        self.sizeVariant = sizeVariant
    }

    var narrowerVariant: ResolvedTextHelper {
        ResolvedTextHelper(sizeVariant: sizeVariant.nextDown)
    }

    func value(for input: Input) -> SizeFittingTextCacheValue<StyledTextLayoutEngine> {
        let candidates = input.text.sizeVariantCandidates
        let index = min(sizeVariant.rawValue, candidates.count - 1)
        let text = candidates[index]
        return SizeFittingTextCacheValue(
            text: text,
            engine: StyledTextLayoutEngine(text: text, renderer: input.renderer),
            renderer: input.renderer
        )
    }
}

/// Measures resolved styled text and answers its baseline alignment guides.
struct StyledTextLayoutEngine: LayoutEngine {
    var text: ResolvedStyledText
    var renderer: TextRendererBoxBase?

    func spacing() -> Spacing {
        text.spacing()
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        let proposal = ProposedViewSize(proposal)
        guard let resolved = text.resolvedText else { return .zero }
        if let renderer {
            return renderer.sizeThatFits(proposal: proposal, text: TextProxy(resolved))
        }
        return text.sizeThatFits(_ProposedSize(proposal))
    }

    func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
        if axis == .horizontal, proposal.width == 0 {
            return 0
        }
        let size = sizeThatFits(proposal)
        return axis == .horizontal ? size.width : size.height
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        guard text.resolvedText != nil else { return nil }
        if key == VerticalAlignment.firstTextBaseline.key {
            return text.firstBaseline(in: size.value)
        }
        if key == VerticalAlignment.lastTextBaseline.key {
            return text.lastBaseline(in: size.value)
        }
        return nil
    }

    var debugContentDescription: String? {
        text.resolvedText?.attributedStorage.string
    }
}

/// Publishes a styled-text layout engine from the current content view.
struct StyledTextLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _textView: Attribute<StyledTextContentView>

    mutating func updateValue() {
        let textView = _textView.value
        update(
            to: StyledTextLayoutEngine(
                text: textView.text,
                renderer: textView.renderer
            )
        )
    }
}

/// Selects and relinks the text variant that best fits the current view size.
struct SizeFittingTextFilter: StatefulRule, AsyncAttribute {
    typealias Value = ResolvedStyledText

    var size: Attribute<ViewSize>
    var text: Attribute<ResolvedStyledText>
    var environment: Attribute<EnvironmentValues>
    var isArchived: Bool
    var cache: SizeFittingTextCache<ResolvedTextHelper, StickyTextSizeFittingLogic>

    mutating func updateValue() {
        let text = text.value
        _ = environment.value
        cache.updateInput(
            changed: _AGGraph.currentStatefulInputChanged(self.text.identifier)
        ) { input in
            input.text = text
        }
        let proposal = ProposedViewSize(size.value.value)
        let selectedVariant = cache.sizeVariant(for: proposal)
        let selected = cache.withValue(for: selectedVariant) { $0.text }

        let candidates = text.sizeVariantCandidates
        guard let selectedIndex = candidates.firstIndex(where: { $0 === selected }) else {
            _AGGraph.setStatefulOutput(selected)
            return
        }

        // Archived text uses a separate dynamic-placeholder splice. Until that
        // path is fully resolved, keep its existing candidate chain intact.
        guard !isArchived else {
            _AGGraph.setStatefulOutput(selected)
            return
        }

        let linkedCandidates = [selected] + candidates.dropFirst(selectedIndex + 1).filter {
            $0.features.contains(.isStandaloneSizeVariant)
        }
        for candidate in linkedCandidates {
            candidate.smallerSizeVariant = nil
            candidate.largerSizeVariant = nil
        }
        for index in linkedCandidates.indices.dropLast() {
            linkedCandidates[index].smallerSizeVariant = linkedCandidates[index + 1]
        }
        _AGGraph.setStatefulOutput(selected)
    }
}

/// Publishes a layout computer that resolves the fitting text variant per proposal.
struct SizeFittingTextLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    /// Dispatches each layout query through the proposal-specific text cache value.
    struct Engine: LayoutEngine {
        var ctx: RuleContext<LayoutComputer>
        var cache: SizeFittingTextCache<ResolvedTextHelper, StickyTextSizeFittingLogic>

        func spacing() -> Spacing {
            withValue(for: .unspecified) { $0.engine.spacing() }
        }

        func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
            withValue(for: ProposedViewSize(proposal)) {
                $0.engine.sizeThatFits(proposal)
            }
        }

        func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
            withValue(for: ProposedViewSize(proposal)) {
                $0.engine.lengthThatFits(proposal, in: axis)
            }
        }

        func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
            withValue(for: ProposedViewSize(size.proposal)) {
                $0.engine.childGeometries(at: size, origin: origin)
            }
        }

        func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
            withValue(for: ProposedViewSize(size.proposal)) {
                $0.engine.explicitAlignment(key, at: size)
            }
        }

        private func withValue<Result>(
            for proposal: ProposedViewSize,
            _ body: (inout SizeFittingTextCacheValue<StyledTextLayoutEngine>) -> Result
        ) -> Result {
            var result: Result?
            ctx.update {
                result = cache.withValue(for: proposal, body)
            }
            return result!
        }
    }

    var _text: Attribute<ResolvedStyledText>
    var _environment: Attribute<EnvironmentValues>
    var _renderer: WeakAttribute<TextRendererBoxBase>
    var cache: SizeFittingTextCache<ResolvedTextHelper, StickyTextSizeFittingLogic>

    mutating func updateValue() {
        let text = _text.value
        _ = _environment.value
        let rendererValue: TextRendererBoxBase?
        if let graph = _AGGraph.current, _renderer.isValid(in: graph) {
            rendererValue = _renderer.toStrong().value
        } else {
            rendererValue = nil
        }
        let textChanged = _AGGraph.currentStatefulInputChanged(_text.identifier)
        let rendererChanged: Bool
        if let graph = _AGGraph.current, _renderer.isValid(in: graph) {
            rendererChanged = _AGGraph.currentStatefulInputChanged(
                _renderer.toStrong().identifier
            )
        } else {
            rendererChanged = false
        }
        cache.updateInput(changed: textChanged || rendererChanged) { input in
            input.text = text
            input.renderer = rendererValue
        }

        let engine = Engine(ctx: context, cache: cache)
        update(to: engine)
    }
}
