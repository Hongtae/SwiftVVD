//
//  File: Canvas.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

public enum ColorRenderingMode: Equatable, Hashable, Sendable {
    case nonLinear
    case linear
    case extendedLinear
}

public struct Canvas<Symbols>: View where Symbols: View {
    public var symbols: Symbols
    public var renderer: (inout GraphicsContext, CGSize) -> Void
    var rasterizationOptions: RasterizationOptions
    var preservesMetadata: Bool

    public var isOpaque: Bool {
        get { rasterizationOptions.isOpaque }
        set { rasterizationOptions.isOpaque = newValue }
    }

    public var colorMode: ColorRenderingMode {
        get { rasterizationOptions.colorMode }
        set { rasterizationOptions.colorMode = newValue }
    }

    public var rendersAsynchronously: Bool {
        get { rasterizationOptions.rendersAsynchronously }
        set { rasterizationOptions.rendersAsynchronously = newValue }
    }

    public init(opaque: Bool = false,
                colorMode: ColorRenderingMode = .nonLinear,
                rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void,
                @ViewBuilder symbols: () -> Symbols) {
        self.symbols = symbols()
        self.renderer = renderer
        self.rasterizationOptions = RasterizationOptions(
            colorMode: colorMode, flags: [.defaultFlags, .isAccelerated]
        )
        self.preservesMetadata = false
        self.isOpaque = opaque
        self.rendersAsynchronously = rendersAsynchronously
    }

    public typealias Body = Never
}

extension Canvas where Symbols == EmptyView {
    public init(opaque: Bool = false,
                colorMode: ColorRenderingMode = .nonLinear,
                rendersAsynchronously: Bool = false,
                renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
        self.symbols = Symbols()
        self.renderer = renderer
        self.rasterizationOptions = RasterizationOptions(
            colorMode: colorMode, flags: [.defaultFlags, .isAccelerated]
        )
        self.preservesMetadata = false
        self.isOpaque = opaque
        self.rendersAsynchronously = rendersAsynchronously
    }
}

extension Canvas {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        var symbols: OptionalAttribute<[CanvasSymbols.Child]> = OptionalAttribute()
        if Symbols.self != EmptyView.self {
            guard let parent = AGSubgraphRef.current else {
                fatalError("Canvas symbols require an active subgraph.")
            }
            var childInputs = inputs
            childInputs.copyCaches()
            childInputs.position = graph.makeInput(value: CGPoint.zero)
            childInputs.containerPosition = childInputs.position
            childInputs.transform = graph.makeInput(value: ViewTransform())
            childInputs.preferences = PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            )
            childInputs.preferences.add(DisplayList.Key.self)
            childInputs.requestsLayoutComputer = true
            childInputs.needsGeometry = true
            childInputs[UsingGraphicsRenderer.self] = true
            let listInputs = _ViewListInputs(from: childInputs)
            let list = Symbols._makeViewList(
                view: view[\.symbols], inputs: listInputs
            ).makeAttribute(inputs: listInputs)
            symbols = OptionalAttribute(graph.makeStatefulRule(CanvasSymbols(
                _list: list, inputs: childInputs, parentSubgraph: parent
            )))
        }
        let dlAttr: Attribute<DisplayList> = graph.makeStatefulRule(CanvasDisplayList(
            _view: view._attribute,
            _position: inputs.position,
            _size: inputs.size,
            _environment: inputs.base.cachedEnvironment.value.environment,
            _symbols: symbols
        ))

        var outputs = _ViewOutputs()
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        return outputs
    }
}

extension Canvas: PrimitiveView, UnaryView, ContentResponder {
}

private struct CanvasDisplayList<Symbols: View>: StatefulRule, AsyncAttribute {
    typealias Value = DisplayList

    var _view: Attribute<Canvas<Symbols>>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _environment: Attribute<EnvironmentValues>
    var _symbols: OptionalAttribute<[CanvasSymbols.Child]>
    var cachedSymbols: SymbolRenderer?

    mutating func updateValue() {
        let canvas = _view.value
        let frame = CGRect(origin: _position.value, size: _size.value.value)
        let environment = _environment.value.untrackedCopy()
        cachedSymbols = _symbols.value.map {
            SymbolRenderer(elts: $0, ctx: AnyRuleContext(context))
        }
        let symbols = cachedSymbols
        let owner = context.attribute.identifier
        let inbox = _AGGraph.current!.inbox
        var list = DisplayList()
        if frame.width > 0 && frame.height > 0 {
            list.appendCustomItem(
                bounds: frame,
                isOpaque: canvas.isOpaque,
                colorMode: canvas.colorMode,
                rendersAsynchronously: canvas.rendersAsynchronously,
                environment: environment
            ) { context in
                context.drawLayer(in: frame) { layerContext, size in
                    // A nested Canvas owns its symbol namespace, including an empty one.
                    layerContext.symbols = symbols
                    _AGGraph.withRuleContext(owner) {
                        withObservationTracking {
                            canvas.renderer(&layerContext, size)
                        } onChange: { [weak inbox] in
                            let transaction = UnsafeBox(Transaction.current)
                            inbox?.enqueue {
                                _AGGraph.current?.markNeedsEvaluation(
                                    owner, transaction: transaction.value,
                                    propagateTransaction: !transaction.value.isEmpty
                                )
                            }
                        }
                    }
                }
            }
        }
        value = list
    }
}

private final class SymbolRenderer: GraphicsContextSymbols {
    enum CachedResolvedSymbol {
        case some(GraphicsContext.ResolvedSymbol)
        case none
    }

    var elts: [CanvasSymbols.Child]
    let ctx: AnyRuleContext
    var cache: [AnyHashable: CachedResolvedSymbol] = [:]

    init(elts: [CanvasSymbols.Child], ctx: AnyRuleContext) {
        self.elts = elts
        self.ctx = ctx
    }

    override func symbol<ID: Hashable>(for id: ID, in context: GraphicsContext) -> GraphicsContext.ResolvedSymbol? {
        let key = AnyHashable(id)
        if let cached = cache[key] {
            switch cached {
            case let .some(symbol): return symbol
            case .none: return nil
            }
        }
        for child in elts {
            guard case let .tagged(tag) = child.traits[TagValueTraitKey<ID>.self],
                  tag == id else { continue }
            // Attribute reads belong to the Canvas output rule even during deferred replay.
            let size = ctx[child.size].value
            let list = ctx[child.list] ?? DisplayList()
            let recordingContext = context.recordingContext(size: size)
            child.renderer.render(list: list, at: .zero, in: recordingContext)
            let symbol = GraphicsContext.ResolvedSymbol(list: recordingContext.recording!, size: size)
            cache[key] = .some(symbol)
            return symbol
        }
        cache[key] = CachedResolvedSymbol.none
        return nil
    }
}

private struct CanvasSymbols: StatefulRule, AsyncAttribute {
    typealias Value = [Child]

    struct Child {
        var subgraph: AGSubgraphRef
        var release: _ViewList_SubgraphRelease?
        var seed: UInt32
        var traits: ViewTraitCollection
        var size: Attribute<ViewSize>
        var list: OptionalAttribute<DisplayList>
        var renderer: DisplayList.GraphicsRenderer
    }

    var _list: Attribute<any ViewList>
    var inputs: _ViewInputs
    var parentSubgraph: AGSubgraphRef
    var children: [_ViewList_ID.Canonical: Child] = [:]
    var seed: UInt32 = 0

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError("CanvasSymbols requires an active graph.")
        }
        seed &+= 1
        var result: [Child] = []
        var from = 0
        _ = _list.value.applySublists(
            from: &from, style: _ViewList_IteratorStyle(), listAttribute: _list,
            transform: _ViewList_TemporarySublistTransform()
        ) { sublist in
            for offset in 0..<sublist.count {
                let index = sublist.start + offset
                let id = sublist.id.elementID(at: index).canonicalID
                if var child = children[id] {
                    guard child.seed != seed else { continue }
                    child.seed = seed
                    child.traits = sublist.traits
                    children[id] = child
                    result.append(child)
                    continue
                }
                let subgraph = AGSubgraphRef(parent: parentSubgraph)
                let child = AGSubgraphRef.withCurrent(subgraph) {
                    var childInputs = inputs
                    childInputs.copyCaches()
                    let size = graph.makeRule(SymbolSize(
                        _size: inputs.size, _layoutComputer: OptionalAttribute()
                    ))
                    childInputs.size = size
                    let outputs = sublist.elements.makeOneElement(
                        at: index, inputs: childInputs
                    ) { elementInputs, makeView in
                        makeView(elementInputs)
                    } ?? _ViewOutputs()
                    size.mutateBody(as: SymbolSize.self, invalidating: true) {
                        $0._layoutComputer = outputs._layoutComputer
                    }
                    let displayList = outputs.preferences.value(for: DisplayList.Key.self)
                        .map { Attribute<DisplayList>($0) }
                    return Child(
                        subgraph: subgraph, release: sublist.elements.retain(),
                        seed: seed, traits: sublist.traits, size: size,
                        list: OptionalAttribute(displayList),
                        renderer: DisplayList.GraphicsRenderer()
                    )
                }
                children[id] = child
                result.append(child)
            }
            return true
        }
        children = children.filter { _, child in
            guard child.seed != seed else { return true }
            child.subgraph.invalidate()
            child.subgraph.removeFromParent()
            return false
        }
        value = result
    }

    struct SymbolSize: Rule, AsyncAttribute {
        var _size: Attribute<ViewSize>
        var _layoutComputer: OptionalAttribute<LayoutComputer>

        var value: ViewSize {
            let proposal = _ProposedSize(_size.value.value)
            guard let computer = _layoutComputer.value else {
                return ViewSize(_size.value.value, proposal: proposal)
            }
            return ViewSize(computer.sizeThatFits(proposal), proposal: proposal)
        }
    }
}

@available(*, unavailable)
extension Canvas: Sendable {}
