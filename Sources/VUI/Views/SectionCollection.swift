//
//  File: SectionCollection.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct GroupSectionsOfContent<Sections, Content>: View
    where Sections: View, Content: View {

    var sections: Sections
    var content: (SectionCollection) -> Content

    init(sections: Sections, content: @escaping (SectionCollection) -> Content) {
        self.sections = sections
        self.content = content
    }

    public var body: some View {
        _VariadicView.Tree(SectionsRoot(content: content)) {
            sections
        }
    }
}

struct SectionsRoot<Content: View>: _VariadicView_MultiViewRoot {
    var content: (SectionCollection) -> Content

    func body(children: _VariadicView.Children) -> Content {
        content(SectionCollection(children: children))
    }
}

public struct SectionCollection: RandomAccessCollection {
    var configurations: [SectionConfiguration]

    init(configurations: [SectionConfiguration] = []) {
        self.configurations = configurations
    }

    init(children: _VariadicView.Children) {
        self.init(
            configurations: SectionAccumulator.collect(
                list: children.list,
                listAttribute: nil,
                contentSubgraph: children.contentSubgraph,
                transform: children.transform
            )
        )
    }

    public subscript(index: Int) -> SectionConfiguration {
        configurations[index]
    }

    public var startIndex: Int { configurations.startIndex }
    public var endIndex: Int { configurations.endIndex }

    public typealias Element = SectionConfiguration
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<SectionCollection>
    public typealias SubSequence = Slice<SectionCollection>
}

public struct SectionConfiguration: Identifiable {
    public struct ID: Hashable {
        var base: AnyHashable

        init(_ base: AnyHashable) {
            self.base = base
        }
    }

    var storage: Storage

    struct Storage {
        var id: ID
        var containerValues: ContainerValues
        var header: SubviewsCollection
        var footer: SubviewsCollection
        var content: SubviewsCollection
    }

    init(
        id: ID,
        containerValues: ContainerValues = ContainerValues(),
        header: SubviewsCollection = SubviewsCollection(),
        footer: SubviewsCollection = SubviewsCollection(),
        content: SubviewsCollection = SubviewsCollection()
    ) {
        self.storage = Storage(
            id: id,
            containerValues: containerValues,
            header: header,
            footer: footer,
            content: content
        )
    }

    init(
        section: _ViewList_Section,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?
    ) {
        let contentTransform = _mergedTransform(
            transform,
            appending: section.subviewIDTransform
        )
        let headerFooterTransform = _mergedTransform(
            transform,
            appending: section.headerFooterSubviewIDTransform
        )
        self.init(
            id: ID(AnyHashable(section.id)),
            containerValues: section.containerValues,
            header: SubviewsCollection(region: section.header, transform: headerFooterTransform, contentSubgraph: contentSubgraph),
            footer: SubviewsCollection(region: section.footer, transform: headerFooterTransform, contentSubgraph: contentSubgraph),
            content: SubviewsCollection(region: section.content, transform: contentTransform, contentSubgraph: contentSubgraph)
        )
    }

    public var id: ID { storage.id }
    public var containerValues: ContainerValues { storage.containerValues }
    public var header: SubviewsCollection { storage.header }
    public var footer: SubviewsCollection { storage.footer }
    public var content: SubviewsCollection { storage.content }
}

public struct Subview: View, Identifiable {
    public struct ID: Hashable {
        var base: AnyHashable

        init(_ base: AnyHashable) {
            self.base = base
        }
    }

    var view: _ViewList_View
    var values: ContainerValues

    init(view: _ViewList_View, values: ContainerValues = ContainerValues()) {
        self.view = view
        self.values = values
    }

    public var id: ID {
        ID(AnyHashable(view.id))
    }

    public var containerValues: ContainerValues {
        values
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewList_View._makeView(view: view[\.view], inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public typealias Body = Never
}

extension Subview: _PrimitiveView {
}

public struct SubviewsCollection: RandomAccessCollection, View {
    var source: Source

    enum Source {
        case empty
        case list(
            any ViewList,
            Attribute<any ViewList>?,
            Range<Int>?,
            _ViewList_SublistTransform,
            AGSubgraph?
        )
    }

    init() {
        self.source = .empty
    }

    init(
        list: any ViewList,
        listAttribute: Attribute<any ViewList>? = nil,
        bounds: Range<Int>? = nil,
        transform: _ViewList_SublistTransform = _ViewList_SublistTransform(),
        contentSubgraph: AGSubgraph? = nil
    ) {
        self.source = .list(list, listAttribute, bounds, transform, contentSubgraph)
    }

    init(
        region: (list: any ViewList, attribute: Attribute<any ViewList>)?,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?
    ) {
        if let region {
            self.init(
                list: region.list,
                listAttribute: region.attribute,
                transform: transform,
                contentSubgraph: contentSubgraph
            )
        } else {
            self.init()
        }
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public subscript(index: Int) -> Subview {
        elements[index]
    }

    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice {
        SubviewsCollectionSlice(base: self, bounds: bounds)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { viewList().count(style: _ViewList_IteratorStyle()) }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        let collection = view._attribute
        let listAttr: Attribute<any ViewList> = graph.makeRule {
            collection.value.viewList()
        }
        return _ViewListOutputs(views: .dynamicList(listAttr, nil), nextImplicitID: 0, staticCount: nil)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        nil
    }

    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<SubviewsCollection>
    public typealias SubSequence = SubviewsCollectionSlice
    public typealias Body = Never

    func viewList() -> any ViewList {
        switch source {
        case .empty:
            return EmptyViewList()
        case let .list(list, attribute, bounds, transform, _):
            let currentList = attribute?.value ?? list
            if bounds == nil, transform.isEmpty {
                return currentList
            }
            return SubviewsCollectionViewList(
                base: currentList,
                listAttribute: attribute,
                bounds: bounds,
                transform: transform
            )
        }
    }

    var elements: [Subview] {
        let contentSubgraph: AGSubgraph?
        switch source {
        case .empty:
            contentSubgraph = nil
        case let .list(_, _, _, _, subgraph):
            contentSubgraph = subgraph
        }

        var built: [Subview] = []
        _ = _forEachSublist(in: viewList()) { sublist in
            let sharedElements = _ViewList_SubgraphElements(base: sublist.elements)
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                built.append(Subview(view: _ViewList_View(
                    elements: sharedElements,
                    id: sublist.id.elementID(at: elementIndex),
                    index: elementIndex,
                    count: sublist.count,
                    contentSubgraph: contentSubgraph
                ), values: _containerValues(in: sublist.elements, at: elementIndex)))
            }
            return true
        }
        return built
    }
}

extension SubviewsCollection: _PrimitiveView {
}

public struct SubviewsCollectionSlice: RandomAccessCollection, View {
    var base: SubviewsCollection
    var bounds: Range<Int>

    public subscript(index: Int) -> Subview {
        base[index]
    }

    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice {
        SubviewsCollectionSlice(base: base, bounds: bounds)
    }

    public var startIndex: Int { bounds.lowerBound }
    public var endIndex: Int { bounds.upperBound }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        let slice = view._attribute
        let listAttr: Attribute<any ViewList> = graph.makeRule {
            slice.value.viewList()
        }
        return _ViewListOutputs(views: .dynamicList(listAttr, nil), nextImplicitID: 0, staticCount: nil)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        nil
    }

    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<SubviewsCollectionSlice>
    public typealias SubSequence = SubviewsCollectionSlice
    public typealias Body = Never

    func viewList() -> any ViewList {
        SubviewsCollectionViewList(
            base: base.viewList(),
            listAttribute: nil,
            bounds: bounds,
            transform: _ViewList_SublistTransform()
        )
    }
}

extension SubviewsCollectionSlice: _PrimitiveView {
}

public struct ForEachSectionCollection<Content: View>: RandomAccessCollection {
    var configurations: [SectionConfiguration]
    var source: (any _ForEachSectionCollectionViewListProducing)?

    init(configurations: [SectionConfiguration] = []) {
        self.configurations = configurations
        self.source = nil
    }

    init<Sections: View>(
        subviewOf sections: Sections,
        content: @escaping (SectionConfiguration) -> Content
    ) {
        self.configurations = []
        self.source = _TypedForEachSectionCollectionSource(
            sections: sections,
            content: content
        )
    }

    public var startIndex: Int { configurations.startIndex }
    public var endIndex: Int { configurations.endIndex }

    public subscript(index: Int) -> SectionConfiguration {
        configurations[index]
    }

    public typealias Element = SectionConfiguration
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<ForEachSectionCollection<Content>>
    public typealias SubSequence = Slice<ForEachSectionCollection<Content>>
}

protocol _ForEachSectionCollectionViewListProducing {
    func makeViewList(inputs: _ViewListInputs, graph: _AGGraph) -> _ViewListOutputs
}

private struct _TypedForEachSectionCollectionSource<Sections, Content>: _ForEachSectionCollectionViewListProducing
    where Sections: View, Content: View {

    var sections: Sections
    var content: (SectionConfiguration) -> Content

    func makeViewList(inputs: _ViewListInputs, graph: _AGGraph) -> _ViewListOutputs {
        let grouped = Group(sections: sections) { collection in
            ForEach(collection) { section in
                content(section)
            }
        }
        let groupedAttr: Attribute<Group<GroupSectionsOfContent<Sections, ForEach<SectionCollection, SectionConfiguration.ID, Content>>>> = graph.makeRule {
            grouped
        }
        return type(of: grouped)._makeViewList(
            view: _GraphValue(_attribute: groupedAttr),
            inputs: inputs
        )
    }
}

extension ForEachSectionCollection: _ForEachSectionCollectionViewListProducing {
    func makeViewList(inputs: _ViewListInputs, graph: _AGGraph) -> _ViewListOutputs {
        source?.makeViewList(inputs: inputs, graph: graph)
            ?? _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
    }
}

extension _ViewListOutputs {
    static func sectionListOutputs(
        _ outputs: [_ViewListOutputs],
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewListOutputs.sectionListOutputs called outside an active _AGGraph context.")
        }
        let listAttributes = outputs.map { $0.viewListAttribute() }
        let viewListAttr: Attribute<any ViewList> = graph.makeRule {
            let group = _ViewList_Group(lists: listAttributes.map { ($0.value, $0) })
            return SectionedViewList(base: group) as any ViewList
        }
        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
    }
}

private struct SubviewsCollectionViewList: ViewList {
    var base: any ViewList
    var listAttribute: Attribute<any ViewList>?
    var bounds: Range<Int>?
    var transform: _ViewList_SublistTransform

    func count(style: _ViewList_IteratorStyle) -> Int {
        if let bounds {
            return max(0, bounds.count)
        }
        return base.count(style: style)
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        if let bounds {
            return max(0, bounds.count)
        }
        return base.estimatedCount(style: style)
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform callbackTransform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        let lowerBound = bounds?.lowerBound ?? 0
        let upperBound = bounds?.upperBound ?? Int.max
        var globalStart = 0
        var baseFrom = 0

        func emitSublist(
            _ sourceSublist: _ViewList_Sublist,
            style: _ViewList_IteratorStyle,
            temporaryTransforms: [_ViewList_TemporarySublistTransform],
            sublistTransforms: [_ViewList_SublistTransform]
        ) -> Bool {
            var sublist = sourceSublist
            for temporaryTransform in temporaryTransforms {
                let transform = _viewListTransformDroppingGroupEntryIDs(
                    temporaryTransform.copy()
                )
                transform.apply(to: &sublist)
            }
            for sublistTransform in sublistTransforms {
                sublistTransform.apply(to: &sublist)
            }
            transform.apply(to: &sublist)

            let sublistStart = globalStart
            let sublistEnd = sublistStart + sublist.count
            globalStart = sublistEnd

            let sliceStart = max(lowerBound, sublistStart)
            let sliceEnd = min(upperBound, sublistEnd)
            guard sliceStart < sliceEnd else {
                return true
            }

            let localOffset = sliceStart - sublistStart
            sublist.start += localOffset
            sublist.count = sliceEnd - sliceStart

            if from > 0 {
                if from >= sublist.count {
                    from -= sublist.count
                    return true
                }
                sublist.start += from
                sublist.count -= from
                from = 0
            }

            return to(&from, style, .sublist(sublist), _ViewList_TemporarySublistTransform())
        }

        func applySection(
            _ section: _ViewList_Section,
            style: _ViewList_IteratorStyle,
            temporaryTransforms: [_ViewList_TemporarySublistTransform],
            sublistTransforms: [_ViewList_SublistTransform]
        ) -> Bool {
            let headerFooterTransform = _sectionRegionTransformDroppingSharedGeneratedID(
                section.headerFooterSubviewIDTransform
            )
            let contentTransform = _sectionRegionTransformDroppingSharedGeneratedID(
                section.subviewIDTransform
            )
            return applyRegion(
                section.header,
                style: style,
                temporaryTransforms: temporaryTransforms,
                sublistTransforms: sublistTransforms + [headerFooterTransform]
            ) && applyRegion(
                section.content,
                style: style,
                temporaryTransforms: temporaryTransforms,
                sublistTransforms: sublistTransforms + [contentTransform]
            ) && applyRegion(
                section.footer,
                style: style,
                temporaryTransforms: temporaryTransforms,
                sublistTransforms: sublistTransforms + [headerFooterTransform]
            )
        }

        func applyRegion(
            _ region: (list: any ViewList, attribute: Attribute<any ViewList>?)?,
            style: _ViewList_IteratorStyle,
            temporaryTransforms: [_ViewList_TemporarySublistTransform],
            sublistTransforms: [_ViewList_SublistTransform]
        ) -> Bool {
            guard let region else {
                return true
            }
            var regionFrom = 0
            return region.list.applyNodes(
                from: &regionFrom,
                style: style,
                list: region.attribute,
                transform: _ViewList_TemporarySublistTransform()
            ) { _, nestedStyle, nestedNode, nestedTemporaryTransform in
                let nestedTemporaryTransforms = temporaryTransforms + [nestedTemporaryTransform]
                switch nestedNode {
                case .sublist(let sublist):
                    return emitSublist(
                        sublist,
                        style: nestedStyle,
                        temporaryTransforms: nestedTemporaryTransforms,
                        sublistTransforms: sublistTransforms
                    )
                case .section(let nestedSection):
                    return applySection(
                        nestedSection,
                        style: nestedStyle,
                        temporaryTransforms: nestedTemporaryTransforms,
                        sublistTransforms: sublistTransforms
                    )
                case .list(let nestedList, let nestedAttribute):
                    return applyRegion(
                        (nestedList, nestedAttribute),
                        style: nestedStyle,
                        temporaryTransforms: nestedTemporaryTransforms,
                        sublistTransforms: sublistTransforms
                    )
                case .group(let group):
                    for entry in group.lists {
                        if !applyRegion(
                            entry,
                            style: nestedStyle,
                            temporaryTransforms: nestedTemporaryTransforms,
                            sublistTransforms: sublistTransforms
                        ) {
                            return false
                        }
                    }
                    return true
                }
            }
        }

        return base.applyNodes(
            from: &baseFrom,
            style: style,
            list: listAttribute,
            transform: callbackTransform
        ) { _, style, node, temporaryTransform in
            switch node {
            case .sublist(let sublist):
                return emitSublist(
                    sublist,
                    style: style,
                    temporaryTransforms: [temporaryTransform],
                    sublistTransforms: []
                )
            case .section(let section):
                return applySection(
                    section,
                    style: style,
                    temporaryTransforms: [temporaryTransform],
                    sublistTransforms: []
                )
            case .list(let nestedList, let nestedAttribute):
                return applyRegion(
                    (nestedList, nestedAttribute),
                    style: style,
                    temporaryTransforms: [temporaryTransform],
                    sublistTransforms: []
                )
            case .group(let group):
                for entry in group.lists {
                    if !applyRegion(
                        entry,
                        style: style,
                        temporaryTransforms: [temporaryTransform],
                        sublistTransforms: []
                    ) {
                        return false
                    }
                }
                return true
            }
        }
    }

    var debugDescription: String {
        "SubviewsCollectionViewList(\(count(style: _ViewList_IteratorStyle())))"
    }
}

private struct SectionedViewList: ViewList {
    var base: any ViewList
    var listAttribute: Attribute<any ViewList>?
    var sharedGeneratedSubviewIDSeed: _ViewList_ID.GeneratedIDSeed
    var sharedGeneratedSubviewIDOwner: AGAttribute
    var rowGeneratedSubviewIDBase: UniqueID

    init(
        base: any ViewList,
        listAttribute: Attribute<any ViewList>? = nil,
        sharedGeneratedSubviewIDSeed: _ViewList_ID.GeneratedIDSeed = _ViewList_ID.GeneratedIDSeed(base: UniqueID(), kind: .shared),
        sharedGeneratedSubviewIDOwner: AGAttribute = _makeSectionGeneratedSubviewIDOwner(),
        rowGeneratedSubviewIDBase: UniqueID = UniqueID()
    ) {
        self.base = base
        self.listAttribute = listAttribute
        self.sharedGeneratedSubviewIDSeed = sharedGeneratedSubviewIDSeed
        self.sharedGeneratedSubviewIDOwner = sharedGeneratedSubviewIDOwner
        self.rowGeneratedSubviewIDBase = rowGeneratedSubviewIDBase
    }

    func count(style: _ViewList_IteratorStyle) -> Int {
        nodeCount(style: style, estimate: false)
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        nodeCount(style: style, estimate: true)
    }

    var traitKeys: ViewTraitKeys? { base.traitKeys }
    var traits: ViewTraitCollection { base.traits }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        var materializedBaseIndex = max(0, from)
        var sectionIndex = 0
        return base.applyNodes(
            from: &from,
            style: style,
            list: listAttribute ?? list,
            transform: transform
        ) { nodeFrom, nodeStyle, node, temporaryTransform in
            let sectioned = sectionedNode(
                from: node,
                sectionIndex: sectionIndex,
                materializedBaseIndex: materializedBaseIndex,
                temporaryTransform: temporaryTransform
            )
            if case .section = sectioned.node {
                sectionIndex += 1
            }
            let shouldContinue = to(&nodeFrom, nodeStyle, sectioned.node, sectioned.temporaryTransform)
            materializedBaseIndex += estimatedCount(of: sectioned.node, style: nodeStyle)
            return shouldContinue
        }
    }

    private func nodeCount(style: _ViewList_IteratorStyle, estimate: Bool) -> Int {
        var total = 0
        var from = 0
        _ = applyNodes(
            from: &from,
            style: style,
            list: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, nodeStyle, node, _ in
            switch node {
            case .sublist(let sublist):
                total += sublist.count
            case .section(let section):
                total += estimate ? section.estimatedCount(style: nodeStyle) : section.count(style: nodeStyle)
            case .list(let list, _):
                total += estimate ? list.estimatedCount(style: nodeStyle) : list.count(style: nodeStyle)
            case .group(let group):
                total += estimate ? group.estimatedCount(style: nodeStyle) : group.count(style: nodeStyle)
            }
            return true
        }
        return total
    }

    private func sectionedNode(
        from node: _ViewList_Node,
        sectionIndex: Int,
        materializedBaseIndex: Int,
        temporaryTransform: _ViewList_TemporarySublistTransform
    ) -> (node: _ViewList_Node, temporaryTransform: _ViewList_TemporarySublistTransform) {
        switch node {
        case .sublist(var sublist):
            temporaryTransform.apply(to: &sublist)
            let rowGeneratedSeed = SectionAccumulator.rowGeneratedSeed(
                for: sublist.id,
                sectionIndex: sectionIndex,
                base: rowGeneratedSubviewIDBase
            )
            if let section = SectionAccumulator.makeSection(
                from: sublist,
                contentSubgraph: nil,
                sharedGeneratedSeed: sharedGeneratedSubviewIDSeed,
                sharedGeneratedOwner: sharedGeneratedSubviewIDOwner,
                rowGeneratedSeed: rowGeneratedSeed,
                materializedSectionBaseIndex: materializedBaseIndex
            ) {
                return (.section(section), _ViewList_TemporarySublistTransform())
            }
            return (node, temporaryTransform)
        case .list(let list, let attribute):
            return (.list(SectionedViewList(
                base: list,
                listAttribute: attribute,
                sharedGeneratedSubviewIDSeed: sharedGeneratedSubviewIDSeed,
                sharedGeneratedSubviewIDOwner: sharedGeneratedSubviewIDOwner,
                rowGeneratedSubviewIDBase: rowGeneratedSubviewIDBase
            ), nil), temporaryTransform)
        case .group(let group):
            return (.group(_ViewList_Group(lists: group.lists.map { entry in
                let sectioned = SectionedViewList(
                    base: entry.list,
                    listAttribute: entry.attribute,
                    sharedGeneratedSubviewIDSeed: sharedGeneratedSubviewIDSeed,
                    sharedGeneratedSubviewIDOwner: sharedGeneratedSubviewIDOwner,
                    rowGeneratedSubviewIDBase: rowGeneratedSubviewIDBase
                )
                return (sectioned as any ViewList, entry.attribute)
            })), temporaryTransform)
        case .section:
            return (node, temporaryTransform)
        }
    }

    var debugDescription: String {
        "SectionedViewList(\(estimatedCount(style: _ViewList_IteratorStyle())))"
    }

    private func estimatedCount(of node: _ViewList_Node, style: _ViewList_IteratorStyle) -> Int {
        switch node {
        case .list(let list, _):
            return list.estimatedCount(style: style)
        case .group(let group):
            return group.estimatedCount(style: style)
        case .section(let section):
            return section.estimatedCount(style: style)
        case .sublist(let sublist):
            return sublist.count
        }
    }
}

private struct SectionAccumulator {
    static func collect(
        list: any ViewList,
        listAttribute: Attribute<any ViewList>?,
        contentSubgraph: AGSubgraph?,
        transform: _ViewList_SublistTransform
    ) -> [SectionConfiguration] {
        var accumulator = Self(
            list: list,
            listAttribute: listAttribute,
            contentSubgraph: contentSubgraph,
            transform: transform
        )
        accumulator.collect()
        return accumulator.configurations
    }

    var list: any ViewList
    var listAttribute: Attribute<any ViewList>?
    var contentSubgraph: AGSubgraph?
    var transform: _ViewList_SublistTransform
    var configurations: [SectionConfiguration] = []
    var implicitStart: Int?
    var implicitEnd: Int?
    var currentOffset: Int = 0
    var sawExplicitSection = false
    var sharedGeneratedSubviewIDSeed = _ViewList_ID.GeneratedIDSeed(base: UniqueID(), kind: .shared)
    var sharedGeneratedSubviewIDOwner = _makeSectionGeneratedSubviewIDOwner()
    var rowGeneratedSubviewIDBase = UniqueID()
    var rowGeneratedSectionIndex = 0

    mutating func collect() {
        Update.begin()
        defer { Update.end() }

        var from = 0
        _ = list.applyNodes(
            from: &from,
            style: _ViewList_IteratorStyle(),
            list: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, node, temporaryTransform in
            apply(node: node, temporaryTransform: temporaryTransform)
            return true
        }
        appendImplicitSectionIfNeeded()
    }

    mutating func apply(
        node: _ViewList_Node,
        temporaryTransform: _ViewList_TemporarySublistTransform
    ) {
        switch node {
        case .sublist(var sublist):
            temporaryTransform.apply(to: &sublist)
            transform.apply(to: &sublist)
            if applyMergedElements(sublist.elements, traits: sublist.traits) {
                return
            }
            let rowGeneratedSeed = rowGeneratedSeed(for: sublist.id)
            if let section = SectionAccumulator.makeSectionConfiguration(
                from: sublist,
                transform: transform,
                contentSubgraph: contentSubgraph,
                sharedGeneratedSeed: sharedGeneratedSubviewIDSeed,
                sharedGeneratedOwner: sharedGeneratedSubviewIDOwner,
                rowGeneratedSeed: rowGeneratedSeed
            ) {
                appendImplicitSectionIfNeeded()
                configurations.append(section)
                sawExplicitSection = true
                advanceRowGeneratedSectionIndex()
            } else {
                appendImplicit(count: sublist.count)
            }
            currentOffset += sublist.count

        case .section(let section):
            appendImplicitSectionIfNeeded()
            configurations.append(SectionConfiguration(
                section: section,
                transform: transform,
                contentSubgraph: contentSubgraph
            ))
            sawExplicitSection = true
            currentOffset += section.estimatedCount(style: _ViewList_IteratorStyle())

        case .list(let list, let attribute):
            var nested = SectionAccumulator(
                list: list,
                listAttribute: attribute,
                contentSubgraph: contentSubgraph,
                transform: transform,
                sharedGeneratedSubviewIDSeed: sharedGeneratedSubviewIDSeed,
                sharedGeneratedSubviewIDOwner: sharedGeneratedSubviewIDOwner,
                rowGeneratedSubviewIDBase: rowGeneratedSubviewIDBase,
                rowGeneratedSectionIndex: rowGeneratedSectionIndex
            )
            nested.collect()
            rowGeneratedSectionIndex = nested.rowGeneratedSectionIndex
            if nested.sawExplicitSection {
                appendImplicitSectionIfNeeded()
                configurations.append(contentsOf: nested.configurations)
                sawExplicitSection = true
            } else {
                appendImplicit(count: list.estimatedCount(style: _ViewList_IteratorStyle()))
            }
            currentOffset += list.estimatedCount(style: _ViewList_IteratorStyle())

        case .group(let group):
            var nested = SectionAccumulator(
                list: group,
                listAttribute: nil,
                contentSubgraph: contentSubgraph,
                transform: transform,
                sharedGeneratedSubviewIDSeed: sharedGeneratedSubviewIDSeed,
                sharedGeneratedSubviewIDOwner: sharedGeneratedSubviewIDOwner,
                rowGeneratedSubviewIDBase: rowGeneratedSubviewIDBase,
                rowGeneratedSectionIndex: rowGeneratedSectionIndex
            )
            nested.collect()
            rowGeneratedSectionIndex = nested.rowGeneratedSectionIndex
            if nested.sawExplicitSection {
                appendImplicitSectionIfNeeded()
                configurations.append(contentsOf: nested.configurations)
                sawExplicitSection = true
            } else {
                appendImplicit(count: group.estimatedCount(style: _ViewList_IteratorStyle()))
            }
            currentOffset += group.estimatedCount(style: _ViewList_IteratorStyle())
        }
    }

    mutating func applyMergedElements(
        _ elements: any _ViewList_Elements,
        traits: ViewTraitCollection
    ) -> Bool {
        if let subgraphElements = elements as? _ViewList_SubgraphElements {
            return applyMergedElements(subgraphElements.base, traits: traits)
        }
        if let viewListElements = elements as? ViewListElements {
            switch viewListElements {
            case .merged(let outputs):
                applyMergedOutputs(outputs, traits: traits)
                return true
            case .modified(let modified):
                return applyMergedElements(modified.base, traits: traits)
            case .unaryElements:
                return false
            }
        }
        if let merged = elements as? MergedElements {
            applyMergedOutputs(merged.outputs, traits: traits)
            return true
        }
        if let modified = elements as? ModifiedElements {
            return applyMergedElements(modified.base, traits: traits)
        }
        return false
    }

    mutating func applyMergedOutputs(
        _ outputs: [_ViewListOutputs],
        traits: ViewTraitCollection
    ) {
        for output in outputs {
            switch output.views {
            case .staticList(let elements):
                applyStaticElements(elements, traits: traits)
            case .dynamicList(let attribute, _):
                let list = attribute.value
                var nested = SectionAccumulator(
                    list: list,
                    listAttribute: attribute,
                    contentSubgraph: contentSubgraph,
                    transform: transform,
                    sharedGeneratedSubviewIDSeed: sharedGeneratedSubviewIDSeed,
                    sharedGeneratedSubviewIDOwner: sharedGeneratedSubviewIDOwner,
                    rowGeneratedSubviewIDBase: rowGeneratedSubviewIDBase,
                    rowGeneratedSectionIndex: rowGeneratedSectionIndex
                )
                nested.collect()
                rowGeneratedSectionIndex = nested.rowGeneratedSectionIndex
                if nested.sawExplicitSection {
                    appendImplicitSectionIfNeeded()
                    configurations.append(contentsOf: nested.configurations)
                    sawExplicitSection = true
                } else {
                    appendImplicit(count: list.estimatedCount(style: _ViewList_IteratorStyle()))
                }
                currentOffset += list.estimatedCount(style: _ViewList_IteratorStyle())
            }
        }
    }

    mutating func applyStaticElements(
        _ elements: any _ViewList_Elements,
        traits: ViewTraitCollection
    ) {
        if applyMergedElements(elements, traits: traits) {
            return
        }
        let count = elements.count
        let sublist = _ViewList_Sublist(
            start: 0,
            count: count,
            id: _ViewList_ID(implicitID: currentOffset),
            elements: elements,
            traits: traits,
            list: nil
        )
        let rowGeneratedSeed = rowGeneratedSeed(for: sublist.id)
        if let section = SectionAccumulator.makeSectionConfiguration(
            from: sublist,
            transform: transform,
            contentSubgraph: contentSubgraph,
            sharedGeneratedSeed: sharedGeneratedSubviewIDSeed,
            sharedGeneratedOwner: sharedGeneratedSubviewIDOwner,
            rowGeneratedSeed: rowGeneratedSeed
        ) {
            appendImplicitSectionIfNeeded()
            configurations.append(section)
            sawExplicitSection = true
            advanceRowGeneratedSectionIndex()
        } else {
            appendImplicit(count: count)
        }
        currentOffset += count
    }

    mutating func appendImplicit(count: Int) {
        guard count > 0 else { return }
        if implicitStart == nil {
            implicitStart = currentOffset
        }
        implicitEnd = currentOffset + count
    }

    mutating func appendImplicitSectionIfNeeded() {
        guard let start = implicitStart,
              let end = implicitEnd,
              start < end else {
            implicitStart = nil
            implicitEnd = nil
            return
        }
        let content = SubviewsCollection(
            list: list,
            listAttribute: listAttribute,
            bounds: start..<end,
            transform: transform,
            contentSubgraph: contentSubgraph
        )
        configurations.append(SectionConfiguration(
            id: SectionConfiguration.ID(AnyHashable(UInt32(configurations.count))),
            content: content
        ))
        implicitStart = nil
        implicitEnd = nil
    }

    func rowGeneratedSeed(for id: _ViewList_ID) -> _ViewList_ID.GeneratedIDSeed {
        Self.rowGeneratedSeed(
            for: id,
            sectionIndex: rowGeneratedSectionIndex,
            base: rowGeneratedSubviewIDBase
        )
    }

    static func rowGeneratedSeed(
        for id: _ViewList_ID,
        sectionIndex: Int,
        base: UniqueID
    ) -> _ViewList_ID.GeneratedIDSeed {
        let stride = _sectionExplicitIDs(from: id).isEmpty ? 29 : 34
        let offset = UInt32(truncatingIfNeeded: sectionIndex &* stride)
        return _ViewList_ID.GeneratedIDSeed(
            base: UniqueID(value: base.value &+ offset),
            kind: .rowLocal
        )
    }

    mutating func advanceRowGeneratedSectionIndex() {
        rowGeneratedSectionIndex += 1
    }

    static func makeSectionConfiguration(
        from sublist: _ViewList_Sublist,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?,
        sharedGeneratedSeed: _ViewList_ID.GeneratedIDSeed,
        sharedGeneratedOwner: AGAttribute,
        rowGeneratedSeed: _ViewList_ID.GeneratedIDSeed
    ) -> SectionConfiguration? {
        guard let section = makeSection(
            from: sublist,
            contentSubgraph: contentSubgraph,
            sharedGeneratedSeed: sharedGeneratedSeed,
            sharedGeneratedOwner: sharedGeneratedOwner,
            rowGeneratedSeed: rowGeneratedSeed
        ) else {
            return nil
        }
        return SectionConfiguration(
            section: section,
            transform: transform,
            contentSubgraph: contentSubgraph
        )
    }

    static func makeSection(
        from sublist: _ViewList_Sublist,
        contentSubgraph: AGSubgraph?,
        sharedGeneratedSeed: _ViewList_ID.GeneratedIDSeed,
        sharedGeneratedOwner: AGAttribute,
        rowGeneratedSeed: _ViewList_ID.GeneratedIDSeed,
        materializedSectionBaseIndex: Int? = nil
    ) -> _ViewList_Section? {
        guard sublist.count == 1,
              let generator = typedUnaryGenerator(in: sublist.elements),
              let sectionType = generator.viewType as? any SectionViewListProducing.Type,
              var section = sectionType.makeSection(
                  from: generator,
                  traits: sublist.traits,
                  transform: _ViewList_SublistTransform(),
                  contentSubgraph: contentSubgraph
        ) else {
            return nil
        }
        let contentBaseIndex = materializedSectionBaseIndex.map {
            $0 + (section.header?.list.estimatedCount(style: _ViewList_IteratorStyle()) ?? 0)
        }
        let materializedRowGeneratedSeed = contentBaseIndex.map {
            _ViewList_ID.GeneratedIDSeed(
                base: UniqueID(value: rowGeneratedSeed.base.value &- UInt32(truncatingIfNeeded: $0)),
                kind: rowGeneratedSeed.kind
            )
        } ?? rowGeneratedSeed
        let includeSharedGeneratedID = !section.isHierarchical
        let contentRowGeneratedSeed = section.isHierarchical
            ? _ViewList_ID.GeneratedIDSeed(
                base: materializedRowGeneratedSeed.uniqueID(at: 0),
                kind: .shared
            )
            : materializedRowGeneratedSeed
        section.containerValues = _containerValues(in: sublist.elements, at: sublist.start)
        section.subviewIDTransform = _subviewIDTransform(
            for: sublist.id,
            sectionOwner: AGAttribute(rawValue: section.id),
            sharedGeneratedSeed: sharedGeneratedSeed,
            sharedGeneratedOwner: sharedGeneratedOwner,
            rowGeneratedSeed: contentRowGeneratedSeed,
            includesSharedGeneratedID: includeSharedGeneratedID,
            includesRowGeneratedID: true
        )
        section.headerFooterSubviewIDTransform = _subviewIDTransform(
            for: sublist.id,
            sectionOwner: AGAttribute(rawValue: section.id),
            sharedGeneratedSeed: sharedGeneratedSeed,
            sharedGeneratedOwner: sharedGeneratedOwner,
            rowGeneratedSeed: materializedRowGeneratedSeed,
            includesSharedGeneratedID: includeSharedGeneratedID,
            includesRowGeneratedID: false
        )
        return section
    }

    static func typedUnaryGenerator(in elements: any _ViewList_Elements) -> TypedUnaryViewGenerator? {
        if let unary = elements as? UnaryElements {
            return unary.typedGenerator
        }
        if let subgraphElements = elements as? _ViewList_SubgraphElements {
            return typedUnaryGenerator(in: subgraphElements.base)
        }
        if let viewListElements = elements as? ViewListElements {
            switch viewListElements {
            case .unaryElements(let unary):
                return unary.typedGenerator
            case .modified(let modified):
                return typedUnaryGenerator(in: modified.base)
            case .merged:
                return nil
            }
        }
        if let modified = elements as? ModifiedElements {
            return typedUnaryGenerator(in: modified.base)
        }
        return nil
    }
}

private struct SectionSubviewIDTransformItem: _ViewList_SublistTransform_Item {
    var explicitIDs: [_ViewList_ID.Explicit]

    func apply(to sublist: inout _ViewList_Sublist) {
        sublist.id.explicitIDs.append(contentsOf: regionExplicitIDs)
    }

    func bindID(_ id: inout _ViewList_ID) {
        id.explicitIDs.append(contentsOf: regionExplicitIDs)
    }

    private var regionExplicitIDs: [_ViewList_ID.Explicit] {
        explicitIDs.map { explicit in
            var copy = explicit
            // Section-level IDs become region identity entries, not unary canonical IDs.
            copy.isUnary = false
            return copy
        }
    }
}

private struct SectionGeneratedSubviewIDTransformItem: _ViewList_SublistTransform_Item {
    var seed: _ViewList_ID.GeneratedIDSeed
    var owner: AGAttribute
    var reuseID: Int

    func apply(to sublist: inout _ViewList_Sublist) {
        bindID(&sublist.id)
    }

    func bindID(_ id: inout _ViewList_ID) {
        id.bindGeneratedID(
            seed: seed,
            owner: owner,
            isUnary: false,
            reuseID: reuseID
        )
    }
}

private func _makeSectionGeneratedSubviewIDOwner() -> AGAttribute {
    guard let graph = _AGGraph.current else {
        fatalError("Section generated subview ID owner requires an active _AGGraph context.")
    }
    return graph.makeInput(value: UniqueID()).identifier
}

private func _subviewIDTransform(
    for id: _ViewList_ID,
    sectionOwner: AGAttribute,
    sharedGeneratedSeed: _ViewList_ID.GeneratedIDSeed,
    sharedGeneratedOwner: AGAttribute,
    rowGeneratedSeed: _ViewList_ID.GeneratedIDSeed,
    includesSharedGeneratedID: Bool = true,
    includesRowGeneratedID: Bool
) -> _ViewList_SublistTransform {
    var transform = _ViewList_SublistTransform()

    if includesSharedGeneratedID {
        transform.push(SectionGeneratedSubviewIDTransformItem(
            seed: sharedGeneratedSeed,
            owner: sharedGeneratedOwner,
            reuseID: _ViewList_ID.generatedSectionReuseID
        ))
    }
    let sectionExplicitIDs = _sectionExplicitIDs(from: id)
    if sectionExplicitIDs.isEmpty == false {
        transform.push(SectionSubviewIDTransformItem(explicitIDs: sectionExplicitIDs))
    }
    if includesRowGeneratedID {
        transform.push(SectionGeneratedSubviewIDTransformItem(
            seed: rowGeneratedSeed,
            owner: sectionOwner,
            reuseID: _ViewList_ID.generatedRowReuseID
        ))
    }
    return transform
}

private func _sectionExplicitIDs(from id: _ViewList_ID) -> [_ViewList_ID.Explicit] {
    id.explicitIDs.filter { ($0.id.base is _ViewList_GroupEntryID) == false }
}

func _sectionRegionTransformDroppingSharedGeneratedID(
    _ transform: _ViewList_SublistTransform
) -> _ViewList_SublistTransform {
    var filtered = _ViewList_SublistTransform()
    for item in transform.items {
        if let generated = item as? SectionGeneratedSubviewIDTransformItem,
           generated.reuseID == _ViewList_ID.generatedSectionReuseID {
            continue
        }
        filtered.push(item)
    }
    return filtered
}

private func _mergedTransform(
    _ base: _ViewList_SublistTransform,
    appending appended: _ViewList_SublistTransform
) -> _ViewList_SublistTransform {
    var merged = base
    for item in appended.items {
        merged.push(item)
    }
    return merged
}

private protocol SectionViewListProducing {
    static func makeSection(
        from generator: TypedUnaryViewGenerator,
        traits: ViewTraitCollection,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?
    ) -> _ViewList_Section?
}

extension Section: SectionViewListProducing where Parent: View, Content: View, Footer: View {
    fileprivate static func makeSection(
        from generator: TypedUnaryViewGenerator,
        traits: ViewTraitCollection,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?
    ) -> _ViewList_Section? {
        guard let graph = _AGGraph.current else {
            fatalError("Section accumulator requires an active _AGGraph context.")
        }
        guard generator.viewType == Self.self,
              generator.view.isValid(in: graph) else {
            return nil
        }

        let sectionAttr = Attribute<Self>(generator.view.toStrong())
        let regionInputs = _ViewListInputs(
            base: generator.baseInputs,
            implicitID: 0,
            options: 0,
            _traits: generator.traitListAttr,
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
        var contentRegionInputs = regionInputs
        contentRegionInputs.formUnion(viewListOptions: Int(_ViewListInputs.sectionListOptions))

        let headerAttr: Attribute<Parent> = graph.makeRule {
            sectionAttr.value.header
        }
        let contentAttr: Attribute<Content> = graph.makeRule {
            sectionAttr.value.content
        }
        let footerAttr: Attribute<Footer> = graph.makeRule {
            sectionAttr.value.footer
        }

        let headerList = Parent._makeViewList(
            view: _GraphValue(_attribute: headerAttr),
            inputs: regionInputs
        ).viewListAttribute()
        let contentList = Content._makeViewList(
            view: _GraphValue(_attribute: contentAttr),
            inputs: contentRegionInputs
        ).viewListAttribute()
        let footerList = Footer._makeViewList(
            view: _GraphValue(_attribute: footerAttr),
            inputs: regionInputs
        ).viewListAttribute()
        let isHierarchical = _viewListContainsSection(contentList.value, listAttribute: contentList)

        return _ViewList_Section(
            id: sectionAttr.identifier.rawValue,
            base: _ViewList_Group(lists: [
                (headerList.value, headerList),
                (contentList.value, contentList),
                (footerList.value, footerList),
            ]),
            traits: traits,
            isHierarchical: isHierarchical
        )
    }
}

private func _viewListContainsSection(
    _ list: any ViewList,
    listAttribute: Attribute<any ViewList>? = nil
) -> Bool {
    var found = false
    var from = 0
    _ = list.applyNodes(
        from: &from,
        style: _ViewList_IteratorStyle(),
        list: listAttribute,
        transform: _ViewList_TemporarySublistTransform()
    ) { _, _, node, _ in
        switch node {
        case .section:
            found = true
            return false
        case .list(let nestedList, let nestedAttribute):
            found = _viewListContainsSection(nestedList, listAttribute: nestedAttribute)
            return !found
        case .group(let group):
            for entry in group.lists where _viewListContainsSection(entry.list, listAttribute: entry.attribute) {
                found = true
                return false
            }
            return true
        case .sublist:
            return true
        }
    }
    return found
}

private func _containerValues(in inputs: _GraphInputs) -> ContainerValues {
    inputs.customInputs.value(forKey: ContainerValuesInput.self)
}

private func _mergedContainerValues(
    _ lowerPriority: ContainerValues,
    overriding higherPriority: ContainerValues
) -> ContainerValues {
    guard !higherPriority.storage.isEmpty else {
        return lowerPriority
    }
    var result = lowerPriority
    result.storage.merge(higherPriority.storage) { _, higher in
        higher
    }
    return result
}

private func _containerValues(
    in outputs: [_ViewListOutputs],
    at index: Int
) -> ContainerValues {
    guard index >= 0 else {
        return ContainerValues()
    }
    var remaining = index
    for output in outputs {
        switch output.views {
        case .staticList(let elements):
            if remaining < elements.count {
                return _containerValues(in: elements, at: remaining)
            }
            remaining -= elements.count
        case .dynamicList(let attribute, _):
            let list = attribute.value
            let count = list.count(style: _ViewList_IteratorStyle())
            if remaining < count {
                return _containerValues(in: list, at: remaining)
            }
            remaining -= count
        }
    }
    return ContainerValues()
}

private func _containerValues(
    in list: any ViewList,
    at index: Int
) -> ContainerValues {
    guard index >= 0 else {
        return ContainerValues()
    }
    var remaining = index
    var result: ContainerValues?
    _ = _forEachSublist(in: list) { sublist in
        guard remaining >= sublist.count else {
            result = _containerValues(in: sublist.elements, at: sublist.start + remaining)
            return false
        }
        remaining -= sublist.count
        return true
    }
    return result ?? ContainerValues()
}

private func _containerValues(
    in elements: any _ViewList_Elements,
    at index: Int
) -> ContainerValues {
    guard index >= 0, index < elements.count else {
        return ContainerValues()
    }
    if let unary = elements as? UnaryElements {
        return index == 0 ? _containerValues(in: unary.baseInputs) : ContainerValues()
    }
    if let modified = elements as? ModifiedElements {
        return _mergedContainerValues(
            _containerValues(in: modified.base, at: index),
            overriding: _containerValues(in: modified.baseInputs)
        )
    }
    if let merged = elements as? MergedElements {
        return _containerValues(in: merged.outputs, at: index)
    }
    if let subgraph = elements as? _ViewList_SubgraphElements {
        return _containerValues(in: subgraph.base, at: index)
    }
    if let viewListElements = elements as? ViewListElements {
        switch viewListElements {
        case .unaryElements(let unary):
            return _containerValues(in: unary, at: index)
        case .merged(let outputs):
            return _containerValues(in: outputs, at: index)
        case .modified(let modified):
            return _containerValues(in: modified, at: index)
        }
    }
    return ContainerValues()
}

private extension _ViewListOutputs {
    func viewListAttribute() -> Attribute<any ViewList> {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewListOutputs.viewListAttribute called outside an active _AGGraph context.")
        }
        switch views {
        case .staticList(let elements):
            return graph.makeRule {
                BaseViewList(elements: elements) as any ViewList
            }
        case .dynamicList(let attribute, _):
            return attribute
        }
    }
}
