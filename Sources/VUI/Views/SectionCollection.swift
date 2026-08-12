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

    private struct Child: Rule {
        var _view: Attribute<SectionsRoot>
        var _viewList: Attribute<any ViewList>
        var contentSubgraph: AGSubgraph?

        var value: Content {
            let list = _viewList.value
            let items: [SectionAccumulator.Item]
            if let unsectioned = SectionAccumulator.processUnsectionedContent(
                list: list,
                contentSubgraph: contentSubgraph,
                accumulationStrategy: .chunked
            ) {
                items = unsectioned
            } else {
                var accumulator = SectionAccumulator(
                    contentSubgraph: contentSubgraph,
                    options: [],
                    accumulationStrategy: .chunked
                )
                accumulator.formResult(
                    from: list,
                    listAttribute: _viewList
                )
                items = accumulator.items
            }
            return _view.value.content(
                SectionCollection(
                    base: items.map { SectionConfiguration(item: $0) }
                )
            )
        }
    }

    static var _viewListOptions: Int {
        let options: _ViewListInputs.Options = [
            .requiresDepthAndSections,
            .requiresSections,
            .allowsNestedSections,
        ]
        return options.rawValue
    }

    static func _makeView(
        root: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: (_Graph, _ViewInputs) -> _ViewListOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(Self.self)._makeView called outside an active _AGGraph context."
            )
        }

        return withoutActuallyEscaping(body) { body in
            Content.makeImplicitRoot(inputs: inputs) { _, bodyInputs in
                guard let contentSubgraph = AGSubgraph.current else {
                    fatalError(
                        "\(Self.self)._makeView requires a current content subgraph."
                    )
                }
                let listInputs = bodyInputs.listInputs
                let viewList = body(_Graph(), bodyInputs)
                    .makeAttribute(inputs: listInputs)
                let child: Attribute<Content> = graph.makeRule(
                    Child(
                        _view: root._attribute,
                        _viewList: viewList,
                        contentSubgraph: contentSubgraph
                    )
                )
                return Content._makeViewList(
                    view: _GraphValue(_attribute: child),
                    inputs: bodyInputs.implicitRootBodyInputs
                )
            }
        }
    }

    static func _makeViewList(
        root: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(Self.self)._makeViewList called outside an active _AGGraph context."
            )
        }
        guard let contentSubgraph = AGSubgraph.current else {
            fatalError(
                "\(Self.self)._makeViewList requires a current content subgraph."
            )
        }

        let viewList = body(_Graph(), inputs).makeAttribute(inputs: inputs)
        let child: Attribute<Content> = graph.makeRule(
            Child(
                _view: root._attribute,
                _viewList: viewList,
                contentSubgraph: contentSubgraph
            )
        )
        return Content._makeViewList(
            view: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }

    typealias Body = Never
}

public struct SectionCollection: RandomAccessCollection {
    var base: [SectionConfiguration]

    init(base: [SectionConfiguration] = []) {
        self.base = base
    }

    public subscript(index: Int) -> SectionConfiguration {
        base[index]
    }

    public var startIndex: Int { base.startIndex }
    public var endIndex: Int { base.endIndex }

    public typealias Element = SectionConfiguration
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<SectionCollection>
    public typealias SubSequence = Slice<SectionCollection>
}

@available(*, unavailable)
extension SectionCollection: Sendable {
}

public struct SectionConfiguration: Identifiable {
    public struct ID: Hashable {
        var base: AnyHashable
    }

    var item: SectionAccumulator.Item

    public var id: ID {
        ID(base: AnyHashable(item.id))
    }

    public var containerValues: ContainerValues {
        guard let section = item.sectionList else {
            return ContainerValues()
        }
        return ContainerValues(base: section.traits)
    }

    var hasSubsections: Bool {
        !item.features.contains(.implicit) && item.hasRows
    }

    public var header: SubviewsCollection {
        guard item.headerCount > 0,
              let region = item.sectionList?.header else {
            return SubviewsCollection()
        }
        return SubviewsCollection(
            list: region.list,
            contentSubgraph: item.contentSubgraph,
            transform: item.transform
        )
    }

    public var footer: SubviewsCollection {
        guard item.footerCount > 0,
              let region = item.sectionList?.footer else {
            return SubviewsCollection()
        }
        return SubviewsCollection(
            list: region.list,
            contentSubgraph: item.contentSubgraph,
            transform: item.transform
        )
    }

    public var content: SubviewsCollection {
        if let section = item.sectionList,
           let region = section.content {
            return SubviewsCollection(
                list: region.list,
                contentSubgraph: item.contentSubgraph,
                transform: item.transform
            )
        }
        return SubviewsCollection(
            list: ViewListSublistSlice(
                base: item.list,
                bounds: item.start..<(item.start + item.count)
            ),
            contentSubgraph: item.contentSubgraph,
            transform: item.transform
        )
    }
}

@available(*, unavailable)
extension SectionConfiguration: Sendable {
}

@available(*, unavailable)
extension SectionConfiguration.ID: Sendable {
}

public struct Subview: View, Identifiable {
    public struct ID: Hashable, HasCustomIDRepresentation {
        var base: _ViewList_ID

        init(_ base: _ViewList_ID) {
            self.base = base
        }

        func containsID<ID: Hashable>(_ id: ID) -> Bool {
            base.containsID(id)
        }
    }

    var base: _VariadicView_Children.Element

    init(_ base: _VariadicView_Children.Element) {
        self.base = base
    }

    public var id: ID {
        ID(base.view.elementID)
    }

    public var containerValues: ContainerValues {
        ContainerValues(base: base.traits)
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        _ViewList_View._makeView(view: view[\.base][\.view], inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(Self.self)._makeViewList called outside an active _AGGraph context."
            )
        }
        let traits: Attribute<ViewTraitCollection> = graph.makeRule(
            MergeTraits(
                _overrideTraits: view[\.base][\.traits]._attribute,
                _baseTraits: inputs._traits
            )
        )
        var modifiedInputs = inputs
        modifiedInputs._traits = OptionalAttribute(traits)
        return _ViewListOutputs.unaryViewList(
            view: view,
            inputs: modifiedInputs
        )
    }

    public typealias Body = Never
}

private struct MergeTraits: Rule {
    var _overrideTraits: Attribute<ViewTraitCollection>
    var _baseTraits: OptionalAttribute<ViewTraitCollection>

    var value: ViewTraitCollection {
        var traits = _baseTraits.value ?? ViewTraitCollection()
        traits.merge(_overrideTraits.value)
        return traits
    }
}

@available(*, unavailable)
extension Subview.ID: Sendable {
}

@available(*, unavailable)
extension Subview: Sendable {
}

extension Subview: PrimitiveView, UnaryView {
}

public struct SubviewsCollection: RandomAccessCollection, View {
    var base: _VariadicView_Children

    init() {
        self.init(
            list: EmptyViewList(),
            contentSubgraph: nil,
            transform: _ViewList_SublistTransform()
        )
    }

    init(_ base: _VariadicView_Children) {
        self.base = base
    }

    init(
        list: any ViewList,
        contentSubgraph: AGSubgraph?,
        transform: _ViewList_SublistTransform
    ) {
        self.base = _VariadicView_Children(
            list: list,
            contentSubgraph: contentSubgraph,
            transform: transform
        )
    }

    init(
        region: (list: any ViewList, attribute: Attribute<any ViewList>)?,
        transform: _ViewList_SublistTransform,
        contentSubgraph: AGSubgraph?
    ) {
        if let region {
            self.init(
                list: region.attribute.value,
                contentSubgraph: contentSubgraph,
                transform: transform,
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
        Subview(base[index])
    }

    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice {
        SubviewsCollectionSlice(
            base: Slice(base: self, bounds: bounds)
        )
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { base.endIndex }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _VariadicView_Children._makeViewList(
            view: view[\.base],
            inputs: inputs
        )
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        ForEach<
            _VariadicView_Children,
            AnyHashable,
            _VariadicView_Children.Element
        >._viewListCount(inputs: inputs)
    }

    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<SubviewsCollection>
    public typealias SubSequence = SubviewsCollectionSlice
    public typealias Body = Never
}

@available(*, unavailable)
extension SubviewsCollection: Sendable {
}

extension SubviewsCollection: PrimitiveView {
}

extension SubviewsCollection: MultiView {}

public struct SubviewsCollectionSlice: RandomAccessCollection, View {
    private struct Child: Rule {
        var _slice: Attribute<Slice<SubviewsCollection>>

        var value: ForEach<
            Slice<SubviewsCollection>,
            Subview.ID,
            Subview
        > {
            ForEach(_slice.value, id: \.id) { $0 }
        }
    }

    var base: Slice<SubviewsCollection>

    public subscript(index: Int) -> Subview {
        base[index]
    }

    public subscript(bounds: Range<Int>) -> SubviewsCollectionSlice {
        SubviewsCollectionSlice(base: base[bounds])
    }

    public var startIndex: Int { base.startIndex }
    public var endIndex: Int { base.endIndex }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewList called outside an active _AGGraph context.")
        }
        let child: Attribute<
            ForEach<Slice<SubviewsCollection>, Subview.ID, Subview>
        > = graph.makeRule(Child(_slice: view[\.base]._attribute))
        return ForEach<
            Slice<SubviewsCollection>,
            Subview.ID,
            Subview
        >._makeViewList(
            view: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        ForEach<
            Slice<SubviewsCollection>,
            Subview.ID,
            Subview
        >._viewListCount(inputs: inputs)
    }

    public typealias Element = Subview
    public typealias Index = Int
    public typealias Indices = Range<Int>
    public typealias Iterator = IndexingIterator<SubviewsCollectionSlice>
    public typealias SubSequence = SubviewsCollectionSlice
    public typealias Body = Never
}

@available(*, unavailable)
extension SubviewsCollectionSlice: Sendable {
}

extension SubviewsCollectionSlice: PrimitiveView {
}

extension SubviewsCollectionSlice: MultiView {}

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

@available(*, unavailable)
extension ForEachSectionCollection: Sendable {
}

private struct MakeSection: Rule {
    var lists: [Attribute<any ViewList>]
    var isHierarchical: Bool
    var _traits: OptionalAttribute<ViewTraitCollection>

    var value: any ViewList {
        guard let attribute = AGAttribute.current else {
            fatalError("MakeSection evaluated outside a rule context.")
        }
        return _ViewList_Section(
            id: attribute.rawValue,
            base: _ViewList_Group(
                lists: lists.map { list in
                    (list.value, list)
                }
            ),
            traits: _traits.value ?? ViewTraitCollection(),
            isHierarchical: isHierarchical
        )
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

        var workingInputs = inputs
        var listAttributes: [Attribute<any ViewList>] = []
        listAttributes.reserveCapacity(outputs.count)
        for output in outputs {
            listAttributes.append(
                output.viewListAttribute(inputs: workingInputs)
            )
            workingInputs.implicitID = output.nextImplicitID
        }
        if inputs.options.contains(.sectionsConcatenateFooter) {
            let grouped: Attribute<any ViewList> = graph.makeRule(
                _ViewList_Group.Init(lists: listAttributes)
            )
            if listAttributes.isEmpty {
                listAttributes.append(grouped)
            } else {
                precondition(listAttributes.count >= 2)
                listAttributes[1] = grouped
                if listAttributes.count >= 3 {
                    let empty: Attribute<any ViewList> =
                        GraphHost.currentHost.intern(
                            EmptyViewList() as any ViewList,
                            for: (any ViewList).self,
                            id: .defaultValue
                        )
                    listAttributes[2] = empty
                }
            }
        }

        let viewListAttr: Attribute<any ViewList> = graph.makeRule(
            MakeSection(
                lists: listAttributes,
                isHierarchical:
                    inputs.options.contains(.sectionsAreHierarchical),
                _traits: inputs._traits
            )
        )
        let staticCount = outputs.reduce(Optional(0)) { partial, output in
            guard let partial, let count = output.staticCount else {
                return nil
            }
            return partial + count
        }
        return _ViewListOutputs(
            views: .dynamicList(viewListAttr, nil),
            nextImplicitID: workingInputs.implicitID,
            staticCount: staticCount
        )
    }
}

struct SectionAccumulator {
    struct Item {
        struct Features: OptionSet {
            var rawValue: UInt8

            static let implicit = Features(rawValue: 1)
        }

        var features: Features
        var list: any ViewList
        var contentSubgraph: AGSubgraph?
        var sectionList: _ViewList_Section?
        var transform: _ViewList_SublistTransform
        var ids: RowIDs
        var headerCount: Int
        var footerCount: Int
        var id: UInt32
        var start: Int
        var traits: [ViewTraitCollection]

        var count: Int {
            ids.count
        }

        var hasRows: Bool {
            !ids.isEmpty
        }

        static func implicitSentinel(
            _ list: any ViewList,
            contentSubgraph: AGSubgraph?,
            accumulationStrategy: RowIDAccumulationStrategy
        ) -> Item {
            let count = list.count(style: _ViewList_IteratorStyle())
            return Item(
                features: .implicit,
                list: list,
                contentSubgraph: contentSubgraph,
                sectionList: nil,
                transform: _ViewList_SublistTransform(),
                ids: RowIDs(
                    list: list,
                    listAttribute: nil,
                    start: 0,
                    count: count,
                    accumulationStrategy: accumulationStrategy
                ),
                headerCount: 0,
                footerCount: 0,
                id: 0,
                start: 0,
                traits: [list.traits]
            )
        }
    }

    struct Options: OptionSet {
        var rawValue: UInt8

        static let retainSubgraphs = Options(rawValue: 1)
    }

    enum RowIDAccumulationStrategy: Hashable {
        case chunked
        case heterogeneous
    }

    struct RowIDs: RandomAccessCollection {
        enum IDs {
            case viewListIDs(_ViewList_ID_Views)
            case idArray([_ViewList_ID])
            case sublist(_ViewList_ID.ElementCollection)
            case heterogeneousViewIDs(HeterogeneousViewIDs)
        }

        struct Chunk {
            var ids: IDs
            var count: Int
            var lowerBound: Int

            init(ids: IDs, count: Int, lowerBound: Int) {
                self.ids = ids
                self.count = count
                self.lowerBound = lowerBound
            }

            init(
                list: any ViewList,
                listAttribute: Attribute<any ViewList>?,
                transform: _ViewList_SublistTransform,
                start: Int,
                count: Int,
                lowerBound: Int
            ) {
                self.count = count
                self.lowerBound = lowerBound

                if let baseIDs = list.viewIDs {
                    if transform.isEmpty {
                        self.ids = .viewListIDs(baseIDs)
                    } else {
                        self.ids = .viewListIDs(
                            _ViewList_ID._Views(
                                TransformedIDs(
                                    base: baseIDs,
                                    transform: transform
                                ),
                                isDataDependent: baseIDs.isDataDependent
                            )
                        )
                    }
                    return
                }

                var values: [_ViewList_ID] = []
                values.reserveCapacity(count)
                var index = start
                var remaining = count
                transform.withTemporaryTransform { temporaryTransform in
                    _ = list.applyIDs(
                        from: &index,
                        listAttribute: listAttribute,
                        transform: temporaryTransform
                    ) { id in
                        guard remaining > 0 else {
                            return false
                        }
                        values.append(id)
                        remaining -= 1
                        return remaining > 0
                    }
                }
                self.ids = .idArray(values)
            }
        }

        var chunks: [Chunk]

        init(chunks: [Chunk]) {
            self.chunks = chunks
        }

        init(ids: [_ViewList_ID]) {
            self.chunks = [
                Chunk(
                    ids: .idArray(ids),
                    count: ids.count,
                    lowerBound: 0
                )
            ]
        }

        init(
            list: any ViewList,
            listAttribute: Attribute<any ViewList>?,
            start: Int,
            count: Int,
            accumulationStrategy: RowIDAccumulationStrategy
        ) {
            switch accumulationStrategy {
            case .chunked:
                self.chunks = [
                    Chunk(
                        list: list,
                        listAttribute: listAttribute,
                        transform: _ViewList_SublistTransform(),
                        start: start,
                        count: count,
                        lowerBound: 0
                    )
                ]
            case .heterogeneous:
                var accumulator = HeterogeneousViewIDsAccumulator()
                list.appendViewIDs(into: &accumulator)
                self.chunks = [
                    Chunk(
                        ids: .heterogeneousViewIDs(
                            accumulator.finalize()
                        ),
                        count: accumulator.count,
                        lowerBound: 0
                    )
                ]
            }
        }

        var heterogeneous: HeterogeneousViewIDs? {
            guard chunks.count == 1,
                  case .heterogeneousViewIDs(let ids) = chunks[0].ids else {
                return nil
            }
            return ids
        }

        var startIndex: Int {
            0
        }

        var endIndex: Int {
            guard let last = chunks.last else {
                return 0
            }
            return last.lowerBound + last.count
        }

        subscript(position: Int) -> _ViewList_ID.Canonical {
            precondition(indices.contains(position))
            guard let chunk = chunks.last(where: {
                $0.lowerBound <= position
                    && position < $0.lowerBound + $0.count
            }) else {
                preconditionFailure("Missing section row ID chunk.")
            }
            let localIndex = position - chunk.lowerBound
            switch chunk.ids {
            case .viewListIDs(let ids):
                return ids[localIndex].canonicalID
            case .idArray(let ids):
                return ids[localIndex].canonicalID
            case .sublist(let ids):
                return ids[localIndex].canonicalID
            case .heterogeneousViewIDs(let ids):
                return ids[localIndex]
            }
        }
    }

    struct TransformedIDs: RandomAccessCollection, Equatable {
        var base: _ViewList_ID_Views
        var transform: _ViewList_SublistTransform

        var startIndex: Int {
            base.startIndex
        }

        var endIndex: Int {
            base.endIndex
        }

        subscript(position: Int) -> _ViewList_ID {
            var sublist = _ViewList_Sublist(
                start: 0,
                count: 1,
                id: base[position],
                elements: _ViewList_SubgraphElements(
                    base: EmptyViewListElements()
                ),
                traits: ViewTraitCollection(),
                list: nil
            )
            transform.apply(to: &sublist)
            return sublist.id
        }

        static func == (lhs: TransformedIDs, rhs: TransformedIDs) -> Bool {
            lhs.indices.elementsEqual(rhs.indices) {
                lhs[$0] == rhs[$1]
            }
        }
    }

    private enum RowIDAccumulator {
        case chunked([RowIDs.Chunk])
        case heterogeneous(HeterogeneousViewIDsAccumulator)

        var accumulationStrategy: RowIDAccumulationStrategy {
            switch self {
            case .chunked:
                return .chunked
            case .heterogeneous:
                return .heterogeneous
            }
        }

        var count: Int {
            switch self {
            case .chunked(let chunks):
                guard let last = chunks.last else {
                    return 0
                }
                return last.lowerBound + last.count
            case .heterogeneous(let accumulator):
                return accumulator.count
            }
        }

        mutating func append(
            sublist sourceSublist: _ViewList_Sublist,
            transform temporaryTransform: _ViewList_TemporarySublistTransform
        ) {
            switch self {
            case .chunked(var chunks):
                var sublist = sourceSublist
                temporaryTransform.apply(to: &sublist)
                let lowerBound = chunks.last.map {
                    $0.lowerBound + $0.count
                } ?? 0
                chunks.append(
                    RowIDs.Chunk(
                        ids: .sublist(
                            _ViewList_ID.ElementCollection(
                                id: sublist.id,
                                count: sublist.count
                            )
                        ),
                        count: sublist.count,
                        lowerBound: lowerBound
                    )
                )
                self = .chunked(chunks)
            case .heterogeneous(var accumulator):
                var sublist = sourceSublist
                temporaryTransform.apply(to: &sublist)
                sublist.appendViewIDs(into: &accumulator)
                self = .heterogeneous(accumulator)
            }
        }

        mutating func append(
            list: any ViewList,
            listAttribute: Attribute<any ViewList>?,
            transform temporaryTransform: _ViewList_TemporarySublistTransform,
            count: Int
        ) {
            switch self {
            case .chunked(var chunks):
                chunks.append(
                    RowIDs.Chunk(
                        list: list,
                        listAttribute: listAttribute,
                        transform: temporaryTransform.copy(),
                        start: 0,
                        count: count,
                        lowerBound: self.count
                    )
                )
                self = .chunked(chunks)
            case .heterogeneous(var accumulator):
                var id = _ViewList_ID()
                temporaryTransform.bindID(&id)
                Self.appendViewIDs(
                    from: list,
                    explicitIDs: id.explicitIDs[...],
                    into: &accumulator
                )
                self = .heterogeneous(accumulator)
            }
        }

        func makeSectionRowIDs(
            list: any ViewList,
            listAttribute: Attribute<any ViewList>?,
            transform: _ViewList_SublistTransform,
            count: Int
        ) -> RowIDs {
            switch self {
            case .chunked:
                return RowIDs(
                    chunks: [
                        RowIDs.Chunk(
                            list: list,
                            listAttribute: listAttribute,
                            transform: transform,
                            start: 0,
                            count: count,
                            lowerBound: 0
                        )
                    ]
                )
            case .heterogeneous:
                var accumulator = HeterogeneousViewIDsAccumulator()
                list.appendViewIDs(into: &accumulator)
                return RowIDs(
                    chunks: [
                        RowIDs.Chunk(
                            ids: .heterogeneousViewIDs(
                                accumulator.finalize()
                            ),
                            count: accumulator.count,
                            lowerBound: 0
                        )
                    ]
                )
            }
        }

        private static func appendViewIDs(
            from list: any ViewList,
            explicitIDs: ArraySlice<_ViewList_ID.Explicit>,
            into accumulator: inout HeterogeneousViewIDsAccumulator
        ) {
            guard let explicitID = explicitIDs.first else {
                list.appendViewIDs(into: &accumulator)
                return
            }
            guard let value = explicitID.id.base as? any Hashable else {
                preconditionFailure("A view-list explicit ID must be Hashable.")
            }
            appendViewIDs(
                from: list,
                explicitID: value,
                isUnary: explicitID.isUnary,
                remainingExplicitIDs: explicitIDs.dropFirst(),
                into: &accumulator
            )
        }

        private static func appendViewIDs<ID: Hashable>(
            from list: any ViewList,
            explicitID: ID,
            isUnary: Bool,
            remainingExplicitIDs: ArraySlice<_ViewList_ID.Explicit>,
            into accumulator: inout HeterogeneousViewIDsAccumulator
        ) {
            accumulator.withExplicitID(
                explicitID,
                isUnary: isUnary
            ) { accumulator in
                appendViewIDs(
                    from: list,
                    explicitIDs: remainingExplicitIDs,
                    into: &accumulator
                )
            }
        }

        func finalize() -> RowIDs {
            switch self {
            case .chunked(let chunks):
                return RowIDs(chunks: chunks)
            case .heterogeneous(let accumulator):
                return RowIDs(
                    chunks: [
                        RowIDs.Chunk(
                            ids: .heterogeneousViewIDs(
                                accumulator.finalize()
                            ),
                            count: accumulator.count,
                            lowerBound: 0
                        )
                    ]
                )
            }
        }

        func empty() -> RowIDAccumulator {
            switch self {
            case .chunked:
                return .chunked([])
            case .heterogeneous:
                return .heterogeneous(HeterogeneousViewIDsAccumulator())
            }
        }
    }

    private var rowIDAccumulator: RowIDAccumulator
    var lastExplicitSectionEnd: Int
    var list: (any ViewList)?
    var contentSubgraph: AGSubgraph?
    var items: [Item]
    var subgraphStorage: _ViewList_SublistSubgraphStorage?
    var options: Options
    var viewCount: Int
    var pendingEmptySectionTraits: [ViewTraitCollection]

    init(
        contentSubgraph: AGSubgraph?,
        options: Options,
        accumulationStrategy: RowIDAccumulationStrategy
    ) {
        switch accumulationStrategy {
        case .chunked:
            rowIDAccumulator = .chunked([])
        case .heterogeneous:
            rowIDAccumulator = .heterogeneous(
                HeterogeneousViewIDsAccumulator()
            )
        }
        lastExplicitSectionEnd = 0
        list = nil
        self.contentSubgraph = contentSubgraph
        items = []
        subgraphStorage = nil
        self.options = options
        viewCount = 0
        pendingEmptySectionTraits = []
    }

    static func processUnsectionedContent(
        list: any ViewList,
        contentSubgraph: AGSubgraph?,
        accumulationStrategy: RowIDAccumulationStrategy
    ) -> [Item]? {
        if list.traitKeys?.contains(IsSectionedTraitKey.self) == true {
            return nil
        }
        if let ids = list.viewIDs, ids.isEmpty {
            return []
        }
        return [
            Item.implicitSentinel(
                list,
                contentSubgraph: contentSubgraph,
                accumulationStrategy: accumulationStrategy
            )
        ]
    }

    mutating func formResult(
        from list: any ViewList,
        listAttribute: Attribute<any ViewList>?
    ) {
        Update.begin()
        defer { Update.end() }

        self.list = list
        defer {
            self.list = nil
        }
        var start = 0
        _ = list.applyNodes(
            from: &start,
            style: _ViewList_IteratorStyle(value: 2),
            list: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { start, style, node, transform in
            apply(
                start: &start,
                style: style,
                node: node,
                transform: transform
            )
        }
        if lastExplicitSectionEnd < viewCount {
            appendImplicitSection()
        }
        if items.isEmpty, viewCount > 0 {
            items = [
                Item.implicitSentinel(
                    list,
                    contentSubgraph: contentSubgraph,
                    accumulationStrategy:
                        rowIDAccumulator.accumulationStrategy
                )
            ]
        }
    }

    private mutating func apply(
        start: inout Int,
        style: _ViewList_IteratorStyle,
        node: _ViewList_Node,
        transform: _ViewList_TemporarySublistTransform
    ) -> Bool {
        switch node {
        case .sublist(let sublist):
            rowIDAccumulator.append(
                sublist: sublist,
                transform: transform
            )
            viewCount += sublist.count
            return true

        case .section(let section):
            if lastExplicitSectionEnd < viewCount {
                appendImplicitSection()
            }

            let sectionCount = section.count(style: style)
            guard sectionCount > 0 else {
                lastExplicitSectionEnd = viewCount
                if items.isEmpty {
                    pendingEmptySectionTraits.append(section.traits)
                } else {
                    items[items.index(before: items.endIndex)]
                        .traits.append(section.traits)
                }
                return true
            }

            let sectionTransform = transform.copy()
            if options.contains(.retainSubgraphs),
               var storage = subgraphStorage {
                transform.wrapSubgraphs(into: &storage)
                subgraphStorage = storage
            }

            let headerCount =
                section.header?.list.count(style: style) ?? 0
            let footerCount =
                section.footer?.list.count(style: style) ?? 0
            let content = section.content
            let contentList: any ViewList =
                content?.list ?? EmptyViewList()
            let contentCount = contentList.count(style: style)
            let rowIDs = rowIDAccumulator.makeSectionRowIDs(
                list: contentList,
                listAttribute: content?.attribute,
                transform: sectionTransform,
                count: contentCount
            )
            let traits =
                pendingEmptySectionTraits + [section.traits]
            pendingEmptySectionTraits.removeAll(
                keepingCapacity: true
            )
            items.append(
                Item(
                    features: [],
                    list: section,
                    contentSubgraph: contentSubgraph,
                    sectionList: section,
                    transform: sectionTransform,
                    ids: rowIDs,
                    headerCount: headerCount,
                    footerCount: footerCount,
                    id: section.id,
                    start: 0,
                    traits: traits
                )
            )
            viewCount += sectionCount
            lastExplicitSectionEnd = viewCount
            return true

        case .list(let nestedList, let attribute):
            if let traitKeys = nestedList.traitKeys,
               !traitKeys.contains(IsSectionedTraitKey.self) {
                let count = nestedList.count(style: style)
                rowIDAccumulator.append(
                    list: nestedList,
                    listAttribute: attribute,
                    transform: transform,
                    count: count
                )
                viewCount += count
                return true
            }
            return nestedList.applyNodes(
                from: &start,
                style: style,
                list: attribute,
                transform: transform
            ) { start, style, node, transform in
                apply(
                    start: &start,
                    style: style,
                    node: node,
                    transform: transform
                )
            }

        case .group(let group):
            return group.applyNodes(
                from: &start,
                style: style,
                transform: transform
            ) { start, style, node, transform in
                apply(
                    start: &start,
                    style: style,
                    node: node,
                    transform: transform
                )
            }
        }
    }

    private mutating func appendImplicitSection() {
        guard let list else {
            fatalError("SectionAccumulator is missing its source list.")
        }
        let rowIDs = rowIDAccumulator.finalize()
        guard let id = UInt32(exactly: items.count) else {
            preconditionFailure("Section item count exceeds UInt32.")
        }
        items.append(
            Item(
                features: .implicit,
                list: list,
                contentSubgraph: contentSubgraph,
                sectionList: nil,
                transform: _ViewList_SublistTransform(),
                ids: rowIDs,
                headerCount: 0,
                footerCount: 0,
                id: id,
                start: lastExplicitSectionEnd,
                traits: [list.traits]
            )
        )
        self.rowIDAccumulator = rowIDAccumulator.empty()
    }
}

private extension _ViewListOutputs {
    func viewListAttribute(inputs: _ViewListInputs) -> Attribute<any ViewList> {
        makeAttribute(inputs: inputs)
    }
}
