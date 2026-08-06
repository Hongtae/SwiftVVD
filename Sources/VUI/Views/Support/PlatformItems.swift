//
//  File: PlatformItems.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct PlatformItem {
    struct Features: OptionSet {
        var rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        static let staticKind = Self(rawValue: 1 << 0)
        static let text = Self(rawValue: 1 << 1)
        static let image = Self(rawValue: 1 << 2)
        static let shape = Self(rawValue: 1 << 3)
        static let textStyle = Self(rawValue: 1 << 4)
        static let geometry = Self(rawValue: 1 << 5)
        static let selection = Self(rawValue: 1 << 6)
        static let secondaryText = Self(rawValue: 1 << 7)
        static let iconText = Self(rawValue: 1 << 8)
        static let children = Self(rawValue: 1 << 9)
        static let accessibility = Self(rawValue: 1 << 10)
        static let textAccessibility = Self(rawValue: 1 << 11)
        static let titleSubtitle: Self = [.text, .secondaryText]
    }

    struct SelectionContent {
        struct Options: OptionSet {
            var rawValue: Int

            init(rawValue: Int) {
                self.rawValue = rawValue
            }

            static let isEnabled = Self(rawValue: 1 << 0)
            static let isMomentary = Self(rawValue: 1 << 1)
            static let isSpringLoaded = Self(rawValue: 1 << 2)
            static let isNewDocumentButton = Self(rawValue: 1 << 3)
        }

        enum AuxiliaryContent {
            case documentCreationStrategy(Any)
        }

        var _onSelectAction: WeakAttribute<(() -> Void)?>?
        var _onDeselectAction: WeakAttribute<(() -> Void)?>?
        var options: Options
        var auxiliaryContent: AuxiliaryContent?

        static func selection(
            onSelect: Attribute<(() -> Void)?>?,
            onDeselect: Attribute<(() -> Void)?>?,
            options: Options,
            auxiliaryContent: AuxiliaryContent?
        ) -> Self {
            Self(
                _onSelectAction: onSelect.map(WeakAttribute.init),
                _onDeselectAction: onDeselect.map(WeakAttribute.init),
                options: options,
                auxiliaryContent: auxiliaryContent
            )
        }
    }

    var features: Features
    var seed: VersionSeed
    var selection: SelectionContent?

    static var empty: Self {
        Self(features: [], seed: .empty, selection: nil)
    }

    var hasContent: Bool {
        selection != nil
    }

    mutating func merge(_ other: Self) {
        features.formUnion(other.features)
        seed.merge(other.seed)
        if selection == nil {
            selection = other.selection
        }
    }
}

struct PlatformItems {
    struct Features: OptionSet {
        var rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        static let multipleItems = Self(rawValue: 1 << 0)
    }

    var features: Features
    var seed: VersionSeed
    var items: [PlatformItem]

    static func empty(features: Features) -> Self {
        Self(features: features, seed: .empty, items: [])
    }

    struct Key: PreferenceKey {
        static var defaultValue: PlatformItems {
            .empty(features: [])
        }

        static func reduce(
            value: inout PlatformItems,
            nextValue: () -> PlatformItems
        ) {
            let next = nextValue()
            if value.items.isEmpty {
                value = next
                return
            }
            if !value.features.contains(.multipleItems),
               value.items.count == 1,
               !value.items[0].hasContent,
               let nextItem = next.items.first {
                value.items[0].merge(nextItem)
                value.seed.merge(next.seed)
                return
            }
            value.seed.merge(next.seed)
            value.items.append(contentsOf: next.items)
        }
    }
}

private struct PlatformItemFeaturesKey: PropertyKey {
    static let defaultValue: PlatformItem.Features = []
}

extension _ViewInputs {
    var platformItemFeatures: PlatformItem.Features {
        get {
            customInputs.value(forKey: PlatformItemFeaturesKey.self)
        }
        set {
            customInputs.setValue(
                newValue,
                forKey: PlatformItemFeaturesKey.self
            )
        }
    }

    func requestsPlatformItem(
        for features: PlatformItem.Features
    ) -> Bool {
        preferences.keys.contains(PlatformItems.Key.self)
            && !platformItemFeatures.intersection(features).isEmpty
    }
}

protocol PlatformItemsModifier: ViewModifier {
    static var features: PlatformItem.Features { get }
    static func updateItems(
        modifier: Self,
        items: inout PlatformItems
    )
}

extension PlatformItemsModifier {
    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(_Graph(), inputs)
        transformPlatformItemsOutputs(
            &outputs,
            inputs: inputs,
            modifier: modifier
        )
        return outputs
    }

    static func transformPlatformItemsOutputs(
        _ outputs: inout _ViewOutputs,
        inputs: _ViewInputs,
        modifier: _GraphValue<Self>
    ) {
        guard inputs.preferences.keys.contains(PlatformItems.Key.self),
              !inputs.platformItemFeatures
                .intersection(features).isEmpty else {
            return
        }
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformItemsModifier called outside an active graph."
            )
        }
        let items = outputs.preferences.reducedValue(
            for: PlatformItems.Key.self,
            in: graph
        )
        let transformed: Attribute<PlatformItems> =
            graph.makeStatefulRule(
                PlatformItemsTransform(
                    _modifier: modifier._attribute,
                    _items: OptionalAttribute(items),
                    seed: 0
                )
            )
        outputs.preferences.setValue(
            transformed.identifier,
            for: PlatformItems.Key.self
        )
    }
}

protocol UnaryPlatformItemsModifier: PlatformItemsModifier {
    static func updateItem(
        modifier: Self,
        item: inout PlatformItem
    )
}

extension UnaryPlatformItemsModifier {
    static func updateItems(
        modifier: Self,
        items: inout PlatformItems
    ) {
        for index in items.items.indices {
            updateItem(
                modifier: modifier,
                item: &items.items[index]
            )
        }
    }
}

struct PlatformItemsTransform<Modifier: PlatformItemsModifier>:
    StatefulRule
{
    typealias Value = PlatformItems

    var _modifier: Attribute<Modifier>
    var _items: OptionalAttribute<PlatformItems>
    var seed: UInt32

    mutating func updateValue() {
        var items = _items.value ?? .empty(features: [])
        Modifier.updateItems(
            modifier: _modifier.value,
            items: &items
        )
        seed &+= 1
        items.seed.mergeValue(seed)
        for index in items.items.indices {
            items.items[index].seed.mergeValue(seed)
        }
        _AGGraph.setStatefulOutput(items)
    }
}

