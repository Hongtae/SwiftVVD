//
//  File: PlatformCommandMenuPresenter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

extension CommandMenuPresentationStyle {
    // Automatic is resolved only where a root chooses its actual presenter.
    // Other platforms keep the framework-rendered bar even when a system-menu
    // capability may be added for an explicit platform request.
    var resolvedForRootPresenter: CommandMenuPresentationStyle {
        switch self {
        case .automatic:
#if os(macOS)
            return .platform
#else
            return .window
#endif
        case .window, .platform:
            return self
        }
    }

    func rootPresenterSelection(
        platformControllerAvailable: Bool?
    ) -> RootCommandMenuPresenterSelection {
        switch resolvedForRootPresenter {
        case .automatic:
            fatalError("Automatic must resolve before presenter selection.")
        case .window:
            return .window
        case .platform:
            switch platformControllerAvailable {
            case true:
                return .platform
            case false:
                return .window
            case nil:
                return .pendingPlatformCapability
            }
        }
    }
}

enum RootCommandMenuPresenterSelection: Equatable {
    case pendingPlatformCapability
    case window
    case platform
}

// Owns the semantic menu hosts for one static Scene root. The Commands list
// remains app-owned and shared; this object only materializes root presenter
// state from the already resolved list.
final class PlatformCommandMenuPresenter: MainMenuItemHostDelegate,
                                          @unchecked Sendable {
    private struct Entry {
        var item: MainMenuItem
        var host: MainMenuItemHost
        var cachedItems: PlatformItemList?

        var menuID: WindowMenu.ID {
            item.id.windowMenuID
        }
    }

    private weak var owner: WindowController?
    private let controllerBridge: PlatformCommandMenuControllerBridge
    private let actionDispatcher: PlatformCommandMenuActionDispatcher
    private let generation = Atomic<UInt64>(0)

    private var entries: [Entry] = []
    private var invalidEntryIDs: Set<MainMenuItem.Identifier> = []
    private var materializationEnvironment = EnvironmentValues()
    private var conversionTask: Task<Void, Never>?

    init(owner: WindowController) {
        self.owner = owner
        self.controllerBridge = PlatformCommandMenuControllerBridge(owner: owner)
        self.actionDispatcher = PlatformCommandMenuActionDispatcher(owner: owner)
    }

    func update(
        items: [MainMenuItem],
        environment: EnvironmentValues
    ) {
        var previous = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.item.id, $0) }
        )
        entries = items.map { item in
            if var entry = previous.removeValue(forKey: item.id) {
                entry.item = item
                entry.host.update(item: item, environment: environment)
                return entry
            }

            let host = MainMenuItemHost(
                item: item,
                environment: environment
            )
            host.delegate = self
            return Entry(item: item, host: host, cachedItems: nil)
        }
        for entry in previous.values {
            entry.host.delegate = nil
        }

        materializationEnvironment = environment.untrackedCopy()
        invalidEntryIDs = Set(items.map(\.id))
    }

    @MainActor
    func attach(to window: any PlatformWindow) {
        attach(to: window.menuController)
    }

    @MainActor
    func attach(to controller: (any WindowMenuController)?) {
        controllerBridge.attach(
            to: controller,
            minimumGeneration: currentGeneration
        )
    }

    func invalidate() {
        conversionTask?.cancel()
        conversionTask = nil
        for entry in entries {
            entry.host.delegate = nil
        }
        entries.removeAll()
        invalidEntryIDs.removeAll()

        let generation = nextGeneration()
        Task { @MainActor [controllerBridge] in
            controllerBridge.detach(minimumGeneration: generation)
        }
    }

    func requestRefresh(menuID: WindowMenu.ID?) {
        guard let menuID else {
            invalidEntryIDs.formUnion(entries.map(\.item.id))
            return
        }

        var found = false
        for entry in entries where menuID == entry.menuID
            || menuID.hasPrefix(entry.menuID + "/") {
            invalidEntryIDs.insert(entry.item.id)
            found = true
        }
        if !found {
            invalidEntryIDs.formUnion(entries.map(\.item.id))
        }
    }

    func update(at time: Time) {
        guard !invalidEntryIDs.isEmpty else { return }

        for index in entries.indices
            where invalidEntryIDs.contains(entries[index].item.id) {
            let host = entries[index].host
            host.currentTimestamp = time
            entries[index].cachedItems = host.menuItems()
        }
        invalidEntryIDs.removeAll()

        let pendingMenus = entries.compactMap { entry -> PendingWindowMenu? in
            guard let items = entry.cachedItems else { return nil }
            return PendingWindowMenu(
                id: entry.menuID,
                title: entry.item.name,
                role: entry.item.id.windowMenuRole,
                items: items
            )
        }
        let input = PendingWindowMenuSnapshot(
            menus: pendingMenus,
            environment: materializationEnvironment,
            actionDispatcher: actionDispatcher
        )
        let device = appContext?.graphicsDeviceContext?.device
        let generation = nextGeneration()
        let controllerBridge = self.controllerBridge

        conversionTask?.cancel()
        conversionTask = Task.detached(priority: .utility) {
            guard let menu = WindowMenuSnapshotBuilder.build(
                input,
                graphicsDevice: device
            ), !Task.isCancelled else {
                return
            }
            await controllerBridge.publish(
                menu,
                generation: generation
            )
        }
    }

    func menuHostDidChangeMenuItems(_ host: MainMenuItemHost) {
        let hostID = ObjectIdentifier(host)
        owner?.enqueueInputAction { [weak self] in
            guard let self,
                  let entry = self.entries.first(where: {
                      ObjectIdentifier($0.host) == hostID
                  }) else {
                return
            }
            self.invalidEntryIDs.insert(entry.item.id)
        }
    }

    private var currentGeneration: UInt64 {
        generation.load(ordering: .relaxed)
    }

    private func nextGeneration() -> UInt64 {
        generation.wrappingAdd(1, ordering: .relaxed).oldValue &+ 1
    }
}

private final class PlatformCommandMenuControllerBridge:
    WindowMenuControllerDelegate, @unchecked Sendable {
    private weak var owner: WindowController?

    @MainActor private weak var controller: (any WindowMenuController)?
    @MainActor private var minimumGeneration: UInt64 = 0
    @MainActor private var latestMenu: WindowMenu?
    @MainActor private var latestMenuGeneration: UInt64 = 0

    nonisolated init(owner: WindowController) {
        self.owner = owner
    }

    @MainActor
    func attach(
        to controller: (any WindowMenuController)?,
        minimumGeneration: UInt64
    ) {
        guard minimumGeneration >= self.minimumGeneration else { return }
        if self.controller !== controller {
            if self.controller?.delegate === self {
                self.controller?.delegate = nil
                self.controller?.setMenu(nil)
            }
            self.controller = controller
        }
        self.minimumGeneration = minimumGeneration
        controller?.delegate = self
        if latestMenuGeneration >= minimumGeneration {
            controller?.setMenu(latestMenu)
        }
    }

    @MainActor
    func detach(minimumGeneration: UInt64) {
        guard minimumGeneration >= self.minimumGeneration else { return }
        self.minimumGeneration = minimumGeneration
        if controller?.delegate === self {
            controller?.delegate = nil
            controller?.setMenu(nil)
        }
        controller = nil
        latestMenu = nil
        latestMenuGeneration = minimumGeneration
    }

    @MainActor
    func publish(_ menu: WindowMenu, generation: UInt64) {
        guard generation >= minimumGeneration,
              generation >= latestMenuGeneration else {
            return
        }
        latestMenu = menu
        latestMenuGeneration = generation
        controller?.setMenu(menu)
    }

    @MainActor
    func windowMenuController(
        _ controller: any WindowMenuController,
        needsUpdateMenu menuID: WindowMenu.ID?
    ) {
        guard self.controller === controller else { return }
        owner?.enqueueInputAction { [weak owner] in
            owner?.platformCommandMenuPresenter?.requestRefresh(menuID: menuID)
        }
    }
}

private final class PlatformCommandMenuActionBox: @unchecked Sendable {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

final class PlatformCommandMenuActionDispatcher: @unchecked Sendable {
    private weak var owner: WindowController?

    init(owner: WindowController) {
        self.owner = owner
    }

    fileprivate func dispatch(_ box: PlatformCommandMenuActionBox) {
        owner?.enqueueInputAction {
            box.action()
        }
    }
}

struct PendingWindowMenu {
    var id: WindowMenu.ID
    var title: String
    var role: WindowMenu.Role
    var items: PlatformItemList
}

// The semantic item list is immutable after the root host publishes it. Its
// closures and resolved GPU resources are retained as one snapshot while the
// detached converter reads them; actions are never invoked on that task.
struct PendingWindowMenuSnapshot: @unchecked Sendable {
    var menus: [PendingWindowMenu]
    var environment: EnvironmentValues
    var actionDispatcher: PlatformCommandMenuActionDispatcher
}

enum WindowMenuSnapshotBuilder {
    static func build(
        _ input: PendingWindowMenuSnapshot,
        graphicsDevice: (any GraphicsDevice)?
    ) -> WindowMenu? {
        var imageRenderer = graphicsDevice.flatMap {
            PlatformCommandMenuImageRenderer(
                device: $0,
                environment: input.environment
            )
        }
        var menus: [WindowMenu.Menu] = []
        menus.reserveCapacity(input.menus.count)

        for pending in input.menus {
            guard !Task.isCancelled else { return nil }
            let elements = makeElements(
                pending.items.items,
                parentID: pending.id,
                imageRenderer: &imageRenderer,
                actionDispatcher: input.actionDispatcher
            )
            menus.append(WindowMenu.Menu(
                id: pending.id,
                title: pending.title,
                role: pending.role,
                elements: elements
            ))
        }
        return WindowMenu(menus: menus)
    }

    private static func makeElements(
        _ items: [PlatformItemList.Item],
        parentID: WindowMenu.ID,
        imageRenderer: inout PlatformCommandMenuImageRenderer?,
        actionDispatcher: PlatformCommandMenuActionDispatcher
    ) -> [WindowMenu.Element] {
        var result: [WindowMenu.Element] = []
        for (index, item) in items.enumerated() {
            guard !Task.isCancelled else { return [] }
            let itemID = resolvedID(
                for: item,
                parentID: parentID,
                index: index
            )

            if case .divider? = item.systemItem {
                result.append(.separator)
                continue
            }

            if case .section? = item.systemItem {
                result.append(.separator)
                if item.label != nil || item.text != nil {
                    result.append(.item(makeItem(
                        item,
                        id: itemID + "/header",
                        imageRenderer: &imageRenderer,
                        actionDispatcher: actionDispatcher,
                        forcesDisabled: true
                    )))
                }
                if let children = item.children {
                    result.append(contentsOf: makeElements(
                        children.items,
                        parentID: itemID + "/section",
                        imageRenderer: &imageRenderer,
                        actionDispatcher: actionDispatcher
                    ))
                }
                result.append(.separator)
                continue
            }

            if let children = item.children {
                let elements = makeElements(
                    children.items,
                    parentID: itemID,
                    imageRenderer: &imageRenderer,
                    actionDispatcher: actionDispatcher
                )
                result.append(.submenu(WindowMenu.Menu(
                    id: itemID,
                    title: title(for: item),
                    image: imageRenderer?.image(for: item),
                    scalesImageToFit: item.scaleDownMenuImage,
                    isEnabled: true,
                    isHidden: item.isHidden,
                    usesPlatformItemValidation:
                        item.wantsPlatformInterfaceValidation,
                    elements: elements
                )))
                continue
            }

            result.append(.item(makeItem(
                item,
                id: itemID,
                imageRenderer: &imageRenderer,
                actionDispatcher: actionDispatcher
            )))
        }
        return result
    }

    private static func makeItem(
        _ item: PlatformItemList.Item,
        id: WindowMenu.ID,
        imageRenderer: inout PlatformCommandMenuImageRenderer?,
        actionDispatcher: PlatformCommandMenuActionDispatcher,
        forcesDisabled: Bool = false
    ) -> WindowMenu.Item {
        let actionBox = item.selectionBehavior?.onSelect.map(
            PlatformCommandMenuActionBox.init
        )
        let action: WindowMenu.Action?
        if let actionBox {
            action = { @MainActor @Sendable in
                actionDispatcher.dispatch(actionBox)
            }
        } else {
            action = nil
        }
        let hasAction = action != nil
        let canUsePlatformValidation =
            item.wantsPlatformInterfaceValidation

        return WindowMenu.Item(
            id: id,
            title: title(for: item),
            image: imageRenderer?.image(for: item),
            scalesImageToFit: item.scaleDownMenuImage,
            state: state(for: item.toggleState),
            isEnabled: !forcesDisabled && item.isEnabled
                && (hasAction || canUsePlatformValidation),
            isHidden: item.isHidden,
            isAlternate: item.isAlternate,
            indentationLevel: item.indentationLevel,
            allowsShortcutWhenHidden: item.allowsKeyEquivalentWhenHidden,
            shortcut: item.keyboardShortcut.map(shortcut),
            toolTip: item.tooltip,
            action: action
        )
    }

    private static func title(for item: PlatformItemList.Item) -> String {
        (item.label ?? item.text)?.string ?? ""
    }

    private static func resolvedID(
        for item: PlatformItemList.Item,
        parentID: WindowMenu.ID,
        index: Int
    ) -> WindowMenu.ID {
        if let identifier = item.platformIdentifier {
            return parentID + "/" + identifier
        }
        return parentID + "/item-" + String(index)
    }

    private static func state(for state: ToggleState?) -> WindowMenu.State {
        switch state {
        case .on?: .on
        case .off?, nil: .off
        case .mixed?: .mixed
        }
    }

    private static func shortcut(
        _ shortcut: KeyboardShortcut
    ) -> WindowMenu.Shortcut {
        WindowMenu.Shortcut(
            shortcutKey(shortcut.key.character),
            modifiers: keyboardModifiers(shortcut.modifiers)
        )
    }

    private static func shortcutKey(
        _ character: Character
    ) -> WindowMenu.Shortcut.Key {
        let virtualKey: VirtualKey? = switch character {
        case "\u{1B}": .escape
        case "\u{7F}": .backspace
        case "\u{F700}": .up
        case "\u{F701}": .down
        case "\u{F702}": .left
        case "\u{F703}": .right
        case "\u{F704}": .f1
        case "\u{F705}": .f2
        case "\u{F706}": .f3
        case "\u{F707}": .f4
        case "\u{F708}": .f5
        case "\u{F709}": .f6
        case "\u{F70A}": .f7
        case "\u{F70B}": .f8
        case "\u{F70C}": .f9
        case "\u{F70D}": .f10
        case "\u{F70E}": .f11
        case "\u{F70F}": .f12
        case "\u{F710}": .f13
        case "\u{F711}": .f14
        case "\u{F712}": .f15
        case "\u{F713}": .f16
        case "\u{F714}": .f17
        case "\u{F715}": .f18
        case "\u{F716}": .f19
        case "\u{F717}": .f20
        case "\u{F728}": .delete
        case "\u{F729}": .home
        case "\u{F72B}": .end
        case "\u{F72C}": .pageUp
        case "\u{F72D}": .pageDown
        case "\t": .tab
        case " ": .space
        case "\r": .return
        default: nil
        }
        if let virtualKey {
            return .virtual(virtualKey)
        }
        return .character(character)
    }

    private static func keyboardModifiers(
        _ modifiers: EventModifiers
    ) -> KeyboardModifierFlags {
        var result: KeyboardModifierFlags = []
        if modifiers.contains(.capsLock) { result.insert(.capsLock) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.numericPad) { result.insert(.numericPad) }
        if modifiers.contains(.function) { result.insert(.function) }
        return result
    }
}

private final class PlatformCommandMenuImageRenderer {
    private static let pointSize: CGFloat = 16
    private static let scale: CGFloat = 2
    private static let completionTimeout = 5.0

    private let deviceContext: GraphicsDeviceContext
    private let commandQueue: CommandQueue
    private let environment: EnvironmentValues

    init?(device: any GraphicsDevice, environment: EnvironmentValues) {
        let deviceContext = GraphicsDeviceContext(device: device)
        guard GraphicsContext.cachePipelineContext(deviceContext),
              let commandQueue = deviceContext.renderQueue() else {
            return nil
        }
        self.deviceContext = deviceContext
        self.commandQueue = commandQueue
        self.environment = environment
    }

    func image(for item: PlatformItemList.Item) -> VVD.Image? {
        guard item.namedResolvedImage != nil || item.resolvedImage != nil,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        let pixelSize = Int(Self.pointSize * Self.scale)
        let sceneResources = SceneResources()
        sceneResources.contentScaleFactor = Self.scale
        guard let context = GraphicsContext(
            sceneResources: sceneResources,
            environment: environment,
            viewport: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            contentOffset: .zero,
            contentScaleFactor: Self.scale,
            resolution: CGSize(width: pixelSize, height: pixelSize),
            commandBuffer: commandBuffer
        ) else {
            return nil
        }

        var resolved: GraphicsContext.ResolvedImage
        if let namedImage = item.namedResolvedImage {
            resolved = context.resolve(namedImage)
        } else if let image = item.resolvedImage {
            resolved = image
        } else {
            return nil
        }
        if let tint = item.tint {
            resolved.shading = .color(tint)
        }

        let sourceSize = resolved.size
        guard sourceSize.width.isFinite, sourceSize.height.isFinite,
              sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }
        let scale = min(
            1,
            Self.pointSize / max(sourceSize.width, sourceSize.height)
        )
        let drawSize = sourceSize * scale
        let drawRect = CGRect(
            x: (Self.pointSize - drawSize.width) * 0.5,
            y: (Self.pointSize - drawSize.height) * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )

        context.clear(with: .clear)
        context.draw(resolved, in: drawRect)
        guard commitAndWait(commandBuffer), !Task.isCancelled,
              let staging = deviceContext.makeCPUAccessible(
                  texture: context.backdrop
              ) else {
            return nil
        }
        return VVD.Image.fromTexture(
            buffer: staging,
            width: context.backdrop.width,
            height: context.backdrop.height,
            pixelFormat: context.backdrop.pixelFormat
        )
    }

    private func commitAndWait(_ commandBuffer: CommandBuffer) -> Bool {
        let condition = NSCondition()
        var completed = false
        commandBuffer.addCompletedHandler { _ in
            condition.lock()
            completed = true
            condition.broadcast()
            condition.unlock()
        }

        condition.lock()
        defer { condition.unlock() }
        guard commandBuffer.commit() else { return false }
        let deadline = Date(timeIntervalSinceNow: Self.completionTimeout)
        while !completed {
            if !condition.wait(until: deadline) {
                Log.error("Timed out while rendering a platform menu image.")
                return false
            }
        }
        return true
    }
}

private extension MainMenuItem.Identifier {
    var windowMenuID: WindowMenu.ID {
        switch self {
        case let .custom(id): "commands.custom." + id.uuidString
        case .app: "commands.application"
        case .file: "commands.file"
        case .edit: "commands.edit"
        case .format: "commands.format"
        case .view: "commands.view"
        case .window: "commands.window"
        case .help: "commands.help"
        case .dock: "commands.dock"
        case .invalid: "commands.invalid"
        case .root: "commands.root"
        }
    }

    var windowMenuRole: WindowMenu.Role {
        switch self {
        case .app: .application
        case .file: .file
        case .edit: .edit
        case .format: .format
        case .view: .view
        case .window: .window
        case .help: .help
        case .custom, .dock, .invalid, .root: .custom
        }
    }
}
