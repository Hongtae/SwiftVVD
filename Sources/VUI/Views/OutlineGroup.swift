//
//  File: OutlineGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct OutlineSubgroupChildren: View, ViewAlias {
    public typealias Body = Never
}

extension OutlineSubgroupChildren: PrimitiveView {}

enum ExpansionState {
    case expanded
    case collapsed
    case unspecified
}

struct IsLeafTraitKey: _ViewTraitKey {
    static var defaultValue: Bool { false }
}

struct _OutlineGenerator_Configuration<Element, Parent, Subgroup>
    where Parent: View, Subgroup: View
{
    struct Subtree: View, ViewAlias {
        typealias Body = Never
    }

    let element: Element
    let isExpanded: Binding<Bool>
    let grouping: (Binding<Bool>, Parent) -> Subgroup
    let parentContent: (Element) -> Parent
    let subtree: Subtree
}

extension _OutlineGenerator_Configuration.Subtree: PrimitiveView {}

struct OutlineGenerator<Element, Parent, Subgroup, Child, Subtree>: View
    where Parent: View, Subgroup: View, Child: View & ViewAlias,
          Subtree: View
{
    let element: Element
    let isExpanded: Binding<Bool>
    let grouping: (Binding<Bool>, Parent) -> Subgroup
    let parentContent: (Element) -> Parent
    let subtree: Subtree

    var body: some View {
        grouping(isExpanded, parentContent(element))
            .modifier(StaticSourceWriter<Child, Subtree>(source: subtree))
    }
}

struct OutlinePrimitive<Data, ID, Parent, Leaf, Subgroup>
    where Data: RandomAccessCollection, ID: Hashable
{
    enum Base {
        case tree(Data.Element)
        case forest(Data)
    }

    struct ExpansionProjection: Projection {
        let id: ID

        func get(base: Set<ID>) -> Bool {
            base.contains(id)
        }

        func set(base: inout Set<ID>, newValue: Bool) {
            if newValue {
                base.insert(id)
            } else {
                base.remove(id)
            }
        }
    }

    let base: Base
    let parentContent: (Data.Element) -> Parent
    let leafContent: (Data.Element) -> Leaf
    let grouping: (Binding<Bool>, Parent) -> Subgroup
    let id: KeyPath<Data.Element, ID>
    let children: (Data.Element) -> Data?
    @Binding var expandedElements: Set<ID>
    let contentID: Int
}

extension OutlinePrimitive: View
    where Parent: View, Leaf: View, Subgroup: View
{
    typealias GeneratorConfiguration = _OutlineGenerator_Configuration<
        Data.Element,
        Parent,
        Subgroup
    >
    typealias GeneratorSubtree = GeneratorConfiguration.Subtree

    @ViewBuilder
    var body: some View {
        switch base {
        case let .tree(element):
            if let descendants = children(element) {
                let elementID = element[keyPath: id]
                OutlineGenerator<
                    Data.Element,
                    Parent,
                    Subgroup,
                    OutlineSubgroupChildren,
                    GeneratorSubtree
                >(
                    element: element,
                    isExpanded: $expandedElements.projecting(
                        ExpansionProjection(id: elementID)
                    ),
                    grouping: grouping,
                    parentContent: parentContent,
                    subtree: GeneratorSubtree()
                )
                .modifier(
                    StaticSourceWriter<GeneratorSubtree, Self>(
                        source: Self(
                            base: .forest(descendants),
                            parentContent: parentContent,
                            leafContent: leafContent,
                            grouping: grouping,
                            id: id,
                            children: children,
                            expandedElements: $expandedElements,
                            contentID: contentID + 1
                        )
                    )
                )
                .tag(elementID)
            } else {
                leafContent(element)
                    ._trait(IsLeafTraitKey.self, true)
                    .tag(element[keyPath: id])
            }

        case let .forest(data):
            if data.isEmpty {
                EmptyView()
                    ._trait(IsLeafTraitKey.self, true)
            } else {
                ForEach(data, id: id) { element in
                    Self(
                        base: .tree(element),
                        parentContent: parentContent,
                        leafContent: leafContent,
                        grouping: grouping,
                        id: id,
                        children: children,
                        expandedElements: $expandedElements,
                        contentID: contentID
                    )
                }
            }
        }
    }
}

public struct OutlineGroup<Data, ID, Parent, Leaf, Subgroup>
    where Data: RandomAccessCollection, ID: Hashable
{
    struct ChildPath {
        let getter: (Data.Element) -> Data?
    }

    @StateOrBinding var expandedElements: Set<ID>
    let base: OutlinePrimitive<Data, ID, Parent, Leaf, Subgroup>.Base
    let id: KeyPath<Data.Element, ID>
    let children: ChildPath
    let parentContent: (Data.Element) -> Parent
    let leafContent: (Data.Element) -> Leaf
    let grouping: (Binding<Bool>, Parent) -> Subgroup

    init(
        base: OutlinePrimitive<Data, ID, Parent, Leaf, Subgroup>.Base,
        id: KeyPath<Data.Element, ID>,
        children: ChildPath,
        parentContent: @escaping (Data.Element) -> Parent,
        leafContent: @escaping (Data.Element) -> Leaf,
        grouping: @escaping (Binding<Bool>, Parent) -> Subgroup
    ) {
        _expandedElements = StateOrBinding(wrappedValue: [])
        self.base = base
        self.id = id
        self.children = children
        self.parentContent = parentContent
        self.leafContent = leafContent
        self.grouping = grouping
    }
}

extension OutlineGroup
    where ID == Data.Element.ID, Parent: View, Parent == Leaf,
          Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>,
          Data.Element: Identifiable
{
    public init<DataElement>(
        _ root: DataElement,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where ID == DataElement.ID, DataElement: Identifiable,
            DataElement == Data.Element
    {
        self.init(
            base: .tree(root),
            id: \.id,
            children: ChildPath { $0[keyPath: children] },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }

    public init<DataElement>(
        _ data: Data,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where ID == DataElement.ID, DataElement: Identifiable,
            DataElement == Data.Element
    {
        self.init(
            base: .forest(data),
            id: \.id,
            children: ChildPath { $0[keyPath: children] },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }
}

extension OutlineGroup
    where Parent: View, Parent == Leaf,
          Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>
{
    private static var defaultGrouping:
        (Binding<Bool>, Parent) -> Subgroup
    {
        { isExpanded, parent in
            DisclosureGroup(
                DisclosureGroupConfiguration(
                    content: OutlineSubgroupChildren(),
                    isExpanded: isExpanded,
                    label: parent
                )
            )
        }
    }

    public init<DataElement>(
        _ root: DataElement,
        id: KeyPath<DataElement, ID>,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(
            base: .tree(root),
            id: id,
            children: ChildPath { $0[keyPath: children] },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }

    public init<DataElement>(
        _ data: Data,
        id: KeyPath<DataElement, ID>,
        children: KeyPath<DataElement, Data?>,
        @ViewBuilder content: @escaping (DataElement) -> Leaf
    ) where DataElement == Data.Element {
        self.init(
            base: .forest(data),
            id: id,
            children: ChildPath { $0[keyPath: children] },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }
}

extension OutlineGroup: View
    where Parent: View, Leaf: View, Subgroup: View
{
    public var body: some View {
        OutlinePrimitive(
            base: base,
            parentContent: parentContent,
            leafContent: leafContent,
            grouping: grouping,
            id: id,
            children: children.getter,
            expandedElements: $expandedElements,
            contentID: 0
        )
    }
}

extension OutlineGroup
    where ID == Data.Element.ID, Parent: View, Parent == Leaf,
          Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>,
          Data.Element: Identifiable
{
    public init<C, E>(
        _ root: Binding<E>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    ) where Data == Binding<C>, ID == E.ID, C: MutableCollection,
            C: RandomAccessCollection, E: Identifiable, E == C.Element
    {
        self.init(
            base: .tree(root),
            id: \.id,
            children: ChildPath {
                Binding<C>($0[dynamicMember: children])
            },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }

    public init<C, E>(
        _ data: Binding<C>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    ) where Data == Binding<C>, ID == E.ID, C: MutableCollection,
            C: RandomAccessCollection, E: Identifiable, E == C.Element
    {
        self.init(
            base: .forest(data),
            id: \.id,
            children: ChildPath {
                Binding<C>($0[dynamicMember: children])
            },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }
}

extension OutlineGroup
    where Parent: View, Parent == Leaf,
          Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>
{
    public init<C, E>(
        _ root: Binding<E>,
        id: KeyPath<E, ID>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    ) where Data == Binding<C>, C: MutableCollection,
            C: RandomAccessCollection, E == C.Element
    {
        let bindingID = (\Binding<E>.wrappedValue).appending(path: id)
        self.init(
            base: .tree(root),
            id: bindingID,
            children: ChildPath {
                Binding<C>($0[dynamicMember: children])
            },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }

    public init<C, E>(
        _ data: Binding<C>,
        id: KeyPath<E, ID>,
        children: WritableKeyPath<E, C?>,
        @ViewBuilder content: @escaping (Binding<E>) -> Leaf
    ) where Data == Binding<C>, C: MutableCollection,
            C: RandomAccessCollection, E == C.Element
    {
        let bindingID = (\Binding<E>.wrappedValue).appending(path: id)
        self.init(
            base: .forest(data),
            id: bindingID,
            children: ChildPath {
                Binding<C>($0[dynamicMember: children])
            },
            parentContent: content,
            leafContent: content,
            grouping: Self.defaultGrouping
        )
    }
}
