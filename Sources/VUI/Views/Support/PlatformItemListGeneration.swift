//
//  File: PlatformItemListGeneration.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - Platform-item inputs

struct PlatformItemListFlagsSet: OptionSet {
    var rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    enum EditOperation {
        case set
        case union
    }
}

protocol PlatformItemListFlags {
    static var flags: PlatformItemListFlagsSet { get }
}

struct AllPlatformItemListFlags: PlatformItemListFlags {
    static let flags = PlatformItemListFlagsSet(rawValue: .max)
}

struct TextPlatformItemListFlags: PlatformItemListFlags {
    static let flags = PlatformItemListFlagsSet(rawValue: 0x4)
}

struct SelectionPlatformItemListFlags: PlatformItemListFlags {
    static let flags = PlatformItemListFlagsSet(rawValue: 0x1)
}

struct LayoutPlatformItemListFlags: PlatformItemListFlags {
    static let flags = PlatformItemListFlagsSet(rawValue: 0x8)
}

struct LabelPlatformItemListFlags: PlatformItemListFlags {
    static let flags = PlatformItemListFlagsSet(rawValue: 0x16)
}

struct ActionPlatformItemListFlags: PlatformItemListFlags {
    static let flags = PlatformItemListFlagsSet(rawValue: 0xD)
}

struct PlatformItemListFlagsInput: ViewInput {
    static var defaultValue: PlatformItemListFlagsSet { [] }
}

struct IsPlatformItemListSourceInput: ViewInput {
    static var defaultValue: Bool { false }
}

extension _ViewInputs {
    var withoutGeometryDependencies: _ViewInputs {
        var inputs = self
        inputs.transform = intern(ViewTransform(), id: .defaultValue)
        let zeroPosition = intern(CGPoint.zero, id: .defaultValue)
        inputs.position = zeroPosition
        inputs.containerPosition = zeroPosition
        inputs.size = intern(ViewSize.zero, id: .defaultValue)
        inputs.base.options.remove([
            .viewRequestsLayoutComputer,
            .viewNeedsGeometry,
        ])
        inputs.preferences.keys.remove(DisplayList.Key.self)
        inputs.preferences.keys.remove(ViewRespondersKey.self)
        return inputs
    }

    mutating func addPlatformItemListKey<Flags: PlatformItemListFlags>(
        flags: Flags.Type,
        editOperation: PlatformItemListFlagsSet.EditOperation? = .set
    ) {
        preferences.add(PlatformItemList.Key.self)
        requestedTextRepresentation = PlatformItemListTextRepresentable.self
        requestedImageRepresentation =
            PlatformItemListImageRepresentable.self
        requestedNamedImageRepresentation =
            PlatformItemListNamedImageRepresentable.self
        requestedDividerRepresentation = PlatformItemListDividerRepresentable.self

        switch editOperation {
        case .set:
            self[PlatformItemListFlagsInput.self] = Flags.flags
        case .union:
            self[PlatformItemListFlagsInput.self].formUnion(Flags.flags)
        case nil:
            break
        }
    }
}

// MARK: - PlatformItemListGenerator

struct PlatformItemListGenerator<
    Flags: PlatformItemListFlags,
    Content: View
>: StatefulRule {
    typealias Value = PlatformItemList

    var subgraph: AGSubgraph
    var _content: Attribute<Content>
    var inputs: _ViewInputs
    var inputsIncludeGeometry: Bool
    var _itemList: OptionalAttribute<PlatformItemList>

    init(
        flags: Flags.Type,
        content: Attribute<Content>,
        inputs: _ViewInputs,
        inputsIncludeGeometry: Bool
    ) {
        guard let subgraph = AGSubgraph.current else {
            fatalError(
                "PlatformItemListGenerator.init requires a current AGSubgraph"
            )
        }
        self.subgraph = subgraph
        self._content = content
        self.inputs = inputs
        self.inputsIncludeGeometry = inputsIncludeGeometry
        self._itemList = OptionalAttribute()
    }

    var itemList: PlatformItemList? {
        _itemList.value
    }

    mutating func updateValue() {
        if !hasValue {
            let content = _content
            let storedInputs = inputs
            let includesGeometry = inputsIncludeGeometry
            let itemList = AGSubgraph.withCurrent(subgraph) {
                Self.makeItemList(
                    content: content,
                    inputs: storedInputs,
                    inputsIncludeGeometry: includesGeometry
                )
            }
            _itemList = itemList
        }
        _AGGraph.setStatefulOutput(itemList ?? PlatformItemList())
    }

    private static func makeItemList(
        content: Attribute<Content>,
        inputs: _ViewInputs,
        inputsIncludeGeometry: Bool
    ) -> OptionalAttribute<PlatformItemList> {
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemListGenerator.makeItemList "
                    + "called outside AG context"
            )
        }
        var inputs = inputs
        if inputsIncludeGeometry {
            inputs = inputs.withoutGeometryDependencies
            inputs.preferences = PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: inputs.intern(
                    PreferenceKeys(),
                    id: .defaultValue
                )
            )
        }
        inputs.addPlatformItemListKey(flags: Flags.self)
        inputs[IsPlatformItemListSourceInput.self] = true
        let outputs = Content._makeView(
            view: _GraphValue(_attribute: content),
            inputs: inputs
        )
        return OptionalAttribute(
            outputs.preferences.reducedValue(
                for: PlatformItemList.Key.self,
                in: graph
            )
        )
    }
}

extension PlatformItemListGenerator
where Flags == AllPlatformItemListFlags {
    init(
        content: Attribute<Content>,
        inputs: _ViewInputs,
        inputsIncludeGeometry: Bool
    ) {
        self.init(
            flags: AllPlatformItemListFlags.self,
            content: content,
            inputs: inputs,
            inputsIncludeGeometry: inputsIncludeGeometry
        )
    }
}

// MARK: - Platform-item preference views

struct PlatformItemListContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(width: 0, height: 0, alignment: .center)
    }
}

struct MergePlatformItemsView<Content: View>: View {
    var content: Content

    struct Transform: Rule {
        var _view: Attribute<MergePlatformItemsView>
        var _list: OptionalAttribute<PlatformItemList>

        var value: PlatformItemList {
            _ = _view.value
            guard let list = _list.value else {
                return PlatformItemList()
            }
            return PlatformItemList(items: [list.mergedContentItem])
        }
    }

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "MergePlatformItemsView._makeView called outside AG context"
            )
        }
        var outputs = Content._makeView(
            view: view[\.content],
            inputs: inputs
        )
        guard inputs.preferences.keys.contains(PlatformItemList.Key.self) else {
            return outputs
        }
        let list = outputs.preferences.reducedValue(
            for: PlatformItemList.Key.self,
            in: graph
        )
        let transformed = graph.makeRule(
            Transform(
                _view: view._attribute,
                _list: OptionalAttribute(list)
            )
        )
        outputs.preferences.setValue(
            transformed.identifier,
            for: PlatformItemList.Key.self
        )
        return outputs
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension MergePlatformItemsView: PrimitiveView {}

struct PlatformItemListGeneratingViewModifier<
    Flags: PlatformItemListFlags,
    SecondaryView: View
>: MultiViewModifier {
    typealias Body = Never

    var secondaryView: SecondaryView

    init(flags: Flags.Type, secondaryView: SecondaryView) {
        self.secondaryView = secondaryView
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var primaryInputs = inputs
        primaryInputs.base.pushStableIndex(0)
        var outputs = body(_Graph(), primaryInputs)

        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemListGeneratingViewModifier._makeView "
                    + "called outside AG context"
            )
        }
        guard inputs.preferences.keys.contains(PlatformItemList.Key.self),
              inputs[PlatformItemListFlagsInput.self]
                .isSuperset(of: Flags.flags) else {
            return outputs
        }

        var secondaryInputs = inputs.withoutGeometryDependencies
        secondaryInputs.base.pushStableIndex(1)
        let secondaryOutputs = SecondaryView._makeView(
            view: modifier[\.secondaryView],
            inputs: secondaryInputs
        )
        outputs.preferences = PreferencesOutputs.merge(
            [outputs.preferences, secondaryOutputs.preferences],
            in: graph
        )
        return outputs
    }
}

struct PlatformItemListTransformModifier<
    Flags: PlatformItemListFlags
>: MultiViewModifier {
    typealias Body = Never

    var transform: (inout PlatformItemList) -> Void

    struct Transform: Rule {
        var _modifier: Attribute<PlatformItemListTransformModifier>
        var _list: OptionalAttribute<PlatformItemList>

        var value: PlatformItemList {
            var list = _list.value ?? PlatformItemList()
            _modifier.value.transform(&list)
            return list
        }
    }

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(_Graph(), inputs)
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemListTransformModifier._makeView "
                    + "called outside AG context"
            )
        }
        guard inputs.preferences.keys.contains(PlatformItemList.Key.self),
              inputs[PlatformItemListFlagsInput.self]
                .isSuperset(of: Flags.flags) else {
            return outputs
        }
        let list = outputs.preferences.reducedValue(
            for: PlatformItemList.Key.self,
            in: graph
        )
        let transformed = graph.makeRule(
            Transform(
                _modifier: modifier._attribute,
                _list: OptionalAttribute(list)
            )
        )
        outputs.preferences.setValue(
            transformed.identifier,
            for: PlatformItemList.Key.self
        )
        return outputs
    }
}
