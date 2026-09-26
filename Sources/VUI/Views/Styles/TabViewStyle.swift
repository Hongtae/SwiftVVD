//
//  File: TabViewStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol TabViewStyle {
    static func _makeView<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable

    static func _makeViewList<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable
}

public struct _TabViewValue<Style, SelectionValue>
where Style: TabViewStyle, SelectionValue: Hashable {
    let style: Style
    let configuration: TabViewStyleConfiguration<SelectionValue>

    init(
        style: Style,
        configuration: TabViewStyleConfiguration<SelectionValue>
    ) {
        self.style = style
        self.configuration = configuration
    }
}

struct TabViewStyleConfiguration<SelectionValue>
where SelectionValue: Hashable {
    struct Content: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var selection: Binding<SelectionValue>?
    var content: Content
}

private protocol AnyTabViewStyleType {
    static func makeView<SelectionValue>(
        view: _GraphValue<ResolvedTabView<SelectionValue>>,
        style: AnyTabViewStyle,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable

    static func makeViewList<SelectionValue>(
        view: _GraphValue<ResolvedTabView<SelectionValue>>,
        style: AnyTabViewStyle,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable
}

private struct AnyTabViewStyle {
    var value: AGAttribute
    var type: any AnyTabViewStyleType.Type
}

private struct TabViewStyleType<Style: TabViewStyle>:
    AnyTabViewStyleType
{
    private static func makeValue<SelectionValue>(
        view: _GraphValue<ResolvedTabView<SelectionValue>>,
        style: AnyTabViewStyle,
        graph: _AGGraph
    ) -> _GraphValue<_TabViewValue<Style, SelectionValue>>
    where SelectionValue: Hashable {
        let styleAttribute = Attribute<Style>(style.value)
        let configuration = view[\.configuration]._attribute
        let value: Attribute<_TabViewValue<Style, SelectionValue>> =
            graph.makeRule {
                _TabViewValue(
                    style: styleAttribute.value,
                    configuration: configuration.value
                )
            }
        return _GraphValue(_attribute: value)
    }

    static func makeView<SelectionValue>(
        view: _GraphValue<ResolvedTabView<SelectionValue>>,
        style: AnyTabViewStyle,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TabViewStyleType.makeView called outside an active graph."
            )
        }
        return Style._makeView(
            value: makeValue(view: view, style: style, graph: graph),
            inputs: inputs
        )
    }

    static func makeViewList<SelectionValue>(
        view: _GraphValue<ResolvedTabView<SelectionValue>>,
        style: AnyTabViewStyle,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TabViewStyleType.makeViewList called outside an active graph."
            )
        }
        return Style._makeViewList(
            value: makeValue(view: view, style: style, graph: graph),
            inputs: inputs
        )
    }
}

private struct TabViewStyleInput: ViewInput {
    static var defaultValue: AnyTabViewStyle? { nil }

    static func valuesEqual(
        _ lhs: AnyTabViewStyle?,
        _ rhs: AnyTabViewStyle?
    ) -> Bool {
        false
    }
}

struct _TabViewStyleWriter<Style: TabViewStyle>:
    ViewModifier,
    _GraphInputsModifier
{
    typealias Body = Never
    var style: Style

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[TabViewStyleInput.self] = AnyTabViewStyle(
            value: modifier[\.style]._attribute.identifier,
            type: TabViewStyleType<Style>.self
        )
    }
}

struct ResolvedTabView<SelectionValue>: View, PrimitiveView
where SelectionValue: Hashable {
    typealias Body = Never
    var configuration: TabViewStyleConfiguration<SelectionValue>

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ResolvedTabView._makeView called outside an active graph."
            )
        }
        let style = inputs.base[TabViewStyleInput.self]
            ?? defaultStyle(in: graph)
        return style.type.makeView(view: view, style: style, inputs: inputs)
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ResolvedTabView._makeViewList called outside an active graph."
            )
        }
        let style = inputs.base[TabViewStyleInput.self]
            ?? defaultStyle(in: graph)
        return style.type.makeViewList(
            view: view,
            style: style,
            inputs: inputs
        )
    }

    private static func defaultStyle(in graph: _AGGraph) -> AnyTabViewStyle {
        let style: Attribute<DefaultTabViewStyle> = graph.makeRule {
            DefaultTabViewStyle()
        }
        return AnyTabViewStyle(
            value: style.identifier,
            type: TabViewStyleType<DefaultTabViewStyle>.self
        )
    }
}

extension View {
    public func tabViewStyle<Style>(_ style: Style) -> some View
    where Style: TabViewStyle {
        modifier(_TabViewStyleWriter(style: style))
    }
}

struct TabSelectionProjection<SelectionValue>
where SelectionValue: Hashable {
    var binding: Binding<SelectionValue>

    func isSelected(_ value: SelectionValue) -> Bool {
        binding.wrappedValue == value
    }

    func select(_ value: SelectionValue?) {
        guard let value else { return }
        binding.wrappedValue = value
    }
}

private struct TabViewStyleBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: TabViewStyleConfiguration<SelectionValue>

    var body: some View {
        _VariadicView.Tree(
            TabViewContainerRoot(selection: configuration.selection)
        ) {
            configuration.content
        }
    }
}

private struct TabViewContainerRoot<SelectionValue>:
    _VariadicView_MultiViewRoot
where SelectionValue: Hashable {
    var selection: Binding<SelectionValue>?

    func body(children: _VariadicView.Children) -> some View {
        TabViewContainer(children: children, selection: selection)
    }
}

private struct TabViewContainer<SelectionValue>: View
where SelectionValue: Hashable {
    var children: _VariadicView.Children
    var selection: Binding<SelectionValue>?
    @State private var internalSelection = 0

    private func tag(
        for child: _VariadicView.Children.Element
    ) -> SelectionValue? {
        switch child[TagValueTraitKey<SelectionValue>.self] {
        case .untagged:
            nil
        case .tagged(let value):
            value
        }
    }

    private var selectedIndex: Int {
        guard !children.isEmpty else { return children.startIndex }
        guard let selection else {
            return children.indices.contains(internalSelection)
                ? internalSelection
                : children.startIndex
        }
        return children.indices.first {
            tag(for: children[$0]) == selection.wrappedValue
        } ?? children.startIndex
    }

    @ViewBuilder
    var body: some View {
        if !children.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(children.indices, id: \.self) { index in
                        TabViewItem(
                            child: children[index],
                            index: index,
                            selection: selection,
                            internalSelection: $internalSelection
                        )
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)

                Divider()
                TabSelectedContent(
                    children: children,
                    selectedIndex: selectedIndex
                )
            }
        }
    }
}

private struct TabSelectedContent: View {
    typealias Body = Never

    var children: _VariadicView.Children
    var selectedIndex: Int

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TabSelectedContent._makeView called outside an active graph."
            )
        }
        guard let parentSubgraph = AGSubgraph.current else {
            fatalError(
                "TabSelectedContent._makeView requires a current parent subgraph."
            )
        }

        let outputs = inputs.makeIndirectOutputs()
        let state = TabSelectionState(
            view: view._attribute,
            inputs: inputs,
            outputs: outputs,
            parentSubgraph: parentSubgraph
        )
        let mux: Attribute<()> = graph.makeStatefulRule(
            TabSelectionMux(state: state)
        )
        outputs.setIndirectDependency(mux.identifier)
        _ = graph.makeSideEffectRule {
            _ = mux.value
            return ()
        }
        return outputs
    }
}

extension TabSelectedContent: PrimitiveView, UnaryView {}

/// Retains every materialized tab while attaching only the selected tab.
private final class TabSelectionState {
    struct ID: Hashable {
        var listID: _ViewList_ID.Canonical
        var occurrence: Int
    }

    struct Child {
        var subgraph: AGSubgraph
        var release: _ViewList_SubgraphRelease?
        var outputs: _ViewOutputs
        var isInserted: Bool
    }

    var view: Attribute<TabSelectedContent>
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var parentSubgraph: AGSubgraph
    var children: [ID: Child] = [:]
    var selectedID: ID?

    init(
        view: Attribute<TabSelectedContent>,
        inputs: _ViewInputs,
        outputs: _ViewOutputs,
        parentSubgraph: AGSubgraph
    ) {
        self.view = view
        self.inputs = inputs
        self.outputs = outputs
        self.parentSubgraph = parentSubgraph
    }

    func updateSelection() {
        guard _AGGraph.current != nil else {
            fatalError("TabSelectionState.updateSelection called outside AG context.")
        }

        let value = view.value
        let elements = Array(value.children)
        var occurrences: [_ViewList_ID.Canonical: Int] = [:]
        let ids = elements.map { element in
            let listID = element.view.elementID.canonicalID
            let occurrence = occurrences[listID, default: 0]
            occurrences[listID] = occurrence + 1
            return ID(listID: listID, occurrence: occurrence)
        }
        let liveIDs = Set(ids)

        for id in children.keys where !liveIDs.contains(id) {
            eraseChild(id)
        }

        guard !elements.isEmpty else {
            commitSelection(nil)
            return
        }

        let index = elements.indices.contains(value.selectedIndex)
            ? value.selectedIndex
            : elements.startIndex
        let element = elements[index]
        let id = ids[index]

        if children[id] == nil {
            children[id] = makeChild(element)
        }
        commitSelection(id)
    }

    func invalidate() {
        guard _AGGraph.current != nil else {
            fatalError("TabSelectionState.invalidate called outside AG context.")
        }
        outputs.detachIndirectOutputs()
        for id in Array(children.keys) {
            eraseChild(id)
        }
        selectedID = nil
    }

    private func commitSelection(_ id: ID?) {
        guard selectedID != id else { return }

        outputs.detachIndirectOutputs()
        if let selectedID, var previous = children[selectedID], previous.isInserted {
            previous.subgraph.willRemove()
            previous.subgraph.removeFromParent()
            previous.isInserted = false
            children[selectedID] = previous
        }

        selectedID = id
        guard let id, var next = children[id] else { return }
        parentSubgraph.addSecondaryChild(next.subgraph)
        next.subgraph.didReinsert()
        next.outputs.attachIndirectOutputs(to: outputs)
        next.isInserted = true
        children[id] = next
    }

    private func makeChild(
        _ element: _VariadicView.Children.Element
    ) -> Child {
        guard _AGGraph.current != nil else {
            fatalError("TabSelectionState.makeChild called outside AG context.")
        }

        let item = element.view
        let subgraph = AGSubgraph(parent: nil)
        let release = item.elements.retain()
        let childOutputs = AGSubgraph.withCurrent(subgraph) {
            var childInputs = inputs
            childInputs.copyCaches()
            return item.elements.makeOneElement(
                at: item.index,
                inputs: childInputs
            ) { elementInputs, makeView in
                makeView(elementInputs)
            }
        }
        guard let childOutputs else {
            fatalError("TabSelectionState requires each tab to materialize one element.")
        }
        return Child(
            subgraph: subgraph,
            release: release,
            outputs: childOutputs,
            isInserted: false
        )
    }

    private func eraseChild(_ id: ID) {
        guard var child = children.removeValue(forKey: id) else { return }
        if child.isInserted {
            child.subgraph.willRemove()
            child.subgraph.removeFromParent()
            child.isInserted = false
        }
        if AGSubgraphIsValid(child.subgraph) {
            child.subgraph.invalidate()
        }
        child.release = nil
        if selectedID == id {
            selectedID = nil
        }
    }
}

private struct TabSelectionMux: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = ()
    var state: TabSelectionState

    mutating func updateValue() {
        state.updateSelection()
        _AGGraph.setStatefulOutput(())
    }

    mutating func destroy() {
        state.invalidate()
    }
}

private struct TabViewItem<SelectionValue>: View
where SelectionValue: Hashable {
    var child: _VariadicView.Children.Element
    var index: Int
    var selection: Binding<SelectionValue>?
    var internalSelection: Binding<Int>

    private var tag: SelectionValue? {
        switch child[TagValueTraitKey<SelectionValue>.self] {
        case .untagged:
            nil
        case .tagged(let value):
            value
        }
    }

    private var isSelected: Bool {
        if let selection, let tag {
            return TabSelectionProjection(binding: selection).isSelected(tag)
        }
        return selection == nil && internalSelection.wrappedValue == index
    }

    private var label: AnyView {
        child[TabItemTraitKey.self]?.label ?? AnyView(Text("Tab"))
    }

    private func select() {
        if let selection {
            TabSelectionProjection(binding: selection).select(tag)
        } else {
            internalSelection.wrappedValue = index
        }
    }

    var body: some View {
        label
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Color.blue.opacity(0.18)
                } else {
                    Color.clear
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SingleTapGesture<MouseEvent>().onEnded { _ in
                    select()
                },
                including: .all
            )
            .simultaneousGesture(
                SingleTapGesture<TouchEvent>().onEnded { _ in
                    select()
                },
                including: .all
            )
    }
}

private enum TabViewStyleRenderer {
    static func makeView<Style, SelectionValue>(
        value: _GraphValue<_TabViewValue<Style, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs
    where Style: TabViewStyle, SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TabViewStyleRenderer.makeView called outside an active graph."
            )
        }
        let configuration = value[\.configuration]._attribute
        let body: Attribute<TabViewStyleBody<SelectionValue>> =
            graph.makeRule {
                TabViewStyleBody(configuration: configuration.value)
            }
        return TabViewStyleBody<SelectionValue>._makeView(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }

    static func makeViewList<Style, SelectionValue>(
        value: _GraphValue<_TabViewValue<Style, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs
    where Style: TabViewStyle, SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TabViewStyleRenderer.makeViewList called outside an active graph."
            )
        }
        let configuration = value[\.configuration]._attribute
        let body: Attribute<TabViewStyleBody<SelectionValue>> =
            graph.makeRule {
                TabViewStyleBody(configuration: configuration.value)
            }
        return TabViewStyleBody<SelectionValue>._makeViewList(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }
}

public struct DefaultTabViewStyle: TabViewStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeViewList(value: value, inputs: inputs)
    }
}

public struct GroupedTabViewStyle: TabViewStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeViewList(value: value, inputs: inputs)
    }
}

public struct SidebarAdaptableTabViewStyle: TabViewStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeViewList(value: value, inputs: inputs)
    }
}

public struct TabBarOnlyTabViewStyle: TabViewStyle, Sendable {
    public init() {}

    public static func _makeView<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeView(value: value, inputs: inputs)
    }

    public static func _makeViewList<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        TabViewStyleRenderer.makeViewList(value: value, inputs: inputs)
    }
}

extension TabViewStyle where Self == DefaultTabViewStyle {
    public static var automatic: DefaultTabViewStyle {
        DefaultTabViewStyle()
    }
}

extension TabViewStyle where Self == GroupedTabViewStyle {
    public static var grouped: GroupedTabViewStyle {
        GroupedTabViewStyle()
    }
}

extension TabViewStyle where Self == SidebarAdaptableTabViewStyle {
    public static var sidebarAdaptable: SidebarAdaptableTabViewStyle {
        SidebarAdaptableTabViewStyle()
    }
}

extension TabViewStyle where Self == TabBarOnlyTabViewStyle {
    public static var tabBarOnly: TabBarOnlyTabViewStyle {
        TabBarOnlyTabViewStyle()
    }
}
