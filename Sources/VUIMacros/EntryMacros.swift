//
//  File: EntryMacros.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

private struct EntryProperty {
    var name: String
    var typeAnnotation: TypeAnnotationSyntax?
    var initializer: InitializerClauseSyntax
}

private struct EntryBinding {
    var name: String
    var typeAnnotation: TypeAnnotationSyntax?
    var initializer: InitializerClauseSyntax?
    var accessorBlock: AccessorBlockSyntax?
    var staticModifier: DeclModifierSyntax?
}

private enum EntryTarget {
    case environment
    case transaction
    case container
    case focused
}

private func entryBinding(
    in declaration: some DeclSyntaxProtocol,
    node: AttributeSyntax,
    context: some MacroExpansionContext
) -> EntryBinding? {
    guard let variable = declaration.as(VariableDeclSyntax.self) else {
        diagnose("'@Entry' can only be applied to a 'var' declaration with a simple name", on: node, in: context)
        return nil
    }

    guard variable.bindingSpecifier.text == "var" else {
        diagnose("'@Entry' can only be applied to a 'var' declaration", on: node, in: context)
        if variable.bindingSpecifier.text == "let" {
            diagnose("Replace 'let' with 'var'", on: variable.bindingSpecifier, in: context, severity: .note)
        }
        return nil
    }

    guard variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
        diagnose("'@Entry' can only be applied to a 'var' declaration with a simple name", on: node, in: context)
        return nil
    }

    return EntryBinding(
        name: pattern.identifier.text,
        typeAnnotation: binding.typeAnnotation,
        initializer: binding.initializer,
        accessorBlock: binding.accessorBlock,
        staticModifier: variable.modifiers.first { $0.name.text == "static" }
    )
}

private func entryAccessorBinding(
    in declaration: some DeclSyntaxProtocol,
    node: AttributeSyntax,
    context: some MacroExpansionContext
) -> EntryBinding? {
    guard let binding = entryBinding(in: declaration, node: node, context: context) else {
        return nil
    }

    if let staticModifier = binding.staticModifier {
        diagnose("'@Entry' cannot be applied to a static member", on: staticModifier, in: context)
        diagnose("Remove 'static'", on: staticModifier, in: context, severity: .note)
        return nil
    }

    if let accessorBlock = binding.accessorBlock {
        diagnose(
            "'@Entry' can only be applied to a stored property",
            on: accessorBlock,
            in: context,
            fixIts: [
                removeFixIt("Remove '@Entry'", node: node, id: "remove-entry"),
            ]
        )
        return nil
    }

    return binding
}

private func entryPeerProperty(
    in declaration: some DeclSyntaxProtocol,
    node: AttributeSyntax,
    context: some MacroExpansionContext
) -> EntryProperty? {
    guard let binding = entryBinding(in: declaration, node: node, context: context) else {
        return nil
    }

    guard let initializer = binding.initializer else {
        diagnose("Property missing a default value", on: node, in: context)
        diagnose("Provide default value", on: node, in: context, severity: .note)
        return nil
    }

    return EntryProperty(
        name: binding.name,
        typeAnnotation: binding.typeAnnotation,
        initializer: initializer
    )
}

private func entryTarget(in context: some MacroExpansionContext) -> EntryTarget? {
    for syntax in context.lexicalContext.reversed() {
        guard let extensionDecl = syntax.as(ExtensionDeclSyntax.self) else {
            continue
        }

        let extendedType = extensionDecl.extendedType.trimmedDescription
        switch extendedType {
        case "EnvironmentValues", "VUI.EnvironmentValues":
            return .environment
        case "Transaction", "VUI.Transaction":
            return .transaction
        case "ContainerValues", "VUI.ContainerValues":
            return .container
        case "FocusedValues", "VUI.FocusedValues":
            return .focused
        default:
            continue
        }
    }

    return nil
}

private func entryKeyProtocol(for target: EntryTarget) -> String? {
    switch target {
    case .environment:
        return "VUI.EnvironmentKey"
    case .transaction:
        return "VUI.TransactionKey"
    case .container:
        return "VUI.ContainerValueKey"
    case .focused:
        return nil
    }
}

private func focusedEntryValueType(
    for property: EntryProperty,
    node: AttributeSyntax,
    context: some MacroExpansionContext
) -> String? {
    guard let typeAnnotation = property.typeAnnotation else {
        diagnose("Property missing a type annotation", on: node, in: context)
        diagnose("Add type annotation", on: node, in: context, severity: .note)
        return nil
    }

    guard let optionalType = typeAnnotation.type.as(OptionalTypeSyntax.self) else {
        diagnose(
            "custom 'FocusedValues' property must be Optional",
            on: typeAnnotation.type,
            in: context
        )
        diagnose("Change type to be Optional", on: typeAnnotation.type, in: context, severity: .note)
        return nil
    }

    if property.initializer.value.trimmedDescription != "nil" {
        diagnose(
            "default value for custom 'FocusedValues' property must be 'nil'",
            on: property.initializer.value,
            in: context
        )
        diagnose("Remove default value", on: property.initializer.value, in: context, severity: .note)
        diagnose("Change default value to 'nil'", on: property.initializer.value, in: context, severity: .note)
    }

    return optionalType.wrappedType.trimmedDescription
}

public struct EntryMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let property = entryAccessorBinding(in: declaration, node: node, context: context) else {
            return []
        }

        return [
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    self[__Key_\(property.name).self]
                }
                """
            ),
            AccessorDeclSyntax(stringLiteral:
                """
                set {
                    self[__Key_\(property.name).self] = newValue
                }
                """
            ),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let property = entryPeerProperty(in: declaration, node: node, context: context) else {
            return []
        }

        guard let target = entryTarget(in: context) else {
            diagnose(
                "'@Entry' macro can only attach to var declarations inside extensions of EnvironmentValues, Transaction, ContainerValues, or FocusedValues",
                on: node,
                in: context
            )
            return []
        }

        if target == .focused {
            guard let valueType = focusedEntryValueType(for: property, node: node, context: context) else {
                return []
            }

            return [
                DeclSyntax(stringLiteral:
                    """
                    private struct __Key_\(property.name): VUI.FocusedValueKey {
                        typealias Value = \(valueType)
                    }
                    """
                ),
            ]
        }

        guard let keyProtocol = entryKeyProtocol(for: target) else {
            return []
        }

        let typeAnnotation = property.typeAnnotation?.description ?? ""
        let initializer = property.initializer.value.description.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            DeclSyntax(stringLiteral:
                """
                private struct __Key_\(property.name): \(keyProtocol) {
                    @VUI.__EntryDefaultValue
                    static var defaultValue\(typeAnnotation) = \(initializer)
                }
                """
            ),
        ]
    }
}

public struct EntryDefaultValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              let binding = variable.bindings.first,
              let initializer = binding.initializer else {
            diagnose("'@__EntryDefaultValue' requires an initialized property", on: node, in: context)
            return []
        }

        let defaultValue = initializer.value.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    \(defaultValue)
                }
                """
            ),
        ]
    }
}
