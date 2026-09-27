import Foundation
import VUI

private enum LabCategory: Int, Identifiable {
    case contextMenus
    case modalsAndPopups
    case animation
    case symbolEffects
    case keyframeAndPhase
    case matchedGeometry
    case contentTransition
    case timeline
    case visualAndMesh
    case customAnimation
    case images
    case textVariants
    case textInput
    case scrollView
    case scrollViewReader
    case splitView

    var id: Int { rawValue }
}

private struct SampleFileItem: Identifiable {
    let id: Int
    let name: String
    let size: String
}

private struct SampleLocalizedError: LocalizedError {
    let errorDescription: String?
    let failureReason: String?
    let recoverySuggestion: String?
}

struct ContentView: View {
    @State private var contentScaleFactorOverride: CGFloat?
    @State private var usesVectorFontRendering = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\._contentScaleFactorOverride)
    private var setContentScaleFactorOverride

    @State private var settingsPresented = false
    @State private var selectedCategory: LabCategory? =
        ProcessInfo.processInfo.environment["VUI_ANIMATION_TRACE_SCENARIO"] != nil
            ? .animation
            : ProcessInfo.processInfo.environment["VUI_SCROLL_READER_SMOKE"] != nil
                ? .scrollViewReader
                : nil
    // Each child presentation keeps its own policy when the lab has a platform
    // window; overlay labs force descendants through the overlay fallback.
    @State private var usesPlatformPresentationWindows = true

    // Keep these presentations attached to the top-level view. Moving every
    // sample into a category sheet would hide top-level presentation regressions.
    @State private var topLevelSheetPresented = false
    @State private var showAlert = false
    @State private var showDataAlert = false
    @State private var showErrorAlert = false
    @State private var selectedFile: SampleFileItem?
    @State private var currentError: SampleLocalizedError?
    @State private var alertResult = ""

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Text("TestApp1 Labs")
                    .font(.system(size: 24, weight: .semibold))

                HStack {
                    Spacer()
                    Button("Settings", systemImage: "settings") {
                        settingsPresented = true
                    }
                }
            }
            .frame(width: 632)

            Text("Open a focused smoke surface. New parity work can add another category here.")
                .font(.system(.callout))
                .foregroundColor(.secondary)

            VStack(spacing: 10) {
                Text("Animation Comparison")
                    .font(.system(.headline))

                HStack(spacing: 10) {
                    categoryButton("Animation Lab", category: .animation, width: 145)
                    categoryButton("Symbol Effects", category: .symbolEffects, width: 145)
                    categoryButton("Keyframe & Phase", category: .keyframeAndPhase, width: 145)
                    categoryButton("Matched Geometry", category: .matchedGeometry, width: 145)
                }
                HStack(spacing: 10) {
                    categoryButton("Content Transition", category: .contentTransition, width: 145)
                    categoryButton("Timeline", category: .timeline, width: 145)
                    categoryButton("Visual Effect & Mesh", category: .visualAndMesh, width: 145)
                    categoryButton("Custom Animation", category: .customAnimation, width: 145)
                }

                Text("Other Labs")
                    .font(.system(.headline))

                HStack(spacing: 10) {
                    categoryButton("Context Menus", category: .contextMenus, width: 145)
                    categoryButton("Modals & Popups", category: .modalsAndPopups, width: 145)
                    categoryButton("Images", category: .images, width: 145)
                    categoryButton("Text Variants", category: .textVariants, width: 145)
                }
                HStack(spacing: 10) {
                    categoryButton("Scroll View", category: .scrollView, width: 145)
                    categoryButton("ScrollView Reader", category: .scrollViewReader, width: 145)
                    categoryButton("Text Input", category: .textInput, width: 145)
                    categoryButton("Split View", category: .splitView, width: 145)
                }
            }

            Divider()

            Text("Top-Level Presentation Tests")
                .font(.system(.headline))

            Button("Open Top-Level Sheet") {
                topLevelSheetPresented = true
            }

            HStack(spacing: 10) {
                Button("Top-Level Alert") {
                    showAlert = true
                }
                Button("Top-Level Data Alert") {
                    selectedFile = SampleFileItem(
                        id: 1,
                        name: "document.pdf",
                        size: "2.4 MB"
                    )
                    showDataAlert = true
                }
                Button("Top-Level Error Alert") {
                    currentError = SampleLocalizedError(
                        errorDescription: "Connection Failed",
                        failureReason: "The server is unreachable.",
                        recoverySuggestion: "Check your network and try again."
                    )
                    showErrorAlert = true
                }
            }

            Text("Result: \(alertResult.isEmpty ? "none" : alertResult)")
                .font(.system(.caption))
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 680, height: 650)
        .focusedSceneValue(
            \.testAppSettingsPresented,
            $settingsPresented
        )
        .sheet(isPresented: $settingsPresented) {
            settingsContent()
        }
        .environment(\.modalSessionUsingPlatformWindow, false)
        .sheet(item: $selectedCategory) { category in
            categoryContent(category)
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            usesPlatformPresentationWindows
        )
        .sheet(isPresented: $topLevelSheetPresented) {
            VStack(spacing: 12) {
                Text("Top-Level Sheet")
                    .font(.system(.headline))
                Text("This presentation stays attached to ContentView.")
                    .foregroundColor(.secondary)
                Button("Close") {
                    topLevelSheetPresented = false
                }
            }
            .padding(24)
            .frame(width: 360, height: 180)
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            usesPlatformPresentationWindows
        )
        .alert("Delete Item?", isPresented: $showAlert) {
            Button("Delete", role: .destructive) { alertResult = "deleted" }
            Button("Cancel", role: .cancel) { alertResult = "cancelled" }
        } message: {
            Text("This action cannot be undone.")
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            usesPlatformPresentationWindows
        )
        .alert("Delete File?", isPresented: $showDataAlert, presenting: selectedFile) { file in
            Button("Delete \(file.name)", role: .destructive) {
                alertResult = "deleted: \(file.name)"
                selectedFile = nil
            }
            Button("Cancel", role: .cancel) {
                alertResult = "cancelled"
                selectedFile = nil
            }
        } message: { file in
            Text("\(file.name) (\(file.size)) will be permanently removed.")
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            usesPlatformPresentationWindows
        )
        .alert(isPresented: $showErrorAlert, error: currentError) {
            Button("Retry") { alertResult = "retried" }
            Button("Cancel", role: .cancel) { alertResult = "error cancelled" }
        }
        .environment(
            \.modalSessionUsingPlatformWindow,
            usesPlatformPresentationWindows
        )
        .environment(
            \.defaultFontRenderingMode,
            usesVectorFontRendering ? .vector() : .bitmap()
        )
    }

    private func settingsContent() -> some View {
        VStack(spacing: 14) {
            Text("Settings")
                .font(.system(size: 22, weight: .semibold))

            Text(String(format: "Effective content scale: %.1fx", displayScale))

            HStack(spacing: 8) {
                contentScaleButton("Default", value: nil)
                contentScaleButton("1x", value: 1)
                contentScaleButton("2x", value: 2)
                contentScaleButton("3x", value: 3)
            }

            Divider()

            Toggle(
                "Vector Font Rendering",
                isOn: $usesVectorFontRendering
            )

            Divider()

            Toggle(
                "Open Test Modals in Platform Windows",
                isOn: $usesPlatformPresentationWindows
            )

            Text("Settings always opens as an overlay.")
                .font(.system(.caption))
                .foregroundColor(.secondary)

            Button("Close") {
                settingsPresented = false
            }
        }
        .padding(24)
        .frame(width: 440, height: 330)
    }

    private func contentScaleButton(
        _ title: String,
        value: CGFloat?
    ) -> some View {
        Button(
            contentScaleFactorOverride == value
                ? "[\(title)]"
                : title
        ) {
            contentScaleFactorOverride = value
            setContentScaleFactorOverride(value)
        }
    }

    @ViewBuilder
    private func categoryContent(_ category: LabCategory) -> some View {
        switch category {
        case .contextMenus:
            ContextMenuLabSheet {
                selectedCategory = nil
            }
        case .modalsAndPopups:
            ModalPopupLabSheet {
                selectedCategory = nil
            }
        case .animation:
            AnimationLabSheet {
                selectedCategory = nil
            }
        case .symbolEffects:
            SymbolEffectsLabSheet {
                selectedCategory = nil
            }
        case .keyframeAndPhase:
            KeyframePhaseLabSheet {
                selectedCategory = nil
            }
        case .matchedGeometry:
            MatchedGeometryLabSheet {
                selectedCategory = nil
            }
        case .contentTransition:
            ContentTransitionLabSheet {
                selectedCategory = nil
            }
        case .timeline:
            TimelineLabSheet {
                selectedCategory = nil
            }
        case .visualAndMesh:
            VisualMeshLabSheet {
                selectedCategory = nil
            }
        case .customAnimation:
            CustomAnimationLabSheet {
                selectedCategory = nil
            }
        case .images:
            ImageLabSheet {
                selectedCategory = nil
            }
        case .textVariants:
            TextVariantLabSheet {
                selectedCategory = nil
            }
        case .textInput:
            TextInputLabSheet {
                selectedCategory = nil
            }
        case .scrollView:
            ScrollViewLabSheet {
                selectedCategory = nil
            }
        case .scrollViewReader:
            ScrollViewReaderLabSheet {
                selectedCategory = nil
            }
        case .splitView:
            SplitViewLabSheet {
                selectedCategory = nil
            }
        }
    }

    private func categoryButton(
        _ title: String,
        category: LabCategory,
        width: CGFloat = 210
    ) -> some View {
        Button(title) {
            selectedCategory = category
        }
        .frame(width: width)
    }
}
