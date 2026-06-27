import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

private struct EntryProperty {
    var name: String
    var typeAnnotation: TypeAnnotationSyntax?
    var initializer: InitializerClauseSyntax
}

private func entryProperty(
    in declaration: some DeclSyntaxProtocol,
    node: AttributeSyntax,
    context: some MacroExpansionContext
) -> EntryProperty? {
    guard let variable = declaration.as(VariableDeclSyntax.self),
          variable.bindingSpecifier.text == "var",
          variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
        diagnose("'@Entry' can only be applied to a stored property.", on: node, in: context)
        return nil
    }

    guard binding.accessorBlock == nil else {
        diagnose("'@Entry' can only be applied to a stored property.", on: node, in: context)
        return nil
    }

    guard let initializer = binding.initializer else {
        diagnose("Property missing a default value.", on: node, in: context)
        return nil
    }

    return EntryProperty(
        name: pattern.identifier.text,
        typeAnnotation: binding.typeAnnotation,
        initializer: initializer
    )
}

private func entryKeyProtocol(in context: some MacroExpansionContext) -> String? {
    for syntax in context.lexicalContext.reversed() {
        guard let extensionDecl = syntax.as(ExtensionDeclSyntax.self) else {
            continue
        }

        let extendedType = extensionDecl.extendedType.trimmedDescription
        switch extendedType {
        case "EnvironmentValues", "VUI.EnvironmentValues":
            return "VUI.EnvironmentKey"
        case "Transaction", "VUI.Transaction":
            return "VUI.TransactionKey"
        case "ContainerValues", "VUI.ContainerValues":
            return "VUI.ContainerValueKey"
        case "FocusedValues", "VUI.FocusedValues":
            return nil
        default:
            continue
        }
    }

    return nil
}

public struct EntryMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let property = entryProperty(in: declaration, node: node, context: context) else {
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
        guard let property = entryProperty(in: declaration, node: node, context: context) else {
            return []
        }

        guard let keyProtocol = entryKeyProtocol(in: context) else {
            diagnose(
                "'@Entry' macro can only attach to var declarations inside extensions of EnvironmentValues, Transaction, ContainerValues, or FocusedValues.",
                on: node,
                in: context
            )
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
            diagnose("'@__EntryDefaultValue' requires an initialized property.", on: node, in: context)
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
