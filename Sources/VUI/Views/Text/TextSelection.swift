//
//  File: TextSelection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public protocol TextSelectability {
    static var allowsSelection: Bool { get }
}

extension TextSelectability where Self == EnabledTextSelectability {
    public static var enabled: EnabledTextSelectability {
        .init()
    }
}

extension TextSelectability where Self == DisabledTextSelectability {
    public static var disabled: DisabledTextSelectability {
        .init()
    }
}

public struct EnabledTextSelectability: TextSelectability, ~Sendable {
    public static let allowsSelection = true

    init() {}
}

public struct DisabledTextSelectability: TextSelectability, ~Sendable {
    public static let allowsSelection = false

    init() {}
}

struct TextAllowsSelection: ViewInput {
    static let defaultValue = false
}

struct TextSelectabilityModifier<Selectability: TextSelectability>:
    PrimitiveViewModifier, _GraphInputsModifier {
    typealias Body = Never

    init() {}

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[TextAllowsSelection.self] = Selectability.allowsSelection
    }
}

extension View {
    public func textSelection<Selectability>(
        _ selectability: Selectability
    ) -> some View where Selectability: TextSelectability {
        _ = selectability
        return modifier(TextSelectabilityModifier<Selectability>())
    }
}

extension TextSelection {
    final class Configuration {
        enum Representation {
            case textItem(WeakBox<ResolvedStyledText.TextLayoutManager>)
        }

        var textSelections: [Range<Int>]
        var _textSelectionsAttribute: WeakAttribute<[Range<Int>]>
        weak var graphHost: GraphHost?
        var representation: Representation
        var isVertical: Bool
        let id: UUID
        weak var layoutManager: ResolvedStyledText.TextLayoutManager?
        var lastConfiguredSize: CGSize?
        var textOrigin: CGPoint
        var sourceText: String
        var copyEnvironment: EnvironmentValues

        init(
            textSelections: Attribute<[Range<Int>]>,
            graphHost: GraphHost?,
            layoutManager: ResolvedStyledText.TextLayoutManager
        ) {
            self.textSelections = textSelections.value
            self._textSelectionsAttribute = WeakAttribute(textSelections)
            self.graphHost = graphHost
            self.representation = .textItem(WeakBox(layoutManager))
            self.isVertical = false
            self.id = UUID()
            self.layoutManager = layoutManager
            self.lastConfiguredSize = nil
            self.textOrigin = .zero
            self.sourceText = ""
            self.copyEnvironment = EnvironmentValues()
        }

        func setTextSelection(_ selection: Range<Int>) {
            let count = sourceText.utf16.count
            let lower = min(max(selection.lowerBound, 0), count)
            let upper = min(max(selection.upperBound, lower), count)
            setTextSelections(lower == upper ? [] : [lower..<upper])
        }

        private func setTextSelections(_ selections: [Range<Int>]) {
            guard textSelections != selections else { return }
            textSelections = selections
            graphHost?.asyncTransaction(
                Transaction.current,
                setting: _textSelectionsAttribute,
                to: selections,
                style: .immediate,
                mayDeferUpdate: false
            )
        }

        var selectedText: String? {
            guard let selection = textSelections.first,
                  !selection.isEmpty else {
                return nil
            }
            let string = sourceText as NSString
            let lower = min(max(selection.lowerBound, 0), string.length)
            let upper = min(max(selection.upperBound, lower), string.length)
            guard lower < upper else { return nil }
            return string.substring(with: NSRange(
                location: lower,
                length: upper - lower
            ))
        }
    }
}

private struct TextSelectionConfigurationForText: StatefulRule {
    typealias Value = TextSelection.Configuration

    var _text: Attribute<ResolvedStyledText>
    var _textSelections: Attribute<[Range<Int>]>
    var layoutManager: ResolvedStyledText.TextLayoutManager?

    mutating func updateValue() {
        let text = _text.value
        guard let resolvedLayoutManager = text as?
                ResolvedStyledText.TextLayoutManager else {
            fatalError(
                "Selectable Text requires ResolvedStyledText.TextLayoutManager"
            )
        }
        layoutManager = resolvedLayoutManager

        let configuration: TextSelection.Configuration
        if let current = _AGGraph.currentStatefulOutput(Value.self) {
            configuration = current
            configuration.layoutManager = resolvedLayoutManager
            configuration.representation = .textItem(
                WeakBox(resolvedLayoutManager)
            )
        } else {
            configuration = TextSelection.Configuration(
                textSelections: _textSelections,
                graphHost: _AGGraphContext.current?.context as? GraphHost,
                layoutManager: resolvedLayoutManager
            )
        }
        _AGGraph.setStatefulOutput(configuration)
    }
}

struct PlatformSelectableTextChildView {
    var isInTextSelectionGroup: Bool
    var prefersDefaultPointerStyleInGroup: Bool
    var configuration: TextSelection.Configuration
    var text: ResolvedStyledText
    var renderer: TextRendererBoxBase?
    var needsDrawingGroup: Bool
    var sortPriority_v1: Double?
}

private struct SelectableTextLayout {
    struct Cluster {
        var sourceRange: Range<Int>
        var frame: CGRect
    }

    struct Line {
        var frame: CGRect
        var clusters: [Cluster]
    }

    var lines: [Line]
    var textOrigin: CGPoint

    static func resolve(
        layoutManager: ResolvedStyledText.TextLayoutManager,
        renderer: TextRendererBoxBase?,
        size: CGSize,
        sourceUTF16Count: Int
    ) -> SelectableTextLayout {
        let textProxy = TextProxy(layoutManager)
        let layoutBounds = renderer?.textLayoutBounds(
            size: size,
            text: textProxy
        ) ?? CGRect(origin: .zero, size: size)
        guard let layout = layoutManager.layoutValue(
            in: layoutBounds,
            with: layoutBounds.size
        ) else {
            return SelectableTextLayout(lines: [], textOrigin: .zero)
        }

        struct PendingCluster {
            var sourceStart: Int
            var frame: CGRect
        }

        var pendingLines: [(frame: CGRect, clusters: [PendingCluster])] = []
        var allStarts: Set<Int> = []
        for line in layout {
            let lineFrame = line.typographicBounds.rect
            var clustersByStart: [Int: PendingCluster] = [:]
            for run in line {
                for glyphIndex in run.indices {
                    let glyph = run[glyphIndex]
                    guard let sourceStart = glyph.characterIndices
                        .map(\.value).min() else {
                        continue
                    }
                    let glyphFrame = glyph.typographicBounds.rect
                    if var cluster = clustersByStart[sourceStart] {
                        cluster.frame = cluster.frame.union(glyphFrame)
                        clustersByStart[sourceStart] = cluster
                    } else {
                        clustersByStart[sourceStart] = PendingCluster(
                            sourceStart: sourceStart,
                            frame: glyphFrame
                        )
                    }
                    allStarts.insert(sourceStart)
                }
            }
            pendingLines.append((
                frame: lineFrame,
                clusters: clustersByStart.values.sorted {
                    if $0.frame.minX == $1.frame.minX {
                        return $0.sourceStart < $1.sourceStart
                    }
                    return $0.frame.minX < $1.frame.minX
                }
            ))
        }

        let orderedStarts = allStarts.sorted()
        var sourceEndByStart: [Int: Int] = [:]
        for index in orderedStarts.indices {
            let start = orderedStarts[index]
            let next = orderedStarts.index(after: index)
            sourceEndByStart[start] = next < orderedStarts.endIndex
                ? orderedStarts[next]
                : sourceUTF16Count
        }

        let lines = pendingLines.map { pending -> Line in
            Line(
                frame: pending.frame,
                clusters: pending.clusters.compactMap { cluster in
                    let upper = sourceEndByStart[cluster.sourceStart]
                        ?? cluster.sourceStart
                    guard cluster.sourceStart < upper else { return nil }
                    return Cluster(
                        sourceRange: cluster.sourceStart..<upper,
                        frame: CGRect(
                            x: cluster.frame.minX,
                            y: pending.frame.minY,
                            width: cluster.frame.width,
                            height: pending.frame.height
                        )
                    )
                }
            )
        }
        return SelectableTextLayout(
            lines: lines,
            textOrigin: layoutBounds.origin
        )
    }

    func characterOffset(at point: CGPoint, sourceUTF16Count: Int) -> Int {
        guard !lines.isEmpty else { return 0 }
        let line: Line
        if point.y <= lines[0].frame.minY {
            line = lines[0]
        } else if point.y >= lines[lines.count - 1].frame.maxY {
            line = lines[lines.count - 1]
        } else {
            line = lines.first {
                point.y >= $0.frame.minY && point.y < $0.frame.maxY
            } ?? lines[lines.count - 1]
        }
        guard !line.clusters.isEmpty else { return sourceUTF16Count }

        for cluster in line.clusters {
            if point.x <= cluster.frame.midX {
                return cluster.sourceRange.lowerBound
            }
        }
        guard let last = line.clusters.last else { return sourceUTF16Count }
        return last.sourceRange.upperBound
    }

    func selectionRects(for selection: Range<Int>) -> [CGRect] {
        guard !selection.isEmpty else { return [] }
        var result: [CGRect] = []
        for line in lines {
            let selected = line.clusters.filter {
                $0.sourceRange.overlaps(selection)
            }
            guard let first = selected.first else { continue }
            let bounds = selected.dropFirst().reduce(first.frame) {
                $0.union($1.frame)
            }
            result.append(CGRect(
                x: bounds.minX,
                y: line.frame.minY,
                width: bounds.width,
                height: line.frame.height
            ))
        }
        return result
    }
}

private struct SelectableTextChildQuery: StatefulRule, RemovableAttribute {
    typealias Value = [ViewResponder]

    var _configuration: Attribute<TextSelection.Configuration>
    var _resolvedText: Attribute<ResolvedStyledText>
    var _unresolvedText: Attribute<Text>
    var _renderer: WeakAttribute<TextRendererBoxBase>
    var _environment: Attribute<EnvironmentValues>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _children: Attribute<[ViewResponder]>
    var responder: SelectableTextResponder?

    mutating func updateValue() {
        let isInitial = !context.hasValue
        if responder == nil {
            responder = SelectableTextResponder()
        }
        guard let responder else {
            fatalError("SelectableTextChildQuery failed to create responder")
        }

        let configuration = _configuration.value
        let resolvedText = _resolvedText.value
        guard let layoutManager = resolvedText as?
                ResolvedStyledText.TextLayoutManager else {
            fatalError("Selectable Text lost its text layout manager")
        }
        let environment = _environment.value
        let renderer = _renderer.value
        let sourceText = _unresolvedText.value._resolveText(in: environment)
        let size = _size.value
        let child = PlatformSelectableTextChildView(
            isInTextSelectionGroup: false,
            prefersDefaultPointerStyleInGroup: false,
            configuration: configuration,
            text: resolvedText,
            renderer: renderer,
            needsDrawingGroup: resolvedText.needsDrawingGroup,
            sortPriority_v1: nil
        )
        configuration.graphHost = _AGGraphContext.current?.context as? GraphHost
        configuration.representation = .textItem(WeakBox(layoutManager))
        configuration.isVertical = layoutManager.layoutProperties.writingMode
            == .verticalRightToLeft
        configuration.layoutManager = layoutManager
        configuration.lastConfiguredSize = size.value
        configuration.sourceText = sourceText
        configuration.copyEnvironment = environment.untrackedCopy()

        let layout = SelectableTextLayout.resolve(
            layoutManager: layoutManager,
            renderer: renderer,
            size: size.value,
            sourceUTF16Count: sourceText.utf16.count
        )
        configuration.textOrigin = layout.textOrigin
        responder.configuration = child.configuration
        responder.layout = layout
        responder.helper.update(
            data: (value: TrivialContentResponder(), changed: false),
            size: (
                value: size,
                changed: _AGGraph.currentStatefulInputChanged(_size.identifier)
            ),
            position: (
                value: _position.value,
                changed: _AGGraph.currentStatefulInputChanged(
                    _position.identifier
                )
            ),
            transform: (
                value: _transform.value,
                changed: _AGGraph.currentStatefulInputChanged(
                    _transform.identifier
                )
            ),
            parent: responder
        )
        responder.updateChildren((
            value: _children.value,
            changed: isInitial || _AGGraph.currentStatefulInputChanged(
                _children.identifier
            )
        ))
        _AGGraph.setStatefulOutput([responder])
    }

    static func willRemove(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "SelectableTextChildQuery.willRemove called outside AG context"
            )
        }
        var responder: SelectableTextResponder?
        graph.mutateStatefulRule(attribute, as: Self.self) { rule in
            responder = rule.responder
        }
        guard let responder else { return }
        (responder.host as? WindowController)?
            .resignTextSelectionFocus(responder)
    }
}

private struct TextSelectionRects: Rule {
    var _resolvedText: Attribute<ResolvedStyledText>
    var _renderer: WeakAttribute<TextRendererBoxBase>
    var _size: Attribute<ViewSize>
    var _configuration: Attribute<TextSelection.Configuration>
    var _textSelections: Attribute<[Range<Int>]>

    var value: [CGRect] {
        let configuration = _configuration.value
        guard let layoutManager = _resolvedText.value as?
                ResolvedStyledText.TextLayoutManager else {
            fatalError("Selectable Text highlight lost its layout manager")
        }
        let layout = SelectableTextLayout.resolve(
            layoutManager: layoutManager,
            renderer: _renderer.value,
            size: _size.value.value,
            sourceUTF16Count: configuration.sourceText.utf16.count
        )
        return _textSelections.value.flatMap(layout.selectionRects(for:))
    }
}

private struct TextSelectionHighlightDisplayList: Rule {
    private static let activeSelectionColor = Color(
        .sRGB,
        red: 186.0 / 255.0,
        green: 214.0 / 255.0,
        blue: 251.0 / 255.0
    )

    var _position: Attribute<CGPoint>
    var _containerPosition: Attribute<CGPoint>
    var _environment: Attribute<EnvironmentValues>
    var _rects: Attribute<[CGRect]>

    var value: DisplayList {
        let position = _position.value
        let containerPosition = _containerPosition.value
        let offset = CGPoint(
            x: position.x - containerPosition.x,
            y: position.y - containerPosition.y
        )
        let environment = _environment.value.untrackedCopy()
        var result = DisplayList()
        for rect in _rects.value where !rect.isEmpty {
            let frame = rect.offsetBy(dx: offset.x, dy: offset.y)
            result.appendShapeItem(
                path: Rectangle().path(in: frame),
                role: .fill,
                style: Self.activeSelectionColor,
                bounds: frame,
                fillStyle: FillStyle(),
                environment: environment
            )
        }
        return result
    }
}

protocol TextSelectionCommandResponder: TextEditingCommandResponder
where Self: ResponderNode {
    func containsTextSelectionPoint(_ point: CGPoint) -> Bool
    func textSelectionFocusDidChange(_ focused: Bool)
}

private final class SelectableTextResponder: MultiViewResponder,
    ExclusiveResponderEventConsumer, TextSelectionCommandResponder {
    var helper = ContentResponderHelper<TrivialContentResponder>()
    var configuration: TextSelection.Configuration?
    var layout = SelectableTextLayout(lines: [], textOrigin: .zero)

    private var isFocused = false
    private var pointerSelectionSession: (
        eventID: EventID,
        anchor: Int
    )?

    override var features: Features {
        [.platformViews]
    }

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        guard hitTestPolicy(options: options) != .exclude else {
            return .stop
        }
        return helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        eventType == MouseEvent.self
    }

    func exclusivelyConsumes(_ event: any EventType) -> Bool {
        guard let event = event as? MouseEvent else { return false }
        return event.button == .primary
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at _: Time
    ) -> GesturePhase<Void> {
        var result: GesturePhase<Void> = .possible(nil)
        for (eventID, event) in events.sorted(by: {
            $0.key.serial < $1.key.serial
        }) {
            guard let event = event as? MouseEvent,
                  event.button == .primary else {
                continue
            }
            let pointer = (
                phase: event.phase,
                location: event.globalLocation
            )

            switch pointer.phase {
            case .began:
                guard let offset = textOffset(
                    atGlobalPoint: pointer.location
                ) else {
                    continue
                }
                (host as? WindowController)?
                    .focusTextSelectionResponder(self)
                pointerSelectionSession = (eventID, offset)
                configuration?.setTextSelection(offset..<offset)
                result = .active(())
            case .active:
                guard let session = pointerSelectionSession,
                      session.eventID == eventID,
                      let offset = textOffset(
                        atGlobalPoint: pointer.location
                      ) else {
                    continue
                }
                updateSelection(anchor: session.anchor, extent: offset)
                result = .active(())
            case .ended:
                if let session = pointerSelectionSession,
                   session.eventID == eventID,
                   let offset = textOffset(
                    atGlobalPoint: pointer.location
                   ) {
                    updateSelection(anchor: session.anchor, extent: offset)
                }
                if pointerSelectionSession?.eventID == eventID {
                    pointerSelectionSession = nil
                }
                result = .ended(())
            case .failed:
                if pointerSelectionSession?.eventID == eventID {
                    pointerSelectionSession = nil
                }
                result = .failed
            }
        }
        return result
    }

    func resetEventSession() {
        pointerSelectionSession = nil
    }

    private func textOffset(atGlobalPoint point: CGPoint) -> Int? {
        guard let configuration else { return nil }
        var points = [point]
        helper.transform.convertGlobal(to: .local, points: &points)
        return layout.characterOffset(
            at: points[0],
            sourceUTF16Count: configuration.sourceText.utf16.count
        )
    }

    private func updateSelection(anchor: Int, extent: Int) {
        configuration?.setTextSelection(
            min(anchor, extent)..<max(anchor, extent)
        )
    }

    func containsTextSelectionPoint(_ point: CGPoint) -> Bool {
        helper.containsGlobalPoints(
            [point],
            cacheKey: nil,
            options: .platformDefault,
            children: children
        ).mask[0]
    }

    func textSelectionFocusDidChange(_ focused: Bool) {
        isFocused = focused
    }

    func canPerformTextEditingCommand(_ command: TextEditingCommand) -> Bool {
        guard isFocused, let configuration else {
            return false
        }
        switch command {
        case .copy:
            return appContext?.clipboard != nil
                && configuration.selectedText != nil
        default:
            return false
        }
    }

    func performTextEditingCommand(_ command: TextEditingCommand) {
        guard canPerformTextEditingCommand(command),
              let configuration else {
            return
        }
        switch command {
        case .copy:
            guard let clipboard = appContext?.clipboard,
                  let representations = configuration.copyRepresentations else {
                return
            }
            Update.enqueueAction {
                try? clipboard.setData(representations)
            }
        default:
            break
        }
    }
}

extension PlatformSelectableTextChildView {
    static func attach(
        unresolvedText: Attribute<Text>,
        resolvedText: Attribute<ResolvedStyledText>,
        renderer: WeakAttribute<TextRendererBoxBase>,
        inputs: _ViewInputs,
        outputs: inout _ViewOutputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformSelectableTextChildView.attach requires AG context"
            )
        }

        let textSelections = graph.makeInput(value: [Range<Int>]())
        let configuration = graph.makeStatefulRule(
            TextSelectionConfigurationForText(
                _text: resolvedText,
                _textSelections: textSelections,
                layoutManager: nil
            )
        )

        let childNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map(\.value)
        let children: Attribute<[ViewResponder]>
        if childNodes.isEmpty {
            children = graph.makeInput(value: [])
        } else if childNodes.count == 1 {
            children = Attribute(childNodes[0])
        } else {
            children = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for node in childNodes {
                    let value = Attribute<[ViewResponder]>(node).value
                    ViewRespondersKey.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let query = graph.makeStatefulRule(SelectableTextChildQuery(
            _configuration: configuration,
            _resolvedText: resolvedText,
            _unresolvedText: unresolvedText,
            _renderer: renderer,
            _environment: inputs.base.cachedEnvironment.value.environment,
            _position: inputs.position,
            _size: inputs.size,
            _transform: inputs.transform,
            _children: children,
            responder: nil
        ))
        outputs.preferences.preferences.removeAll {
            $0.key == ViewRespondersKey.self
        }
        outputs.preferences.append(
            ViewRespondersKey.self,
            node: query.identifier
        )

        if inputs.preferences.keys.contains(DisplayList.Key.self) {
            let rects = graph.makeRule(TextSelectionRects(
                _resolvedText: resolvedText,
                _renderer: renderer,
                _size: inputs.size,
                _configuration: configuration,
                _textSelections: textSelections
            ))
            let highlight = graph.makeRule(
                TextSelectionHighlightDisplayList(
                    _position: inputs.position,
                    _containerPosition: inputs.containerPosition,
                    _environment: inputs.base.cachedEnvironment.value.environment,
                    _rects: rects
                )
            )
            outputs.preferences.append(
                DisplayList.Key.self,
                node: highlight.identifier
            )
        }
    }
}
