//
//  File: WindowCommandMenuPresenter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Materializes the renderer-owned root menu without introducing a second
// display-list or input path. The root WindowController installs the returned
// view only while this presenter is selected.
final class WindowCommandMenuPresenter {
    static let menuBarHeight: CGFloat = 28
    fileprivate static let itemHorizontalPadding: CGFloat = 8

    private(set) var items: [MainMenuItem] = []
    private(set) var environment = EnvironmentValues()
    private var itemWidths: [MainMenuItem.Identifier: CGFloat] = [:]

    func update(
        items: [MainMenuItem],
        environment: EnvironmentValues,
        hostEnvironment: EnvironmentValues,
        sceneResources: SceneResources
    ) {
        self.items = items
        self.environment = environment.untrackedCopy()
        var measurementEnvironment = self.environment
        measurementEnvironment.displayScale = hostEnvironment.displayScale
        measurementEnvironment._contentScaleFactor =
            hostEnvironment._contentScaleFactor
        let context = GraphTextResolutionContext(
            environment: measurementEnvironment,
            sceneResources: sceneResources
        )
        itemWidths.removeAll(keepingCapacity: true)
        // MenuControlResponder derives its activation region from the label's
        // laid-out frame. Resolve each short menu title synchronously so the
        // first input frame already owns the complete clickable region.
        for item in items {
            let textWidth = Text(verbatim: item.name)
                .font(.system(size: 13))
                ._resolve(context: context, referenceDate: Date())?
                .measure()
                .width ?? 0
            itemWidths[item.id] = textWidth
                + Self.itemHorizontalPadding * 2
        }
    }

    func rootView(sceneContent: AnyView) -> AnyView {
        AnyView(
            WindowCommandMenuRoot(
                sceneContent: sceneContent,
                items: items,
                itemWidths: itemWidths,
                menuEnvironment: environment
            )
        )
    }

    // The root graph keeps this outer type installed for the entire static
    // Scene lifetime. Changing the presenter's presence then selects a child
    // branch instead of replacing an AnyView with a different stored type.
    static func hostRootView(
        sceneContent: AnyView,
        presenter: WindowCommandMenuPresenter?
    ) -> AnyView {
        AnyView(
            WindowCommandMenuRootHost(
                sceneContent: sceneContent,
                presenter: presenter
            )
        )
    }

    // VVD window sizes describe logical client content. Keep the Scene's
    // existing content proposal stable by allocating the menu bar in addition
    // to that client size while the renderer-owned presenter is installed.
    static func platformContentSize(
        preserving sceneContentSize: CGSize
    ) -> CGSize {
        CGSize(
            width: sceneContentSize.width,
            height: sceneContentSize.height + menuBarHeight
        )
    }

    static func sceneContentSize(
        from platformContentSize: CGSize
    ) -> CGSize {
        CGSize(
            width: platformContentSize.width,
            height: max(0, platformContentSize.height - menuBarHeight)
        )
    }
}

private struct WindowCommandMenuRootHost: View {
    var sceneContent: AnyView
    var presenter: WindowCommandMenuPresenter?

    @ViewBuilder
    var body: some View {
        if let presenter {
            presenter.rootView(sceneContent: sceneContent)
        } else {
            sceneContent
        }
    }
}

private struct WindowCommandMenuRoot: View {
    var sceneContent: AnyView
    var items: [MainMenuItem]
    var itemWidths: [MainMenuItem.Identifier: CGFloat]
    var menuEnvironment: EnvironmentValues

    var body: some View {
        VStack(spacing: 0) {
            WindowCommandMenuBar(
                items: items,
                itemWidths: itemWidths,
                menuEnvironment: menuEnvironment
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: WindowCommandMenuPresenter.menuBarHeight)

            sceneContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }
}

private struct WindowCommandMenuBar: View {
    var items: [MainMenuItem]
    var itemWidths: [MainMenuItem.Identifier: CGFloat]
    var menuEnvironment: EnvironmentValues

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                WindowCommandMenuItem(
                    item: item,
                    width: itemWidths[item.id]
                        ?? WindowCommandMenuPresenter.menuBarHeight
                )
            }
            Spacer(minLength: 0)
        }
        .modifier(
            CommandMenuMaterializationEnvironmentModifier(
                environment: menuEnvironment
            )
        )
        .background(Color(white: 0.94))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct WindowCommandMenuItem: View {
    var item: MainMenuItem
    var width: CGFloat

    @State private var isHovered = false
    @State private var isPressing = false
    @State private var isOpen = false

    private var background: Color {
        if isPressing || isOpen {
            return Color(white: 0.78)
        }
        if isHovered {
            return Color(white: 0.86)
        }
        return .clear
    }

    var body: some View {
        Text(verbatim: item.name)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary)
            .frame(
                width: max(
                    0,
                    width
                        - WindowCommandMenuPresenter.itemHorizontalPadding * 2
                ),
                height: WindowCommandMenuPresenter.menuBarHeight
            )
            .padding(
                .horizontal,
                WindowCommandMenuPresenter.itemHorizontalPadding
            )
            .background(background)
            .modifier(
                MenuControlModifier(
                    content: menuContent,
                    onMenuOpenChanged: { isOpen = $0 },
                    onMenuPressingChanged: { isPressing = $0 },
                    onPresentationChanged: nil
                )
            )
            .onHover { isHovered = $0 }
    }

    private var menuContent: some View {
        MainMenuItem.Content.item(item)
            .modifier(
                SectionStyleModifier(style: DefaultSectionStyle())
            )
            .modifier(
                LabelStyleWritingModifier(style: DefaultLabelStyle())
            )
            .environment(\.menuIndicatorVisibility, .automatic)
            .input(LabelVisibilityConfigured.self)
            .modifier(StyleContextWriter<MenuStyleContext>())
    }
}

// Commands are materialized from the app-root environment, not from the
// active Scene content environment. Host-specific scale and transient-window
// policy still come from the actual root window containing this menu.
private struct CommandMenuMaterializationEnvironmentModifier:
    ViewModifier,
    _GraphInputsModifier
{
    typealias Body = Never

    var environment: EnvironmentValues

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "CommandMenuMaterializationEnvironmentModifier._makeInputs "
                    + "called outside an active _AGGraph context."
            )
        }
        let parentEnvironment = inputs.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule {
            let modifier = modifier._attribute.value
            let host = parentEnvironment.value
            var result = modifier.environment.trackingCopy()
            result.displayScale = host.displayScale
            result._contentScaleFactor = host._contentScaleFactor
            result.defaultPresentationHostMode =
                host.defaultPresentationHostMode
            return result
        }
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }
}
