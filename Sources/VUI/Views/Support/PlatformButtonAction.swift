//
//  File: PlatformButtonAction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct OnPlatformContainerSelectionModifier: ViewModifier {
    var action: (() -> Void)?
    var isMomentary: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.keyboardShortcut) private var shortcut
    @Environment(\.springLoadingBehavior) private var springLoadingBehavior

    func body(content: Content) -> some View {
        content
            .mergePlatformItems()
            .transformPlatformItemList(
                SelectionPlatformItemListFlags.self
            ) { list in
                precondition(
                    list.items.count == 1,
                    "OnPlatformContainerSelectionModifier requires one item."
                )
                guard let action else {
                    return
                }
                list.modify { item in
                    item.selectionBehavior = PlatformItemList.Item
                        .SelectionBehavior(
                            isMomentary: isMomentary,
                            isContainerSelection: true,
                            yieldsToContainerSelection: false,
                            isPickerOption: false,
                            visualStyle: .plain,
                            onSelect: isEnabled ? action : nil,
                            onDeselect: nil,
                            springLoadingBehavior:
                                springLoadingBehavior
                        )
                    item.isEnabled = isEnabled
                    item.keyboardShortcut = shortcut
                }
            }
    }
}

struct PlatformButtonActionTransform:
    UnaryPlatformItemsModifier,
    UnaryViewModifier
{
    typealias Body = Never

    var selection: PlatformItem.SelectionContent

    struct SelectionContent: Rule {
        var _action: Attribute<(() -> Void)?>
        var _isEnabled: Attribute<Bool>
        var _springLoadingBehavior:
            Attribute<SpringLoadingBehavior>

        var value: PlatformItem.SelectionContent {
            var options: PlatformItem.SelectionContent.Options = []
            if _isEnabled.value {
                options.insert(.isEnabled)
            }
            if _springLoadingBehavior.value == .enabled {
                options.insert(.isSpringLoaded)
            }
            return .selection(
                onSelect: _action,
                onDeselect: nil,
                options: options,
                auxiliaryContent: nil
            )
        }
    }

    struct MakeTransform: Rule {
        var _selection: Attribute<PlatformItem.SelectionContent>

        var value: PlatformButtonActionTransform {
            PlatformButtonActionTransform(
                selection: _selection.value
            )
        }
    }

    static var features: PlatformItem.Features {
        .selection
    }

    static func updateItem(
        modifier: Self,
        item: inout PlatformItem
    ) {
        item.selection = modifier.selection
        item.features.insert(.selection)
    }
}

private extension CachedEnvironment.ID {
    static let platformItemIsEnabled = Self(base: UniqueID())
    static let platformItemSpringLoadingBehavior =
        Self(base: UniqueID())
}

struct PlatformButtonActionModifier: ViewModifier, UnaryViewModifier {
    typealias Body = Never

    var action: (() -> Void)?

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        var outputs = body(_Graph(), inputs)
        guard inputs.requestsPlatformItem(for: .selection) else {
            return outputs
        }
        guard let graph = _AGGraph.current else {
            fatalError(
                "PlatformButtonActionModifier called outside an active graph."
            )
        }

        let cacheBox = inputs.base.cachedEnvironment
        var cache = cacheBox.value
        let isEnabled = cache.attribute(
            id: .platformItemIsEnabled,
            \.isEnabled
        )
        let springLoadingBehavior = cache.attribute(
            id: .platformItemSpringLoadingBehavior,
            \.springLoadingBehavior
        )
        cacheBox.value = cache

        let selection = graph.makeRule(
            PlatformButtonActionTransform.SelectionContent(
                _action: modifier[\.action]._attribute,
                _isEnabled: isEnabled,
                _springLoadingBehavior: springLoadingBehavior
            )
        )
        let transform = graph.makeRule(
            PlatformButtonActionTransform.MakeTransform(
                _selection: selection
            )
        )
        PlatformButtonActionTransform
            .transformPlatformItemsOutputs(
                &outputs,
                inputs: inputs,
                modifier: _GraphValue(_attribute: transform)
            )
        return outputs
    }
}

