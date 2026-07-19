//
//  File: ViewList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - ViewList protocol

/// Internal protocol for dynamic view lists.
protocol ViewList: CustomDebugStringConvertible {
    func count(style: _ViewList_IteratorStyle) -> Int
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int
    var traitKeys: ViewTraitKeys? { get }
    var traits: ViewTraitCollection { get }
    var viewIDs: _ViewList_ID_Views? { get }
    func appendViewIDs(into: inout HeterogeneousViewIDsAccumulator)
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool
    func firstOffset<A: Hashable>(forID: A, style: _ViewList_IteratorStyle) -> Int?
    func edit(forID: _ViewList_ID, since: TransactionID) -> _ViewList_Edit?
    func print(into: inout SExpPrinter)
}

extension ViewList {
    func count(style: _ViewList_IteratorStyle) -> Int { 0 }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { count(style: style) }
    var traitKeys: ViewTraitKeys? { nil }
    var traits: ViewTraitCollection { ViewTraitCollection() }
    var viewIDs: _ViewList_ID_Views? { nil }
    func appendViewIDs(into: inout HeterogeneousViewIDsAccumulator) {}
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool { false }
    func firstOffset<A: Hashable>(forID id: A, style: _ViewList_IteratorStyle) -> Int? {
        var traversalOffset = 0
        var from = 0
        var found: Int?
        _ = applyNodes(
            from: &from,
            style: style,
            list: nil,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, node, transform in
            guard case .sublist(var sublist) = node else {
                return true
            }
            transform.apply(to: &sublist)
            for offset in 0..<sublist.count {
                let elementIndex = sublist.start + offset
                let elementID = sublist.id.elementID(at: elementIndex)
                if _viewListID(elementID, matches: id) {
                    found = traversalOffset + offset
                    return false
                }
            }
            traversalOffset += sublist.count
            return true
        }
        return found
    }

    @discardableResult
    func applyIDs(
        from index: inout Int,
        listAttribute: Attribute<any ViewList>? = nil,
        style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
        transform sublistTransform: _ViewList_TemporarySublistTransform = _ViewList_TemporarySublistTransform(),
        to body: (_ViewList_ID) -> Bool
    ) -> Bool {
        let startIndex = index
        var traversalIndex = 0
        var nextIndex = index
        var completed = true
        var from = 0
        _ = applyNodes(
            from: &from,
            style: style,
            list: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, node, temporaryTransform in
            guard case .sublist(var sublist) = node else { return true }
            temporaryTransform.apply(to: &sublist)
            sublistTransform.apply(to: &sublist)
            for offset in 0..<sublist.count {
                if traversalIndex < startIndex {
                    traversalIndex += 1
                    continue
                }
                let elementIndex = sublist.start + offset
                let id = sublist.id.elementID(at: elementIndex)
                traversalIndex += 1
                nextIndex = traversalIndex
                if !body(id) {
                    completed = false
                    return false
                }
            }
            return true
        }
        index = nextIndex
        return completed
    }

    func edit(forID: _ViewList_ID, since: TransactionID) -> _ViewList_Edit? { nil }
    func print(into: inout SExpPrinter) {}
    var debugDescription: String { "ViewList(\(count(style: _ViewList_IteratorStyle())))" }
}

private func _viewListID<A: Hashable>(_ viewID: _ViewList_ID, matches target: A) -> Bool {
    if let canonical = target as? _ViewList_ID.Canonical {
        return viewID.canonicalID == canonical
    }
    if let exactID = target as? _ViewList_ID {
        return viewID == exactID
    }
    if viewID.allExplicitIDs.contains(AnyHashable(target)) {
        return true
    }
    return viewID.containsID(target)
}

// MARK: - _ViewList_Backing

/// Concrete backing adapter returned by variadic children.
struct _ViewList_Backing {
    var list: any ViewList
}

// MARK: - BaseViewList

/// ViewList backed by a _ViewList_Elements tree.
struct BaseViewList: ViewList {
    var elements: any _ViewList_Elements
    var implicitID: Int
    var traitKeys: ViewTraitKeys?
    var traits: ViewTraitCollection

    init(elements: any _ViewList_Elements, implicitID: Int = 0) {
        self.elements = elements
        self.implicitID = implicitID
        self.traitKeys = nil
        self.traits = ViewTraitCollection()
    }

    init(
        elements: any _ViewList_Elements,
        implicitID: Int = 0,
        traitKeys: ViewTraitKeys? = nil,
        traits: ViewTraitCollection
    ) {
        self.elements = elements
        self.implicitID = implicitID
        self.traitKeys = traitKeys
        self.traits = traits
    }

    func count(style: _ViewList_IteratorStyle) -> Int { elements.count }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { elements.count }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        // Builds a _ViewList_Sublist from self.elements and calls the callback once.
        let sublist = _ViewList_Sublist(
            start: from,
            count: elements.count,
            id: _ViewList_ID(implicitID: implicitID),
            elements: _ViewList_SubgraphElements(base: elements),
            traits: traits,
            list: list
        )
        let result = to(&from, style, .sublist(sublist), transform)
        from = 0
        return result
    }
}

// MARK: - EmptyViewList

/// An empty ViewList with no elements.
struct EmptyViewList: ViewList {
    init() {}
    func count(style: _ViewList_IteratorStyle) -> Int { 0 }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { 0 }
    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        true  // No elements. Traversal completes immediately.
    }
}

// MARK: - _ViewList_IteratorStyle

/// Controls granularity when traversing a ViewList.
/// The current modeled storage is a single UInt value.
struct _ViewList_IteratorStyle: Equatable {
    var value: UInt
    init() { value = 0 }
    init(value: UInt) { self.value = value }
}

// MARK: - _ViewList_ID / _ViewList_Edit

/// A stable identity for a specific view in a ViewList.
/// Current storage keeps the known index, implicit ID, and explicit ID list.
/// Explicit binding behavior remains partial.
struct _ViewList_ID {
    enum GeneratedIDKind: Hashable {
        case rowLocal
        case shared
    }

    struct GeneratedIDSeed: Hashable {
        var base: UniqueID
        var kind: GeneratedIDKind

        func uniqueID(at index: Int) -> UniqueID {
            switch kind {
            case .rowLocal:
                return UniqueID(value: base.value &+ UInt32(truncatingIfNeeded: index &+ 1))
            case .shared:
                return base
            }
        }
    }

    struct Canonical: Hashable, CustomStringConvertible {
        var _index: Int32
        var implicitID: Int32
        var explicitID: AnyHashable?

        init(_index: Int32, implicitID: Int32, explicitID: AnyHashable?) {
            self._index = _index
            self.implicitID = implicitID
            self.explicitID = explicitID
        }

        init(value: Int32, explicitID: AnyHashable?) {
            self.init(_index: value, implicitID: value, explicitID: explicitID)
        }

        var value: Int32 {
            get { _index }
            set { _index = newValue }
        }

        var index: Int {
            get { Int(_index) }
            set { _index = Int32(newValue) }
        }

        var requiresImplicitID: Bool {
            implicitID >= 0
        }

        var description: String {
            let base = explicitID?.base
            let explicitType = base.map { type(of: $0) }
            return "ViewList.ID.Canonical(index: \(index), implicitID: \(implicitID), explicitID: \(String(describing: base))[\(String(describing: explicitType))])"
        }
    }

    struct Explicit: Equatable {
        var id: AnyHashable
        var reuseID: Int
        var owner: AGAttribute?
        var isUnary: Bool

        init(
            id: AnyHashable,
            reuseID: Int = 0,
            owner: AGAttribute? = nil,
            isUnary: Bool = false
        ) {
            self.id = id
            self.reuseID = reuseID
            self.owner = owner
            self.isUnary = isUnary
        }

        private var ownerRawValue: UInt32 {
            owner?.rawValue ?? AGAttribute.invalid.rawValue
        }

        static func == (lhs: Explicit, rhs: Explicit) -> Bool {
            lhs.id == rhs.id &&
                lhs.ownerRawValue == rhs.ownerRawValue &&
                lhs.reuseID == rhs.reuseID &&
                lhs.isUnary == rhs.isUnary
        }

        func hashIdentity(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(reuseID)
        }

        func matches(owner: AGAttribute) -> Bool {
            ownerRawValue == owner.rawValue
        }
    }

    struct ElementCollection: RandomAccessCollection, Equatable {
        var id: _ViewList_ID
        var count: Int

        init(id: _ViewList_ID, count: Int) {
            self.id = id
            self.count = count
        }

        var startIndex: Int { 0 }
        var endIndex: Int { count }

        subscript(position: Int) -> _ViewList_ID {
            id.elementID(at: position)
        }
    }

    var _index: Int32
    var implicitID: Int32
    var explicitIDs: [Explicit] = []

    static let generatedRowReuseID = 8_397_012_648
    static let generatedSectionReuseID = Int(bitPattern: ObjectIdentifier(_ViewList_ID.self))

    var index: Int { Int(_index) }

    init(implicitID: Int = 0) {
        self._index = Int32(implicitID)
        self.implicitID = Int32(implicitID)
    }

    init(explicitID: AnyHashable, implicitID: Int = 0) {
        self._index = Int32(implicitID)
        self.implicitID = Int32(implicitID)
        self.explicitIDs = [Explicit(id: explicitID)]
    }

    static func explicit<ID: Hashable>(_ explicitID: ID, owner: AGAttribute) -> _ViewList_ID {
        var id = _ViewList_ID(implicitID: 0)
        id.bind(explicitID: explicitID, owner: owner, isUnary: true, reuseID: 0)
        return id
    }

    static func explicit<ID: Hashable>(_ explicitID: ID) -> _ViewList_ID {
        var id = _ViewList_ID(implicitID: 0)
        id.bind(explicitID: explicitID, owner: nil, isUnary: true, reuseID: 0)
        return id
    }

    mutating func bind<ID: Hashable>(
        explicitID: ID,
        owner: AGAttribute,
        isUnary: Bool,
        reuseID: Int
    ) {
        bind(explicitID: explicitID, owner: Optional(owner), isUnary: isUnary, reuseID: reuseID)
    }

    mutating func bind<ID: Hashable>(
        explicitID: ID,
        owner: AGAttribute,
        reuseID: Int
    ) {
        bind(explicitID: explicitID, owner: Optional(owner), isUnary: false, reuseID: reuseID)
    }

    mutating func bind<ID: Hashable>(
        explicitID: ID,
        owner: AGAttribute,
        isUnary: Bool
    ) {
        bind(explicitID: explicitID, owner: Optional(owner), isUnary: isUnary, reuseID: 0)
    }

    mutating func bind<ID: Hashable>(
        explicitID: ID,
        owner: AGAttribute
    ) {
        bind(explicitID: explicitID, owner: Optional(owner), isUnary: false, reuseID: 0)
    }

    private mutating func bind<ID: Hashable>(
        explicitID: ID,
        owner: AGAttribute?,
        isUnary: Bool,
        reuseID: Int
    ) {
        explicitIDs.append(
            Explicit(
                id: AnyHashable(explicitID),
                reuseID: reuseID,
                owner: owner,
                isUnary: isUnary
            )
        )
    }

    mutating func bindGeneratedID(
        seed: GeneratedIDSeed,
        owner: AGAttribute,
        isUnary: Bool,
        reuseID: Int
    ) {
        bind(explicitID: seed, owner: Optional(owner), isUnary: isUnary, reuseID: reuseID)
    }

    func elementID(at index: Int) -> _ViewList_ID {
        var id = self
        id._index = Int32(index)
        id.materializeGeneratedIDs(at: index)
        return id
    }

    private mutating func materializeGeneratedIDs(at index: Int) {
        var hasUnary = false
        for explicitIndex in explicitIDs.indices {
            if let seed = explicitIDs[explicitIndex].id.base as? GeneratedIDSeed {
                explicitIDs[explicitIndex].id = AnyHashable(seed.uniqueID(at: index))
                if seed.kind == .rowLocal {
                    explicitIDs[explicitIndex].isUnary = !hasUnary
                }
            }
            if explicitIDs[explicitIndex].isUnary {
                hasUnary = true
            }
        }
    }

    var canonicalID: Canonical {
        if let explicit = explicitIDs.first {
            let canonicalImplicitID = explicit.isUnary ? Int32(-1) : implicitID
            return Canonical(_index: _index, implicitID: canonicalImplicitID, explicitID: explicit.id)
        }
        return Canonical(_index: _index, implicitID: implicitID, explicitID: nil)
    }

    var primaryExplicitID: AnyHashable? {
        explicitIDs.first?.id
    }

    var allExplicitIDs: [AnyHashable] {
        explicitIDs.map(\.id)
    }

    func explicitID<ID: Hashable>(for type: ID.Type) -> ID? {
        for explicit in explicitIDs {
            if let value = explicit.id.base as? ID {
                return value
            }
        }
        return nil
    }

    func explicitID<ID: Hashable>(owner: AGAttribute) -> ID? {
        for explicit in explicitIDs where explicit.matches(owner: owner) {
            if let value = explicit.id.base as? ID {
                return value
            }
        }
        return nil
    }

    func containsID<ID: Hashable>(_ id: ID) -> Bool {
        for explicit in explicitIDs {
            if let value = explicit.id.base as? ID, value == id {
                return true
            }
        }
        return false
    }

    func elementIDs(count: Int) -> ElementCollection {
        ElementCollection(id: self, count: count)
    }

    var reuseIdentifier: Int {
        var hasher = Hasher()
        hasher.combine(_index)
        hasher.combine(implicitID)
        for explicitID in allExplicitIDs {
            hasher.combine(explicitID)
        }
        return hasher.finalize()
    }
}

extension _ViewList_ID: Hashable {
    static func == (lhs: _ViewList_ID, rhs: _ViewList_ID) -> Bool {
        lhs._index == rhs._index &&
        lhs.implicitID == rhs.implicitID &&
        lhs.explicitIDs == rhs.explicitIDs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(_index)
        hasher.combine(implicitID)
        for explicit in explicitIDs {
            explicit.hashIdentity(into: &hasher)
        }
    }
}

/// Describes a change that occurred to a specific ViewList item.
enum _ViewList_Edit: Hashable { case inserted, removed }

// MARK: - ID collections / accumulator

class _ViewList_ID_Views: RandomAccessCollection, Equatable {
    typealias Index = Int
    typealias Element = _ViewList_ID

    let isDataDependent: Bool

    required init(isDataDependent: Bool) {
        self.isDataDependent = isDataDependent
    }

    var startIndex: Int { 0 }

    var endIndex: Int {
        preconditionFailure("abstract _ViewList_ID_Views.endIndex")
    }

    subscript(position: Int) -> _ViewList_ID {
        preconditionFailure("abstract _ViewList_ID_Views subscript")
    }

    func isEqual(to other: _ViewList_ID_Views) -> Bool {
        preconditionFailure("abstract _ViewList_ID_Views.isEqual(to:)")
    }

    static func == (lhs: _ViewList_ID_Views, rhs: _ViewList_ID_Views) -> Bool {
        lhs.isEqual(to: rhs)
    }

    func withDataDependency() -> _ViewList_ID_Views {
        if isDataDependent {
            return self
        }
        return _ViewList_ID._Views(self, isDataDependent: true)
    }
}

extension _ViewList_ID {
    final class _Views<Base>: _ViewList_ID_Views
    where Base: RandomAccessCollection,
          Base.Index == Int,
          Base.Element == _ViewList_ID {
        let base: Base

        init(_ base: Base, isDataDependent: Bool) {
            self.base = base
            super.init(isDataDependent: isDataDependent)
        }

        required init(isDataDependent: Bool) {
            fatalError("_ViewList_ID._Views requires a base collection")
        }

        override var endIndex: Int { base.endIndex }

        override subscript(position: Int) -> _ViewList_ID {
            base[position]
        }

        override func isEqual(to other: _ViewList_ID_Views) -> Bool {
            guard let other = other as? _Views<Base> else {
                return false
            }
            return base.elementsEqual(other.base)
        }
    }

    final class JoinedViews: _ViewList_ID_Views {
        let views: [(views: _ViewList_ID_Views, endOffset: Int)]
        let count: Int

        init(_ source: [_ViewList_ID_Views], isDataDependent: Bool) {
            var endOffset = 0
            self.views = source.map { viewIDs in
                endOffset += viewIDs.count
                return (viewIDs, endOffset)
            }
            self.count = endOffset
            super.init(isDataDependent: isDataDependent)
        }

        required init(isDataDependent: Bool) {
            self.views = []
            self.count = 0
            super.init(isDataDependent: isDataDependent)
        }

        override var endIndex: Int { count }

        override subscript(position: Int) -> _ViewList_ID {
            precondition(indices.contains(position), "View ID index out of range")
            for entry in views where position < entry.endOffset {
                let startOffset = entry.endOffset - entry.views.count
                return entry.views[position - startOffset]
            }
            preconditionFailure("View ID index out of range")
        }

        override func isEqual(to other: _ViewList_ID_Views) -> Bool {
            guard let other = other as? JoinedViews,
                  count == other.count,
                  views.count == other.views.count else {
                return false
            }
            return zip(views, other.views).allSatisfy { pair in
                let (lhs, rhs) = pair
                return lhs.endOffset == rhs.endOffset && lhs.views == rhs.views
            }
        }
    }
}

private protocol AbstractContiguousArray {
    associatedtype Element: Hashable

    func asContiguousArray<ID: Hashable>(
        of type: ID.Type
    ) -> ContiguousArray<ID>?
    var contiguousArray: ContiguousArray<Element> { get }
    var count: Int { get }
    var isEmpty: Bool { get }
}

extension ContiguousArray: AbstractContiguousArray where Element: Hashable {
    fileprivate func asContiguousArray<ID: Hashable>(
        of type: ID.Type
    ) -> ContiguousArray<ID>? {
        self as? ContiguousArray<ID>
    }

    fileprivate var contiguousArray: ContiguousArray<Element> { self }
}

private func makeHomogeneousCollection<Buffer: AbstractContiguousArray>(
    _ buffer: Buffer
) -> AbstractHomogeneousCollection {
    HomogeneousCollection(buffer.contiguousArray)
}

class AbstractHomogeneousCollection {
    let elementTypeID: ObjectIdentifier
    let count: Int

    init(elementTypeID: ObjectIdentifier, count: Int) {
        self.elementTypeID = elementTypeID
        self.count = count
    }

    func isElementEqual(
        at index: Int,
        toElementIn other: AbstractHomogeneousCollection,
        at otherIndex: Int
    ) -> Bool {
        preconditionFailure("abstract homogeneous collection equality")
    }

    func element(at index: Int) -> Any {
        preconditionFailure("abstract homogeneous collection element access")
    }

    func forEach(_ body: (Any) -> Void) {
        preconditionFailure("abstract homogeneous collection traversal")
    }
}

final class HomogeneousCollection<Element: Hashable>: AbstractHomogeneousCollection {
    let wrapped: ContiguousArray<Element>

    init(_ wrapped: ContiguousArray<Element>) {
        self.wrapped = wrapped
        super.init(elementTypeID: ObjectIdentifier(Element.self), count: wrapped.count)
    }

    override func isElementEqual(
        at index: Int,
        toElementIn other: AbstractHomogeneousCollection,
        at otherIndex: Int
    ) -> Bool {
        guard let other = other as? HomogeneousCollection<Element> else {
            return false
        }
        return wrapped[index] == other.wrapped[otherIndex]
    }

    override func element(at index: Int) -> Any {
        wrapped[index]
    }

    override func forEach(_ body: (Any) -> Void) {
        wrapped.forEach { body($0) }
    }
}

final class HomogeneousLookupTable {
    var indices: [AnyHashable: Int]

    init(indices: [AnyHashable: Int]) {
        self.indices = indices
    }
}

struct HeterogeneousIndexLookupTable {
    var homogenousLookupTable: [ObjectIdentifier: HomogeneousLookupTable]
    var count: Int

    init(_ values: [_ViewList_ID.Canonical]) {
        var indices: [AnyHashable: Int] = [:]
        indices.reserveCapacity(values.count)
        for (index, value) in values.enumerated() where indices[AnyHashable(value)] == nil {
            indices[AnyHashable(value)] = index
        }
        homogenousLookupTable = [
            ObjectIdentifier(_ViewList_ID.Canonical.self): HomogeneousLookupTable(indices: indices)
        ]
        count = values.count
    }

    func index<ID: Hashable>(for id: ID) -> Int? {
        homogenousLookupTable[ObjectIdentifier(ID.self)]?.indices[AnyHashable(id)]
    }
}

struct HeterogeneousCollection {
    var subCollections: ContiguousArray<AbstractHomogeneousCollection>
    var runningTotal: [UInt32]
    var lookupTableCache: HeterogeneousIndexLookupTable?

    init(_ subCollections: ContiguousArray<AbstractHomogeneousCollection> = []) {
        self.subCollections = subCollections
        var total: UInt32 = 0
        self.runningTotal = subCollections.map { collection in
            total &+= UInt32(collection.count)
            return total
        }
        self.lookupTableCache = nil
    }

    var count: Int {
        Int(runningTotal.last ?? 0)
    }

    func element(at index: Int) -> Any {
        precondition(index >= 0 && index < count, "heterogeneous collection index out of range")
        var start = 0
        for (collectionIndex, collection) in subCollections.enumerated() {
            let end = Int(runningTotal[collectionIndex])
            if index < end {
                return collection.element(at: index - start)
            }
            start = end
        }
        preconditionFailure("heterogeneous collection index out of range")
    }

    func forEach(_ body: (Any) -> Void) {
        subCollections.forEach { $0.forEach(body) }
    }

    func map<Result>(_ transform: (Any) -> Result) -> [Result] {
        var result: [Result] = []
        result.reserveCapacity(count)
        forEach { result.append(transform($0)) }
        return result
    }

    mutating func makeIndexLookupTableIfNeeded(
        canonicalValues: [_ViewList_ID.Canonical]
    ) -> HeterogeneousIndexLookupTable {
        if let lookupTableCache {
            return lookupTableCache
        }
        let table = HeterogeneousIndexLookupTable(canonicalValues)
        lookupTableCache = table
        return table
    }
}

private protocol CanonicalViewIDProtocol {
    func asCanonical() -> _ViewList_ID.Canonical
}

private struct Nil: Hashable {}

struct TypedCanonicalViewID<ExplicitID: Hashable>: Hashable, CanonicalViewIDProtocol {
    var index: Int32
    var implicitID: Int32
    var explicitID: ExplicitID

    func asCanonical() -> _ViewList_ID.Canonical {
        _ViewList_ID.Canonical(
            _index: index,
            implicitID: implicitID,
            explicitID: ExplicitID.self == Nil.self ? nil : AnyHashable(explicitID)
        )
    }
}

struct HeterogeneousViewIDs {
    var collection: HeterogeneousCollection

    init() {
        collection = HeterogeneousCollection()
    }

    init(_ collection: HeterogeneousCollection) {
        self.collection = collection
    }

    init(_ list: any ViewList) {
        var accumulator = HeterogeneousViewIDsAccumulator()
        list.appendViewIDs(into: &accumulator)
        self = accumulator.finalize()
    }

    static var empty: HeterogeneousViewIDs {
        HeterogeneousViewIDs()
    }

    var count: Int {
        collection.count
    }

    subscript(index: Int) -> _ViewList_ID.Canonical {
        makeCanonical(collection.element(at: index))
    }

    func asCanonical() -> [_ViewList_ID.Canonical] {
        collection.map(makeCanonical)
    }

    func forEach(_ body: (_ViewList_ID.Canonical) -> Void) {
        collection.forEach { body(makeCanonical($0)) }
    }

    mutating func makeIndexLookupTableIfNeeded() -> HeterogeneousViewIDIndexLookupTable {
        HeterogeneousViewIDIndexLookupTable(
            lookupTable: collection.makeIndexLookupTableIfNeeded(
                canonicalValues: asCanonical()
            )
        )
    }

    private func makeCanonical(_ value: Any) -> _ViewList_ID.Canonical {
        if let canonical = value as? _ViewList_ID.Canonical {
            return canonical
        }
        if let typed = value as? any CanonicalViewIDProtocol {
            return typed.asCanonical()
        }
        if value is Nil {
            return _ViewList_ID.Canonical(
                _index: 0,
                implicitID: -1,
                explicitID: nil
            )
        }
        if let explicitID = value as? AnyHashable {
            return _ViewList_ID.Canonical(
                _index: 0,
                implicitID: -1,
                explicitID: explicitID
            )
        }
        preconditionFailure("heterogeneous view ID element is not Hashable")
    }
}

struct HeterogeneousViewIDIndexLookupTable {
    var lookupTable: HeterogeneousIndexLookupTable

    func index(for id: _ViewList_ID.Canonical) -> Int? {
        lookupTable.index(for: id)
    }
}

struct HeterogeneousViewIDsAccumulator {
    private var collections: ContiguousArray<AbstractHomogeneousCollection>
    private var _count: Int
    private var currentCollection: (any AbstractContiguousArray)?
    private var currentExplicitID: (any Hashable, isUnary: Bool)?

    init() {
        collections = []
        _count = 0
        currentCollection = nil
        currentExplicitID = nil
    }

    var count: Int {
        _count + (currentCollection?.count ?? 0)
    }

    var isEmpty: Bool {
        _count == 0 && (currentCollection?.isEmpty ?? true)
    }

    func finalize() -> HeterogeneousViewIDs {
        var finalizedCollections = collections
        if let currentCollection, !currentCollection.isEmpty {
            finalizedCollections.append(makeHomogeneousCollection(currentCollection))
        }
        return HeterogeneousViewIDs(HeterogeneousCollection(finalizedCollections))
    }

    mutating func withBuffer<ID: Hashable>(
        of type: ID.Type,
        body: (inout ContiguousArray<ID>) -> Void
    ) {
        if var buffer = currentCollection as? ContiguousArray<ID> {
            body(&buffer)
            currentCollection = buffer
            return
        }

        flushCurrentCollection()
        var buffer = ContiguousArray<ID>()
        body(&buffer)
        currentCollection = buffer
    }

    mutating func append<ID: Hashable>(contentsOf values: ContiguousArray<ID>) {
        guard !values.isEmpty else { return }
        withBuffer(of: ID.self) { $0.append(contentsOf: values) }
    }

    mutating func withExplicitID<ID: Hashable>(
        _ id: ID,
        isUnary: Bool,
        body: (inout HeterogeneousViewIDsAccumulator) -> Void
    ) {
        let previous = currentExplicitID
        currentExplicitID = (id, isUnary)
        body(&self)
        currentExplicitID = previous
    }

    mutating func append(_ id: _ViewList_ID.Canonical) {
        if let explicitID = id.explicitID {
            append(index: id._index, implicitID: id.implicitID, explicitID: explicitID)
        } else {
            append(index: id._index, implicitID: id.implicitID)
        }
    }

    mutating func append<ID: Hashable>(
        index: Int32 = 0,
        implicitID: Int32 = -1,
        explicitID: ID
    ) {
        if index == 0 && implicitID == -1 {
            withBuffer(of: ID.self) { $0.append(explicitID) }
        } else {
            append(
                TypedCanonicalViewID(
                    index: index,
                    implicitID: implicitID,
                    explicitID: explicitID
                )
            )
        }
    }

    mutating func append(index: Int32, implicitID: Int32) {
        if let currentExplicitID {
            appendCurrentExplicitID(
                currentExplicitID.0,
                isUnary: currentExplicitID.isUnary,
                index: index,
                implicitID: implicitID
            )
        } else {
            append(
                TypedCanonicalViewID(
                    index: index,
                    implicitID: implicitID,
                    explicitID: Nil()
                )
            )
        }
    }

    mutating func append<ID: Hashable>(
        indices: Range<Int32>,
        implicitID: Int32,
        explicitID: ID
    ) {
        guard !indices.isEmpty else { return }
        if implicitID == -1, indices.contains(0) {
            append(
                indices: indices.lowerBound..<0,
                implicitID: implicitID,
                explicitID: explicitID
            )
            append(index: 0, implicitID: -1, explicitID: explicitID)
            append(
                indices: 1..<indices.upperBound,
                implicitID: implicitID,
                explicitID: explicitID
            )
            return
        }
        withBuffer(of: TypedCanonicalViewID<ID>.self) { buffer in
            buffer.reserveCapacity(buffer.count + indices.count)
            for index in indices {
                buffer.append(
                    TypedCanonicalViewID(
                        index: index,
                        implicitID: implicitID,
                        explicitID: explicitID
                    )
                )
            }
        }
    }

    mutating func appendWithoutExplicitID(
        indices: Range<Int32>,
        implicitID: Int32
    ) {
        guard !indices.isEmpty else { return }
        if let currentExplicitID {
            appendCurrentExplicitID(
                currentExplicitID.0,
                isUnary: currentExplicitID.isUnary,
                indices: indices,
                implicitID: implicitID
            )
        } else {
            append(
                indices: indices,
                implicitID: implicitID,
                explicitID: Nil()
            )
        }
    }

    struct UnsafeOutputBuffer {
        var pointer: UnsafeMutableRawPointer
        var count: Int
        var stride: Int
        var indexOffset: Int
        var implicitIDOffset: Int
        var explicitIDOffset: Int

        func initialize<ID: Hashable>(
            at position: Int,
            index: Int32,
            implicitID: Int32,
            explicitID: ID
        ) {
            precondition(position >= 0 && position < count)
            let element = pointer.advanced(by: position * stride)
            element.advanced(by: indexOffset)
                .assumingMemoryBound(to: Int32.self)
                .initialize(to: index)
            element.advanced(by: implicitIDOffset)
                .assumingMemoryBound(to: Int32.self)
                .initialize(to: implicitID)
            element.advanced(by: explicitIDOffset)
                .assumingMemoryBound(to: ID.self)
                .initialize(to: explicitID)
        }

        func initialize(
            at position: Int,
            index: Int32,
            implicitID: Int32
        ) {
            initialize(
                at: position,
                index: index,
                implicitID: implicitID,
                explicitID: Nil()
            )
        }

        func mutableExplicitIDPointer<ID: Hashable>(
            at position: Int,
            for type: ID.Type = ID.self
        ) -> UnsafeMutablePointer<ID> {
            precondition(position >= 0 && position < count)
            return pointer
                .advanced(by: position * stride + explicitIDOffset)
                .assumingMemoryBound(to: ID.self)
        }
    }

    mutating func appendWithUnsafeOutputBuffer<ID: Hashable>(
        explicitID type: ID.Type = ID.self,
        count: Int,
        body: (UnsafeOutputBuffer) -> Void
    ) {
        guard count > 0 else { return }
        let pointer = UnsafeMutablePointer<TypedCanonicalViewID<ID>>.allocate(capacity: count)
        let rawPointer = UnsafeMutableRawPointer(pointer)
        let buffer = UnsafeOutputBuffer(
            pointer: rawPointer,
            count: count,
            stride: MemoryLayout<TypedCanonicalViewID<ID>>.stride,
            indexOffset: MemoryLayout<TypedCanonicalViewID<ID>>.offset(of: \.index)!,
            implicitIDOffset: MemoryLayout<TypedCanonicalViewID<ID>>.offset(of: \.implicitID)!,
            explicitIDOffset: MemoryLayout<TypedCanonicalViewID<ID>>.offset(of: \.explicitID)!
        )
        body(buffer)
        let values = ContiguousArray(
            UnsafeBufferPointer(start: pointer, count: count)
        )
        pointer.deinitialize(count: count)
        pointer.deallocate()
        append(contentsOf: values)
    }

    private mutating func append<ID: Hashable>(_ value: TypedCanonicalViewID<ID>) {
        withBuffer(of: TypedCanonicalViewID<ID>.self) { $0.append(value) }
    }

    private mutating func appendCurrentExplicitID<ID: Hashable>(
        _ explicitID: ID,
        isUnary: Bool,
        index: Int32,
        implicitID: Int32
    ) {
        append(
            index: index,
            implicitID: isUnary ? -1 : implicitID,
            explicitID: explicitID
        )
    }

    private mutating func appendCurrentExplicitID<ID: Hashable>(
        _ explicitID: ID,
        isUnary: Bool,
        indices: Range<Int32>,
        implicitID: Int32
    ) {
        append(
            indices: indices,
            implicitID: isUnary ? -1 : implicitID,
            explicitID: explicitID
        )
    }

    private mutating func flushCurrentCollection() {
        guard let currentCollection else { return }
        if !currentCollection.isEmpty {
            collections.append(makeHomogeneousCollection(currentCollection))
            _count += currentCollection.count
        }
        self.currentCollection = nil
    }
}

// MARK: - _ViewList_SublistTransform

struct _ViewList_SublistTransform_ItemFlags: OptionSet {
    var rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let graphDependent = _ViewList_SublistTransform_ItemFlags(rawValue: 1)
}

protocol _ViewList_SublistTransform_Item {
    static var flags: _ViewList_SublistTransform_ItemFlags { get }
    func apply(sublist: inout _ViewList_Sublist)
    func bindID(_ id: inout _ViewList_ID)
    func wrapSubgraph(into storage: inout _ViewList_SublistSubgraphStorage)
}

extension _ViewList_SublistTransform_Item {
    static var flags: _ViewList_SublistTransform_ItemFlags { [] }
    func bindID(_ id: inout _ViewList_ID) {}
    func wrapSubgraph(into storage: inout _ViewList_SublistSubgraphStorage) {}
}

struct _ViewList_SublistTransform {
    var items: [any _ViewList_SublistTransform_Item]
    var subgraphCount: Int

    init() {
        self.items = []
        self.subgraphCount = 0
    }

    mutating func push(_ item: any _ViewList_SublistTransform_Item) {
        items.append(item)
    }

    @discardableResult
    mutating func pop() -> (any _ViewList_SublistTransform_Item)? {
        items.popLast()
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    func apply(to sublist: inout _ViewList_Sublist) {
        for item in items.reversed() {
            item.apply(sublist: &sublist)
        }
    }

    func bindID(_ id: inout _ViewList_ID) {
        for item in items.reversed() {
            item.bindID(&id)
        }
    }

    func wrapSubgraphs(into storage: inout _ViewList_SublistSubgraphStorage) {
        for item in items.reversed() {
            item.wrapSubgraph(into: &storage)
        }
    }

    func withTemporaryTransform<Result>(
        do body: (_ViewList_TemporarySublistTransform) -> Result
    ) -> Result {
        body(_ViewList_TemporarySublistTransform(transform: self))
    }
}

// MARK: - _ViewList_TemporarySublistTransform

/// Context passed during ViewList sublist traversal.
/// Carries list modifiers that are pushed while dynamic lists are traversed.
struct _ViewList_TemporarySublistTransform {
    fileprivate var storage: _TemporarySublistTransformStorage?
    fileprivate var flag: Bool

    init() {
        self.storage = nil
        self.flag = false
    }

    fileprivate init(storage: _TemporarySublistTransformStorage?, flag: Bool) {
        self.storage = storage
        self.flag = flag
    }

    fileprivate init(transform: _ViewList_SublistTransform) {
        if transform.items.isEmpty {
            self.storage = nil
            self.flag = false
        } else {
            self.storage = _TemporarySublistTransformStorage(
                items: transform.items,
                subgraphCount: transform.subgraphCount
            )
            self.flag = true
        }
    }
}

private final class _TemporarySublistTransformStorage {
    var items: [any _ViewList_SublistTransform_Item]
    var subgraphCount: Int

    init(items: [any _ViewList_SublistTransform_Item] = [], subgraphCount: Int = 0) {
        self.items = items
        self.subgraphCount = subgraphCount
    }
}

// MARK: - _ViewList_Elements protocol

/// Abstraction for the view-creation mechanism within a ViewList sublist.
protocol _ViewList_Elements {
    var count: Int { get }

    /// Creates view outputs for elements starting at the given offset.
    /// - from: elements to skip before processing (0 = process, >0 = skip and decrement)
    /// - returns: (lastOutputs, shouldContinue)
    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool)

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool
}

extension _ViewList_Elements {
    /// Creates a single element at `index`.
    /// The exact helper body and conformer override behavior are still partial.
    func makeOneElement(
        at index: Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap? = nil,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> _ViewOutputs?
    ) -> _ViewOutputs? {
        var from = index
        var resolved: _ViewOutputs?
        _ = makeElements(from: &from, inputs: inputs, indirectMap: indirectMap) { elementInputs, makeView in
            resolved = body(elementInputs, makeView)
            return (resolved, false)
        }
        return resolved
    }

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool { false }
}

struct EmptyViewListElements: _ViewList_Elements {
    var count: Int { 0 }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        (nil, true)
    }
}

// MARK: - UnaryElements

/// Single-view _ViewList_Elements.
/// makeElements skips one element when from != 0.
/// When from == 0, it calls body(inputs, makeViewClosure).
///
/// This collapses separate generator specializations into one closure path.
struct UnaryElements: _ViewList_Elements {
    /// Retained for typed generator construction.
    /// nil for body-generator construction.
    var typedGenerator: TypedUnaryViewGenerator?
    var makeViewClosure: (_ViewInputs) -> _ViewOutputs
    var baseInputs: _GraphInputs

    init(generator: TypedUnaryViewGenerator) {
        self.typedGenerator = generator
        self.makeViewClosure = { inputs in generator.makeView(inputs: inputs) ?? _ViewOutputs() }
        self.baseInputs = generator.baseInputs
    }

    /// BodyUnaryViewGenerator path.
    /// Exact layout wiring remains simplified.
    init(body: @escaping (_ViewInputs) -> _ViewOutputs, baseInputs: _GraphInputs) {
        self.typedGenerator = nil
        self.makeViewClosure = body
        self.baseInputs = baseInputs
    }

    var count: Int { 1 }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        if from != 0 {
            from -= 1
            return (nil, true)
        }
        let closure = makeViewClosure
        return body(inputs, { i in closure(i) })
    }
}

// MARK: - MergedElements

/// Aggregates multiple _ViewListOutputs into a single _ViewList_Elements.
struct MergedElements: _ViewList_Elements {
    var outputs: [_ViewListOutputs]

    var count: Int {
        outputs.reduce(0) { acc, output in
            switch output.views {
            case .staticList(let elems): return acc + elems.count
            case .dynamicList(let attr, _): return acc + attr.value.count(style: _ViewList_IteratorStyle())
            }
        }
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        for output in outputs {
            switch output.views {
            case .staticList(let elems):
                let (result, cont) = elems.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
                if !cont { return (result, false) }
            case .dynamicList(let attr, _):
                var traversalFrom = from
                var remaining = from
                let list = attr.value
                var dynamicResult: _ViewOutputs?
                let cont = _applySublists(in: list, from: &traversalFrom, listAttribute: attr) { sublist in
                    var elementFrom = remaining
                    let (result, shouldContinue) = sublist.elements.makeElements(
                        from: &elementFrom,
                        inputs: inputs,
                        indirectMap: indirectMap,
                        body: body
                    )
                    dynamicResult = result
                    remaining = elementFrom
                    return shouldContinue
                }
                from = remaining
                if !cont { return (dynamicResult, false) }
            }
        }
        return (nil, true)
    }
}

// MARK: - ModifiedElements

/// Wraps a base _ViewList_Elements with a ViewModifier applied per-element.
/// Stores a type-erased projection closure for concrete modifier dispatch.
struct ModifiedElements: _ViewList_Elements {
    var base: any _ViewList_Elements
    var modifier: AGWeakAttribute
    var baseInputs: _GraphInputs
    // Type-erased closure for concrete M._makeView dispatch.
    // Calls M._makeView(modifier:inputs:body:) with the captured concrete M.
    var project: (AGAttribute, _ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> _ViewOutputs

    var count: Int { base.count }

    func tryToReuseElement(
        at index: Int,
        by other: any _ViewList_Elements,
        at otherIndex: Int,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        false
    }

    /// Creates a ModifiedElements wrapping `base` with modifier `M`.
    /// This is the primary factory used by multiModifier and PreferenceModifiers.
    static func make<M: ViewModifier>(
        base: any _ViewList_Elements,
        modifier: _GraphValue<M>,
        inputs: _GraphInputs
    ) -> ModifiedElements {
        let weakMod = modifier._attribute.asWeak().base
        return ModifiedElements(
            base: base,
            modifier: weakMod,
            baseInputs: inputs,
            project: { rawAttr, mergedInputs, outerBody in
                let modAttr = Attribute<M>(rawAttr)
                let gv = _GraphValue(_attribute: modAttr)
                return M._makeView(modifier: gv, inputs: mergedInputs,
                                   body: { _, bodyInputs in outerBody(bodyInputs) })
            }
        )
    }

    /// Per-element modifier application.
    ///
    /// Flow:
    ///   1. Delegate to base.makeElements with a wrappedBody.
    ///   2. wrappedBody (called per-element by base):
    ///      a. Merge baseInputs (modifier's, higher priority) + elementInputs.base (element's)
    ///      b. Resolve modifier weak attr and return nil if expired.
    ///      c. Call project(modAttr, mergedInputs, makeView).
    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        let capturedModifier  = modifier
        let capturedBaseInputs = baseInputs
        let capturedProject   = project

        let wrappedBody: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool) = {
            elementInputs, makeView in
            guard let graph = _AGGraph.current else {
                fatalError("ModifiedElements.makeElements wrappedBody called outside AG context.")
            }

            // Merge modifier baseInputs at higher priority than elementInputs.base.
            var mergedBase = capturedBaseInputs
            mergedBase.merge(elementInputs.base, ignoringPhase: false)
            mergedBase.applyViewPhaseOverrideIfNeeded()
            var mergedInputs = elementInputs
            mergedInputs.base = mergedBase

            // Resolve modifier weak attr.
            guard capturedModifier.isValid(in: graph) else { return (nil, false) }

            // Pass a modifier-aware makeView closure to the outer materializer.
            // The materializer (Layout/ViewThatFits/etc.) must first install its
            // geometry/indirect attrs, then invoke this closure with the final
            // child inputs. Applying the modifier here directly would bypass that
            // wiring and drop child preferences.
            let strongModifier = capturedModifier.toStrong()
            return body(mergedInputs) { childInputs in
                capturedProject(strongModifier, childInputs) { innerInputs in
                    makeView(innerInputs)
                }
            }
        }

        return base.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: wrappedBody)
    }
}

// MARK: - _ViewList_SubgraphElements

/// Refcounted subgraph holder used by retained ViewList slices.
/// Stores an AGSubgraph object plus a manual retain count for list slices.
class _ViewList_Subgraph {
    var subgraph: AGSubgraph
    var refcount: UInt32 = 1

    init(subgraph: AGSubgraph) {
        self.subgraph = subgraph
    }

    func release() {
        guard refcount > 0 else { return }
        refcount -= 1
        if refcount == 0 {
            invalidate()
            invalidateSubgraph()
        }
    }

    /// Subclass hook invoked exactly once when the manual retain count reaches zero.
    /// The actual graph invalidation is performed by `release()` after this hook returns.
    func invalidate() {
    }

    private func invalidateSubgraph() {
        guard AGSubgraphIsValid(subgraph), let graph = subgraph.graph else {
            return
        }
        if _AGGraph.current === graph {
            invalidateInCurrentContext(graph: graph)
        } else {
            _AGGraph.withCurrent(graph) {
                invalidateInCurrentContext(graph: graph)
            }
        }
    }

    private func invalidateInCurrentContext(graph: _AGGraph) {
        guard AGSubgraphIsValid(subgraph) else { return }
        Update.begin()
        defer { Update.end() }
        if subgraph.isInserted {
            subgraph.willRemove()
        }
        subgraph.invalidate()
        graph.drainActionOutbox()
        subgraph.removeFromParent()
    }
}

/// Storage for sublist subgraphs. `retain()` returns a release token.
/// retain() walks backwards, skips dead entries (refcount==0), retains live ones,
/// then creates a _ViewList_SubgraphRelease covering the live slice.
final class _ViewList_SublistSubgraphStorage {
    var subgraphs: [_ViewList_Subgraph] = []
    var isValid: Bool { !subgraphs.isEmpty }

    func retain() -> _ViewList_SubgraphRelease? {
        // Walk backwards: skip dead (refcount==0) and invalid subgraphs, retain live ones.
        var liveItems: [_ViewList_Subgraph] = []
        var i = subgraphs.count - 1
        while i >= 0 {
            let item = subgraphs[i]
            if item.refcount > 0, AGSubgraphIsValid(item.subgraph) {
                item.refcount += 1
                liveItems.append(item)
            }
            i -= 1
        }
        guard !liveItems.isEmpty else { return nil }
        return _ViewList_SubgraphRelease(owner: self, subgraphs: liveItems.reversed())
    }
}

/// Release token for a retained subgraph slice. Decrements refcounts on dealloc.
/// deinit walks the slice and decrements refcount per item.
/// It invalidates when refcount reaches 0. The retained slice is stored as an Array copy.
final class _ViewList_SubgraphRelease {
    private let owner: _ViewList_SublistSubgraphStorage
    private let subgraphs: [_ViewList_Subgraph]

    init(owner: _ViewList_SublistSubgraphStorage, subgraphs: [_ViewList_Subgraph]) {
        self.owner = owner
        self.subgraphs = subgraphs
    }

    deinit {
        for item in subgraphs {
            item.release()
        }
    }
}

/// Wraps a base _ViewList_Elements with per-item subgraph lifecycle management.
/// Used by per-item sublists so each item can retain its own element lifetime.
struct _ViewList_SubgraphElements: _ViewList_Elements {
    var base: any _ViewList_Elements
    var subgraphs: _ViewList_SublistSubgraphStorage? = nil
    var releaseElements: _ViewList_SubgraphRelease? = nil

    var count: Int { base.count }

    func retain() -> _ViewList_SubgraphRelease? {
        subgraphs?.retain() ?? releaseElements
    }

    /// Attaches a subgraph to this elements wrapper for lifecycle tracking.
    /// Item-subgraph link behavior is not fully wired.
    mutating func wrap(subgraph: _ViewList_Subgraph) {
        if subgraphs == nil { subgraphs = _ViewList_SublistSubgraphStorage() }
        if subgraphs?.subgraphs.contains(where: { $0 === subgraph }) == false {
            subgraphs?.subgraphs.append(subgraph)
        }
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        base.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
    }
}

// MARK: - _ViewList_Node

/// A single node yielded by `ViewList.applyNodes`.
enum _ViewList_Node {
    case list(any ViewList, Attribute<any ViewList>?)
    case group(_ViewList_Group)
    case section(_ViewList_Section)
    case sublist(_ViewList_Sublist)
}

struct _ViewList_Section: ViewList {
    struct Info {
        var id: UInt32
        var isHeader: Bool
        var isFooter: Bool

        init(id: UInt32 = 0, isHeader: Bool = false, isFooter: Bool = false) {
            self.id = id
            self.isHeader = isHeader
            self.isFooter = isFooter
        }
    }

    var id: UInt32
    var base: _ViewList_Group
    var traits: ViewTraitCollection
    var isHierarchical: Bool
    var containerValues: ContainerValues
    var subviewIDTransform: _ViewList_SublistTransform
    var headerFooterSubviewIDTransform: _ViewList_SublistTransform

    init(
        id: UInt32 = 0,
        base: _ViewList_Group = _ViewList_Group(lists: []),
        traits: ViewTraitCollection = ViewTraitCollection(),
        isHierarchical: Bool = false,
        containerValues: ContainerValues = ContainerValues(),
        subviewIDTransform: _ViewList_SublistTransform = _ViewList_SublistTransform(),
        headerFooterSubviewIDTransform: _ViewList_SublistTransform = _ViewList_SublistTransform()
    ) {
        self.id = id
        self.base = base
        self.traits = traits
        self.isHierarchical = isHierarchical
        self.containerValues = containerValues
        self.subviewIDTransform = subviewIDTransform
        self.headerFooterSubviewIDTransform = headerFooterSubviewIDTransform
    }

    var header: (list: any ViewList, attribute: Attribute<any ViewList>)? {
        region(at: 0)
    }

    var content: (list: any ViewList, attribute: Attribute<any ViewList>)? {
        region(at: 1)
    }

    var footer: (list: any ViewList, attribute: Attribute<any ViewList>)? {
        region(at: 2)
    }

    func region(at index: Int) -> (list: any ViewList, attribute: Attribute<any ViewList>)? {
        guard base.lists.indices.contains(index) else {
            return nil
        }
        return base.lists[index]
    }

    func count(style: _ViewList_IteratorStyle) -> Int {
        base.count(style: style)
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        base.estimatedCount(style: style)
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        to(&from, style, .section(self), transform)
    }

    var debugDescription: String {
        "_ViewList_Section(id: \(id), count: \(count(style: _ViewList_IteratorStyle())))"
    }
}

// MARK: - _ViewList_Group

/// Wraps multiple ViewList entries for mixed static+dynamic content.
/// Created when TupleView/ViewBuilder mixes static and dynamic content (Text + ForEach, etc.).
/// applyNodes iterates each entry and delegates to its list.applyNodes, passing entry.attribute
/// as the list: parameter so each sublist has its own AG reactivity anchor.
struct _ViewList_Group: ViewList {
    /// Each entry is (current ViewList value, its AG node for dependency tracking).
    var lists: [(list: any ViewList, attribute: Attribute<any ViewList>)]

    func count(style: _ViewList_IteratorStyle) -> Int {
        lists.reduce(0) { $0 + $1.list.count(style: style) }
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        for (entryIndex, entry) in lists.enumerated() {
            let entryTransform = transform.withPushedItem(
                _ViewList_GroupEntryTransform(
                    owner: entry.attribute.identifier,
                    index: entryIndex
                )
            )
            let cont = entry.list.applyNodes(
                from: &from,
                style: style,
                list: entry.attribute,
                transform: entryTransform,
                to: to
            )
            if !cont { return false }
        }
        return true
    }
}

struct _ViewList_GroupEntryID: Hashable {
    var owner: UInt32
    var index: Int
    var child: _ViewList_ID.Canonical
}

private struct _ViewList_GroupEntryTransform: _ViewList_SublistTransform_Item {
    var owner: AGAttribute
    var index: Int

    private static let reuseID = Int(bitPattern: ObjectIdentifier(_ViewList_GroupEntryTransform.self))

    func apply(sublist: inout _ViewList_Sublist) {
        bindID(&sublist.id)
    }

    func bindID(_ id: inout _ViewList_ID) {
        let groupID = _ViewList_GroupEntryID(
            owner: owner.rawValue,
            index: index,
            child: id.canonicalID
        )
        id.explicitIDs.append(
            _ViewList_ID.Explicit(
                id: AnyHashable(groupID),
                reuseID: Self.reuseID,
                owner: owner,
                isUnary: false
            )
        )
    }
}

func _viewListTransformDroppingGroupEntryIDs(
    _ transform: _ViewList_SublistTransform
) -> _ViewList_SublistTransform {
    var filtered = _ViewList_SublistTransform()
    for item in transform.items {
        if item is _ViewList_GroupEntryTransform {
            continue
        }
        filtered.push(item)
    }
    filtered.subgraphCount = transform.subgraphCount
    return filtered
}

/// A contiguous slice of a ViewList passed to the `applyNodes` callback.
struct _ViewList_Sublist {
    var start: Int
    var count: Int
    var id: _ViewList_ID
    var elements: _ViewList_SubgraphElements
    var traits: ViewTraitCollection
    var list: Attribute<any ViewList>?
}

/// View wrapper used by `_VariadicView_Children.Element`.
struct _ViewList_View {
    var elements: _ViewList_SubgraphElements
    var releaseElements: _ViewList_SubgraphRelease?
    var id: _ViewList_ID
    var index: Int
    var count: Int
    var contentSubgraph: AGSubgraph?

    init(
        elements: _ViewList_SubgraphElements,
        id: _ViewList_ID,
        index: Int,
        count: Int,
        contentSubgraph: AGSubgraph?
    ) {
        self.elements = elements
        self.releaseElements = elements.retain()
        self.id = id
        self.index = index
        self.count = count
        self.contentSubgraph = contentSubgraph
    }

    var elementID: _ViewList_ID {
        var result = id
        result._index = Int32(index)
        return result
    }

    var viewID: AnyHashable {
        if let explicitID = id.explicitIDs.first {
            if explicitID.isUnary {
                if count == 1 {
                    return explicitID.id
                }
                return AnyHashable(
                    _ViewList_ID.Canonical(
                        _index: Int32(index),
                        implicitID: -1,
                        explicitID: explicitID.id
                    )
                )
            }
            if count == 1 && id.implicitID < 0 {
                return explicitID.id
            }
        }
        return AnyHashable(
            _ViewList_ID.Canonical(
                _index: Int32(index),
                implicitID: id.implicitID,
                explicitID: id.explicitIDs.first?.id
            )
        )
    }

    var reuseIdentifier: Int {
        elementID.reuseIdentifier
    }

    var subviewID: _ViewList_ID {
        elementID
    }

    /// _VariadicView_Children.Element._makeView delegates here.
    /// This creates placeholder outputs, then uses `PlaceholderInfo` to attach
    /// concrete child outputs through indirect output attributes.
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewList_View._makeView called outside an active _AGGraph context.")
        }
        let placeholders = inputs.makeIndirectOutputs()
        let infoAttr: Attribute<_ViewOutputs> = graph.makeStatefulRule(
            PlaceholderInfo(view: view._attribute, inputs: inputs, placeholders: placeholders)
        )
        _ = graph.makeSideEffectRule {
            _ = infoAttr.value
            return ()
        }
        return placeholders
    }
}

extension _ViewList_View: PrimitiveView, UnaryView {}

/// Stateful placeholder rule for `_ViewList_View._makeView`.
private struct PlaceholderInfo: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = _ViewOutputs

    var view: Attribute<_ViewList_View>
    var inputs: _ViewInputs
    var placeholders: _ViewOutputs
    var childSubgraph: AGSubgraph?
    var releaseElements: _ViewList_SubgraphRelease?
    var lastID: _ViewList_ID?
    var lastIndex: Int?
    var lastContentSubgraph: AGSubgraph?

    mutating func updateValue() {
        let item = view.value

        // Reuse the item when contentSubgraph and _ViewList_ID identity match.
        if canReuse(item) {
            releaseElements = item.elements.retain()
            _AGGraph.setStatefulOutput(placeholders)
            return
        }

        eraseItem()

        let subgraph = AGSubgraph()
        childSubgraph = subgraph
        lastID = item.id
        lastIndex = item.index
        lastContentSubgraph = item.contentSubgraph

        releaseElements = item.elements.retain()
        var childInputs = inputs
        childInputs.copyCaches()
        let concrete = AGSubgraph.withCurrent(subgraph) {
            item.elements.makeOneElement(at: item.index, inputs: childInputs) { elementInputs, makeView in
                makeView(elementInputs)
            }
        } ?? _ViewOutputs()

        concrete.attachIndirectOutputs(to: placeholders)
        _AGGraph.setStatefulOutput(placeholders)
    }

    private func canReuse(_ item: _ViewList_View) -> Bool {
        guard childSubgraph != nil,
              let lastID,
              let lastIndex else { return false }
        return lastID == item.id &&
            lastIndex == item.index &&
            lastContentSubgraph === item.contentSubgraph
    }

    private mutating func eraseItem() {
        guard let subgraph = childSubgraph else { return }
        placeholders.detachIndirectOutputs()
        subgraph.invalidate()
        subgraph.removeFromParent()
        childSubgraph = nil
        releaseElements = nil
        lastID = nil
        lastIndex = nil
        lastContentSubgraph = nil
    }

    mutating func destroy() {
        eraseItem()
    }
}

// MARK: - TransactionID

/// Comparable token for list edit queries.
struct TransactionID: Comparable, Hashable {
    var value: UInt = 0
    init() {}
    init(graph: _AGGraph) {
        value = graph.graphCounter(lane: 1)
    }
    init<A>(context: RuleContext<A>) {
        self.init(context: AnyRuleContext(context))
    }
    init(context: AnyRuleContext) {
        guard let graph = _AGGraph.current else {
            fatalError("TransactionID.init(context:) called outside an active _AGGraph context.")
        }
        context.update {}
        value = graph.graphCounter(lane: 1)
    }
    static func < (a: TransactionID, b: TransactionID) -> Bool {
        Int(bitPattern: a.value) < Int(bitPattern: b.value)
    }
}

// MARK: - SExpPrinter

/// Debug pretty-printer for ViewList trees. Stub.
struct SExpPrinter {}

// MARK: - ViewListElements

/// Discriminated union for a fully-static view list structure.
indirect enum ViewListElements {
    case unaryElements(UnaryElements)
    case merged([_ViewListOutputs])
    // staticList modifier path.
    case modified(ModifiedElements)
}

extension ViewListElements: _ViewList_Elements {
    var count: Int {
        switch self {
        case .unaryElements(let unary): return unary.count
        case .merged(let outputs): return MergedElements(outputs: outputs).count
        case .modified(let mod): return mod.count
        }
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        switch self {
        case .unaryElements(let unary):
            return unary.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
        case .merged(let outputs):
            return MergedElements(outputs: outputs).makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
        case .modified(let mod):
            return mod.makeElements(from: &from, inputs: inputs, indirectMap: indirectMap, body: body)
        }
    }
}

// MARK: - Trait types

/// Type-erased storage for a single trait entry in a `ViewTraitCollection`.
protocol AnyViewTrait {}

/// Typed wrapper for one `_ViewTraitKey` value.
struct AnyTrait<Key: _ViewTraitKey>: AnyViewTrait {
    var value: Key.Value
}

/// Per-view trait values propagated from child to container.
struct ViewTraitCollection {
    var storage: [AnyViewTrait] = []
    init() {}

    subscript<K: _ViewTraitKey>(key: K.Type) -> K.Value {
        get {
            for item in storage { if let t = item as? AnyTrait<K> { return t.value } }
            return K.defaultValue
        }
        set {
            for i in 0..<storage.count {
                if storage[i] is AnyTrait<K> {
                    storage[i] = AnyTrait<K>(value: newValue)
                    return
                }
            }
            storage.append(AnyTrait<K>(value: newValue))
        }
    }
}

/// The set of trait keys a view list is tracking.
/// Data-dependency propagation is surface-modeled only.
struct ViewTraitKeys {
    var types: Set<ObjectIdentifier> = []
    var isDataDependent: Bool = false

    mutating func insert<T: _ViewTraitKey>(_ key: T.Type) {
        types.insert(ObjectIdentifier(key))
    }
    func contains<T: _ViewTraitKey>(_ key: T.Type) -> Bool {
        types.contains(ObjectIdentifier(key))
    }
    mutating func formUnion(_ other: ViewTraitKeys) {
        types.formUnion(other.types)
        isDataDependent = isDataDependent || other.isDataDependent
    }
    func withDataDependency() -> ViewTraitKeys {
        var copy = self
        copy.isDataDependent = true
        return copy
    }
}

enum ViewContentOffset: _ViewTraitKey {
    static var defaultValue: ViewContentOffset? { nil }

    case staticCount(Int, Bool)
    case dynamic(Attribute<Int>, Int)

    var offset: Int {
        switch self {
        case .staticCount(let count, _):
            return count
        case .dynamic(let count, let offset):
            return count.value + offset
        }
    }
}

// MARK: - ListModifier

/// Abstract base for `_ViewListOutputs.Views.dynamicList` modifier chain.
/// Stores a type-erased projection closure for concrete modifier dispatch.
class ListModifier: _ViewList_SublistTransform_Item {
    var pred: ListModifier?
    let modifierType: any ViewModifier.Type
    let modifier: AGWeakAttribute
    let baseInputs: _GraphInputs
    // Type-erased closure for concrete M._makeView dispatch.
    let project: (AGAttribute, _ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> _ViewOutputs

    init<M: ViewModifier>(pred: ListModifier?,
                          modifier: Attribute<M>,
                          inputs: _GraphInputs) {
        self.pred = pred
        self.modifierType = M.self
        self.modifier = modifier.asWeak().base
        self.baseInputs = inputs
        self.project = { rawAttr, mergedInputs, outerBody in
            let modAttr = Attribute<M>(rawAttr)
            let gv = _GraphValue(_attribute: modAttr)
            return M._makeView(modifier: gv, inputs: mergedInputs,
                               body: { _, bodyInputs in outerBody(bodyInputs) })
        }
    }

    /// Applies this modifier chain to `list`.
    func apply(to list: inout any ViewList) {
        pred?.apply(to: &list)
        let modified = ModifiedViewList(list: list, listModifier: self)
        list = modified
    }

    func apply(sublist: inout _ViewList_Sublist) {
        sublist.elements.base = ModifiedElements(
            base: sublist.elements.base,
            modifier: modifier,
            baseInputs: baseInputs,
            project: project
        )
    }
}

extension _ViewList_TemporarySublistTransform {
    /// Pushes a ListModifier during ModifiedViewList.applyNodes, then applies
    /// the stack when sublists are materialized.
    func withPushedItem(_ item: any _ViewList_SublistTransform_Item) -> Self {
        var items = storage?.items ?? []
        items.append(item)
        let subgraphCount = (storage?.subgraphCount ?? 0) + (Self.countsSubgraphs(item) ? 1 : 0)
        return Self(
            storage: _TemporarySublistTransformStorage(
                items: items,
                subgraphCount: subgraphCount
            ),
            flag: true
        )
    }

    var isEmpty: Bool {
        guard let storage else { return true }
        return storage.items.isEmpty
    }

    func copy() -> _ViewList_SublistTransform {
        var transform = _ViewList_SublistTransform()
        guard let storage else { return transform }
        transform.items = storage.items
        transform.subgraphCount = storage.subgraphCount
        return transform
    }

    func apply(to sublist: inout _ViewList_Sublist) {
        guard let storage else { return }
        let items = storage.items
        for item in items.reversed() {
            item.apply(sublist: &sublist)
        }
    }

    func bindID(_ id: inout _ViewList_ID) {
        guard let storage else { return }
        let items = storage.items
        for item in items.reversed() {
            item.bindID(&id)
        }
    }

    func wrapSubgraphs(into storage: inout _ViewList_SublistSubgraphStorage) {
        guard let temporaryStorage = self.storage else { return }
        let items = temporaryStorage.items
        for item in items.reversed() {
            item.wrapSubgraph(into: &storage)
        }
    }

    private static func countsSubgraphs(_ item: any _ViewList_SublistTransform_Item) -> Bool {
        type(of: item).flags.contains(.graphDependent)
    }
}

// MARK: - ModifiedViewList

/// Wraps a ViewList with a ListModifier chain for the dynamicList modifier path.
/// applyNodes: pushes modifier info into transform, then delegates to original list.applyNodes.
struct ModifiedViewList: ViewList {
    var list: any ViewList
    var listModifier: ListModifier

    func count(style: _ViewList_IteratorStyle) -> Int { list.count(style: style) }
    func estimatedCount(style: _ViewList_IteratorStyle) -> Int { list.estimatedCount(style: style) }
    var traitKeys: ViewTraitKeys? { list.traitKeys }
    var traits: ViewTraitCollection { list.traits }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list listAttr: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        let newTransform = transform.withPushedItem(listModifier)
        return list.applyNodes(
            from: &from,
            style: style,
            list: listAttr,
            transform: newTransform,
            to: to
        )
    }

    var debugDescription: String { "ModifiedViewList(\(list))" }
}

// MARK: - ViewListContent

enum ViewListContent {
    case staticList(ViewListElements)
    case dynamicList(Attribute<any ViewList>, ListModifier?)
}

// MARK: - Generator extraction helper

/// Traverses a ViewList via applyNodes and visits each sublist in order.
@discardableResult
func _forEachSublist(
    in list: any ViewList,
    listAttribute: Attribute<any ViewList>? = nil,
    style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
    sublistTransform: _ViewList_SublistTransform = _ViewList_SublistTransform(),
    body: (_ViewList_Sublist) -> Bool
) -> Bool {
    var from = 0
    return list.applyNodes(
        from: &from,
        style: style,
        list: listAttribute,
        transform: _ViewList_TemporarySublistTransform()
    ) { _, _, node, transform in
        guard case .sublist(var sublist) = node else { return true }
        transform.apply(to: &sublist)
        sublistTransform.apply(to: &sublist)
        return body(sublist)
    }
}

/// Applies a callback to sublists before materializing children.
@discardableResult
func _applySublists(
    in list: any ViewList,
    from: inout Int,
    listAttribute: Attribute<any ViewList>? = nil,
    style: _ViewList_IteratorStyle = _ViewList_IteratorStyle(),
    sublistTransform: _ViewList_SublistTransform = _ViewList_SublistTransform(),
    body: (_ViewList_Sublist) -> Bool
) -> Bool {
    list.applyNodes(
        from: &from,
        style: style,
        list: listAttribute,
        transform: _ViewList_TemporarySublistTransform()
    ) { _, _, node, transform in
        guard case .sublist(var sublist) = node else { return true }
        transform.apply(to: &sublist)
        sublistTransform.apply(to: &sublist)
        return body(sublist)
    }
}

// MARK: - ApplyModifiers

/// AG Rule that wraps a source ViewList with a ListModifier chain.
/// Reads the source list, applies the modifier chain, and returns the wrapped list.
struct ApplyModifiers: Rule {
    typealias Value = any ViewList
    var source: Attribute<any ViewList>
    var listModifier: ListModifier

    var value: any ViewList {
        var list: any ViewList = source.value   // registers AG dependency on source ViewList
        listModifier.apply(to: &list)
        return list
    }
}

// MARK: - _ViewListOutputs.multiModifier

extension _ViewListOutputs {
    /// Wraps the current view list content with a ViewModifier applied to each element.
    ///
    /// staticList branch (tag != 1): creates ModifiedElements, stores as .staticList(.modified(...))
    /// dynamicList branch (tag == 1): creates ListModifier + ApplyModifiers AG rule
    mutating func multiModifier<M: ViewModifier>(
        _ modifier: _GraphValue<M>,
        inputs: _ViewListInputs
    ) {
        switch views {
        case .staticList(let innerElements):
            let modElements = ModifiedElements.make(base: innerElements, modifier: modifier,
                                                    inputs: inputs.base)
            views = .staticList(.modified(modElements))

        case .dynamicList(let listAttr, let pred):
            guard let graph = _AGGraph.current else {
                fatalError("_ViewListOutputs.multiModifier called outside AG context.")
            }
            let lm = ListModifier(pred: pred, modifier: modifier._attribute, inputs: inputs.base)
            let newAttr: Attribute<any ViewList> = graph.makeRule(
                ApplyModifiers(source: listAttr, listModifier: lm)
            )
            views = .dynamicList(newAttr, lm)
        }
    }
}
