//
//  File: NavigationDestination.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

class NavigationDestinationResolverBase {
    var dataType: Any.Type { Never.self }

    func resolve(_ element: NavigationPathElement) -> AnyView? {
        nil
    }
}

final class NavigationDestinationResolver<Data, Destination>:
    NavigationDestinationResolverBase
where Data: Hashable, Destination: View {
    let transform: (Data) -> Destination

    init(transform: @escaping (Data) -> Destination) {
        self.transform = transform
    }

    override var dataType: Any.Type { Data.self }

    override func resolve(_ element: NavigationPathElement) -> AnyView? {
        let data: Data?
        if Data.self == AnyHashable.self {
            data = element.value as? Data
        } else {
            data = element.value?.base as? Data
        }
        return data.map { AnyView(transform($0)) }
    }
}

struct NavigationDestinationPresentation {
    var id: AnyHashable
    var content: AnyView
    var onDismiss: () -> Void
}

struct ResolvedNavigationDestinations {
    var destinations: [NavigationDestinationResolverBase] = []
    var presentations: [NavigationDestinationPresentation] = []

    mutating func merge(_ other: Self) {
        for resolver in other.destinations {
            let typeID = ObjectIdentifier(resolver.dataType)
            if !destinations.contains(where: {
                ObjectIdentifier($0.dataType) == typeID
            }) {
                destinations.append(resolver)
            }
        }
        presentations.append(contentsOf: other.presentations)
    }

    func resolve(_ element: NavigationPathElement) -> AnyView? {
        guard let typeID = element.typeID,
              let resolver = destinations.first(where: {
                ObjectIdentifier($0.dataType) == typeID
              }) else {
            return nil
        }
        return resolver.resolve(element)
    }
}

struct NavigationDestinationsKey: PreferenceKey {
    static var defaultValue: ResolvedNavigationDestinations {
        ResolvedNavigationDestinations()
    }

    static func reduce(
        value: inout ResolvedNavigationDestinations,
        nextValue: () -> ResolvedNavigationDestinations
    ) {
        value.merge(nextValue())
    }
}

struct NavigationDestinationModifier<Data, Destination>:
    ViewModifier, MultiViewModifier
where Data: Hashable, Destination: View {
    typealias Body = Never

    var destination: (Data) -> Destination

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "NavigationDestinationModifier._makeView called outside "
                    + "an active _AGGraph context."
            )
        }
        var outputs = body(_Graph(), inputs)

        let preference: Attribute<ResolvedNavigationDestinations> =
            graph.makeRule {
                ResolvedNavigationDestinations(destinations: [
                    NavigationDestinationResolver(
                        transform: modifier._attribute.value.destination
                    )
                ])
            }
        outputs.preferences.append(
            NavigationDestinationsKey.self,
            node: preference.identifier
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

struct ViewDestinationNavigationDestinationModifier<Destination>:
    ViewModifier, MultiViewModifier
where Destination: View {
    typealias Body = Never

    var _isPresented: Binding<Bool>
    var destination: Destination
    @Namespace private var namespace

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ViewDestinationNavigationDestinationModifier._makeView "
                    + "called outside an active _AGGraph context."
            )
        }
        var graphInputs = inputs.base
        let fields = DynamicPropertyCache.fields(of: Self.self)
        let propertyBuffer = _DynamicPropertyBuffer(
            fields: fields,
            container: modifier,
            inputs: &graphInputs
        )
        let resolvedModifier: Attribute<Self> = graph.makeRule {
            var value = modifier._attribute.value
            propertyBuffer.applyContexts(to: &value)
            return value
        }
        var inputs = inputs
        inputs.base = graphInputs
        var outputs = body(_Graph(), inputs)

        let preference: Attribute<ResolvedNavigationDestinations> =
            graph.makeRule {
                let value = resolvedModifier.value
                guard value._isPresented.wrappedValue else {
                    return ResolvedNavigationDestinations()
                }
                let binding = value._isPresented
                return ResolvedNavigationDestinations(presentations: [
                    NavigationDestinationPresentation(
                        id: AnyHashable(value.namespace),
                        content: AnyView(value.destination),
                        onDismiss: { binding.wrappedValue = false }
                    )
                ])
            }
        outputs.preferences.append(
            NavigationDestinationsKey.self,
            node: preference.identifier
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

private struct ItemNavigationDestinationID: Hashable {
    var namespace: Namespace.ID
    var item: AnyHashable
}

struct ItemBoundNavigationDestinationModifier<Item, Destination>:
    ViewModifier, MultiViewModifier
where Item: Hashable, Destination: View {
    typealias Body = Never

    var item: Binding<Item?>
    var destination: (Item) -> Destination
    @Namespace private var namespace

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "ItemBoundNavigationDestinationModifier._makeView called "
                    + "outside an active _AGGraph context."
            )
        }
        var graphInputs = inputs.base
        let fields = DynamicPropertyCache.fields(of: Self.self)
        let propertyBuffer = _DynamicPropertyBuffer(
            fields: fields,
            container: modifier,
            inputs: &graphInputs
        )
        let resolvedModifier: Attribute<Self> = graph.makeRule {
            var value = modifier._attribute.value
            propertyBuffer.applyContexts(to: &value)
            return value
        }
        var inputs = inputs
        inputs.base = graphInputs
        var outputs = body(_Graph(), inputs)

        let preference: Attribute<ResolvedNavigationDestinations> =
            graph.makeRule {
                let value = resolvedModifier.value
                guard let item = value.item.wrappedValue else {
                    return ResolvedNavigationDestinations()
                }
                let binding = value.item
                return ResolvedNavigationDestinations(presentations: [
                    NavigationDestinationPresentation(
                        id: AnyHashable(ItemNavigationDestinationID(
                            namespace: value.namespace,
                            item: AnyHashable(item)
                        )),
                        content: AnyView(value.destination(item)),
                        onDismiss: { binding.wrappedValue = nil }
                    )
                ])
            }
        outputs.preferences.append(
            NavigationDestinationsKey.self,
            node: preference.identifier
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

extension View {
    public func navigationDestination<Data, Destination>(
        for data: Data.Type,
        @ViewBuilder destination: @escaping (Data) -> Destination
    ) -> some View where Data: Hashable, Destination: View {
        modifier(NavigationDestinationModifier(destination: destination))
    }

    public func navigationDestination<Destination>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: () -> Destination
    ) -> some View where Destination: View {
        modifier(ViewDestinationNavigationDestinationModifier(
            _isPresented: isPresented,
            destination: destination()
        ))
    }

    public func navigationDestination<Item, Destination>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View where Item: Hashable, Destination: View {
        modifier(ItemBoundNavigationDestinationModifier(
            item: item,
            destination: destination
        ))
    }
}
