//
//  File: PlatformItemLabel.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct PlatformItemLabelView<
    Flags: PlatformItemListFlags,
    Label: View,
    Content: View
>: View {
    var flags: Flags
    var label: Label
    var content: Content

    var body: some View {
        content
            .mergePlatformItems()
            .modifier(
                PlatformItemListGeneratingViewModifier<
                    Flags,
                    MergePlatformItemsView<
                        ModifiedContent<
                            Label,
                            PlatformItemListContentModifier
                        >
                    >
                >(
                    flags: Flags.self,
                    secondaryView: label
                        .modifier(PlatformItemListContentModifier())
                        .mergePlatformItems()
                )
            )
            .transformPlatformItemList(Flags.self) { list in
                guard list.items.count > 1 else {
                    return
                }
                var item = list.items[0]
                let secondary = list.items[1]
                item.label = secondary.label ?? secondary.text
                list.items = [item]
            }
    }
}

extension View {
    func mergePlatformItems() -> MergePlatformItemsView<Self> {
        MergePlatformItemsView(content: self)
    }

    func transformPlatformItemList<Flags: PlatformItemListFlags>(
        _ flags: Flags.Type,
        _ transform: @escaping (inout PlatformItemList) -> Void
    ) -> some View {
        modifier(
            PlatformItemListTransformModifier<Flags>(
                transform: transform
            )
        )
    }

    func platformItemLabel<
        Label: View,
        Flags: PlatformItemListFlags
    >(
        _ label: Label,
        flags: Flags
    ) -> some View {
        PlatformItemLabelView(
            flags: flags,
            label: label,
            content: self
        )
    }

    func platformItemHierarchicalLevel(_ level: Int) -> some View {
        transformPlatformItemList(LabelPlatformItemListFlags.self) { list in
            list.modify { item in
                item.hierarchicalLevel = level
            }
        }
    }

    func platformItemTint(_ tint: Color?) -> some View {
        transformPlatformItemList(
            LayoutPlatformItemListFlags.self
        ) { list in
            list.modify { item in
                if item.tint == nil {
                    item.tint = tint
                }
            }
        }
    }

    func platformItemIdentifier(_ identifier: String) -> some View {
        transformPreference(PlatformItemList.Key.self) { list in
            list.modify { item in
                item.platformIdentifier = identifier
            }
        }
    }

    func onPlatformContainerSelection(
        _ action: (() -> Void)?,
        isMomentary: Bool
    ) -> some View {
        modifier(
            OnPlatformContainerSelectionModifier(
                action: action,
                isMomentary: isMomentary
            )
        )
    }

    private func secondaryPlatformItemListContent<
        Content: View,
        Flags: PlatformItemListFlags
    >(
        flags: Flags.Type,
        @ViewBuilder content: () -> Content,
        transform: @escaping (inout PlatformItemList) -> Void
    ) -> some View {
        modifier(
            PlatformItemListGeneratingViewModifier(
                flags: flags,
                secondaryView: content()
                    .modifier(PlatformItemListContentModifier())
                    .transformPreference(
                        PlatformItemList.Key.self,
                        transform
                    )
            )
        )
    }

    func platformItemChildren<Content: View>(
        systemItem: PlatformItemList.Item.SystemItem?,
        primaryAction: (() -> Void)?,
        menuIndicatorVisibility: Visibility,
        controlSize: ControlSize,
        @ViewBuilder children: () -> Content
    ) -> some View {
        secondaryPlatformItemListContent(
            flags: SelectionPlatformItemListFlags.self,
            content: children
        ) { list in
            var item = PlatformItemList.Item()
            item.systemItem = systemItem
            item.children = list
            item.menuIndicatorVisibility = menuIndicatorVisibility
            item.controlSize = controlSize
            list.items = [item]
        }
        .onPlatformContainerSelection(
            primaryAction,
            isMomentary: true
        )
    }
}

extension _ViewOutputs {
    mutating func writePlatformItemList(
        inputs: _ViewInputs,
        value: Attribute<PlatformItemList>
    ) {
        guard inputs.preferences.keys.contains(PlatformItemList.Key.self) else {
            return
        }
        preferences.append(
            PlatformItemList.Key.self,
            node: value.identifier
        )
    }

    mutating func transformPlatformItemList(
        inputs: _ViewInputs,
        transform: Attribute<(inout PlatformItemList) -> Void>
    ) {
        guard _AGGraph.current != nil else {
            fatalError(
                "_ViewOutputs.transformPlatformItemList "
                    + "called outside AG context"
            )
        }
        guard inputs.preferences.keys.contains(PlatformItemList.Key.self) else {
            return
        }
        preferences.makePreferenceTransformer(
            inputs: inputs.preferences,
            key: PlatformItemList.Key.self,
            transform: transform
        )
    }
}

