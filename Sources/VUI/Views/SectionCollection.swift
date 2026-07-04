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
        let regionTransform = _mergedTransform(
            transform,
            appending: section.subviewIDTransform
        )
        self.init(
            id: ID(AnyHashable(section.id)),
            containerValues: section.containerValues,
            header: SubviewsCollection(region: section.header, transform: regionTransform, contentSubgraph: contentSubgraph),
            footer: SubviewsCollection(region: section.footer, transform: regionTransform, contentSubgraph: contentSubgraph),
            content: SubviewsCollection(region: section.content, transform: regionTransform, contentSubgraph: contentSubgraph)
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
                    id: sublist.id,
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
        return base.applyNodes(
            from: &baseFrom,
            style: style,
            list: listAttribute,
            transform: callbackTransform
        ) { _, style, node, temporaryTransform in
            guard case .sublist(var sublist) = node else {
                return true
            }

            temporaryTransform.apply(to: &sublist)
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
    }

    var debugDescription: String {
        "SubviewsCollectionViewList(\(count(style: _ViewList_IteratorStyle())))"
    }
}

private struct SectionedViewList: ViewList {
    var base: any ViewList
    var listAttribute: Attribute<any ViewList>?

    init(
        base: any ViewList,
        listAttribute: Attribute<any ViewList>? = nil
    ) {
        self.base = base
        self.listAttribute = listAttribute
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
        base.applyNodes(
            from: &from,
            style: style,
            list: listAttribute ?? list,
            transform: transform
        ) { nodeFrom, nodeStyle, node, temporaryTransform in
            to(&nodeFrom, nodeStyle, sectionedNode(from: node), temporaryTransform)
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

    private func sectionedNode(from node: _ViewList_Node) -> _ViewList_Node {
        switch node {
        case .sublist(let sublist):
            if let section = SectionAccumulator.makeSection(
                from: sublist,
                contentSubgraph: nil
            ) {
                return .section(section)
            }
            return node
        case .list(let list, let attribute):
            return .list(SectionedViewList(base: list, listAttribute: attribute), nil)
        case .group(let group):
            return .group(_ViewList_Group(lists: group.lists.map { entry in
                let sectioned = SectionedViewList(
                    base: entry.list,
                    listAttribute: entry.attribute
                )
                return (sectioned as any ViewList, entry.attribute)
            }))
        case .section:
            return node
        }
    }

    var debugDescription: String {
        "SectionedViewList(\(estimatedCount(style: _ViewList_IteratorStyle())))"
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
            if let section = SectionAccumulator.makeSectionConfiguration(
                from: sublist,
                transform: transform,
                contentSubgraph: contentSubgraph
            ) {
                appendImplicitSectionIfNeeded()
                configurations.append(section)
                sawExplicitSection = true
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
                transform: transform
            )
            nested.collect()
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
                transform: transform
            )
            nested.collect()
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
                    transform: transform
                )
                nested.collect()
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
        if let section = SectionAccumulator.makeSectionConfiguration(
            from: sublist,
            transform: transform,
            contentSubgraph: contentSubgraph
        ) {
            appendImplicitSectionIfNeeded()
            configurations.append(section)
            sawExplicitSection = true
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

    static func makeSectionConfiguration(
        from sublist: _ViewList_Sublist,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?
    ) -> SectionConfiguration? {
        guard let section = makeSection(
            from: sublist,
            contentSubgraph: contentSubgraph
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
        contentSubgraph: AGSubgraph?
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
        section.containerValues = _containerValues(in: sublist.elements, at: sublist.start)
        section.subviewIDTransform = _subviewIDTransform(for: sublist.id)
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
        sublist.id.explicitIDs.append(contentsOf: explicitIDs)
    }

    func bindID(_ id: inout _ViewList_ID) {
        id.explicitIDs.append(contentsOf: explicitIDs)
    }
}

private func _subviewIDTransform(for id: _ViewList_ID) -> _ViewList_SublistTransform {
    var transform = _ViewList_SublistTransform()
    guard !id.explicitIDs.isEmpty else {
        return transform
    }
    transform.push(SectionSubviewIDTransformItem(explicitIDs: id.explicitIDs))
    return transform
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
            inputs: regionInputs
        ).viewListAttribute()
        let footerList = Footer._makeViewList(
            view: _GraphValue(_attribute: footerAttr),
            inputs: regionInputs
        ).viewListAttribute()

        return _ViewList_Section(
            id: sectionAttr.identifier.rawValue,
            base: _ViewList_Group(lists: [
                (headerList.value, headerList),
                (contentList.value, contentList),
                (footerList.value, footerList),
            ]),
            traits: traits,
            isHierarchical: false
        )
    }
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
