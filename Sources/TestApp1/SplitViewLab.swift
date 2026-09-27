import VUI

struct SplitViewLabSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Split View")
                .font(.system(size: 22, weight: .semibold))

            Text(
                "Hover each divider to verify its resize pointer, then drag "
                    + "past both pane limits and confirm the released position is retained."
            )
            .font(.system(.caption))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            Text("HSplitView · left-right resize pointer")
                .font(.system(.headline))

            HSplitView {
                pane(
                    title: "Navigator",
                    detail: "120…420 pt",
                    color: .blue
                )
                .frame(
                    minWidth: 120,
                    idealWidth: 180,
                    maxWidth: 420,
                    maxHeight: .infinity
                )

                pane(
                    title: "Workspace",
                    detail: "minimum 180 pt",
                    color: .orange
                )
                .frame(
                    minWidth: 180,
                    idealWidth: 360,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
            .frame(width: 600, height: 180)
            .border(Color.gray.opacity(0.5), width: 1)

            Text("VSplitView · up-down resize pointer")
                .font(.system(.headline))

            VSplitView {
                pane(
                    title: "Viewport",
                    detail: "60…160 pt",
                    color: .green
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 60,
                    idealHeight: 110,
                    maxHeight: 160
                )

                pane(
                    title: "Console",
                    detail: "minimum 60 pt",
                    color: .purple
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 60,
                    idealHeight: 220,
                    maxHeight: .infinity
                )
            }
            .frame(width: 600, height: 180)
            .border(Color.gray.opacity(0.5), width: 1)

            Button("Close") {
                onClose()
            }
        }
        .padding(18)
        .frame(width: 660, height: 600)
    }

    private func pane(
        title: String,
        detail: String,
        color: Color
    ) -> some View {
        ZStack {
            color.opacity(0.18)

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.headline))
                Text(detail)
                    .font(.system(.caption))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
