//
//  File: SizeFittingText.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct TextSizeVariant: RawRepresentable, Hashable, Sendable {
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

struct ClosestFitCache<Value> {
    struct Entry {
        var proposal: ProposedViewSize
        var value: Value
    }

    var capacity: Int
    private(set) var entries: [Entry]

    init(capacity: Int = 10) {
        self.capacity = capacity
        self.entries = []
    }

    mutating func callAsFunction(
        for proposal: ProposedViewSize,
        makeValue: (Value?) -> Value
    ) -> Value {
        if let entry = entries.last(where: { $0.proposal == proposal }) {
            return entry.value
        }
        let value = makeValue(entries.last?.value)
        entries.append(Entry(proposal: proposal, value: value))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
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
        // Current Text storage can only resolve the regular entry. Keep the
        // cache/rule ownership boundary in place so variant-producing storage
        // can extend this resolver chain without replacing the layout route.
        self.resultCache = [CacheEntry(resolver: resolver)]
        self.logic = logic
        self._input = input
    }

    func setInput(_ input: Resolver.Input, changed: Bool) {
        _input = input
        guard changed else { return }
        sizeVariantCache.removeAll()
        for index in resultCache.indices {
            resultCache[index].inputChanged = true
        }
    }

    func updateInput(changed: Bool, _ body: (inout Resolver.Input) -> Void) {
        body(&_input)
        guard changed else { return }
        sizeVariantCache.removeAll()
        for index in resultCache.indices {
            resultCache[index].inputChanged = true
        }
    }

    func sizeVariant(for proposal: ProposedViewSize) -> TextSizeVariant {
        let suggestion = logic.suggestedVariant(for: proposal)
        let selected = sizeVariantCache(for: proposal) { previous in
            suggestion ?? previous ?? resultCache[0].resolver.sizeVariant
        }
        let available = resultCache[0].resolver.sizeVariant
        let result = selected == available ? selected : available
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
        logic.onInvalidation(of: variant)
    }

    private func index(for variant: TextSizeVariant) -> Int {
        guard let index = resultCache.firstIndex(where: { $0.resolver.sizeVariant == variant }) else {
            // Current VUI Text storage has one regular variant. A future
            // size-adaptive storage extends the resolver chain before this lookup.
            return 0
        }
        return index
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
        SizeFittingTextCacheValue(
            text: input.text,
            engine: StyledTextLayoutEngine(text: input.text, renderer: input.renderer),
            renderer: input.renderer
        )
    }
}

struct StyledTextLayoutEngine: LayoutEngine {
    var text: ResolvedStyledText
    var renderer: TextRendererBoxBase?

    func spacing() -> ViewSpacing {
        .text
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        guard let resolved = text.resolvedText else { return .zero }
        if let renderer {
            return renderer.sizeThatFits(proposal: proposal, text: TextProxy(resolved))
        }
        if proposal == .zero {
            return .zero
        }
        if proposal.width == 0 {
            let measured = resolved.measure(maxWidth: 0, maxHeight: proposal.height)
            return CGSize(width: 0, height: measured.height)
        }
        if proposal == .infinity {
            return resolved.measure()
        }
        return resolved.measure(maxWidth: proposal.width, maxHeight: proposal.height)
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        guard let resolved = text.resolvedText else { return nil }
        if key == VerticalAlignment.firstTextBaseline.key {
            return resolved.firstBaseline(in: size.value)
        }
        if key == VerticalAlignment.lastTextBaseline.key {
            return resolved.lastBaseline(in: size.value)
        }
        return nil
    }
}

struct SizeFittingTextFilter: StatefulRule {
    typealias Value = ResolvedStyledText

    var size: Attribute<ViewSize>
    var text: Attribute<ResolvedStyledText>
    var cache: SizeFittingTextCache<ResolvedTextHelper, StickyTextSizeFittingLogic>

    mutating func updateValue() {
        let text = text.value
        cache.updateInput(
            changed: _AGGraph.currentStatefulInputChanged(self.text.identifier)
        ) { input in
            input.text = text
        }
        let proposal = ProposedViewSize(size.value.value)
        let selected = cache.withValue(for: proposal) { $0.text }
        selected.smallerSizeVariant = nil
        selected.largerSizeVariant = nil
        _AGGraph.setStatefulOutput(selected)
    }
}

struct SizeFittingTextLayoutComputer: StatefulRule {
    typealias Value = LayoutComputer

    struct Engine: LayoutEngine {
        var ctx: RuleContext<LayoutComputer>
        var cache: SizeFittingTextCache<ResolvedTextHelper, StickyTextSizeFittingLogic>

        func spacing() -> ViewSpacing {
            withValue(for: .unspecified) { $0.engine.spacing() }
        }

        func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
            withValue(for: proposal) { $0.engine.sizeThatFits(proposal) }
        }

        func lengthThatFits(_ proposal: ProposedViewSize, in axis: Axis) -> CGFloat {
            withValue(for: proposal) { $0.engine.lengthThatFits(proposal, in: axis) }
        }

        func childGeometries(at size: ViewSize, origin: CGPoint) -> [ViewGeometry] {
            withValue(for: size.proposal) {
                $0.engine.childGeometries(at: size, origin: origin)
            }
        }

        func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
            withValue(for: size.proposal) {
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

    var text: Attribute<ResolvedStyledText>
    var renderer: WeakAttribute<TextRendererBoxBase>
    var cache: SizeFittingTextCache<ResolvedTextHelper, StickyTextSizeFittingLogic>

    mutating func updateValue() {
        let text = text.value
        let rendererValue: TextRendererBoxBase?
        if let graph = _AGGraph.current, renderer.isValid(in: graph) {
            rendererValue = renderer.toStrong().value
        } else {
            rendererValue = nil
        }
        let textChanged = _AGGraph.currentStatefulInputChanged(self.text.identifier)
        let rendererChanged: Bool
        if let graph = _AGGraph.current, renderer.isValid(in: graph) {
            rendererChanged = _AGGraph.currentStatefulInputChanged(
                renderer.toStrong().identifier
            )
        } else {
            rendererChanged = false
        }
        cache.updateInput(changed: textChanged || rendererChanged) { input in
            input.text = text
            input.renderer = rendererValue
        }

        let engine = Engine(ctx: context, cache: cache)
        if var current = _AGGraph.currentStatefulOutput(LayoutComputer.self),
           let box = current.box as? LayoutEngineBox<Engine> {
            box.engine = engine
            current.changeCount &+= 1
            _AGGraph.setStatefulOutput(current)
        } else {
            _AGGraph.setStatefulOutput(
                LayoutComputer(box: LayoutEngineBox(engine: engine))
            )
        }
    }
}
