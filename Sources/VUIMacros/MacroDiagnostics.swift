//
//  File: MacroDiagnostics.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct MacroDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity

    init(_ message: String, id: String = "vui-macro", severity: DiagnosticSeverity = .error) {
        self.message = message
        self.diagnosticID = MessageID(domain: "VUIMacros", id: id)
        self.severity = severity
    }
}

struct MacroFixIt: FixItMessage {
    let message: String
    let fixItID: MessageID

    init(_ message: String, id: String = "vui-macro-fixit") {
        self.message = message
        self.fixItID = MessageID(domain: "VUIMacros", id: id)
    }
}

func diagnose(
    _ message: String,
    on node: some SyntaxProtocol,
    in context: some MacroExpansionContext,
    severity: DiagnosticSeverity = .error,
    fixIts: [FixIt] = []
) {
    context.diagnose(
        Diagnostic(
            node: Syntax(node),
            message: MacroDiagnostic(message, severity: severity),
            fixIts: fixIts
        )
    )
}

func removeFixIt(
    _ message: String,
    node: some SyntaxProtocol,
    id: String = "remove"
) -> FixIt {
    let syntax = Syntax(node)
    let removalRange = syntax.positionAfterSkippingLeadingTrivia..<syntax.endPositionBeforeTrailingTrivia
    return FixIt(
        message: MacroFixIt(message, id: id),
        changes: [
            .replaceText(range: removalRange, with: "", in: syntax.root),
        ]
    )
}
