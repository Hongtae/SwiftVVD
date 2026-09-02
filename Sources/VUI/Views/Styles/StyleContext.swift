//
//  File: StyleContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol StyleContextVisitor {
    mutating func visit<Context: StyleContext>(_ type: Context.Type)
}

protocol StyleContext {
    static func accepts<Context>(_ type: Context.Type, at index: Int) -> Bool
    static func acceptsAny<each Context: StyleContext>(
        _ types: repeat (each Context).Type
    ) -> Bool
    static func visitStyle<Visitor: StyleContextVisitor>(_ visitor: inout Visitor)
}

extension StyleContext {
    static func accepts<Context>(_ type: Context.Type, at index: Int) -> Bool {
        index == 0 && ObjectIdentifier(type) == ObjectIdentifier(Self.self)
    }

    static func acceptsAny<each Context: StyleContext>(
        _ types: repeat (each Context).Type
    ) -> Bool {
        for type in repeat each types {
            if accepts(type, at: 0) {
                return true
            }
        }
        return false
    }

    static func visitStyle<Visitor: StyleContextVisitor>(_ visitor: inout Visitor) {
        visitor.visit(Self.self)
    }
}

// Marker types: empty structs with no stored properties.
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

// Menu-related contexts retained until Menu is rewritten.
struct MenuStyleContext: StyleContext {}

struct ScrollViewStyleContext: StyleContext {}

struct SheetStyleContext: StyleContext {}

// AnyStyleContextType: value type representing the current style context stack.
// Uses a Set<ObjectIdentifier> for context membership:
//   - pushing(T) adds T's ObjectIdentifier to the set (union)
//   - acceptsTop(T) checks if T's ObjectIdentifier is in the set
// This gives the OR-logic behavior needed by style predicates.
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

// StyleContextInput: PropertyKey storing the current AnyStyleContextType
// in _GraphInputs.customInputs.
struct StyleContextInput: ViewInput {
    typealias Value = AnyStyleContextType
    static var defaultValue: AnyStyleContextType { .defaultValue }
    var description: String { "StyleContextInput" }
}

// Extends inherited context membership using T's type without storing a value.
struct StyleContextWriter<T: StyleContext>: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        let current = inputs.customInputs.value(forKey: StyleContextInput.self)
        let new = current.pushing(T.self)
        inputs.customInputs.setValue(new, forKey: StyleContextInput.self)
    }
}

// Resets inherited context membership to the default no-style context.
struct DefaultStyleContextWriter: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        inputs.customInputs.setValue(.defaultValue, forKey: StyleContextInput.self)
    }
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

// StyleContext static accessors for use in styleContext(_:) calls.
extension StyleContext where Self == SheetStyleContext {
    static var sheet: SheetStyleContext { SheetStyleContext() }
}

extension View {
    // styleContext(_:) pushes T into the StyleContextInput via StyleContextWriter<T>.
    // The context parameter value is unused at the call site. Only T.Type matters.
    func styleContext<T: StyleContext>(_ context: T) -> some View {
        modifier(StyleContextWriter<T>())
    }

    // input(_:) installs T through ViewInputFlagModifier<T>.
    // The concrete return type is ModifiedContent<Self, ViewInputFlagModifier<T>>.
    func input<T: ViewInputFlag>(_ type: T.Type) -> some View {
        modifier(ViewInputFlagModifier(flag: T()))
    }
}

extension EnvironmentValues {
    var _menuContext: MenuContext? {
        get { self[_MenuContextKey.self] }
        set { self[_MenuContextKey.self] = newValue }
    }
}
