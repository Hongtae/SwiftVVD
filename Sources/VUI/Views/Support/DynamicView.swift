//
//  File: DynamicView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

@_silgen_name("swift_conformsToProtocolCommon")
private func _runtimeConformance(
    _ type: UnsafeRawPointer,
    _ descriptor: UnsafeRawPointer
) -> UnsafeRawPointer?

protocol ProtocolDescriptor {
    static var descriptor: UnsafeRawPointer { get }
}

extension ProtocolDescriptor {
    static func conformance(of type: Any.Type) -> TypeConformance<Self>? {
        let metadata = unsafeBitCast(type, to: UnsafeRawPointer.self)
        guard let conformance = _runtimeConformance(metadata, descriptor) else {
            return nil
        }
        return TypeConformance(
            storage: (type: type, conformance: conformance)
        )
    }
}

protocol ConditionalProtocolDescriptor: ProtocolDescriptor {}

protocol TupleDescriptor: ProtocolDescriptor {
    static var typeCache: [ObjectIdentifier: TupleTypeDescription<Self>] {
        get set
    }
}

extension TupleDescriptor {
    static func tupleDescription(_ type: Any.Type) -> TupleTypeDescription<Self> {
        let identifier = ObjectIdentifier(type)
        if let cached = typeCache[identifier] {
            return cached
        }
        let description = TupleTypeDescription<Self>(type)
        typeCache[identifier] = description
        return description
    }
}

struct ViewDescriptor: ConditionalProtocolDescriptor, TupleDescriptor {
    nonisolated(unsafe) static var typeCache: [
        ObjectIdentifier: TupleTypeDescription<ViewDescriptor>
    ] = [:]

    static var descriptor: UnsafeRawPointer {
        _protocolDescriptor(of: (any View).self)
    }
}

protocol ViewTypeVisitor {
    mutating func visit<V>(type: V.Type) where V: View
}

struct TypeConformance<Descriptor> {
    var storage: (type: Any.Type, conformance: UnsafeRawPointer)

    init(storage: (type: Any.Type, conformance: UnsafeRawPointer)) {
        self.storage = storage
    }

    var type: Any.Type {
        storage.type
    }

    var conformance: UnsafeRawPointer {
        storage.conformance
    }

    var metadata: UnsafeRawPointer {
        unsafeBitCast(storage.type, to: UnsafeRawPointer.self)
    }

    /// Rebuilds an existential metatype from its metadata and witness table.
    func unsafeExistentialMetatype<T>(_ type: T.Type) -> T {
        precondition(
            MemoryLayout<T>.size == MemoryLayout.size(ofValue: storage),
            "The requested existential metatype has an unexpected layout."
        )
        return unsafeBitCast(storage, to: T.self)
    }
}

extension TypeConformance where Descriptor: ProtocolDescriptor {
    init(_ type: Any.Type) {
        guard let conformance = Descriptor.conformance(of: type) else {
            preconditionFailure("\(type) does not conform to the described protocol.")
        }
        self = conformance
    }
}

struct TupleTypeDescription<Descriptor> {
    var contentTypes: [(Int, TypeConformance<Descriptor>)]
}

extension TupleTypeDescription where Descriptor: TupleDescriptor {
    init(_ type: Any.Type) {
        if _MetadataKind(type) != .tuple {
            contentTypes = Descriptor.conformance(of: type).map { [(0, $0)] }
                ?? []
            return
        }

        // Keep logical element indices here. Projection converts an index to
        // the storage offset only when the concrete tuple is accessed.
        var contentTypes: [(Int, TypeConformance<Descriptor>)] = []
        var index = 0
        _forEachField(of: type) { _, _, fieldType in
            if let conformance = Descriptor.conformance(of: fieldType) {
                contentTypes.append((index, conformance))
            }
            index += 1
            return true
        }
        self.contentTypes = contentTypes
    }
}

/// Returns the stored-field offset for a tuple element index.
func tupleElementOffset(of type: Any.Type, at targetIndex: Int) -> Int {
    guard _MetadataKind(type) == .tuple else {
        precondition(targetIndex == 0)
        return 0
    }

    var index = 0
    var result: Int?
    _forEachField(of: type) { _, offset, _ in
        defer { index += 1 }
        guard index == targetIndex else { return true }
        result = offset
        return false
    }
    guard let result else {
        preconditionFailure("Tuple element index \(targetIndex) is out of bounds.")
    }
    return result
}

/// Extracts the sole Swift protocol descriptor from existential metadata.
func _protocolDescriptor(of existentialType: Any.Type) -> UnsafeRawPointer {
    let metadata = unsafeBitCast(
        existentialType,
        to: UnsafeRawPointer.self
    )
    let wordSize = MemoryLayout<UInt>.size
    let protocolCount = metadata.load(
        fromByteOffset: wordSize + MemoryLayout<UInt32>.size,
        as: UInt32.self
    )
    precondition(protocolCount == 1)

    let storedReference = metadata.load(
        fromByteOffset: wordSize + 2 * MemoryLayout<UInt32>.size,
        as: UInt.self
    )
    precondition(storedReference & 1 == 0)
    guard let descriptor = UnsafeRawPointer(bitPattern: storedReference) else {
        preconditionFailure("The existential protocol descriptor is missing.")
    }
    return descriptor
}

struct ConditionalTypeDescriptor<Descriptor> {
    indirect enum Storage {
        case atom(TypeConformance<Descriptor>)
        case optional(Any.Type, ConditionalTypeDescriptor<Descriptor>)
        case either(
            Any.Type,
            ConditionalTypeDescriptor<Descriptor>,
            ConditionalTypeDescriptor<Descriptor>
        )
    }

    var storage: Storage
    var count: Int

    static func atom(_ type: Any.Type) -> Self where Descriptor: ProtocolDescriptor {
        Self(storage: .atom(TypeConformance(type)), count: 1)
    }
}

struct ConditionalMetadata<Descriptor> {
    var desc: ConditionalTypeDescriptor<Descriptor>
    var ids: [UniqueID]

    init(desc: ConditionalTypeDescriptor<Descriptor>) {
        self.desc = desc
        self.ids = (0..<desc.count).map { _ in UniqueID() }
    }
}

private protocol ConditionalValueProjecting {
    var conditionalProjection: (branch: Int, value: Any?) { get }
}

protocol ConditionalTypeDescriptorProvider {
    static var conditionalTypeDescriptor: ConditionalTypeDescriptor<ViewDescriptor> { get }
}

private struct ConditionalProjection {
    var index: Int
    var type: Any.Type
    var value: Any
}

func makeConditionalTypeDescriptor<V: View>(
    for type: V.Type
) -> ConditionalTypeDescriptor<ViewDescriptor> {
    if let provider = type as? any ConditionalTypeDescriptorProvider.Type {
        return provider.conditionalTypeDescriptor
    }
    return .atom(type)
}

extension ConditionalTypeDescriptor where Descriptor == ViewDescriptor {
    fileprivate func project(
        _ value: Any,
        baseIndex: Int = 0,
        emptyType: Any.Type = EmptyView.self
    ) -> ConditionalProjection? {
        switch storage {
        case .atom(let conformance):
            return ConditionalProjection(
                index: baseIndex,
                type: conformance.storage.type,
                value: value
            )
        case .optional(_, let wrapped):
            guard let source = value as? any ConditionalValueProjecting else {
                return nil
            }
            let projection = source.conditionalProjection
            guard projection.branch != 0, let wrappedValue = projection.value else {
                return ConditionalProjection(
                    index: baseIndex,
                    type: emptyType,
                    value: EmptyView()
                )
            }
            return wrapped.project(
                wrappedValue,
                baseIndex: baseIndex + 1,
                emptyType: emptyType
            )
        case .either(_, let first, let second):
            guard let source = value as? any ConditionalValueProjecting else {
                return nil
            }
            let projection = source.conditionalProjection
            guard let childValue = projection.value else { return nil }
            if projection.branch == 0 {
                return first.project(
                    childValue,
                    baseIndex: baseIndex,
                    emptyType: emptyType
                )
            }
            return second.project(
                childValue,
                baseIndex: baseIndex + first.count,
                emptyType: emptyType
            )
        }
    }
}

private struct UnwrapConditional<Source, Descriptor, Value>: _AttributeBody {
    var _source: Attribute<Source>
    var desc: ConditionalTypeDescriptor<Descriptor>
    var index: Int
}

extension UnwrapConditional: StatefulRule, AsyncAttribute where Descriptor == ViewDescriptor {
    mutating func updateValue() {
        guard let projection = desc.project(_source.value),
              projection.index == index,
              let value = projection.value as? Value else {
            // A replaced conditional no longer projects the outgoing case. Keep
            // its last cached value until the owner invalidates that child subgraph.
            return
        }
        _AGGraph.setStatefulOutput(value)
    }
}

extension Optional: ConditionalValueProjecting {
    fileprivate var conditionalProjection: (branch: Int, value: Any?) {
        switch self {
        case .none:
            return (0, nil)
        case .some(let value):
            return (1, value as Any)
        }
    }
}

extension _ConditionalContent: ConditionalValueProjecting {
    fileprivate var conditionalProjection: (branch: Int, value: Any?) {
        switch storage {
        case .trueContent(let value):
            return (0, value)
        case .falseContent(let value):
            return (1, value)
        }
    }
}

extension ConditionalMetadata where Descriptor == ViewDescriptor {
    func childInfo(
        source: Any,
        emptyType: Any.Type = EmptyView.self
    ) -> (type: Any.Type, id: UniqueID?) {
        guard let projection = desc.project(source, emptyType: emptyType) else {
            fatalError("ConditionalMetadata could not project the active child.")
        }
        return (projection.type, ids[projection.index])
    }

    func childView<Source>(
        source: Attribute<Source>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ConditionalMetadata.childView called outside an active graph.")
        }
        guard let projection = desc.project(source.value),
              let childView = projection.value as? any View else {
            fatalError("ConditionalMetadata could not open the active child view.")
        }
        func make<Child: View>(_ childValue: Child) -> _ViewOutputs {
            let child: Attribute<Child> = graph.makeStatefulRule(
                UnwrapConditional(
                    _source: source,
                    desc: desc,
                    index: projection.index
                )
            )
            return Child._makeView(
                view: _GraphValue(_attribute: child),
                inputs: inputs
            )
        }
        return make(childView)
    }

    func childViewList<Source>(
        source: Attribute<Source>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ConditionalMetadata.childViewList called outside an active graph.")
        }
        guard let projection = desc.project(source.value),
              let childView = projection.value as? any View else {
            fatalError("ConditionalMetadata could not open the active child list view.")
        }
        func make<Child: View>(_ childValue: Child) -> _ViewListOutputs {
            let child: Attribute<Child> = graph.makeStatefulRule(
                UnwrapConditional(
                    _source: source,
                    desc: desc,
                    index: projection.index
                )
            )
            return Child._makeViewList(
                view: _GraphValue(_attribute: child),
                inputs: inputs
            )
        }
        return make(childView)
    }
}

protocol DynamicView {
    associatedtype Metadata
    associatedtype ID: Hashable

    static var canTransition: Bool { get }
    static var traitKeysDependOnView: Bool { get }
    static func makeID() -> ID

    func childInfo(metadata: Metadata) -> (type: Any.Type, id: ID?)
    func makeChildView(
        metadata: Metadata,
        view: Attribute<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs
    func makeChildViewList(
        metadata: Metadata,
        view: Attribute<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs
}

extension DynamicView {
    static var traitKeysDependOnView: Bool { true }

    static func makeDynamicView(
        metadata: Metadata,
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self).makeDynamicView called outside an active _AGGraph context.")
        }

        let outputs = inputs.makeIndirectOutputs()
        let container: Attribute<DynamicViewContainer<Self>.Value> = graph.makeStatefulRule(
            DynamicViewContainer(
                metadata: metadata,
                _view: view._attribute,
                inputs: inputs,
                outputs: outputs,
                parentSubgraph: AGSubgraph.current
            )
        )
        outputs.setIndirectDependency(container.identifier)
        _ = graph.makeSideEffectRule {
            _ = container.value
            return ()
        }
        return outputs
    }

    static func makeDynamicViewList(
        metadata: Metadata,
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self).makeDynamicViewList called outside an active _AGGraph context.")
        }

        let allItems = MutableBox<[Unmanaged<DynamicViewList<Self>.Item>]>([])
        let list: Attribute<any ViewList> = graph.makeStatefulRule(
            DynamicViewList(
                metadata: metadata,
                _view: view._attribute,
                inputs: inputs,
                parentSubgraph: AGSubgraph.current,
                allItems: allItems,
                lastItem: nil
            )
        )
        return _ViewListOutputs(
            views: .dynamicList(list, nil),
            nextImplicitID: inputs.implicitID,
            staticCount: nil
        )
    }
}

extension DynamicView where ID == UniqueID {
    static func makeID() -> UniqueID { UniqueID() }
}

private struct DynamicViewContainer<V: DynamicView>: StatefulRule, AsyncAttribute {
    struct Value {
        var type: Any.Type
        var id: V.ID?
        var subgraph: AGSubgraph

        func matches(type: Any.Type, id: V.ID?) -> Bool {
            ObjectIdentifier(self.type) == ObjectIdentifier(type) && self.id == id
        }
    }

    var metadata: V.Metadata
    var _view: Attribute<V>
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var parentSubgraph: AGSubgraph?

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError("DynamicViewContainer.updateValue evaluated outside an active _AGGraph context.")
        }

        let viewValue = _view.value
        let (type, id) = viewValue.childInfo(metadata: metadata)
        if let current = _AGGraph.currentStatefulOutput(Value.self),
           current.matches(type: type, id: id) {
            return
        }

        outputs.detachIndirectOutputs()
        if let current = _AGGraph.currentStatefulOutput(Value.self) {
            current.subgraph.willRemove()
            current.subgraph.invalidate()
            graph.drainActionOutbox()
            current.subgraph.removeFromParent()
        }

        let subgraph = AGSubgraph.withCurrent(parentSubgraph) {
            AGSubgraph()
        }
        var childInputs = inputs
        childInputs.copyCaches()
        let childOutputs = AGSubgraph.withCurrent(subgraph) {
            viewValue.makeChildView(
                metadata: metadata,
                view: _view,
                inputs: childInputs
            )
        }
        childOutputs.attachIndirectOutputs(to: outputs)
        _AGGraph.setStatefulOutput(Value(type: type, id: id, subgraph: subgraph))
    }
}

private struct DynamicViewList<V: DynamicView>: StatefulRule, AsyncAttribute {
    typealias Value = any ViewList

    final class Item: _ViewList_Subgraph {
        var type: Any.Type
        var id: V.ID
        var owner: AGAttribute
        var _list: Attribute<any ViewList>
        var isUnary: Bool
        var allItems: MutableBox<[Unmanaged<Item>]>

        init(
            type: Any.Type,
            owner: AGAttribute,
            list: Attribute<any ViewList>,
            id: V.ID,
            isUnary: Bool,
            subgraph: AGSubgraph,
            allItems: MutableBox<[Unmanaged<Item>]>
        ) {
            self.type = type
            self.owner = owner
            self._list = list
            self.id = id
            self.isUnary = isUnary
            self.allItems = allItems
            super.init(subgraph: subgraph)
            allItems.value.append(Unmanaged.passUnretained(self))
        }

        var list: any ViewList { _list.value }

        func matches(type: Any.Type, id: V.ID?) -> Bool {
            guard ObjectIdentifier(self.type) == ObjectIdentifier(type) else {
                return false
            }
            return id.map { $0 == self.id } ?? true
        }

        func bindID(_ id: inout _ViewList_ID) {
            id.bind(
                explicitID: self.id,
                owner: owner,
                isUnary: isUnary,
                reuseID: Int(bitPattern: ObjectIdentifier(type))
            )
        }

        override func invalidate() {
            allItems.value.removeAll { entry in
                entry.takeUnretainedValue() === self
            }
        }
    }

    struct WrappedList: ViewList {
        var base: any ViewList
        var item: Item
        var lastID: V.ID?
        var lastTransaction: TransactionID

        func count(style: _ViewList_IteratorStyle) -> Int {
            base.count(style: style)
        }

        func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
            base.estimatedCount(style: style)
        }

        var traitKeys: ViewTraitKeys? {
            var keys = base.traitKeys
            if V.traitKeysDependOnView {
                keys?.isDataDependent = true
            }
            return keys
        }
        var traits: ViewTraitCollection { base.traits }
        var viewIDs: _ViewList_ID_Views? {
            base.viewIDs.map {
                _ViewList_ID._Views(
                    WrappedIDs(base: $0, item: item),
                    isDataDependent: true
                )
            }
        }

        func appendViewIDs(into accumulator: inout HeterogeneousViewIDsAccumulator) {
            accumulator.withExplicitID(item.id, isUnary: item.isUnary) {
                base.appendViewIDs(into: &$0)
            }
        }

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
                list: list,
                transform: transform.withPushedItem(Transform(item: item)),
                to: to
            )
        }

        func edit(forID id: _ViewList_ID, since transaction: TransactionID) -> _ViewList_Edit? {
            let explicitID: V.ID? = id.explicitID(owner: item.owner)
            guard transaction >= lastTransaction,
                  let lastID,
                  lastID != item.id,
                  let explicitID else {
                return base.edit(forID: id, since: transaction)
            }
            if explicitID == lastID {
                return .removed
            }
            if explicitID == item.id {
                return .inserted
            }
            return base.edit(forID: id, since: transaction)
        }

        func firstOffset<A: Hashable>(forID id: A, style: _ViewList_IteratorStyle) -> Int? {
            guard let otherID = id as? V.ID,
                  otherID == item.id else {
                return base.firstOffset(forID: id, style: style)
            }
            return 0
        }

        func print(into printer: inout SExpPrinter) {
            base.print(into: &printer)
        }

        var debugDescription: String {
            "DynamicViewList.WrappedList(\(base))"
        }
    }

    struct WrappedIDs: RandomAccessCollection, Equatable {
        typealias Index = Int
        typealias Element = _ViewList_ID

        var base: _ViewList_ID_Views
        var item: Item

        var startIndex: Int { base.startIndex }
        var endIndex: Int { base.endIndex }

        subscript(position: Int) -> _ViewList_ID {
            var id = base[position]
            item.bindID(&id)
            return id
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.base == rhs.base && lhs.item === rhs.item
        }
    }

    struct Transform: _ViewList_SublistTransform_Item {
        var item: Item

        func apply(sublist: inout _ViewList_Sublist) {
            item.bindID(&sublist.id)
            sublist.elements.wrap(subgraph: item)
        }

        func bindID(_ id: inout _ViewList_ID) {
            item.bindID(&id)
        }

        func wrapSubgraph(into storage: inout _ViewList_SublistSubgraphStorage) {
            if !storage.subgraphs.contains(where: { $0 === item }) {
                storage.subgraphs.append(item)
            }
        }
    }

    var metadata: V.Metadata
    var _view: Attribute<V>
    var inputs: _ViewListInputs
    var parentSubgraph: AGSubgraph?
    var allItems: MutableBox<[Unmanaged<Item>]>
    var lastItem: Item?

    mutating func updateValue() {
        guard _AGGraph.current != nil else {
            fatalError("DynamicViewList.updateValue evaluated outside an active _AGGraph context.")
        }

        let viewValue = _view.value
        let (type, requestedID) = viewValue.childInfo(metadata: metadata)
        let previousItem = lastItem
        let lastID = previousItem?.id
        let item: Item

        if let current = previousItem,
           current.refcount > 0,
           AGSubgraphIsValid(current.subgraph),
           current.matches(type: type, id: requestedID) {
            item = current
        } else {
            if let current = previousItem {
                if AGSubgraphIsValid(current.subgraph) {
                    current.subgraph.willRemove()
                    current.subgraph.removeFromParent()
                }
                current.release()
                lastItem = nil
            }

            if let retained = retainedItem(
                matching: type,
                id: requestedID,
                excluding: previousItem
            ) {
                retained.refcount += 1
                if let parentSubgraph {
                    parentSubgraph.addSecondaryChild(retained.subgraph)
                }
                retained.subgraph.didReinsert()
                lastItem = retained
                item = retained
            } else {
                if let parentSubgraph, !AGSubgraphIsValid(parentSubgraph) {
                    _AGGraph.setStatefulOutput(EmptyViewList() as any ViewList)
                    return
                }
                let subgraph = AGSubgraph.withCurrent(parentSubgraph) {
                    AGSubgraph()
                }
                var childInputs = inputs
                childInputs.base.cachedEnvironment = MutableBox(childInputs.base.cachedEnvironment.value)
                if V.canTransition {
                    childInputs.options.insert(.canTransition)
                }
                childInputs.implicitID = 0
                let outputs = AGSubgraph.withCurrent(subgraph) {
                    viewValue.makeChildViewList(
                        metadata: metadata,
                        view: _view,
                        inputs: childInputs
                    )
                }
                let list = AGSubgraph.withCurrent(subgraph) {
                    outputs.makeAttribute(inputs: childInputs)
                }
                let newItem = Item(
                    type: type,
                    owner: context.attribute.identifier,
                    list: list,
                    id: requestedID ?? V.makeID(),
                    isUnary: outputs.staticCount == 1,
                    subgraph: subgraph,
                    allItems: allItems
                )
                lastItem = newItem
                item = newItem
            }
        }

        _AGGraph.setStatefulOutput(
            WrappedList(
                base: item.list,
                item: item,
                lastID: lastID,
                lastTransaction: TransactionID(context: context)
            ) as any ViewList
        )
    }

    private func retainedItem(
        matching type: Any.Type,
        id: V.ID?,
        excluding excluded: Item?
    ) -> Item? {
        for entry in allItems.value {
            let candidate = entry.takeUnretainedValue()
            guard candidate !== excluded,
                  candidate.refcount > 0,
                  AGSubgraphIsValid(candidate.subgraph),
                  candidate.matches(type: type, id: id) else {
                continue
            }
            return candidate
        }
        return nil
    }

}
