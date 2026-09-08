//
//  File: PlatformItemList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - PlatformItemList

// PlatformItemList shared by alert, confirmationDialog, contextMenu, and Menu.
struct PlatformItemList {
    struct Item {
        enum SystemItem: Sendable {
            case palette(effect: PaletteSelectionEffect)
            case divider
            case spacer
            case section
            case labelGroup
            case controlGroup
            case helpLink
            case button
            case menu
        }

        var text: NSAttributedString?
        var secondaryText: NSAttributedString?
        var platformIdentifier: String?
        var isExternal: Bool
        var hierarchicalLevel: Int
        var platformTag: Int?
        var allowsKeyEquivalentWhenHidden: Bool
        var isHidden: Bool
        var wantsPlatformInterfaceValidation: Bool
        // Retains target-dependent validation until the presentation surface
        // consumes the semantic item.
        var interfaceValidation: (() -> Bool)?
        var isAlternate: Bool
        var isAlternateDespiteNonMatchingKeyEquivalent: Bool
        var indentationLevel: Int
        var imageColorResolver: ImageColorResolver?
        var isEnabled: Bool
        var resolvedImage: ImageDrawing?
        var namedResolvedImage: Image?
        var systemItem: SystemItem?
        var selectionBehavior: SelectionBehavior?
        var keyboardShortcut: KeyboardShortcut?
        // Present only for framework commands resolved by the active preset.
        var builtInKeyBinding: KeyBindingID?
        var onHover: ((Bool) -> Void)?
        var buttonRole: ButtonRole?
        var label: NSAttributedString?
        var tooltip: String?
        var badge: String?
        var children: PlatformItemList?
        var labelGroupChildren: PlatformItemList?
        var menuIndicatorVisibility: Visibility?
        var controlSize: ControlSize?
        var toggleState: ToggleState?
        var commandOperation: CommandOperation?
        var textEditingCommand: TextEditingCommand?
        var textFormattingCommand: TextFormattingCommand?
        var scaleDownMenuImage: Bool
        var tint: Color?

        struct ImageColorResolver {
            var shapeStyle: AnyShapeStyle
        }

        struct SelectionBehavior: @unchecked Sendable {
            enum VisualStyle: Sendable {
                case plain
                case checkmark
                case selected
            }

            var isMomentary: Bool
            var isContainerSelection: Bool
            var yieldsToContainerSelection: Bool
            var isPickerOption: Bool
            var visualStyle: VisualStyle
            var onSelect: (() -> Void)?
            var onDeselect: (() -> Void)?
            var springLoadingBehavior: SpringLoadingBehavior
        }

        init() {
            text = nil
            secondaryText = nil
            platformIdentifier = nil
            isExternal = false
            hierarchicalLevel = -1
            platformTag = nil
            allowsKeyEquivalentWhenHidden = false
            isHidden = false
            wantsPlatformInterfaceValidation = false
            interfaceValidation = nil
            isAlternate = false
            isAlternateDespiteNonMatchingKeyEquivalent = false
            indentationLevel = 0
            imageColorResolver = nil
            isEnabled = true
            resolvedImage = nil
            namedResolvedImage = nil
            systemItem = nil
            selectionBehavior = nil
            keyboardShortcut = nil
            builtInKeyBinding = nil
            onHover = nil
            buttonRole = nil
            label = nil
            tooltip = nil
            badge = nil
            children = nil
            labelGroupChildren = nil
            menuIndicatorVisibility = nil
            controlSize = nil
            toggleState = nil
            commandOperation = nil
            textEditingCommand = nil
            textFormattingCommand = nil
            scaleDownMenuImage = false
            tint = nil
        }

        init(systemItem: SystemItem) {
            self.init()
            self.systemItem = systemItem
        }

        var isInterfaceEnabled: Bool {
            isEnabled && (interfaceValidation?() ?? true)
        }

        mutating func addInterfaceValidation(
            _ validation: @escaping () -> Bool
        ) {
            let previous = interfaceValidation
            interfaceValidation = {
                (previous?() ?? true) && validation()
            }
        }

        mutating func resolveInterfaceValidation() {
            guard let interfaceValidation else { return }
            isEnabled = isEnabled && interfaceValidation()
            self.interfaceValidation = nil
        }
    }

    var items: [Item] = []

    init(items: [Item] = []) {
        self.items = items
    }

    var flattenedItems: [Item] { items }
    var buttonItems: [Item] {
        items.filter { item in
            switch item.systemItem {
            case .button, .palette:
                true
            default:
                false
            }
        }
    }
    var menuItems: [Item] { items }
    var mergedContentItem: Item {
        guard items.count != 1 else {
            return items[0]
        }

        var result = Item()
        var previousHierarchicalLevel: Int?
        var groupedItems: [Item] = []

        for item in items {
            let belongsToLabelGroup =
                previousHierarchicalLevel.map {
                    $0 >= 0 && item.hierarchicalLevel == $0 + 1
                } == true
            previousHierarchicalLevel = item.hierarchicalLevel

            if belongsToLabelGroup {
                groupedItems.append(item)
                continue
            }

            if let text = item.text {
                if result.text == nil {
                    result.text = text
                } else if result.secondaryText == nil {
                    result.secondaryText = text
                }
            }
            if result.platformIdentifier == nil {
                result.platformIdentifier = item.platformIdentifier
            }
            if result.indentationLevel == 0 {
                result.indentationLevel = item.indentationLevel
            }
            if result.imageColorResolver == nil {
                result.imageColorResolver = item.imageColorResolver
            }
            if result.resolvedImage == nil {
                result.resolvedImage = item.resolvedImage
            }
            if result.namedResolvedImage == nil {
                result.namedResolvedImage = item.namedResolvedImage
            }
            if result.systemItem == nil {
                result.systemItem = item.systemItem
            }
            if result.buttonRole == nil {
                result.buttonRole = item.buttonRole
            }
            if result.label == nil {
                result.label = item.label
            }
            if result.tooltip == nil {
                result.tooltip = item.tooltip
            }
            if result.badge == nil {
                result.badge = item.badge
            }
            if result.children == nil {
                result.children = item.children
            }
            if result.labelGroupChildren == nil {
                result.labelGroupChildren = item.labelGroupChildren
            }
            if result.menuIndicatorVisibility == nil {
                result.menuIndicatorVisibility =
                    item.menuIndicatorVisibility
            }
            if result.controlSize == nil {
                result.controlSize = item.controlSize
            }
            if result.tint == nil {
                result.tint = item.tint
            }
        }

        if !groupedItems.isEmpty {
            result.systemItem = .labelGroup
            result.labelGroupChildren = PlatformItemList(items: groupedItems)
        }
        return result
    }

    mutating func append(_ item: Item) {
        items.append(item)
    }

    mutating func merge(_ other: PlatformItemList) {
        items.append(contentsOf: other.items)
    }

    mutating func modify(_ transform: (inout Item) -> Void) {
        for index in items.indices {
            transform(&items[index])
        }
    }

    mutating func resolveInterfaceValidation() {
        for index in items.indices {
            items[index].resolveInterfaceValidation()
            items[index].children?.resolveInterfaceValidation()
            items[index].labelGroupChildren?.resolveInterfaceValidation()
        }
    }

    struct Key: PreferenceKey {
        typealias Value = PlatformItemList
        static var defaultValue: PlatformItemList { PlatformItemList() }

        static func reduce(value: inout PlatformItemList, nextValue: () -> PlatformItemList) {
            value.merge(nextValue())
        }
    }
}

func platformItemText(_ item: PlatformItemList.Item) -> Text {
    guard let attributedString = item.label ?? item.text else {
        return Text("")
    }
    return Text(_attributedStringFromResolvedTextStorage(attributedString))
}
