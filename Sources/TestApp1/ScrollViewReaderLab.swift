import Foundation
import VUI

struct ScrollViewReaderLabSheet: View {
    let onClose: () -> Void

    @State private var lastRequest = "none"
    @State private var contentOffset = CGPoint.zero

    private var isAutomatedSmoke: Bool {
        ProcessInfo.processInfo.environment["VUI_SCROLL_READER_SMOKE"] != nil
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 12) {
                Text("ScrollView Reader")
                    .font(.system(size: 22, weight: .semibold))

                HStack(spacing: 10) {
                    Button("Row 0") {
                        lastRequest = "0 / top"
                        proxy.scrollTo(0, anchor: .top)
                    }
                    Button("Row 75") {
                        lastRequest = "75 / center"
                        proxy.scrollTo(75, anchor: .center)
                    }
                    Button("Row 150") {
                        lastRequest = "150 / top"
                        proxy.scrollTo(150, anchor: .top)
                    }
                }

                Text("Request: \(lastRequest), offset: \(Int(contentOffset.y))")
                    .font(.system(.caption))
                    .foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(0..<200, id: \.self) { row in
                            Text("Row \(row)")
                                .frame(width: 280, height: 30, alignment: .leading)
                                .border(row == 150 ? .blue : .gray, width: 1)
                                .id(row)
                        }
                    }
                }
                .frame(width: 300, height: 260)
                .border(.gray, width: 1)
                .onScrollGeometryChange(for: CGPoint.self) { geometry in
                    geometry.contentOffset
                } action: { _, newValue in
                    contentOffset = newValue
                    if isAutomatedSmoke {
                        print("VUI_SCROLL_READER_SMOKE offset \(newValue.x) \(newValue.y)")
                    }
                }
                .onAppear {
                    guard isAutomatedSmoke else { return }
                    lastRequest = "150 / top"
                    print("VUI_SCROLL_READER_SMOKE request 150")
                    proxy.scrollTo(150, anchor: .top)
                }

                Button("Close") {
                    onClose()
                }
            }
            .padding(20)
            .frame(width: 520, height: 470)
        }
    }
}
