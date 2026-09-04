import Foundation
import VUI

struct TextInputLabSheet: View {
    let close: () -> Void

    @State private var primaryText = ""
    @State private var primarySelection: TextSelection?
    @State private var secondaryText = "Second field"
    @State private var secureText = "A😀e\u{301}한"
    @State private var enclosesCompositionText = true
    @State private var usesIBeamCursor = true
    @State private var clipboardStatus = "Clipboard has not been tested yet."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Text Input")
                .font(.system(size: 22, weight: .semibold))

            Text(
                "Click a field, then test direct Latin input and an IME "
                    + "composition such as Korean, Chinese, or Japanese."
            )
            .font(.system(.callout))
            .foregroundColor(.secondary)

            Toggle(
                "Enclose composition text",
                isOn: $enclosesCompositionText
            )

            Toggle(
                "Use I-beam cursor for text fields",
                isOn: $usesIBeamCursor
            )

            TextField(
                "Type with a direct keyboard or IME",
                text: $primaryText,
                selection: $primarySelection
            )
            .frame(width: 420)

            Text("Committed value: \(primaryText)")
                .font(.system(.caption))

            HStack {
                Button("Copy") {
                    copyPrimaryText()
                }
                Button("Paste") {
                    pasteIntoPrimaryText()
                }
                Text(clipboardStatus)
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }

            Divider()

            TextField("Click to transfer focus", text: $secondaryText)
                .frame(width: 420)

            Text("Second value: \(secondaryText)")
                .font(.system(.caption))

            Divider()

            SecureField(
                "Protected input",
                text: $secureText,
                prompt: Text("Copy and Cut should stay disabled")
            )
            .frame(width: 420)

            Text(
                "Protected value: \(secureText.count) characters, "
                    + "\(secureText.utf16.count) UTF-16 units"
            )
            .font(.system(.caption))
            .foregroundColor(.secondary)

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    close()
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 540)
        .environment(\.isTextFieldCursorEnabled, usesIBeamCursor)
        .textFieldCompositionCaretStyle(
            enclosesCompositionText ? .enclosing : .insertionPoint
        )
    }

    private func copyPrimaryText() {
        guard let clipboard = TestApp1.clipboard else {
            clipboardStatus = "Clipboard is unavailable."
            return
        }
        do {
            let data = Data(primaryText.utf8)
            try clipboard.setData(
                data,
                forType: ClipboardContentType.utf8PlainText
            )
            clipboardStatus = "Copied \(data.count) UTF-8 bytes."
        } catch {
            clipboardStatus = "Copy failed: \(error)"
        }
    }

    private func pasteIntoPrimaryText() {
        guard let clipboard = TestApp1.clipboard else {
            clipboardStatus = "Clipboard is unavailable."
            return
        }
        do {
            guard let data = try clipboard.data(
                forType: ClipboardContentType.utf8PlainText
            ) else {
                clipboardStatus = "The clipboard has no plain text."
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                clipboardStatus = "Clipboard text is not valid UTF-8."
                return
            }
            primaryText = text
            primarySelection = TextSelection(insertionPoint: text.endIndex)
            clipboardStatus = "Pasted \(data.count) UTF-8 bytes."
        } catch {
            clipboardStatus = "Paste failed: \(error)"
        }
    }
}
