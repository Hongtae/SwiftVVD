//
//  File: AnimatableMacros.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private struct AnimatableMacroPayload: Codable {
    struct VarDecl: Codable {
        var name: String
        var line: String?
    }

    var fileName: String?
    var selfName: String
    var animatableDataName: String
    var varDecls: [VarDecl]
}

private struct AnimatableProperty {
    var name: String
    var fileName: String?
    var line: String?
}

private func hasAttribute(named name: String, in attributes: AttributeListSyntax) -> Bool {
    attributes.description.contains(name)
}

private func hasModifier(named name: String, in modifiers: DeclModifierListSyntax) -> Bool {
    modifiers.contains { $0.name.text == name }
}

private func isStoredBinding(_ binding: PatternBindingSyntax) -> Bool {
    switch binding.accessorBlock?.accessors {
    case .none:
        return true
    case .accessors(let accessors):
        return accessors.allSatisfy { accessor in
            switch accessor.accessorSpecifier.tokenKind {
            case .keyword(.willSet), .keyword(.didSet):
                return true
            default:
                return false
            }
        }
    case .getter:
        return false
    }
}

private func declarationAccessPrefix(for declaration: some DeclGroupSyntax) -> String {
    for modifier in declaration.modifiers {
        switch modifier.name.text {
        case "public", "open":
            return "public "
        case "private", "fileprivate":
            return "fileprivate "
        case "package":
            return "package "
        default:
            break
        }
    }
    return ""
}

private func animatableProperties(
    in declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> [AnimatableProperty] {
    declaration.memberBlock.members.flatMap { member -> [AnimatableProperty] in
        guard let variable = member.decl.as(VariableDeclSyntax.self),
              variable.bindingSpecifier.text == "var",
              !hasAttribute(named: "AnimatableIgnored", in: variable.attributes),
              !hasModifier(named: "lazy", in: variable.modifiers) else {
            return []
        }

        return variable.bindings.compactMap { binding in
            guard isStoredBinding(binding),
                  let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }
            let name = pattern.identifier.text
            guard name != "_" else { return nil }
            let location = context.location(
                of: binding.pattern,
                at: .afterLeadingTrivia,
                filePathMode: .fileID
            )
            return AnimatableProperty(
                name: name,
                fileName: location?.file.trimmedDescription,
                line: location?.line.trimmedDescription
            )
        }
    }
}

private func rawStringLiteralContents(_ expression: ExprSyntax) -> String? {
    if let literal = expression.as(StringLiteralExprSyntax.self) {
        var result = ""
        for segment in literal.segments {
            guard case .stringSegment(let stringSegment) = segment else {
                return nil
            }
            result += stringSegment.content.text
        }
        return result
    }

    let text = expression.description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let firstQuote = text.firstIndex(of: "\""),
          let lastQuote = text.lastIndex(of: "\""),
          firstQuote < lastQuote else {
        return nil
    }
    return String(text[text.index(after: firstQuote)..<lastQuote])
}

private func animatableMacroPayload(from node: some FreestandingMacroExpansionSyntax) -> AnimatableMacroPayload? {
    guard let argument = node.arguments.first(where: { $0.label?.text == "animatableMacroContext" }),
          let payloadString = rawStringLiteralContents(argument.expression),
          let payloadData = payloadString.data(using: .utf8) else {
        return nil
    }
    return try? JSONDecoder().decode(AnimatableMacroPayload.self, from: payloadData)
}

private func propertyNames(in declaration: some DeclSyntaxProtocol) -> [String] {
    guard let variable = declaration.as(VariableDeclSyntax.self),
          let binding = variable.bindings.first,
          let initializer = binding.initializer else {
        return []
    }

    let source = initializer.value.description
    guard let regex = try? NSRegularExpression(pattern: #"\\\.([A-Za-z_][A-Za-z0-9_]*)"#) else {
        return []
    }

    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    return regex.matches(in: source, range: range).compactMap { match in
        guard let nameRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        return String(source[nameRange])
    }
}

private func animatableValuesGetAccessor(for names: [String]) -> AccessorDeclSyntax {
    let arguments = names
        .map { "self[_animatableValue: \\.\($0)]" }
        .joined(separator: ",\n            ")

    return AccessorDeclSyntax(stringLiteral:
        """
        get {
            VUI.AnimatableValues(
                \(arguments)
            )
        }
        """
    )
}

private func animatableValuesSetAccessor(for names: [String]) -> AccessorDeclSyntax {
    let assignments = names.enumerated().map { index, name in
        let valuePath = names.count == 1 ? "newValue.value" : "newValue.value.\(index)"
        return "self[_animatableValue: \\.\(name)] = \(valuePath)"
    }.joined(separator: "\n        ")

    return AccessorDeclSyntax(stringLiteral:
        """
        set {
            \(assignments)
        }
        """
    )
}

private func animatablePairExpression(for names: ArraySlice<String>) -> String {
    guard let first = names.first else {
        return "VUI.EmptyAnimatableData()"
    }
    if names.count == 1 {
        return "self[_animatableValue: \\.\(first)]"
    }
    let remaining = names.dropFirst()
    return """
    VUI.AnimatablePair(
            self[_animatableValue: \\.\(first)],
            \(animatablePairExpression(for: remaining))
        )
    """
}

private func animatablePairGetAccessor(for names: [String]) -> AccessorDeclSyntax {
    AccessorDeclSyntax(stringLiteral:
        """
        get {
            \(animatablePairExpression(for: names[...]))
        }
        """
    )
}

private func animatablePairValuePath(for index: Int, count: Int) -> String {
    guard count > 1 else {
        return "newValue"
    }
    if index == 0 {
        return "newValue.first"
    }

    var components = Array(repeating: "second", count: index)
    if index < count - 1 {
        components.append("first")
    }
    return "newValue." + components.joined(separator: ".")
}

private func animatablePairSetAccessor(for names: [String]) -> AccessorDeclSyntax {
    let assignments = names.enumerated().map { index, name in
        "self[_animatableValue: \\.\(name)] = \(animatablePairValuePath(for: index, count: names.count))"
    }.joined(separator: "\n        ")

    return AccessorDeclSyntax(stringLiteral:
        """
        set {
            \(assignments)
        }
        """
    )
}

public struct AnimatableValuesMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let properties = animatableProperties(in: declaration, context: context)
        guard !properties.isEmpty else {
            diagnose(
                "'@Animatable' macro has no effect; it can only attach to types with animatable properties.",
                on: node,
                in: context,
                fixIts: [
                    removeFixIt("Remove '@Animatable'", node: node, id: "remove-animatable"),
                ]
            )
            return []
        }

        let storageName = context.makeUniqueName("_animatableData").text
        let payload = AnimatableMacroPayload(
            fileName: properties.first?.fileName,
            selfName: "Self",
            animatableDataName: storageName,
            varDecls: properties.map {
                AnimatableMacroPayload.VarDecl(name: $0.name, line: $0.line)
            }
        )
        let payloadData = try JSONEncoder().encode(payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        let accessPrefix = declarationAccessPrefix(for: declaration)

        return [
            DeclSyntax(stringLiteral:
                """
                #_SwiftUIAnimatableDataProperty(animatableMacroContext: #"\(payloadString)"#, kind: VUI._animatableMacroKind())

                \(accessPrefix)nonisolated var animatableData: some VUI.VectorArithmetic {
                    get {
                        \(storageName)
                    }
                    set {
                        nonisolated func inferType<T, U>(_ t: T) -> U {
                            t as! U
                        }
                        \(storageName) = inferType(newValue)
                    }
                }
                """
            ),
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        [
            try ExtensionDeclSyntax("extension \(raw: type.trimmedDescription): nonisolated VUI.Animatable {}"),
        ]
    }
}

public struct AnimatableIgnoredMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        []
    }
}

public struct AnimatableValuesDataPropertyMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let payload = animatableMacroPayload(from: node) else {
            diagnose("Invalid animatable macro context.", on: node, in: context)
            return []
        }

        let declarations = payload.varDecls.map { varDecl in
            let declaration = "let \(varDecl.name) = #_SwiftUIAnimatableProperty(\(payload.selfName)[_animatableType: \\.\(varDecl.name)])"
            guard let fileName = payload.fileName,
                  let line = varDecl.line else {
                return declaration
            }
            return """
            #sourceLocation(file: \(fileName), line: \(line))
            \(declaration)
            #sourceLocation()
            """
        }.joined(separator: "\n    ")
        let arguments = payload.varDecls.map(\.name).joined(separator: ", ")

        return [
            DeclSyntax(stringLiteral:
                """
                @VUI._AnimatableData
                private nonisolated var \(payload.animatableDataName) = {
                    \(declarations)
                    return VUI.AnimatableValues(\(arguments))
                }()
                """
            ),
        ]
    }
}

public struct AnimatableValuesDataMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let names = propertyNames(in: declaration)
        guard !names.isEmpty else {
            diagnose(
                "'@_AnimatableData' macro did not discover any key paths to animated properties.",
                on: node,
                in: context
            )
            return []
        }

        return [
            animatableValuesGetAccessor(for: names),
            animatableValuesSetAccessor(for: names),
        ]
    }
}

public struct AnimatablePairDataMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let names = propertyNames(in: declaration)
        guard !names.isEmpty else {
            diagnose(
                "'@_AnimatableData' macro did not discover any key paths to animated properties.",
                on: node,
                in: context
            )
            return []
        }

        return [
            animatablePairGetAccessor(for: names),
            animatablePairSetAccessor(for: names),
        ]
    }
}

public struct AnimatablePropertyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        node.arguments.first?.expression ?? ExprSyntax(stringLiteral: "VUI.EmptyAnimatableData.self")
    }
}

public struct InvalidAnimatablePropertyMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        diagnose(
            "Cannot automatically synthesize 'animatableData'.",
            on: node,
            in: context
        )
        diagnose("Mark this property with '@AnimatableIgnored'.", on: node, in: context, severity: .note)
        diagnose(
            "Conform the type of this property to 'Animatable' or 'VectorArithmetic'.",
            on: node,
            in: context,
            severity: .note
        )
        return ExprSyntax(stringLiteral: "VUI.EmptyAnimatableData.self")
    }
}
