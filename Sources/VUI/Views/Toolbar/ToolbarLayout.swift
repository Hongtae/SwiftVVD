//
//  File: ToolbarLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Layout used for search/content/modal-toolbar vertical composition.
struct SheetContentRoot<L: Layout>: Layout {
    var layout: L

    typealias AnimatableData = L.AnimatableData
    var animatableData: L.AnimatableData {
        get { layout.animatableData }
        set { layout.animatableData = newValue }
    }

    init(_ layout: L) {
        self.layout = layout
    }

    func makeCache(subviews: Subviews) -> L.Cache {
        layout.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout L.Cache, subviews: Subviews) {
        layout.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout L.Cache) -> ViewSpacing {
        layout.spacing(subviews: subviews, cache: &cache)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout L.Cache) -> CGSize {
        switch subviews.count {
        case 2:
            let content = subviews[0].sizeThatFits(proposal)
            let toolbar = subviews[1].sizeThatFits(
                ProposedViewSize(width: proposal.width ?? content.width, height: nil))
            return CGSize(width: max(content.width, toolbar.width),
                          height: content.height + toolbar.height)
        case 3:
            let search = subviews[0].sizeThatFits(.zero)
            let content = subviews[1].sizeThatFits(proposal)
            let toolbar = subviews[2].sizeThatFits(
                ProposedViewSize(width: proposal.width ?? max(search.width, content.width), height: nil))
            return CGSize(width: max(search.width, max(content.width, toolbar.width)),
                          height: search.height + content.height + toolbar.height)
        default:
            return layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout L.Cache) {
        switch subviews.count {
        case 2:
            let toolbarProposal = ProposedViewSize(width: bounds.width, height: nil)
            let toolbar = subviews[1].sizeThatFits(toolbarProposal)
            let contentHeight = max(0, bounds.height - toolbar.height)
            let contentProposal = ProposedViewSize(width: bounds.width, height: contentHeight)
            let content = subviews[0].sizeThatFits(contentProposal)
            let contentX = bounds.minX + (bounds.width - content.width) * 0.5

            subviews[0].place(at: CGPoint(x: contentX, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: contentProposal)
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - toolbar.height),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: toolbar.height))
        case 3:
            let search = subviews[0].sizeThatFits(.zero)
            let toolbarProposal = ProposedViewSize(width: bounds.width, height: nil)
            let toolbar = subviews[2].sizeThatFits(toolbarProposal)
            let contentHeight = max(0, bounds.height - search.height - toolbar.height)
            let contentProposal = ProposedViewSize(width: bounds.width, height: contentHeight)
            let content = subviews[1].sizeThatFits(contentProposal)
            let searchX = bounds.minX + (bounds.width - search.width) * 0.5
            let contentX = bounds.minX + (bounds.width - content.width) * 0.5

            subviews[0].place(at: CGPoint(x: searchX, y: bounds.minY),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(search))
            subviews[1].place(at: CGPoint(x: contentX, y: bounds.minY + search.height),
                              anchor: .topLeading,
                              proposal: contentProposal)
            subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - toolbar.height),
                              anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: toolbar.height))
        default:
            layout.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        }
    }

    func explicitAlignment(of guide: HorizontalAlignment,
                           in bounds: CGRect,
                           proposal: ProposedViewSize,
                           subviews: Subviews,
                           cache: inout L.Cache) -> CGFloat? {
        layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }

    func explicitAlignment(of guide: VerticalAlignment,
                           in bounds: CGRect,
                           proposal: ProposedViewSize,
                           subviews: Subviews,
                           cache: inout L.Cache) -> CGFloat? {
        layout.explicitAlignment(of: guide, in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
    }
}
// Layout for modal sheet bottom buttons. Baseline-specific alignment can be
// refined separately. This places leading content at the leading edge and action
// buttons from the trailing edge, matching the confirmed slot separation.
struct DialogBottomButtonsHLayout: Layout {
    typealias AnimatableData = EmptyAnimatableData

    var leadingCount: Int

    init(leadingCount: Int = 0) {
        self.leadingCount = leadingCount
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).reduce(0, max)

        let leadingEnd = min(max(leadingCount, 0), subviews.count)
        let leadingIndices = Array(subviews.indices.prefix(leadingEnd))
        let actionIndices = Array(subviews.indices.dropFirst(leadingEnd))

        func width(for indices: [Subviews.Index]) -> CGFloat {
            let spacing = CGFloat(max(0, indices.count - 1)) * ViewSpacing.defaultSpacing
            return indices.map { sizes[$0].width }.reduce(0, +) + spacing
        }

        let leadingWidth = width(for: leadingIndices)
        let actionWidth = width(for: actionIndices)
        let groupSpacing = leadingWidth > 0 && actionWidth > 0 ? ViewSpacing.defaultSpacing : 0
        let intrinsicWidth = leadingWidth + groupSpacing + actionWidth

        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            return CGSize(width: max(proposedWidth, intrinsicWidth), height: height)
        }
        return CGSize(width: intrinsicWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        var leadingX = bounds.minX
        var trailingX = bounds.maxX
        let midY = bounds.midY

        let leadingEnd = min(max(leadingCount, 0), subviews.count)
        for index in subviews.indices.prefix(leadingEnd) {
            let size = sizes[index]
            subviews[index].place(at: CGPoint(x: leadingX, y: midY),
                                  anchor: .leading,
                                  proposal: ProposedViewSize(size))
            leadingX += size.width + Spacing.defaultValue.width
        }

        for index in subviews.indices.dropFirst(leadingEnd).reversed() {
            let size = sizes[index]
            trailingX -= size.width
            subviews[index].place(at: CGPoint(x: trailingX, y: midY),
                                  anchor: .leading,
                                  proposal: ProposedViewSize(size))
            trailingX -= Spacing.defaultValue.width
        }
    }
}

// MARK: - ContainerBackgroundKeys

// ContainerBackgroundKeys namespace for container background preference keys.
// PresentationKey is used by SheetContent.body via renderContainerBackgroundInHostingView.
enum ContainerBackgroundKeys {
    // PresentationKey: signals to the hosting view that the sheet should render
    // its container background. first-writer-wins Optional<Bool> preference.
    struct PresentationKey: PreferenceKey {
        typealias Value = Bool?
        static var defaultValue: Bool? { nil }
        static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
            if value == nil { value = nextValue() }
        }
    }
}

extension View {
    // renderContainerBackgroundInHostingView signals to the host that the presentation
    // should render a container background. Full implementation requires hosting layer.
    // The current path is a no-op passthrough.
    func renderContainerBackgroundInHostingView<K: PreferenceKey>(_ keyType: K.Type) -> some View {
        self
    }
}

// MARK: - SidebarState

// SidebarState: 1-byte enum/struct controlling sidebar visibility in sheets.
// Used by SheetContent.FixedSidebarModifier to write a fixed Binding<SidebarState>.
// rawValue 2 is written as the constant value (Binding.constant(SidebarState(rawValue: 2))).
// Raw values are carried directly until named sidebar states are introduced.
struct SidebarState: RawRepresentable, Equatable {
    var rawValue: UInt8
    init(rawValue: UInt8) { self.rawValue = rawValue }
}

// Private env key for Optional<Binding<SidebarState>>.
// The external key name is unavailable. Use local name _SidebarStateBindingKey.
private struct _SidebarStateBindingKey: EnvironmentKey {
    static var defaultValue: Binding<SidebarState>? { nil }
}

extension EnvironmentValues {
    var _sidebarStateBinding: Binding<SidebarState>? {
        get { self[_SidebarStateBindingKey.self] }
        set { self[_SidebarStateBindingKey.self] = newValue }
    }
}

// MARK: - InteractiveResizeDisabledKey

// InteractiveResizeDisabledKey: Optional<Bool> HostPreferenceKey.
// First-writer-wins: once set, subsequent writes are ignored.
// SheetContent.body writes true (disabling interactive resize) when no other writer has set a value.
struct InteractiveResizeDisabledKey: HostPreferenceKey {
    typealias Value = Bool?
    static var defaultValue: Bool? { nil }
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        if value == nil { value = nextValue() }
    }
}
