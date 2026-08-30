import VUI

struct TextInputLabSheet: View {
    let close: () -> Void

    @State private var primaryText = ""
    @State private var primarySelection: TextSelection?
    @State private var secondaryText = "Second field"
    @State private var enclosesCompositionText = true

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

            TextField(
                "Type with a direct keyboard or IME",
                text: $primaryText,
                selection: $primarySelection
            )
            .frame(width: 420)

            Text("Committed value: \(primaryText)")
                .font(.system(.caption))

            Divider()

            TextField("Click to transfer focus", text: $secondaryText)
                .frame(width: 420)

            Text("Second value: \(secondaryText)")
                .font(.system(.caption))

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    close()
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 370)
        .textFieldCompositionCaretStyle(
            enclosesCompositionText ? .enclosing : .insertionPoint
        )
    }
}
