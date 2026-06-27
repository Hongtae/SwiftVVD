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

func diagnose(_ message: String, on node: some SyntaxProtocol, in context: some MacroExpansionContext) {
    context.diagnose(Diagnostic(node: Syntax(node), message: MacroDiagnostic(message)))
}
