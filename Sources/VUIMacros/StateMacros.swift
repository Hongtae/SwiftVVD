//
//  File: StateMacros.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

private struct StateMacroProperty {
    var name: String
    var type: String?
    var initializer: String?
    var hasExplicitInitializer: Bool
    var usesLazyStorage: Bool
    var isReferenceType: Bool
}

private func stateMacroArgument(
    from node: AttributeSyntax
) -> ExprSyntax? {
    guard case .argumentList(let arguments)? = node.arguments else {
        return nil
    }
    return arguments.first { argument in
        switch argument.label?.text {
        case "initialValue", "wrappedValue":
            return true
        default:
            return false
        }
    }?.expression
}

private func isOptionalType(_ type: TypeSyntax?) -> Bool {
    guard let type else { return false }
    if type.is(OptionalTypeSyntax.self) || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return true
    }
    guard let identifier = type.as(IdentifierTypeSyntax.self) else {
        return false
    }
    return identifier.name.text == "Optional"
}

private func stateMacroProperty(
    in declaration: some DeclSyntaxProtocol,
    node: AttributeSyntax,
    context: some MacroExpansionContext
) -> StateMacroProperty? {
    guard let variable = declaration.as(VariableDeclSyntax.self) else {
        diagnose("'@State' can only be applied to a 'var' declaration with a simple name", on: node, in: context)
        return nil
    }

    guard variable.bindingSpecifier.text == "var" else {
        diagnose("'@State' can only be applied to a 'var' declaration", on: node, in: context)
        if variable.bindingSpecifier.text == "let" {
            diagnose("Replace 'let' with 'var'", on: variable.bindingSpecifier, in: context, severity: .note)
        }
        return nil
    }

    guard variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
        diagnose("'@State' can only be applied to a 'var' declaration with a simple name", on: node, in: context)
        return nil
    }

    let type = binding.typeAnnotation?.type.trimmedDescription
    let declarationInitializer = binding.initializer?.value
    let macroInitializer = stateMacroArgument(from: node)
    let explicitInitializer = declarationInitializer ?? macroInitializer
    let hasExplicitInitializer = explicitInitializer != nil
    let implicitNil = explicitInitializer == nil && isOptionalType(binding.typeAnnotation?.type)
    let initializer = explicitInitializer?.trimmedDescription ?? (implicitNil ? "nil" : nil)
    let isPrivate = variable.modifiers.contains { $0.name.text == "private" }
    let isReferenceType = context.lexicalContext.contains { syntax in
        syntax.is(ClassDeclSyntax.self) || syntax.is(ActorDeclSyntax.self)
    }

    return StateMacroProperty(
        name: pattern.identifier.text,
        type: type,
        initializer: initializer,
        hasExplicitInitializer: hasExplicitInitializer,
        usesLazyStorage: isPrivate && initializer != nil,
        isReferenceType: isReferenceType
    )
}

private func declarationAccessPrefix(
    for declaration: some DeclSyntaxProtocol
) -> String {
    guard let variable = declaration.as(VariableDeclSyntax.self) else {
        return ""
    }
    for modifier in variable.modifiers {
        switch modifier.name.text {
        case "public", "package", "fileprivate", "private":
            return "\(modifier.name.text) "
        default:
            continue
        }
    }
    return ""
}

private func typedStateConstruction(
    type: String?,
    initializer: String
) -> String {
    if let type {
        return "VUI.State<\(type)>(initialValue: \(initializer))"
    }
    return "VUI.State(initialValue: \(initializer))"
}

private func lazyStorageExpression(
    type: String?,
    initializer: String
) -> String {
    if let type {
        return
            """
            VUI.State._makeStorage(({
                let value: \(type) = \(initializer)
                return value
            }))
            """
    }
    return
        """
        VUI.State._makeStorage({
            \(initializer)
        })
        """
}

private func eagerStorageExpression(
    type: String?,
    initializer: String
) -> String {
    if let type {
        return
            """
            VUI.State._makeStorage(initialValue: {
                let value: \(type) = \(initializer)
                return value
            }())
            """
    }
    return "VUI.State._makeStorage(initialValue: \(initializer))"
}

private func encodedStateMacroPayload(_ source: String) -> String {
    Data(source.utf8).base64EncodedString()
}

private func rawStringLiteralContents(_ expression: ExprSyntax) -> String? {
    guard let literal = expression.as(StringLiteralExprSyntax.self) else {
        return nil
    }
    var result = ""
    for segment in literal.segments {
        guard case .stringSegment(let stringSegment) = segment else {
            return nil
        }
        result += stringSegment.content.text
    }
    return result
}

private func decodedStateMacroPayload(from node: AttributeSyntax) -> String? {
    guard case .argumentList(let arguments)? = node.arguments,
          let expression = arguments.first?.expression,
          let encoded = rawStringLiteralContents(expression),
          let data = Data(base64Encoded: encoded) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func identifierName(
    in declaration: some DeclSyntaxProtocol
) -> String? {
    guard let variable = declaration.as(VariableDeclSyntax.self),
          variable.bindings.count == 1,
          let binding = variable.bindings.first,
          let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
        return nil
    }
    return pattern.identifier.text
}

public struct StateMacro: AccessorMacro, PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let property = stateMacroProperty(
            in: declaration,
            node: node,
            context: context
        ) else {
            return []
        }

        let storageName = property.usesLazyStorage
            ? "__\(property.name)"
            : "_\(property.name)"
        let initialStorage = property.usesLazyStorage
            ? "VUI.State._makeStorage(initialValue: initialValue)"
            : "VUI.State(initialValue: initialValue)"
        var accessors: [AccessorDeclSyntax] = []
        if !property.hasExplicitInitializer {
            accessors.append(
                AccessorDeclSyntax(stringLiteral:
                    """
                    @storageRestrictions(initializes: \(storageName))
                    init(initialValue) {
                        \(storageName) = \(initialStorage)
                    }
                    """
                )
            )
        }
        accessors.append(
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    \(storageName).wrappedValue
                }
                """
            )
        )
        let setterSpecifier = property.isReferenceType ? "set" : "nonmutating set"
        accessors.append(
            AccessorDeclSyntax(stringLiteral:
                """
                \(setterSpecifier) {
                    \(storageName).wrappedValue = newValue
                }
                """
            )
        )
        return accessors
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let property = stateMacroProperty(
            in: declaration,
            node: node,
            context: context
        ) else {
            return []
        }

        let access = declarationAccessPrefix(for: declaration)
        if property.usesLazyStorage, let initializer = property.initializer {
            let storageAccess = property.isReferenceType ? "" : "private "
            let initialStorageName = context.makeUniqueName("_initialStoredValue_").text
            let lazyStorage = lazyStorageExpression(
                type: property.type,
                initializer: initializer
            )
            let eagerStorage = eagerStorageExpression(
                type: property.type,
                initializer: initializer
            )
            let wrapper = typedStateConstruction(
                type: property.type,
                initializer: initializer
            )
            let encodedName = encodedStateMacroPayload(initialStorageName)
            let encodedStorage = encodedStateMacroPayload(lazyStorage)

            return [
                DeclSyntax(stringLiteral:
                    """
                    \(storageAccess)var __\(property.name) = \(lazyStorage)
                    """
                ),
                DeclSyntax(stringLiteral:
                    """
                    @VUI._StatePropertyWrapperStorage(initialValue: "\(encodedName)")
                    \(storageAccess)var _\(property.name): VUI.State<_>! = VUI._stateNil(of: {
                        \(wrapper)
                    })
                    """
                ),
                DeclSyntax(stringLiteral:
                    """
                    @VUI._StateProjectedValue
                    \(access)var $\(property.name) = \(wrapper).projectedValue
                    """
                ),
                DeclSyntax(stringLiteral:
                    """
                    @VUI._StateInitialStoredValue("\(encodedStorage)")
                    private static var \(initialStorageName) = (\(eagerStorage))
                    """
                ),
            ]
        }

        guard let initializer = property.initializer else {
            guard let type = property.type else {
                return []
            }
            return [
                DeclSyntax(stringLiteral:
                    """
                    private var _\(property.name): VUI.State<\(type)>
                    """
                ),
                DeclSyntax(stringLiteral:
                    """
                    \(access)var $\(property.name): VUI.Binding<\(type)> {
                        _\(property.name).projectedValue
                    }
                    """
                ),
            ]
        }

        let wrapper = typedStateConstruction(
            type: property.type,
            initializer: initializer
        )
        return [
            DeclSyntax(stringLiteral:
                """
                private var _\(property.name) = \(wrapper)
                """
            ),
            DeclSyntax(stringLiteral:
                """
                @VUI._PropertyWrapperProjectedValue
                \(access)var $\(property.name) = \(wrapper).projectedValue
                """
            ),
        ]
    }
}

public struct StatePropertyWrapperStorageMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let storageProperty = identifierName(in: declaration),
              storageProperty.hasPrefix("_"),
              let initialStorageName = decodedStateMacroPayload(from: node) else {
            diagnose("Invalid State property-wrapper storage.", on: node, in: context)
            return []
        }
        let propertyName = String(storageProperty.dropFirst())
        let lazyStorageName = "__\(propertyName)"

        return [
            AccessorDeclSyntax(stringLiteral:
                """
                @storageRestrictions(initializes: \(lazyStorageName))
                init(initialValue) {
                    if initialValue == nil {
                        \(lazyStorageName) = Self.\(initialStorageName)
                    } else {
                        \(lazyStorageName) = VUI.State._makeStorage(initialValue: initialValue.wrappedValue)
                    }
                }
                """
            ),
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    VUI.State(initialValue: \(lazyStorageName).wrappedValue)
                }
                """
            ),
            AccessorDeclSyntax(stringLiteral:
                """
                set {
                    if newValue != nil {
                        \(lazyStorageName) = VUI.State._makeStorage(initialValue: newValue.wrappedValue)
                    }
                }
                """
            ),
        ]
    }
}

public struct StateInitialStoredValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let storage = decodedStateMacroPayload(from: node) else {
            diagnose("Invalid State initial-storage expression.", on: node, in: context)
            return []
        }
        return [
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    \(storage)
                }
                """
            ),
        ]
    }
}

public struct StateProjectedValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let projectedProperty = identifierName(in: declaration),
              projectedProperty.hasPrefix("$") else {
            diagnose("Invalid State projected-value property.", on: node, in: context)
            return []
        }
        let propertyName = String(projectedProperty.dropFirst())
        return [
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    __\(propertyName).projectedValue
                }
                """
            ),
        ]
    }
}

public struct ProjectedValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let projectedProperty = identifierName(in: declaration),
              projectedProperty.hasPrefix("$") else {
            diagnose("Invalid projected-value property.", on: node, in: context)
            return []
        }
        let propertyName = String(projectedProperty.dropFirst())
        return [
            AccessorDeclSyntax(stringLiteral:
                """
                get {
                    _\(propertyName).projectedValue
                }
                """
            ),
        ]
    }
}
