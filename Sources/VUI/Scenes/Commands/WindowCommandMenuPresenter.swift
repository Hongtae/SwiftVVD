//
//  File: WindowCommandMenuPresenter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// Materializes the renderer-owned root menu without introducing a second
// display-list or input path. The root WindowController installs the returned
// view only while this presenter is selected.
final class WindowCommandMenuPresenter {
    private struct KeyStream: Hashable {
        var deviceID: Int
        var key: VirtualKey
    }

    private struct MenuResponder {
        var id: MainMenuItem.Identifier
        var responder: MenuControlResponder
    }

    static let menuBarHeight: CGFloat = 28
    fileprivate static let itemHorizontalPadding: CGFloat = 8

    private(set) var items: [MainMenuItem] = []
    private(set) var environment = EnvironmentValues()
    private var itemWidths: [MainMenuItem.Identifier: CGFloat] = [:]
    private var accessKeys: [MainMenuItem.Identifier: Character] = [:]
    private(set) var keyboardSelectedItemID: MainMenuItem.Identifier?
    private(set) var keyboardMenuIsActive = false
    private var consumedKeyStreams: Set<KeyStream> = []
    private var pendingOptionKeyStream: KeyStream?
    private var retainedClosingMenuID: MainMenuItem.Identifier?
    private weak var keyboardOwner: WindowController?

    func update(
        items: [MainMenuItem],
        environment: EnvironmentValues,
        hostEnvironment: EnvironmentValues,
        sceneResources: SceneResources
    ) {
        self.items = items
        self.environment = environment.untrackedCopy()
        accessKeys = resolvedMenuAccessKeys(
            for: items.map { (id: $0.id, title: $0.name) }
        )
        if let keyboardSelectedItemID,
           !items.contains(where: { $0.id == keyboardSelectedItemID }) {
            self.keyboardSelectedItemID = nil
            keyboardMenuIsActive = false
        }
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
                menuEnvironment: environment,
                presenter: self
            )
        )
    }

    func accessKey(for id: MainMenuItem.Identifier) -> Character? {
        accessKeys[id]
    }

    @discardableResult
    func handleKeyboardEvent(
        _ event: KeyboardEvent,
        in owner: WindowController,
        isMenuBoundary: Bool = false
    ) -> Bool {
        keyboardOwner = owner
        let stream = KeyStream(deviceID: event.deviceID, key: event.key)

        if event.type == .keyUp {
            if pendingOptionKeyStream == stream {
                pendingOptionKeyStream = nil
                let responders = menuResponders(in: owner)
                if keyboardMenuIsActive {
                    leaveKeyboardMenu(using: responders)
                } else {
                    selectFirstMenu(using: responders)
                }
            }
            return consumedKeyStreams.remove(stream) != nil
        }

        guard event.type == .keyDown else { return false }

        if event.key == .leftOption || event.key == .rightOption {
            if !event.isRepeat {
                pendingOptionKeyStream = stream
            }
            consumedKeyStreams.insert(stream)
            return true
        }

        // Any non-modifier key turns a pending bare-Option gesture into a
        // chord. Its eventual key-up remains consumed, but does not toggle the
        // menu bar a second time.
        pendingOptionKeyStream = nil
        let responders = menuResponders(in: owner)

        if isAccessKeyChord(event),
           let character = event.key.shortcutCharacter
                ?? event.text.first,
           let id = itemID(forAccessKey: character),
           let menu = responders.first(where: { $0.id == id }) {
            consumedKeyStreams.insert(stream)
            owner.viewGraph.data.withCurrent {
                openMenu(menu, among: responders, in: owner)
            }
            return true
        }

        let navigationModifiers = event.modifiers.subtracting([
            .capsLock,
            .numericPad,
            .function,
        ])

        // Once a popup is open, its row controller owns navigation and access
        // keys. It forwards only left/right/Escape boundary operations back to
        // this presenter. Root shortcuts with actual modifiers still bypass
        // the popup and search the complete mounted command tree below.
        if !isMenuBoundary,
           responders.contains(where: { $0.responder.menuIsOpen }) {
            switch event.key {
            case .up, .down, .home, .end,
                 .left, .right,
                 .return, .enter, .space, .escape:
                return false
            default:
                let accessModifiers = navigationModifiers.subtracting(.shift)
                if accessModifiers.isEmpty,
                   event.key.shortcutCharacter != nil
                    || event.text.first != nil {
                    return false
                }
            }
        }
        if navigationModifiers.isEmpty {
            switch event.key {
            case .f10:
                consumedKeyStreams.insert(stream)
                if !event.isRepeat {
                    if keyboardMenuIsActive {
                        leaveKeyboardMenu(using: responders)
                    } else {
                        selectFirstMenu(using: responders)
                    }
                }
                return true

            case .left:
                let moved = owner.viewGraph.data.withCurrent {
                    moveSelection(
                        by: -1,
                        among: responders,
                        in: owner
                    )
                }
                guard moved else { break }
                consumedKeyStreams.insert(stream)
                return true

            case .right:
                let moved = owner.viewGraph.data.withCurrent {
                    moveSelection(
                        by: 1,
                        among: responders,
                        in: owner
                    )
                }
                guard moved else { break }
                consumedKeyStreams.insert(stream)
                return true

            case .down, .return, .enter, .space:
                let opened = owner.viewGraph.data.withCurrent {
                    openSelectedMenu(
                        among: responders,
                        in: owner
                    )
                }
                guard opened else { break }
                consumedKeyStreams.insert(stream)
                return true

            case .escape:
                guard keyboardMenuIsActive
                        || responders.contains(where: {
                            $0.responder.menuIsOpen
                        }) else {
                    break
                }
                consumedKeyStreams.insert(stream)
                escapeMenu(using: responders)
                return true

            default:
                break
            }
        }

        guard let key = KeyEquivalent(platformEvent: event),
              let action = shortcutAction(
                key: key,
                modifiers: EventModifiers(platformFlags: event.modifiers),
                responders: responders,
                in: owner
              ) else {
            return false
        }
        consumedKeyStreams.insert(stream)
        leaveKeyboardMenu(using: responders)
        Update.enqueueAction(action)
        return true
    }

    func menuOpenChanged(
        _ id: MainMenuItem.Identifier,
        isOpen: Bool
    ) {
        guard keyboardMenuIsActive else { return }
        if isOpen {
            guard keyboardSelectedItemID != id else { return }
            keyboardSelectedItemID = id
            synchronizeKeyboardState()
            return
        }
        if retainedClosingMenuID == id {
            retainedClosingMenuID = nil
            return
        }
        guard keyboardSelectedItemID == id else { return }
        keyboardSelectedItemID = nil
        keyboardMenuIsActive = false
        synchronizeKeyboardState()
    }

    private func menuResponders(
        in owner: WindowController
    ) -> [MenuResponder] {
        guard let root = owner.responderNode else { return [] }
        var byID: [MainMenuItem.Identifier: MenuControlResponder] = [:]
        _ = root.visit { responder in
            guard let menu = responder as? MenuControlResponder,
                  let id = menu.menuBarItemIdentifier?.base
                    as? MainMenuItem.Identifier else {
                return .next
            }
            byID[id] = menu
            return .skipToNextSibling
        }
        return items.compactMap { item in
            byID[item.id].map { MenuResponder(id: item.id, responder: $0) }
        }
    }

    private func selectFirstMenu(using responders: [MenuResponder]) {
        guard let first = responders.first(where: {
            $0.responder.isEnabled != false
        }) else { return }
        keyboardMenuIsActive = true
        keyboardSelectedItemID = first.id
        synchronizeKeyboardState(responders)
    }

    private func leaveKeyboardMenu(using responders: [MenuResponder]) {
        keyboardMenuIsActive = false
        keyboardSelectedItemID = nil
        retainedClosingMenuID = nil
        if let open = responders.first(where: { $0.responder.menuIsOpen }) {
            open.responder.dismissMenu()
        }
        synchronizeKeyboardState(responders)
    }

    private func escapeMenu(using responders: [MenuResponder]) {
        if let open = responders.first(where: { $0.responder.menuIsOpen }) {
            keyboardMenuIsActive = true
            keyboardSelectedItemID = open.id
            retainedClosingMenuID = open.id
            open.responder.dismissMenu()
            synchronizeKeyboardState(responders)
        } else {
            leaveKeyboardMenu(using: responders)
        }
    }

    private func moveSelection(
        by offset: Int,
        among responders: [MenuResponder],
        in owner: WindowController
    ) -> Bool {
        let enabled = responders.filter { $0.responder.isEnabled != false }
        guard !enabled.isEmpty else { return false }
        let open = enabled.first(where: { $0.responder.menuIsOpen })
        guard keyboardMenuIsActive || open != nil else { return false }

        let currentID = keyboardSelectedItemID ?? open?.id
        let currentIndex = currentID.flatMap { id in
            enabled.firstIndex(where: { $0.id == id })
        } ?? (offset > 0 ? -1 : 0)
        let count = enabled.count
        let nextIndex = (currentIndex + offset + count) % count
        let next = enabled[nextIndex]
        let switchesOpenMenu = open != nil

        keyboardMenuIsActive = true
        keyboardSelectedItemID = next.id
        synchronizeKeyboardState(responders)
        if switchesOpenMenu, open?.id != next.id {
            open?.responder.dismissMenu()
            next.responder.present(from: owner, selectsFirstItem: true)
        }
        return true
    }

    private func openSelectedMenu(
        among responders: [MenuResponder],
        in owner: WindowController
    ) -> Bool {
        let selectedID = keyboardSelectedItemID
            ?? responders.first(where: { $0.responder.menuIsOpen })?.id
        guard let selectedID,
              let menu = responders.first(where: {
                  $0.id == selectedID && $0.responder.isEnabled != false
              }) else {
            return false
        }
        openMenu(menu, among: responders, in: owner)
        return true
    }

    private func openMenu(
        _ menu: MenuResponder,
        among responders: [MenuResponder],
        in owner: WindowController
    ) {
        keyboardMenuIsActive = true
        keyboardSelectedItemID = menu.id
        synchronizeKeyboardState(responders)
        if let open = responders.first(where: {
            $0.id != menu.id && $0.responder.menuIsOpen
        }) {
            open.responder.dismissMenu()
        }
        if !menu.responder.menuIsOpen {
            menu.responder.present(from: owner, selectsFirstItem: true)
        }
    }

    private func shortcutAction(
        key: KeyEquivalent,
        modifiers: EventModifiers,
        responders: [MenuResponder],
        in owner: WindowController
    ) -> (() -> Void)? {
        owner.viewGraph.data.withCurrent {
            for menu in responders {
                if let action = Self.shortcutAction(
                    key: key,
                    modifiers: modifiers,
                    in: menu.responder.itemList.value
                ) {
                    return action
                }
            }
            return nil
        }
    }

    private static func shortcutAction(
        key: KeyEquivalent,
        modifiers: EventModifiers,
        in list: PlatformItemList
    ) -> (() -> Void)? {
        for item in list.items {
            let participates = !item.isHidden
                || item.allowsKeyEquivalentWhenHidden
            if participates,
               item.isEnabled,
               let shortcut = item.keyboardShortcut,
               shortcut.modifiers == modifiers,
               equivalent(shortcut.key, key),
               let action = item.selectionBehavior?.onSelect {
                return action
            }
            if let children = item.children,
               let action = shortcutAction(
                    key: key,
                    modifiers: modifiers,
                    in: children
               ) {
                return action
            }
            if let children = item.labelGroupChildren,
               let action = shortcutAction(
                    key: key,
                    modifiers: modifiers,
                    in: children
               ) {
                return action
            }
        }
        return nil
    }

    private static func equivalent(
        _ lhs: KeyEquivalent,
        _ rhs: KeyEquivalent
    ) -> Bool {
        menuCharactersAreEquivalent(lhs.character, rhs.character)
    }

    private func synchronizeKeyboardState(
        _ responders: [MenuResponder]? = nil
    ) {
        let responders = responders
            ?? keyboardOwner.map(menuResponders(in:))
            ?? []
        for menu in responders {
            menu.responder.updateKeyboardMenuState(
                isSelected: keyboardMenuIsActive
                    && keyboardSelectedItemID == menu.id,
                showsAccessKeys: keyboardMenuIsActive
            )
        }
    }

    private func isAccessKeyChord(_ event: KeyboardEvent) -> Bool {
        event.modifiers.contains(.option)
            && !event.modifiers.contains(.command)
            && !event.modifiers.contains(.control)
    }

    private func itemID(
        forAccessKey character: Character
    ) -> MainMenuItem.Identifier? {
        items.first { item in
            accessKeys[item.id].map {
                menuCharactersAreEquivalent($0, character)
            } == true
        }?.id
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
    var presenter: WindowCommandMenuPresenter

    var body: some View {
        VStack(spacing: 0) {
            WindowCommandMenuBar(
                items: items,
                itemWidths: itemWidths,
                menuEnvironment: menuEnvironment,
                presenter: presenter
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
    var presenter: WindowCommandMenuPresenter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.id) { item in
                WindowCommandMenuItem(
                    item: item,
                    width: itemWidths[item.id]
                        ?? WindowCommandMenuPresenter.menuBarHeight,
                    accessKey: presenter.accessKey(for: item.id),
                    presenter: presenter
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
    var accessKey: Character?
    var presenter: WindowCommandMenuPresenter

    @State private var isHovered = false
    @State private var isPressing = false
    @State private var isOpen = false
    @State private var isKeyboardSelected = false
    @State private var showsAccessKey = false

    private var background: Color {
        if isPressing || isOpen || isKeyboardSelected {
            return Color(white: 0.78)
        }
        if isHovered {
            return Color(white: 0.86)
        }
        return .clear
    }

    var body: some View {
        menuTitle
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
                    menuBarItemIdentifier: AnyHashable(item.id),
                    onMenuOpenChanged: { isOpen in
                        self.isOpen = isOpen
                        presenter.menuOpenChanged(item.id, isOpen: isOpen)
                    },
                    onMenuPressingChanged: { isPressing = $0 },
                    onKeyboardMenuStateChanged: {
                        isSelected,
                        showsAccessKeys in
                        isKeyboardSelected = isSelected
                        showsAccessKey = showsAccessKeys
                    },
                    onPresentationChanged: nil
                )
            )
            .onHover { isHovered = $0 }
    }

    private var menuTitle: Text {
        menuAccessKeyText(
            item.name,
            accessKey: accessKey,
            showsAccessKey: showsAccessKey
        )
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
