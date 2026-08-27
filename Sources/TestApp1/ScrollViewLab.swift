import Foundation
import VUI

private enum ScrollLabAxis: Int {
    case vertical
    case horizontal
    case both

    var axes: Axis.Set {
        switch self {
        case .vertical:
            .vertical
        case .horizontal:
            .horizontal
        case .both:
            [.horizontal, .vertical]
        }
    }

    var title: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        case .both: "Both Axes"
        }
    }
}

private struct ScrollLabGeometry: Equatable {
    var contentOffset = CGPoint.zero
    var contentSize = CGSize.zero
    var containerSize = CGSize.zero
    var visibleRect = CGRect.zero
}

struct ScrollViewLabSheet: View {
    let onClose: () -> Void

    @State private var axis = ScrollLabAxis.vertical
    @State private var showsScrollView = true
    @State private var usesAlternateContent = false
    @State private var usesLazyContent = false
    @State private var usesContentMargins = false
    @State private var showsIndicators = true
    @State private var usesFixedAreaIndicators = false
    @State private var showsViewportBorder = true
    @State private var transformsViewport = false
    @State private var animatesRequests = false
    @State private var geometry = ScrollLabGeometry()
    @State private var phase = ScrollPhase.idle
    @State private var velocity = CGVector.zero
    @State private var lastRequest = "none"
    @State private var lastTap = "none"
    @State private var hostGeneration = 1

    private var itemCount: Int {
        usesLazyContent ? 120 : 36
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 10) {
                header

                HStack(spacing: 8) {
                    modeButton("Vertical", selected: axis == .vertical) {
                        axis = .vertical
                    }
                    modeButton("Horizontal", selected: axis == .horizontal) {
                        axis = .horizontal
                    }
                    modeButton("Both", selected: axis == .both) {
                        axis = .both
                    }
                    modeButton(
                        usesLazyContent ? "Lazy 120" : "Eager 36",
                        selected: usesLazyContent
                    ) {
                        usesLazyContent.toggle()
                    }
                    modeButton(
                        usesAlternateContent ? "Content B" : "Content A",
                        selected: usesAlternateContent
                    ) {
                        usesAlternateContent.toggle()
                    }
                }

                HStack(spacing: 8) {
                    Button(showsScrollView ? "Remove Host" : "Reinsert Host") {
                        showsScrollView.toggle()
                        if showsScrollView {
                            hostGeneration += 1
                        }
                    }
                    modeButton("Margins", selected: usesContentMargins) {
                        usesContentMargins.toggle()
                    }
                    modeButton("Indicators", selected: showsIndicators) {
                        showsIndicators.toggle()
                    }
                    modeButton(
                        "Fixed Bars",
                        selected: usesFixedAreaIndicators
                    ) {
                        usesFixedAreaIndicators.toggle()
                    }
                    modeButton("Border", selected: showsViewportBorder) {
                        showsViewportBorder.toggle()
                    }
                    modeButton("Transform", selected: transformsViewport) {
                        transformsViewport.toggle()
                    }
                    modeButton("Animate Jump", selected: animatesRequests) {
                        animatesRequests.toggle()
                    }
                }

                HStack(spacing: 8) {
                    Button("Start") {
                        requestScroll(to: 0, anchor: .topLeading, proxy: proxy)
                    }
                    Button("Middle") {
                        requestScroll(
                            to: itemCount / 2,
                            anchor: .center,
                            proxy: proxy
                        )
                    }
                    Button("End") {
                        requestScroll(
                            to: itemCount - 1,
                            anchor: .bottomTrailing,
                            proxy: proxy
                        )
                    }
                    Text("Request: \(lastRequest) · Tap: \(lastTap)")
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }

                if showsScrollView {
                    scrollSurface
                } else {
                    VStack(spacing: 10) {
                        Text("ScrollView removed from the hierarchy")
                            .font(.system(.headline))
                        Text("Reinsert it, then verify offset reset and a fresh host lifecycle.")
                            .font(.system(.caption))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 700, height: 360)
                    .border(Color.red, width: 2)
                }

                Text(
                    "Drag or wheel in the outer viewport and the nested strip. "
                        + "Tap rows after scrolling, replace only the child content, "
                        + "then remove and reinsert the whole host."
                )
                .font(.system(.caption))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

                Button("Close") {
                    onClose()
                }
            }
            .padding(18)
            .frame(width: 820, height: 680)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Scroll View Lab")
                .font(.system(size: 22, weight: .semibold))
            Text(
                String(
                    format: "Host %d · %@ · %@ bars · phase %@ · offset (%.1f, %.1f) · velocity (%.1f, %.1f)",
                    hostGeneration,
                    axis.title,
                    usesFixedAreaIndicators ? "fixed" : "overlay",
                    phase.debugDescription,
                    geometry.contentOffset.x,
                    geometry.contentOffset.y,
                    velocity.dx,
                    velocity.dy
                )
            )
            .font(.system(.caption))
            .foregroundColor(.secondary)
            Text(
                String(
                    format: "content %.0f×%.0f · viewport %.0f×%.0f · visible origin %.1f, %.1f",
                    geometry.contentSize.width,
                    geometry.contentSize.height,
                    geometry.containerSize.width,
                    geometry.containerSize.height,
                    geometry.visibleRect.origin.x,
                    geometry.visibleRect.origin.y
                )
            )
            .font(.system(.caption))
            .foregroundColor(.secondary)
        }
    }

    private var scrollSurface: some View {
        ScrollView(axis.axes, showsIndicators: showsIndicators) {
            scrollContent
        }
        .scrollIndicatorStyle(
            usesFixedAreaIndicators ? .fixedArea : .overlay
        )
        .contentMargins(
            usesContentMargins ? 18 : 0,
            for: .scrollContent
        )
        // Mark the measured ScrollView viewport before the outer fixed frame.
        // A one-axis ScrollView keeps its content size on the non-scrolling axis.
        .border(showsViewportBorder ? Color.blue : Color.clear, width: 2)
        .frame(width: 700, height: 360)
        .scaleEffect(transformsViewport ? 0.94 : 1)
        .rotationEffect(.degrees(transformsViewport ? 1.5 : 0))
        .onScrollGeometryChange(for: ScrollLabGeometry.self) { value in
            ScrollLabGeometry(
                contentOffset: value.contentOffset,
                contentSize: value.contentSize,
                containerSize: value.containerSize,
                visibleRect: value.visibleRect
            )
        } action: { _, newValue in
            geometry = newValue
        }
        .onScrollPhaseChange { _, newPhase, context in
            phase = newPhase
            velocity = context.velocity ?? .zero
            geometry = ScrollLabGeometry(
                contentOffset: context.geometry.contentOffset,
                contentSize: context.geometry.contentSize,
                containerSize: context.geometry.containerSize,
                visibleRect: context.geometry.visibleRect
            )
        }
    }

    @ViewBuilder
    private var scrollContent: some View {
        if axis == .horizontal {
            horizontalContent
        } else if usesLazyContent {
            LazyVStack(spacing: 7) {
                verticalItems
            }
        } else {
            VStack(spacing: 7) {
                verticalItems
            }
        }
    }

    @ViewBuilder
    private var horizontalContent: some View {
        if usesLazyContent {
            LazyHStack(spacing: 8) {
                horizontalItems
            }
        } else {
            HStack(spacing: 8) {
                horizontalItems
            }
        }
    }

    private var verticalItems: some View {
        ForEach(0..<itemCount, id: \.self) { item in
            VStack(spacing: 5) {
                Button(rowTitle(item)) {
                    lastTap = "outer \(item)"
                }
                .frame(
                    width: axis == .both ? 900 : 640,
                    height: item.isMultiple(of: 9) ? 58 : 38,
                    alignment: .leading
                )
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(rowColor(item).opacity(0.28))
                }
                .border(item == itemCount / 2 ? Color.red : Color.gray, width: 1)
                .id(item)

                if item == 4 {
                    nestedHorizontalStrip
                }
            }
        }
    }

    private var horizontalItems: some View {
        ForEach(0..<itemCount, id: \.self) { item in
            Button(rowTitle(item)) {
                lastTap = "outer \(item)"
            }
            .frame(
                width: item.isMultiple(of: 7) ? 180 : 112,
                height: 290
            )
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(rowColor(item).opacity(0.30))
            }
            .border(item == itemCount / 2 ? Color.red : Color.gray, width: 1)
            .id(item)
        }
    }

    private var nestedHorizontalStrip: some View {
        VStack(spacing: 4) {
            Text("Nested horizontal scroll — wheel/drag here, then tap a card")
                .font(.system(.caption))
                .foregroundColor(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(0..<18, id: \.self) { item in
                        Button("Nested \(item)") {
                            lastTap = "nested \(item)"
                        }
                        .frame(width: 105, height: 58)
                        .background {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.purple.opacity(0.24))
                        }
                    }
                }
            }
            .frame(width: 620, height: 76)
            .border(Color.purple, width: 1)
        }
        .frame(width: axis == .both ? 900 : 640, height: 108)
    }

    private func rowTitle(_ item: Int) -> String {
        let content = usesAlternateContent ? "B" : "A"
        if item == 0 {
            return "◀︎ TOP / LEADING · Content \(content) · row 0"
        }
        if item == itemCount - 1 {
            return "BOTTOM / TRAILING ▶︎ · Content \(content) · row \(item)"
        }
        return "Content \(content) · row \(item)"
    }

    private func rowColor(_ item: Int) -> Color {
        if usesAlternateContent {
            return item.isMultiple(of: 2) ? .orange : .purple
        }
        return item.isMultiple(of: 2) ? .blue : .green
    }

    private func modeButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(selected ? "[\(title)]" : title, action: action)
    }

    private func requestScroll(
        to id: Int,
        anchor: UnitPoint,
        proxy: ScrollViewProxy
    ) {
        lastRequest = "\(id) / \(anchor) / \(animatesRequests ? "animated" : "instant")"
        if animatesRequests {
            withAnimation(.easeInOut(duration: 0.6)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }
}
