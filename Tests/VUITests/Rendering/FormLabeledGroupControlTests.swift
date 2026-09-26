import Foundation
import XCTest
@testable import VUI
@testable import VVD

final class FormLabeledGroupControlTests: XCTestCase {
    // ASSERTIONS formPublicStructure27Observed
    // ASSERTIONS formOwnerLowering27Observed
    // ASSERTIONS formLabeledGroupFieldMetadata27Observed
    func testFormRetainsContentAndResolvedStyleBoundary() {
        let textType: Any.Type = Text.self
        let aliasType: Any.Type = FormStyleConfiguration.Content.self
        XCTAssertFalse(textType is any FormFooterBearing.Type)
        XCTAssertTrue(
            aliasType is any FormFooterBearing.Type
        )
        let form = Form {
            Section {
                Text("Value")
            } header: {
                Text("Header")
            }
        }

        XCTAssertEqual(
            Mirror(reflecting: form).children.compactMap(\.label),
            ["content"]
        )
        let bodyType = String(reflecting: type(of: form.body))
        XCTAssertTrue(bodyType.contains("ContentIsFooterBearing"), bodyType)
        XCTAssertTrue(bodyType.contains("ResolvedFormStyle"), bodyType)
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"), bodyType)
        _ = form.formStyle(.automatic)
        _ = form.formStyle(.columns)
        _ = form.formStyle(.grouped)
    }

    // ASSERTIONS formStyleRouting27Observed
    // ASSERTIONS formCustomStyleReachability27Observed
    func testFormStyleConfigurationRetainsContentAndFooterAliases() {
        let configuration = FormStyleConfiguration()
        XCTAssertEqual(
            Mirror(reflecting: configuration).children.compactMap(\.label),
            ["content", "footer"]
        )
        let automatic = String(
            reflecting: type(
                of: AutomaticFormStyle().makeBody(
                    configuration: configuration
                )
            )
        )
        let columns = String(
            reflecting: type(
                of: ColumnsFormStyle().makeBody(configuration: configuration)
            )
        )
        let grouped = String(
            reflecting: type(
                of: GroupedFormStyle().makeBody(configuration: configuration)
            )
        )
        XCTAssertTrue(automatic.contains("FormStyleWritingModifier"), automatic)
        XCTAssertTrue(automatic.contains("ColumnsFormStyle"), automatic)
        XCTAssertTrue(columns.contains("FormVStack"), columns)
        XCTAssertTrue(columns.contains("ColumnsFormStyleContext"), columns)
        XCTAssertTrue(grouped.contains("UniversalGroupedForm"), grouped)
        XCTAssertTrue(grouped.contains("FormStyleConfiguration.Footer"), grouped)
    }

    // ASSERTIONS labeledContentPublicStructure27Observed
    // ASSERTIONS labeledContentOwnerLowering27Observed
    // ASSERTIONS labeledContentStyleRouting27Observed
    func testLabeledContentRetainsSourcesAndAutomaticStyleContexts() {
        let labeled = LabeledContent {
            Text("Value")
        } label: {
            Text("Label")
        }
        let textValue = LabeledContent("Title", value: "Value")
        let formatted = LabeledContent("Count", value: 42, format: .number)

        let fields = ["label", "content", "accessibilityPresentation"]
        XCTAssertEqual(
            Mirror(reflecting: labeled).children.compactMap(\.label),
            fields
        )
        XCTAssertEqual(
            Mirror(reflecting: textValue).children.compactMap(\.label),
            fields
        )
        XCTAssertEqual(
            Mirror(reflecting: formatted).children.compactMap(\.label),
            fields
        )
        let bodyType = String(reflecting: type(of: labeled.body))
        XCTAssertTrue(bodyType.contains("ResolvedLabeledContent"), bodyType)
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"), bodyType)

        let configuration = LabeledContentStyleConfiguration()
        let styleType = String(
            reflecting: type(
                of: AutomaticLabeledContentStyle().makeBody(
                    configuration: configuration
                )
            )
        )
        XCTAssertTrue(styleType.contains("GroupedFormStyleContext"), styleType)
        XCTAssertTrue(styleType.contains("ColumnsFormStyleContext"), styleType)
        XCTAssertTrue(
            styleType.contains("LeadingTrailingLabeledContentStyle"),
            styleType
        )
        _ = labeled.labeledContentStyle(.automatic)
    }

    // ASSERTIONS groupBoxPublicStructure27Observed
    // ASSERTIONS groupBoxOwnerLowering27Observed
    // ASSERTIONS groupBoxStyleRouting27Observed
    func testGroupBoxRetainsOptionalLabelAndDefaultStyleChain() {
        let group = GroupBox {
            Text("Content")
        } label: {
            Text("Label")
        }
        let unlabeled = GroupBox {
            Text("Content")
        }

        let fields = ["label", "content", "_namespace"]
        XCTAssertEqual(
            Mirror(reflecting: group).children.compactMap(\.label),
            fields
        )
        XCTAssertEqual(
            Mirror(reflecting: unlabeled).children.compactMap(\.label),
            fields
        )
        let bodyType = String(reflecting: type(of: group.body))
        XCTAssertTrue(bodyType.contains("ResolvedGroupBoxStyle"), bodyType)
        XCTAssertTrue(bodyType.contains("OptionalSourceWriter"), bodyType)
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"), bodyType)

        let configuration = GroupBoxStyleConfiguration()
        let styleType = String(
            reflecting: type(
                of: DefaultGroupBoxStyle().makeBody(
                    configuration: configuration
                )
            )
        )
        XCTAssertTrue(styleType.contains("DefaultGroupBoxStyle"), styleType)
        XCTAssertTrue(styleType.contains("MacIdiomGroupBoxStyle"), styleType)
        _ = group.groupBoxStyle(.automatic)
    }

    // ASSERTIONS formCustomStyleReachability27Observed
    // ASSERTIONS labeledContentStyleRouting27Observed
    // ASSERTIONS groupBoxStyleRouting27Observed
    func testCustomStylesReceiveRuntimeDispatch() {
        let recorder = FormLabeledGroupStyleRecorder()
        mount(
            Form {
                EmptyView()
            }
            .formStyle(RecordingFormStyle(recorder: recorder))
        )
        mount(
            LabeledContent {
                EmptyView()
            } label: {
                EmptyView()
            }
                .labeledContentStyle(
                    RecordingLabeledContentStyle(recorder: recorder)
                )
        )
        mount(
            GroupBox {
                EmptyView()
            } label: {
                EmptyView()
            }
            .groupBoxStyle(RecordingGroupBoxStyle(recorder: recorder))
        )

        XCTAssertEqual(recorder.formCount, 1)
        XCTAssertEqual(recorder.labeledCount, 1)
        XCTAssertEqual(recorder.groupCount, 1)
    }

    private func mount<Content: View>(_ content: Content) {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(value: content)
            let environment = graph.makeInput(value: EnvironmentValues())
            let inputs = _ViewInputs(
                base: _GraphInputs(
                    time: graph.makeInput(value: Time(seconds: 0)),
                    phase: graph.makeInput(value: _GraphInputs.Phase()),
                    environment: environment,
                    transaction: graph.makeInput(value: Transaction())
                ),
                customInputs: PropertyList(),
                preferences: PreferencesInputs(
                    keys: PreferenceKeys(),
                    hostKeys: graph.makeInput(value: PreferenceKeys())
                ),
                transform: graph.makeInput(value: ViewTransform()),
                position: graph.makeInput(value: CGPoint.zero),
                containerPosition: graph.makeInput(value: CGPoint.zero),
                size: graph.makeInput(
                    value: ViewSize(width: 300, height: 240)
                ),
                safeAreaInsets: OptionalAttribute(),
                containerSize: OptionalAttribute(),
                stackOrientation: nil
            )
            _ = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )
        }
    }

    // ASSERTIONS formColumnsSectionLayout27Observed
    // ASSERTIONS labeledContentPublicLayout27Observed
    // ASSERTIONS groupBoxPublicLayout27Observed
    func testDefaultLayoutOwnersRetainObservedAxisRelationships() {
        let labeled = ResolvedLabeledContent._Body(
            configuration: LabeledContentStyleConfiguration()
        )
        let labeledType = String(reflecting: type(of: labeled.body))
        XCTAssertTrue(labeledType.contains("HStack"), labeledType)

        let group = MacIdiomGroupBoxStyle().makeBody(
            configuration: GroupBoxStyleConfiguration()
        )
        let groupType = String(reflecting: type(of: group))
        XCTAssertTrue(groupType.contains("VStack"), groupType)

        let columns = ColumnsFormStyle().makeBody(
            configuration: FormStyleConfiguration()
        )
        let columnsType = String(reflecting: type(of: columns))
        XCTAssertTrue(columnsType.contains("FormVStack"), columnsType)
        XCTAssertTrue(
            columnsType.contains("ColumnsFormStyleContext"),
            columnsType
        )
    }

    // ASSERTIONS formColumnsSectionLayout27Observed
    // ASSERTIONS labeledContentPublicLayout27Observed
    // ASSERTIONS groupBoxPublicLayout27Observed
    @MainActor
    func testMountedDefaultControlsProduceLayoutAndDisplay() throws {
        let root = VStack(spacing: 12) {
            Form {
                Section {
                    LabeledContent("Label", value: "Value")
                } header: {
                    Text("Header")
                }
            }
            .frame(width: 280, height: 120)

            GroupBox("Group") {
                Text("Content")
            }
        }
        let controller = WindowController(
            content: root,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(type(of: root))
            )
        )
        for tick in 0..<4 {
            var redraw = false
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 320, height: 260),
                redraw: &redraw
            ) { _, _ in }
        }

        try controller.viewGraph.data.withCurrent {
            let layout = try XCTUnwrap(
                controller.viewGraph.rootLayoutComputer
            ).value
            let size = layout.sizeThatFits(
                _ProposedSize(width: 320, height: 260)
            )
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertFalse(
                try XCTUnwrap(
                    controller.viewGraph.rootDisplayList
                ).value.items.isEmpty
            )
        }
    }
}

private final class FormLabeledGroupStyleRecorder: @unchecked Sendable {
    var formCount = 0
    var labeledCount = 0
    var groupCount = 0
}

private struct RecordingFormStyle: FormStyle {
    let recorder: FormLabeledGroupStyleRecorder

    func makeBody(configuration: Configuration) -> some View {
        FormLabeledGroupStyleRecordingView(
            recorder: recorder,
            kind: .form
        )
    }
}

private struct RecordingLabeledContentStyle: LabeledContentStyle {
    let recorder: FormLabeledGroupStyleRecorder

    func makeBody(configuration: Configuration) -> some View {
        FormLabeledGroupStyleRecordingView(
            recorder: recorder,
            kind: .labeled
        )
    }
}

private struct RecordingGroupBoxStyle: GroupBoxStyle {
    let recorder: FormLabeledGroupStyleRecorder

    func makeBody(configuration: Configuration) -> some View {
        FormLabeledGroupStyleRecordingView(
            recorder: recorder,
            kind: .group
        )
    }
}

private struct FormLabeledGroupStyleRecordingView:
    View, PrimitiveView, UnaryView {
    enum Kind {
        case form
        case labeled
        case group
    }

    typealias Body = Never

    let recorder: FormLabeledGroupStyleRecorder
    let kind: Kind

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "FormLabeledGroupStyleRecordingView requires an active graph."
            )
        }
        switch view._attribute.value.kind {
        case .form:
            view._attribute.value.recorder.formCount += 1
        case .labeled:
            view._attribute.value.recorder.labeledCount += 1
        case .group:
            view._attribute.value.recorder.groupCount += 1
        }
        return _ViewOutputs(
            layoutComputer: OptionalAttribute(
                graph.makeInput(
                    value: LayoutComputer.fixed(
                        CGSize(width: 1, height: 1)
                    )
                )
            )
        )
    }
}
