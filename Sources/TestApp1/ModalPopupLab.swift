import Foundation
import VUI

private struct ModalLabFileItem: Identifiable {
    let id: Int
    let name: String
    let size: String
}

private struct ModalLabError: LocalizedError {
    let errorDescription: String?
    let failureReason: String?
    let recoverySuggestion: String?
}

struct ModalPopupLabSheet: View {
    let onClose: () -> Void

    @Environment(\.modalSessionUsingPlatformWindow)
    private var currentSheetUsesPlatformWindow

    @State private var usesPlatformPresentationWindows = true
    @State private var showNestedSheet = false
    @State private var showAlert = false
    @State private var showDataAlert = false
    @State private var showErrorAlert = false
    @State private var selectedFile: ModalLabFileItem?
    @State private var currentError: ModalLabError?
    @State private var result = ""

    private var childPresentationsUsePlatformWindows: Bool {
        currentSheetUsesPlatformWindow && usesPlatformPresentationWindows
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Modals & Popups")
                .font(.system(size: 22, weight: .semibold))

            Text("These controls exercise presentation from inside a category sheet.")
                .font(.system(.callout))
                .foregroundColor(.secondary)

            Toggle(
                "Open Presentations in Platform Windows",
                isOn: Binding(
                    get: { childPresentationsUsePlatformWindows },
                    set: { usesPlatformPresentationWindows = $0 }
                )
            )
            .environment(\.isEnabled, currentSheetUsesPlatformWindow)

            Button("Open Nested Sheet") {
                showNestedSheet = true
            }

            HStack(spacing: 10) {
                Button("Alert") {
                    showAlert = true
                }
                Button("Data Alert") {
                    selectedFile = ModalLabFileItem(
                        id: 1,
                        name: "document.pdf",
                        size: "2.4 MB"
                    )
                    showDataAlert = true
                }
                Button("Error Alert") {
                    currentError = ModalLabError(
                        errorDescription: "Connection Failed",
                        failureReason: "The server is unreachable.",
                        recoverySuggestion: "Check your network and try again."
                    )
                    showErrorAlert = true
                }
            }

            Text("Result: \(result.isEmpty ? "none" : result)")
                .font(.system(.caption))
                .foregroundColor(.secondary)

            Button("Close Category") {
                onClose()
            }
        }
        .padding(20)
        .frame(width: 520, height: 300)
        .sheet(isPresented: $showNestedSheet) {
            VStack(spacing: 12) {
                Text("Nested Sheet")
                    .font(.system(.headline))
                Button("Close") {
                    showNestedSheet = false
                }
            }
            .padding(20)
            .frame(width: 320, height: 160)
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            childPresentationsUsePlatformWindows
        )
        .alert("Delete Item?", isPresented: $showAlert) {
            Button("Delete", role: .destructive) { result = "deleted" }
            Button("Cancel", role: .cancel) { result = "cancelled" }
        } message: {
            Text("This action cannot be undone.")
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            childPresentationsUsePlatformWindows
        )
        .alert("Delete File?", isPresented: $showDataAlert, presenting: selectedFile) { file in
            Button("Delete \(file.name)", role: .destructive) {
                result = "deleted: \(file.name)"
                selectedFile = nil
            }
            Button("Cancel", role: .cancel) {
                result = "cancelled"
                selectedFile = nil
            }
        } message: { file in
            Text("\(file.name) (\(file.size)) will be permanently removed.")
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            childPresentationsUsePlatformWindows
        )
        .alert(isPresented: $showErrorAlert, error: currentError) {
            Button("Retry") { result = "retried" }
            Button("Cancel", role: .cancel) { result = "error cancelled" }
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            childPresentationsUsePlatformWindows
        )
    }
}
