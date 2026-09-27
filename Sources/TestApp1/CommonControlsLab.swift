import VUI

private struct CommonControlsTableRow: Identifiable {
    let id: Int
    let control: String
    let value: String
}

private struct CommonControlsOutlineItem: Identifiable {
    let id: Int
    let name: String
    let children: [CommonControlsOutlineItem]?
}

struct CommonControlsLabSheet: View {
    let onClose: () -> Void

    @State private var pickerSelection = 1
    @State private var sliderValue = 40.0
    @State private var stepperValue = 2
    @State private var isFeatureEnabled = true
    @State private var isDisclosureExpanded = true
    @State private var selectedColor = Color(
        .sRGB,
        red: 0.22,
        green: 0.52,
        blue: 0.92,
        opacity: 0.85
    )
    @State private var tableSelection: Int? = 2
    @State private var selectedPage = 0

    var body: some View {
        VStack(spacing: 12) {
            Text("Common Controls")
                .font(.system(size: 22, weight: .semibold))

            Text(
                "Exercise the portable controls added in the common-view tranche. "
                    + "Every interaction is rendered and owned by VUI."
            )
            .font(.system(.caption))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            Picker("Control Group", selection: $selectedPage) {
                Text("Values").tag(0)
                Text("Hierarchy").tag(1)
                Text("Form").tag(2)
                Text("Table").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 620)

            selectedControlPage
                .frame(width: 680, height: 400)

            Button("Close") {
                onClose()
            }
        }
        .padding(18)
        .frame(width: 740, height: 620)
    }

    @ViewBuilder
    private var selectedControlPage: some View {
        switch selectedPage {
        case 1:
            hierarchyControls

        case 2:
            formControls

        case 3:
            tableControls

        default:
            valueControls
        }
    }

    private var valueControls: some View {
        GroupBox("Value Controls") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Quality", selection: $pickerSelection) {
                    Text("Low").tag(0)
                    Text("Medium").tag(1)
                    Text("High").tag(2)
                }
                .pickerStyle(.menu)

                Slider(
                    value: $sliderValue,
                    in: 0...100,
                    step: 5
                ) {
                    Text("Intensity: \(Int(sliderValue))")
                }

                Stepper(
                    "Copies: \(stepperValue)",
                    value: $stepperValue,
                    in: 0...10
                )

                ProgressView(value: sliderValue, total: 100) {
                    Text("Progress")
                } currentValueLabel: {
                    Text("\(Int(sliderValue))%")
                }
                .progressViewStyle(.linear)

                ColorPicker(
                    "Accent Color",
                    selection: $selectedColor,
                    supportsOpacity: true
                )

                Toggle(
                    "Feature Enabled",
                    isOn: $isFeatureEnabled
                )
            }
        }
        .frame(width: 600, height: 360)
    }

    private var hierarchyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Disclosure & Outline")
                .font(.system(.headline))

            DisclosureGroup(
                "Disclosure Group",
                isExpanded: $isDisclosureExpanded
            ) {
                Text("Expanded content")
                    .foregroundColor(.secondary)
            }

            OutlineGroup(outlineItems, children: \.children) { item in
                Text(item.name)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 600, height: 360, alignment: .topLeading)
        .border(Color.gray.opacity(0.35), width: 1)
    }

    private var formControls: some View {
        Form {
            Section {
                LabeledContent(
                    "Quality",
                    value: qualityName
                )

                Toggle(
                    "Feature Enabled",
                    isOn: $isFeatureEnabled
                )
            } header: {
                Text("Form & Labeled Content")
            }

            Section {
                Button("Back to Common Controls") {
                    selectedPage = 0
                }

                Button("Close") {
                    onClose()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 660, height: 360)
    }

    private var tableControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Table")
                .font(.system(.headline))

            Table(tableRows, selection: $tableSelection) {
                TableColumn("Control") { row in
                    Text(row.control)
                }
                .width(min: 140, ideal: 180, max: 220)

                TableColumn("Current Value") { row in
                    Text(row.value)
                }
                .width(min: 180, ideal: 260, max: 320)
            }
            .frame(width: 640, height: 310)

            Text(
                "Selected table row: "
                    + (tableSelection.map(String.init) ?? "none")
            )
            .font(.system(.caption))
            .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 668, height: 390, alignment: .topLeading)
        .border(Color.gray.opacity(0.35), width: 1)
    }

    private var qualityName: String {
        switch pickerSelection {
        case 0: "Low"
        case 2: "High"
        default: "Medium"
        }
    }

    private var outlineItems: [CommonControlsOutlineItem] {
        [
            CommonControlsOutlineItem(
                id: 1,
                name: "Project",
                children: [
                    CommonControlsOutlineItem(
                        id: 11,
                        name: "Scenes",
                        children: nil
                    ),
                    CommonControlsOutlineItem(
                        id: 12,
                        name: "Assets",
                        children: nil
                    ),
                ]
            ),
        ]
    }

    private var tableRows: [CommonControlsTableRow] {
        [
            CommonControlsTableRow(
                id: 1,
                control: "Picker",
                value: qualityName
            ),
            CommonControlsTableRow(
                id: 2,
                control: "Slider / ProgressView",
                value: "\(Int(sliderValue))%"
            ),
            CommonControlsTableRow(
                id: 3,
                control: "Stepper",
                value: "\(stepperValue) copies"
            ),
            CommonControlsTableRow(
                id: 4,
                control: "DisclosureGroup",
                value: isDisclosureExpanded ? "Expanded" : "Collapsed"
            ),
            CommonControlsTableRow(
                id: 5,
                control: "Toggle",
                value: isFeatureEnabled ? "Enabled" : "Disabled"
            ),
        ]
    }
}
