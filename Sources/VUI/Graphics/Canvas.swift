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
            identity: _DisplayList_Identity(),
            _view: view._attribute,
            _position: inputs.position,
            _containerPosition: inputs.containerPosition,
            _size: graph.makeRule { inputs.size.value.value },
            _transform: inputs.transform,
            _environment: inputs.base.cachedEnvironment.value.environment,
            _symbols: symbols,
            tracker: PropertyList.Tracker(),
            lastBounds: .null,
            isFlattened: inputs[UsingGraphicsRenderer.self],
            rendererInvalidated: AtomicBox(wrappedValue: false),
            cachedSymbols: nil
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

    var identity: _DisplayList_Identity
    var _view: Attribute<Canvas<Symbols>>
    var _position: Attribute<CGPoint>
    var _containerPosition: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var _transform: Attribute<ViewTransform>
    var _environment: Attribute<EnvironmentValues>
    var _symbols: OptionalAttribute<[CanvasSymbols.Child]>
    var tracker: PropertyList.Tracker
    var lastBounds: CGRect
    let isFlattened: Bool
    var rendererInvalidated: AtomicBox<Bool>
    var cachedSymbols: SymbolRenderer?

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let previous = _AGGraph.currentStatefulOutput(DisplayList.self)
        let viewChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_view.identifier)
        let positionChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_position.identifier)
        let containerPositionChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_containerPosition.identifier)
        let sizeChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_size.identifier)

        let canvas = _view.value
        let position = _position.value
        let containerPosition = _containerPosition.value
        let size = _size.value
        let transform = _transform.value
        let rawEnvironment = _environment.value
        let elements = _symbols.value
        let frame = CGRect(
            x: position.x - containerPosition.x,
            y: position.y - containerPosition.y,
            width: size.width,
            height: size.height
        )
        let recordingBounds = recordingBounds(size: size, transform: transform)
        let colorSpace: RBColorSpace = canvas.colorMode == .nonLinear
            ? .sRGB
            : .linearSRGB

        let excludedInputs = [
            _view.identifier.rawValue,
            _position.identifier.rawValue,
            _containerPosition.identifier.rawValue,
            _size.identifier.rawValue,
            _transform.identifier.rawValue,
            _environment.identifier.rawValue,
        ]
        let dependentInputChanged = excludedInputs.withUnsafeBufferPointer {
            _AGGraphAnyInputsChanged($0.baseAddress, $0.count)
        }
        let boundsChanged = recordingBounds != lastBounds
        let environmentChanged = isInitialValue ||
            tracker.hasDifferentUsedValues(rawEnvironment._plist)
        let rendererChanged = rendererInvalidated.access { invalidated in
            defer { invalidated = false }
            return invalidated
        }
        let needsRecording = isInitialValue || viewChanged || sizeChanged ||
            dependentInputChanged || boundsChanged || environmentChanged ||
            rendererChanged

        if dependentInputChanged || sizeChanged || environmentChanged ||
            cachedSymbols?.colorSpace != colorSpace {
            cachedSymbols = nil
        }
        lastBounds = recordingBounds

        if !needsRecording, let previous {
            if positionChanged || containerPositionChanged,
               let previousOrigin = canvasOrigin(in: previous) {
                let offset = CGSize(
                    width: frame.minX - previousOrigin.x,
                    height: frame.minY - previousOrigin.y
                )
                if offset != .zero {
                    value = previous.translated(by: offset)
                }
            }
            return
        }

        tracker.reset()
        let environment = EnvironmentValues(
            rawEnvironment._plist,
            tracker: tracker
        )
        if cachedSymbols == nil, let elements {
            cachedSymbols = SymbolRenderer(
                elts: elements,
                ctx: AnyRuleContext(context),
                colorSpace: colorSpace,
                environment: _environment
            )
        }

        var list = DisplayList()
        guard !recordingBounds.isNull, !recordingBounds.isEmpty else {
            value = list
            return
        }
        guard let viewGraph = _AGGraphContext.current?.context as? ViewGraph,
              let rendererHost = viewGraph.rendererHost else {
            fatalError("Canvas recording requires an active ViewGraph renderer host.")
        }

        let scale = environment.displayScale
        precondition(scale.isFinite && scale > 0)
        let viewport = CGRect(
            origin: .zero,
            size: CGSize(
                width: recordingBounds.width * scale,
                height: recordingBounds.height * scale
            )
        )
        let recording = RBDisplayList(
            viewport: viewport,
            colorSpace: colorSpace
        )
        var recordingContext = GraphicsContext(
            recording: recording,
            environment: environment,
            inputs: GraphicsContext.DrawingInputs(
                sceneResources: rendererHost.sceneResources,
                viewport: viewport,
                contentScaleFactor: scale,
                resourceCommandQueue: nil
            )
        )
        recordingContext.translateBy(
            x: -recordingBounds.minX,
            y: -recordingBounds.minY
        )
        recordingContext.clipBoundingRect = recordingBounds
        recordingContext.symbols = cachedSymbols

        let owner = context.attribute.identifier
        let inbox = _AGGraph.current!.inbox
        let rendererInvalidated = rendererInvalidated
        _AGGraph.withRuleContext(owner) {
            withObservationTracking {
                canvas.renderer(&recordingContext, size)
            } onChange: { [weak inbox, rendererInvalidated] in
                rendererInvalidated.access { $0 = true }
                let transaction = UnsafeSendableBox(Transaction.current)
                inbox?.enqueue {
                    _AGGraph.current?.markNeedsEvaluation(
                        owner,
                        transaction: transaction.value,
                        propagateTransaction: !transaction.value.isEmpty
                    )
                }
            }
        }

        let contents = recording.moveContents()
        if contents.isEmpty && !isFlattened {
            value = list
            return
        }
        let publishedBounds: CGRect
        let contentOrigin: CGPoint
        let publishedContents: any RBDisplayListContents
        if isFlattened {
            publishedBounds = frame
            contentOrigin = frame.origin
            publishedContents = contents
        } else {
            guard !contents.boundingRect.isNull,
                  !contents.boundingRect.isEmpty else {
                value = list
                return
            }
            let localBounds = snappedBounds(contents.boundingRect).intersection(
                CGRect(origin: .zero, size: recordingBounds.size)
            )
            guard !localBounds.isNull, !localBounds.isEmpty else {
                value = list
                return
            }
            publishedBounds = localBounds.offsetBy(
                dx: frame.minX + recordingBounds.minX,
                dy: frame.minY + recordingBounds.minY
            )
            contentOrigin = CGPoint(
                x: frame.minX + localBounds.minX,
                y: frame.minY + localBounds.minY
            )
            publishedContents = CanvasDisplayListContents(
                contents,
                recordingOrigin: recordingBounds.origin,
                contentOrigin: localBounds.origin
            )
        }

        var content = DisplayList.Content(
            drawing: publishedContents,
            origin: contentOrigin,
            options: canvas.rasterizationOptions
        )
        content.recordBoundsOverride = publishedBounds
        list.items = [DisplayList.Item(
            content: content,
            frame: publishedBounds,
            identity: identity,
            version: DisplayList.Version(forUpdate: ())
        )]
        list.interpolationBounds = publishedBounds
        value = list
    }

    private func recordingBounds(
        size: CGSize,
        transform: ViewTransform
    ) -> CGRect {
        let canvasBounds = CGRect(origin: .zero, size: size)
        guard let scrollGeometry = transform.containingScrollGeometry else {
            return canvasBounds
        }
        let visibleRect = scrollGeometry.visibleRect
        if visibleRect.width * 2 > size.width,
           visibleRect.height * 2 > size.height {
            return canvasBounds
        }
        let tileLength: CGFloat = 128
        let tiledBounds = CGRect(
            x: floor(visibleRect.minX / tileLength) * tileLength,
            y: floor(visibleRect.minY / tileLength) * tileLength,
            width: visibleRect.width + tileLength,
            height: visibleRect.height + tileLength
        )
        return tiledBounds.intersection(canvasBounds)
    }

    private func snappedBounds(_ bounds: CGRect) -> CGRect {
        let tileLength: CGFloat = 16
        let minX = floor(bounds.minX / tileLength) * tileLength
        let minY = floor(bounds.minY / tileLength) * tileLength
        return CGRect(
            x: minX,
            y: minY,
            width: ceil(bounds.maxX / tileLength) * tileLength - minX,
            height: ceil(bounds.maxY / tileLength) * tileLength - minY
        )
    }

    private func canvasOrigin(in list: DisplayList) -> CGPoint? {
        guard let item = list.items.first,
              case let .content(content) = item.value else {
            return nil
        }
        if isFlattened {
            return item.frame.origin
        }
        guard case let .drawing(contents, origin, _) = content.value,
              let canvasContents = contents as? CanvasDisplayListContents else {
            return nil
        }
        return CGPoint(
            x: origin.x - canvasContents.contentOrigin.x,
            y: origin.y - canvasContents.contentOrigin.y
        )
    }
}

private final class CanvasDisplayListContents: RBDisplayListContents {
    // Recorded tiles are local to their 128-point recording origin. Replay
    // restores that origin while keeping the public 16-point content origin.
    let contents: any RBDisplayListContents
    let recordingOrigin: CGPoint
    let contentOrigin: CGPoint

    var boundingRect: CGRect {
        contents.boundingRect.offsetBy(
            dx: recordingOrigin.x - contentOrigin.x,
            dy: recordingOrigin.y - contentOrigin.y
        )
    }

    var isEmpty: Bool { contents.isEmpty }

    init(
        _ contents: any RBDisplayListContents,
        recordingOrigin: CGPoint,
        contentOrigin: CGPoint
    ) {
        self.contents = contents
        self.recordingOrigin = recordingOrigin
        self.contentOrigin = contentOrigin
    }

    func draw(in context: GraphicsContext) {
        var context = context
        context.translateBy(
            x: recordingOrigin.x - contentOrigin.x,
            y: recordingOrigin.y - contentOrigin.y
        )
        contents.draw(in: context)
    }
}

private final class SymbolRenderer: GraphicsContextSymbols {
    enum CachedResolvedSymbol {
        case some(GraphicsContext.ResolvedSymbol)
        case none
    }

    var elts: [CanvasSymbols.Child]
    let ctx: AnyRuleContext
    let colorSpace: RBColorSpace
    let environment: Attribute<EnvironmentValues>
    var cache: [AnyHashable: CachedResolvedSymbol] = [:]

    init(
        elts: [CanvasSymbols.Child],
        ctx: AnyRuleContext,
        colorSpace: RBColorSpace,
        environment: Attribute<EnvironmentValues>
    ) {
        self.elts = elts
        self.ctx = ctx
        self.colorSpace = colorSpace
        self.environment = environment
    }

    override func symbol<ID: Hashable>(for id: ID) -> GraphicsContext.ResolvedSymbol? {
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
            // Attribute reads belong to the Canvas output rule that owns this provider.
            let size = ctx[child.size].value
            let list = ctx[child.list] ?? DisplayList()
            let environment = ctx[self.environment]
            guard let viewGraph = _AGGraphContext.current?.context as? ViewGraph,
                  let rendererHost = viewGraph.rendererHost else {
                fatalError("Canvas symbol recording requires an active ViewGraph renderer host.")
            }
            let scale = environment.displayScale
            precondition(scale.isFinite && scale > 0)
            let viewport = CGRect(
                origin: .zero,
                size: CGSize(width: size.width * scale, height: size.height * scale)
            )
            let recording = RBDisplayList(
                viewport: viewport,
                colorSpace: colorSpace
            )
            var recordingContext = GraphicsContext(
                recording: recording,
                environment: environment,
                inputs: GraphicsContext.DrawingInputs(
                    sceneResources: rendererHost.sceneResources,
                    viewport: viewport,
                    contentScaleFactor: scale,
                    resourceCommandQueue: nil
                )
            )
            recordingContext.clipBoundingRect = CGRect(origin: .zero, size: size)
            child.renderer.render(list: list, at: .zero, in: recordingContext)
            let symbol = GraphicsContext.ResolvedSymbol(list: recording, size: size)
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
