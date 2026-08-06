//
//  File: MappedViews.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct MappedViewElement {
    var id: _ViewList_ID
    var traits: ViewTraitCollection

    subscript<Key: _ViewTraitKey>(key: Key.Type) -> Key.Value {
        get { traits[key] }
        set { traits[key] = newValue }
    }

    var view: some View {
        Placeholder()
    }

    private struct Placeholder: PrimitiveView {
        typealias Body = Never

        static func _makeView(
            view: _GraphValue<Self>,
            inputs: _ViewInputs
        ) -> _ViewOutputs {
            var inputs = inputs
            guard let makeView = inputs.popLast(BodyInput.self) else {
                return _ViewOutputs()
            }
            return makeView(inputs)
        }
    }

    fileprivate struct BodyInput: ViewInput {
        typealias Value = Stack<(_ViewInputs) -> _ViewOutputs>

        static var defaultValue: Value { .empty }

        static func valuesEqual(_ lhs: Value, _ rhs: Value) -> Bool {
            false
        }
    }
}

struct MappedViews<Content, MappedContent>: PrimitiveView, MultiView
    where Content: View, MappedContent: View {

    typealias Body = Never

    var content: Content
    var transform: (MappedViewElement) -> MappedContent

    init(
        content: Content,
        transform: @escaping (MappedViewElement) -> MappedContent
    ) {
        self.content = content
        self.transform = transform
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "MappedViews._makeViewList called outside an active _AGGraph context."
            )
        }

        var contentInputs = inputs
        contentInputs.options.insert(.needsDynamicTraits)
        let outputs = Content._makeViewList(
            view: view[\.content],
            inputs: contentInputs
        )
        let list = outputs.makeAttribute(inputs: contentInputs)
        let views = MutableBox<
            [_ViewList_ID.Canonical: WeakAttribute<MappedContent>]
        >([:])
        let mappedList: Attribute<any ViewList> = graph.makeRule(
            MappedList.Init(
                _list: list,
                _view: view._attribute,
                baseInputs: inputs.base,
                views: views
            )
        )
        return _ViewListOutputs(
            views: .dynamicList(mappedList, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
    }

    struct MappedList: ViewList {
        var base: any ViewList
        var baseInputs: _GraphInputs
        var _view: Attribute<MappedViews>
        var views: MutableBox<
            [_ViewList_ID.Canonical: WeakAttribute<MappedContent>]
        >

        struct Init: Rule {
            var _list: Attribute<any ViewList>
            var _view: Attribute<MappedViews>
            var baseInputs: _GraphInputs
            var views: MutableBox<
                [_ViewList_ID.Canonical: WeakAttribute<MappedContent>]
            >

            var value: any ViewList {
                MappedList(
                    base: _list.value,
                    baseInputs: baseInputs,
                    _view: _view,
                    views: views
                )
            }
        }

        func count(style: _ViewList_IteratorStyle) -> Int {
            base.count(style: style)
        }

        func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
            base.estimatedCount(style: style)
        }

        var traitKeys: ViewTraitKeys? {
            base.traitKeys
        }

        var traits: ViewTraitCollection {
            base.traits
        }

        var viewIDs: _ViewList_ID_Views? {
            base.viewIDs
        }

        func appendViewIDs(
            into accumulator: inout HeterogeneousViewIDsAccumulator
        ) {
            base.appendViewIDs(into: &accumulator)
        }

        func applyNodes(
            from: inout Int,
            style: _ViewList_IteratorStyle,
            list: Attribute<any ViewList>?,
            transform: _ViewList_TemporarySublistTransform,
            to body: (
                inout Int,
                _ViewList_IteratorStyle,
                _ViewList_Node,
                _ViewList_TemporarySublistTransform
            ) -> Bool
        ) -> Bool {
            let transform = transform.withPushedItem(
                Transform(
                    _view: _view,
                    baseInputs: baseInputs,
                    views: views
                )
            )
            return base.applyNodes(
                from: &from,
                style: style,
                list: list,
                transform: transform,
                to: body
            )
        }

        func firstOffset<ID: Hashable>(
            forID id: ID,
            style: _ViewList_IteratorStyle
        ) -> Int? {
            base.firstOffset(forID: id, style: style)
        }

        func edit(
            forID id: _ViewList_ID,
            since transaction: TransactionID
        ) -> _ViewList_Edit? {
            base.edit(forID: id, since: transaction)
        }

        func print(into printer: inout SExpPrinter) {
            base.print(into: &printer)
        }
    }

    struct MappedElements: _ViewList_Elements {
        var base: any _ViewList_Elements
        var baseInputs: _GraphInputs
        var id: _ViewList_ID
        var _list: WeakAttribute<any ViewList>
        var _view: Attribute<MappedViews>
        var views: MutableBox<
            [_ViewList_ID.Canonical: WeakAttribute<MappedContent>]
        >

        var count: Int {
            base.count
        }

        func makeElements(
            from: inout Int,
            inputs: _ViewInputs,
            indirectMap: IndirectAttributeMap?,
            body: (
                _ViewInputs,
                @escaping (_ViewInputs) -> _ViewOutputs
            ) -> (_ViewOutputs?, Bool)
        ) -> (_ViewOutputs?, Bool) {
            guard let graph = _AGGraph.current else {
                fatalError(
                    "MappedViews.MappedElements.makeElements called outside an active _AGGraph context."
                )
            }

            var elementIndex = from
            return base.makeElements(
                from: &from,
                inputs: inputs,
                indirectMap: indirectMap
            ) { elementInputs, makeView in
                let elementID = id.elementID(at: elementIndex)
                elementIndex += 1
                let canonicalID = elementID.canonicalID

                let mappedView: Attribute<MappedContent>
                if let cached = views.value[canonicalID],
                   cached.isValid(in: graph),
                   let attribute = cached.attribute {
                    mappedView = attribute
                } else {
                    mappedView = graph.makeRule(
                        ElementView(
                            id: elementID,
                            _view: _view,
                            _list: _list
                        )
                    )
                    views.value[canonicalID] = WeakAttribute(mappedView)
                }

                var mappedInputs = elementInputs
                var mergedInputs = baseInputs
                mergedInputs.merge(elementInputs.base, ignoringPhase: false)
                if let indirectMap {
                    mergedInputs.makeReusable(indirectMap: indirectMap)
                }
                mappedInputs.base = mergedInputs

                return body(mappedInputs) { childInputs in
                    var childInputs = childInputs
                    childInputs.base.append(
                        makeView,
                        to: MappedViewElement.BodyInput.self
                    )
                    return MappedContent._makeView(
                        view: _GraphValue(_attribute: mappedView),
                        inputs: childInputs
                    )
                }
            }
        }

        func tryToReuseElement(
            at index: Int,
            by other: any _ViewList_Elements,
            at otherIndex: Int,
            indirectMap: IndirectAttributeMap,
            testOnly: Bool
        ) -> Bool {
            guard let graph = _AGGraph.current else {
                fatalError(
                    "MappedViews.MappedElements.tryToReuseElement called outside an active _AGGraph context."
                )
            }
            guard let other = other as? Self else {
                return false
            }

            let oldID = id.elementID(at: index)
            let newID = other.id.elementID(at: otherIndex)
            guard let mappedView = views.value[oldID.canonicalID],
                  mappedView.isValid(in: graph),
                  base.tryToReuseElement(
                      at: index,
                      by: other.base,
                      at: otherIndex,
                      indirectMap: indirectMap,
                      testOnly: testOnly
                  )
            else {
                return false
            }

            var reusableInputs = baseInputs
            guard reusableInputs.tryToReuse(
                by: other.baseInputs,
                indirectMap: indirectMap,
                testOnly: testOnly
            ) else {
                return false
            }

            if !testOnly, let attribute = mappedView.attribute {
                attribute.mutateBody(
                    as: ElementView.self,
                    invalidating: true
                ) { elementView in
                    elementView.id = newID
                    elementView._view = other._view
                    elementView._list = other._list
                }
                views.value.removeValue(forKey: oldID.canonicalID)
                views.value[newID.canonicalID] = mappedView
            }
            return true
        }
    }

    private struct ElementView: Rule {
        var id: _ViewList_ID
        var _view: Attribute<MappedViews>
        var _list: WeakAttribute<any ViewList>

        private var list: (any ViewList)? {
            _list.value
        }

        var value: MappedContent {
            let element = MappedViewElement(
                id: id,
                traits: list?.traits ?? ViewTraitCollection()
            )
            return _view.value.transform(element)
        }
    }

    private struct Transform: _ViewList_SublistTransform_Item {
        var _view: Attribute<MappedViews>
        var baseInputs: _GraphInputs
        var views: MutableBox<
            [_ViewList_ID.Canonical: WeakAttribute<MappedContent>]
        >

        func apply(sublist: inout _ViewList_Sublist) {
            let base = sublist.elements
            sublist.elements = _ViewList_SubgraphElements(
                base: MappedElements(
                    base: base,
                    baseInputs: baseInputs,
                    id: sublist.id,
                    _list: WeakAttribute(sublist.list),
                    _view: _view,
                    views: views
                )
            )
        }
    }
}

struct EnumeratedViews<Content, MappedContent>: PrimitiveView, MultiView
    where Content: View, MappedContent: View {

    typealias Body = Never

    var views: MappedViews<Content, MappedContent>

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        MappedViews<Content, MappedContent>._makeViewList(
            view: view[\.views],
            inputs: inputs
        )
    }
}

extension View {
    func enumerated<MappedContent: View>(
        @ViewBuilder transform:
            @escaping (MappedViewElement) -> MappedContent
    ) -> EnumeratedViews<Self, MappedContent> {
        EnumeratedViews(
            views: MappedViews(content: self, transform: transform)
        )
    }
}
