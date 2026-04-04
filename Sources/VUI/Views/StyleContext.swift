//
//  File: StyleContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// StyleContext — marker protocol for style context types.
// Context behavior is implemented directly on AnyStyleContextType using
// ObjectIdentifier-based tracking.
protocol StyleContext: Sendable {}

// Marker types — empty structs with no stored properties.
struct NoStyleContext: StyleContext {}
struct PlainListStyleContext: StyleContext {}
struct GroupedFormStyleContext: StyleContext {}
struct TableStyleContext: StyleContext {}
struct SidebarListStyleContext: StyleContext {}
struct InsetListStyleContext: StyleContext {}
struct BorderedListStyleContext: StyleContext {}
struct SystemPreferencesSidebarListStyleContext: StyleContext {}
struct TextInputSuggestionsContext: StyleContext {}
struct ToolbarStyleContext: StyleContext {}
struct SectionHeaderStyleContext: StyleContext {}
struct ListAccessoryBarStyleContext: StyleContext {}
struct SwipeActionsStyleContext: StyleContext {}
struct AccessibilityQuickActionStyleContext: StyleContext {}
struct AccessibilityRepresentableStyleContext: StyleContext {}

// Menu-related contexts (used by Menu; will be superseded when Menu is rewritten).
struct MenuStyleContext: StyleContext {}

// AnyStyleContextType — value type representing the current style context stack.
// Uses a Set<ObjectIdentifier> to track accepted context types:
//   - pushing(T) adds T's ObjectIdentifier to the set (union)
//   - acceptsTop(T) checks if T's ObjectIdentifier is in the set
struct AnyStyleContextType: Equatable {
    private var contextIDs: Set<ObjectIdentifier>

    fileprivate init(contextIDs: Set<ObjectIdentifier>) {
        self.contextIDs = contextIDs
    }

    static var defaultValue: AnyStyleContextType {
        AnyStyleContextType(contextIDs: [ObjectIdentifier(NoStyleContext.self)])
    }

    func acceptsTop(_ type: any StyleContext.Type) -> Bool {
        contextIDs.contains(ObjectIdentifier(type))
    }

    func pushing<T: StyleContext>(_ type: T.Type) -> AnyStyleContextType {
        var ids = contextIDs
        ids.insert(ObjectIdentifier(type))
        return AnyStyleContextType(contextIDs: ids)
    }

    func acceptsAny(_ types: [any StyleContext.Type]) -> Bool {
        types.contains { contextIDs.contains(ObjectIdentifier($0)) }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.contextIDs == rhs.contextIDs
    }
}

// StyleContextInput — PropertyKey storing the current AnyStyleContextType
// in _GraphInputs.customInputs.
struct StyleContextInput: PropertyKey {
    typealias Value = AnyStyleContextType
    static var defaultValue: AnyStyleContextType { .defaultValue }
    var description: String { "StyleContextInput" }
}

// Menu-related context management (retained until Menu is fully rewritten).
struct _SubmenuRegistration: @unchecked Sendable {
    var close: () -> Void
    var isHovered: () -> Bool
}

class MenuContext: @unchecked Sendable {
    var activeSubmenuRegistration: _SubmenuRegistration? = nil
}

private struct _MenuContextKey: EnvironmentKey {
    static let defaultValue: MenuContext? = nil
}

extension EnvironmentValues {
    var _menuContext: MenuContext? {
        get { self[_MenuContextKey.self] }
        set { self[_MenuContextKey.self] = newValue }
    }
}
