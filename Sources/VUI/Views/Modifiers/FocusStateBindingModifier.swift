//
//  File: FocusStateBindingModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct FocusStoreList {
    struct Item {
        var version: DisplayList.Version
        var propertyID: ObjectIdentifier
        var bindingUpdateAction: FocusStateBindingUpdateAction
        var storeUpdateAction: FocusStoreUpdateAction
        weak var responder: ResponderNode?
        weak var bridge: FocusBridge?
        var isFocused: Bool
    }

    struct Key: HostPreferenceKey {
        nonisolated(unsafe) static let defaultValue = FocusStoreList()

        static func reduce(
            value: inout FocusStoreList,
            nextValue: () -> FocusStoreList
        ) {
            value.items.append(contentsOf: nextValue().items)
        }
    }

    var items: [Item] = []

    var version: DisplayList.Version {
        var version = DisplayList.Version()
        for item in items {
            version.combine(with: item.version)
        }
        return version
    }
}

final class FocusStateBindingResponder: MultiViewResponder {
    var context: AnyRuleContext?
    var _viewResponders: Attribute<[ViewResponder]>

    init(viewResponders: Attribute<[ViewResponder]>) {
        _viewResponders = viewResponders
        super.init()
    }

    func updateViewResponders() {
        guard let context else { return }
        context.update {
            updateChildren(
                context.changedValue(of: _viewResponders, options: [])
            )
        }
    }
}

private struct FocusStateBindingResponderFilter: StatefulRule {
    typealias Value = [ViewResponder]

    var responder: FocusStateBindingResponder

    mutating func updateValue() {
        responder.context = AnyRuleContext(context)
        responder.updateChildren(
            responder._viewResponders.changedValue(options: [])
        )
        _AGGraph.setStatefulOutput([responder])
    }
}

private struct FocusStateBindingModifier<FocusValue: Hashable>:
    ViewModifier, MultiViewModifier {
    typealias Body = Never

    var binding: FocusState<FocusValue>.Binding
    var value: FocusValue

    private struct ListItemFilter: StatefulRule {
        typealias Value = FocusStoreList

        var _modifier: Attribute<FocusStateBindingModifier>
        var responder: FocusStateBindingResponder
        var _focusItem: OptionalAttribute<FocusItem?>
        var _focusBridge: OptionalAttribute<FocusBridge?>
        var _focusScopes: Attribute<[Namespace.ID]>
        var isFocused: Bool

        mutating func updateValue() {
            let modifier = _modifier.changedValue(options: [])
            let focusItem = _focusItem.changedValue(options: [])
            let focusBridge = _focusBridge.changedValue(options: [])
            let focusScopes = _focusScopes.changedValue(options: [])

            let focusedResponder = focusItem?.value?.responder
            let nextIsFocused: Bool
            if let focusedResponder = focusedResponder as? ViewResponder {
                nextIsFocused = focusedResponder === responder
                    || focusedResponder.isDescendant(of: responder)
            } else {
                nextIsFocused = false
            }

            guard !hasValue
                    || modifier.changed
                    || focusItem?.changed == true
                    || focusBridge?.changed == true
                    || focusScopes.changed
                    || nextIsFocused != isFocused else {
                return
            }
            isFocused = nextIsFocused

            let binding = modifier.value.binding
            let value = modifier.value.value
            let propertyID = binding.propertyID
            let bridge = focusBridge?.value ?? nil
            let scopes = focusScopes.value
            let targetResponder = responder
            let item = FocusStoreList.Item(
                version: DisplayList.Version(forUpdate: ()),
                propertyID: propertyID,
                bindingUpdateAction: FocusStateBindingUpdateAction {
                    binding.wrappedValue = value
                },
                storeUpdateAction: FocusStoreUpdateAction { plist in
                    guard let bridge else { return }
                    let entry = FocusStore.Entry(
                        value: value,
                        focusScopes: scopes,
                        target: .focusResponder(
                            WeakBox(targetResponder),
                            WeakBox(bridge)
                        )
                    )
                    plist.setValue(
                        Optional(entry),
                        forKey: FocusStore.Key<FocusValue>.self
                    )
                },
                responder: targetResponder,
                bridge: bridge,
                isFocused: isFocused
            )
            _AGGraph.setStatefulOutput(FocusStoreList(items: [item]))
        }
    }

    private struct ListTransform: Rule {
        typealias Value = (inout FocusStoreList) -> Void

        var _list: Attribute<FocusStoreList>

        var value: Value {
            let list = _list.value
            return { value in
                value.items.append(contentsOf: list.items)
            }
        }
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "FocusStateBindingModifier._makeView called outside an active "
                    + "_AGGraph context."
            )
        }

        var outputs = body(_Graph(), inputs)
        let innerNodes = outputs.preferences.values(for: ViewRespondersKey.self)
        let innerResponders: Attribute<[ViewResponder]>
        if innerNodes.isEmpty {
            innerResponders = graph.makeInput(value: [])
        } else if innerNodes.count == 1 {
            innerResponders = Attribute(innerNodes[0])
        } else {
            innerResponders = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for node in innerNodes {
                    let next = Attribute<[ViewResponder]>(node).value
                    ViewRespondersKey.reduce(value: &combined) { next }
                }
                return combined
            }
        }

        let responder = FocusStateBindingResponder(
            viewResponders: innerResponders
        )
        let responderOutput = graph.makeStatefulRule(
            FocusStateBindingResponderFilter(responder: responder)
        )
        outputs.preferences.setValue(
            responderOutput.identifier,
            for: ViewRespondersKey.self
        )

        let list = graph.makeStatefulRule(
            ListItemFilter(
                _modifier: modifier._attribute,
                responder: responder,
                _focusItem: inputs[FocusedItemInputKey.self],
                _focusBridge: inputs[FocusBridgeInputKey.self],
                _focusScopes: graph.makeInput(value: []),
                isFocused: false
            )
        )
        outputs.preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: FocusStoreList.Key.self,
            transform: graph.makeRule(ListTransform(_list: list))
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError(
                "FocusStateBindingModifier._makeViewList called outside an "
                    + "active _AGGraph context."
            )
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

extension View {
    public func focused<Value>(
        _ binding: FocusState<Value>.Binding,
        equals value: Value
    ) -> some View where Value: Hashable {
        modifier(FocusStateBindingModifier(binding: binding, value: value))
    }

    public func focused(
        _ condition: FocusState<Bool>.Binding
    ) -> some View {
        focused(condition, equals: true)
    }
}
