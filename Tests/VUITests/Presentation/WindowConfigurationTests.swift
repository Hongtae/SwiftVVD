import XCTest
@testable import VUI

final class WindowConfigurationTests: XCTestCase {
    func testApplyingOverrideChangesOnlySpecifiedFields() {
        var base = WindowConfiguration()
        base.activeFrameInterval = 0.1
        base.inactiveFrameInterval = 0.2
        base.displaySyncEnabled = true
        base.drawEveryFrames = true
        base.drawDebugInfo = [.frameInfo]
        base.drawDebugInfoPosition = CGPoint(x: 7, y: 9)
        base.contentScaleFactorOverride = 1.5

        let override = WindowConfiguration.Override(
            activeFrameInterval: 0.01,
            displaySyncEnabled: false,
            drawEveryFrames: false,
            drawDebugInfo: [.thread],
            drawDebugInfoPosition: CGPoint(x: 11, y: 13),
            contentScaleFactor: 2
        )
        let resolved = base.applying(override)

        XCTAssertEqual(resolved.activeFrameInterval, 0.01)
        XCTAssertEqual(resolved.inactiveFrameInterval, 0.2)
        XCTAssertFalse(resolved.displaySyncEnabled)
        XCTAssertFalse(resolved.drawEveryFrames)
        XCTAssertEqual(resolved.backgroundColor, base.backgroundColor)
        XCTAssertEqual(resolved.drawDebugInfo, [.thread])
        XCTAssertEqual(
            resolved.drawDebugInfoPosition,
            CGPoint(x: 11, y: 13)
        )
        XCTAssertEqual(resolved.contentScaleFactorOverride, 2)
    }

    func testEmptyOverridePreservesBaseConfiguration() {
        var base = WindowConfiguration()
        base.activeFrameInterval = 0.1
        base.inactiveFrameInterval = 0.2
        base.displaySyncEnabled = false
        base.drawEveryFrames = false
        base.drawDebugInfo = [.queue, .windowState]
        base.drawDebugInfoPosition = CGPoint(x: 17, y: 19)
        base.contentScaleFactorOverride = 1.5

        let resolved = base.applying(.init())

        XCTAssertEqual(resolved.activeFrameInterval, base.activeFrameInterval)
        XCTAssertEqual(resolved.inactiveFrameInterval, base.inactiveFrameInterval)
        XCTAssertEqual(resolved.displaySyncEnabled, base.displaySyncEnabled)
        XCTAssertEqual(resolved.drawEveryFrames, base.drawEveryFrames)
        XCTAssertEqual(resolved.backgroundColor, base.backgroundColor)
        XCTAssertEqual(resolved.drawDebugInfo, base.drawDebugInfo)
        XCTAssertEqual(
            resolved.drawDebugInfoPosition,
            base.drawDebugInfoPosition
        )
        XCTAssertEqual(
            resolved.contentScaleFactorOverride,
            base.contentScaleFactorOverride
        )
    }

    func testExplicitEmptyDebugOverrideClearsBaseDebugInfo() {
        var base = WindowConfiguration()
        base.drawDebugInfo = .all

        let resolved = base.applying(.init(drawDebugInfo: []))

        XCTAssertTrue(resolved.drawDebugInfo.isEmpty)
    }

    func testDebugInfoPositionDefaultsToTopLeadingInset() {
        XCTAssertEqual(
            WindowConfiguration().drawDebugInfoPosition,
            CGPoint(x: 5, y: 5)
        )
    }

    func testOverridePreferenceReductionUsesLastScalarAndUnionsDebugInfo() {
        var value = WindowConfiguration.Override(
            activeFrameInterval: 0.1,
            displaySyncEnabled: true,
            drawDebugInfo: [.frameInfo],
            drawDebugInfoPosition: CGPoint(x: 5, y: 33),
            contentScaleFactor: 1
        )

        WindowConfiguration.Override.Key.reduce(value: &value) {
            WindowConfiguration.Override(
                activeFrameInterval: 0.01,
                inactiveFrameInterval: 0.2,
                displaySyncEnabled: false,
                drawEveryFrames: false,
                drawDebugInfo: [.thread],
                drawDebugInfoPosition: CGPoint(x: 7, y: 41),
                contentScaleFactor: 3
            )
        }

        XCTAssertEqual(value.activeFrameInterval, 0.01)
        XCTAssertEqual(value.inactiveFrameInterval, 0.2)
        XCTAssertEqual(value.displaySyncEnabled, false)
        XCTAssertEqual(value.drawEveryFrames, false)
        XCTAssertEqual(value.drawDebugInfo, [.frameInfo, .thread])
        XCTAssertEqual(
            value.drawDebugInfoPosition,
            CGPoint(x: 7, y: 41)
        )
        XCTAssertEqual(value.contentScaleFactor, 3)

        WindowConfiguration.Override.Key.reduce(value: &value) {
            WindowConfiguration.Override(drawDebugInfo: [.queue])
        }
        XCTAssertEqual(
            value.drawDebugInfoPosition,
            CGPoint(x: 7, y: 41)
        )
    }

    func testFrameRateModifierMapsRenderingModesAndInactiveDefault() {
        XCTAssertTrue(WindowConfiguration().displaySyncEnabled)
        XCTAssertTrue(WindowConfiguration().drawEveryFrames)

        let inheritedInactive = _UpdateFrameRate(active: 120)
        XCTAssertEqual(inheritedInactive.active, 120)
        XCTAssertEqual(inheritedInactive.inactive, 120)
        XCTAssertEqual(
            inheritedInactive.renderingMode,
            .continuousWithDisplaySync
        )

        let explicitInactive = _UpdateFrameRate(
            active: 120,
            inactive: 30,
            renderingMode: .onDemand
        )
        XCTAssertEqual(explicitInactive.inactive, 30)

        let modes: [(FrameRenderingMode, Bool, Bool)] = [
            (.continuousWithDisplaySync, true, true),
            (.continuousWithoutDisplaySync, false, true),
            (.onDemand, true, false),
        ]
        for (mode, displaySyncEnabled, drawsEveryFrame) in modes {
            XCTAssertEqual(
                mode.displaySyncEnabled,
                displaySyncEnabled,
                "\(mode)"
            )
            XCTAssertEqual(
                mode.drawsEveryFrame,
                drawsEveryFrame,
                "\(mode)"
            )
        }

        _ = _EmptyScene().updateFrameRate(
            forActiveState: 120
        )
        _ = _EmptyScene().updateFrameRate(
            forActiveState: 300,
            forInactiveState: 300,
            renderingMode: .continuousWithoutDisplaySync
        )
        _ = _EmptyScene().updateFrameRate(
            forActiveState: 60,
            renderingMode: .onDemand
        )
    }

    @MainActor
    func testPresentationChildrenInheritAndTrackConfigurationOverride() {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowConfigurationTests.self)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.configurationOverride = .init(
            activeFrameInterval: 0.01,
            displaySyncEnabled: false,
            drawDebugInfo: [.frameInfo],
            drawDebugInfoPosition: CGPoint(x: 11, y: 13),
            contentScaleFactor: 2
        )

        let child = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: true
        )
        root.addPresentationChild(child: child)
        XCTAssertEqual(child.configurationOverride.activeFrameInterval, 0.01)
        XCTAssertEqual(child.configurationOverride.displaySyncEnabled, false)
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.frameInfo])
        XCTAssertEqual(
            child.configurationOverride.drawDebugInfoPosition,
            CGPoint(x: 11, y: 13)
        )
        XCTAssertEqual(child.configurationOverride.contentScaleFactor, 2)

        let nestedChild = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: true
        )
        child.addPresentationChild(child: nestedChild)

        root.configurationOverride = .init(
            inactiveFrameInterval: 0.2,
            displaySyncEnabled: true,
            drawDebugInfo: [.thread, .queue],
            drawDebugInfoPosition: CGPoint(x: 17, y: 19),
            contentScaleFactor: 3
        )

        for controller in [child, nestedChild] {
            XCTAssertNil(controller.configurationOverride.activeFrameInterval)
            XCTAssertEqual(controller.configurationOverride.inactiveFrameInterval, 0.2)
            XCTAssertEqual(controller.configurationOverride.displaySyncEnabled, true)
            XCTAssertEqual(controller.configurationOverride.drawDebugInfo, [.thread, .queue])
            XCTAssertEqual(
                controller.configurationOverride.drawDebugInfoPosition,
                CGPoint(x: 17, y: 19)
            )
            XCTAssertEqual(controller.configurationOverride.contentScaleFactor, 3)
        }
    }

    @MainActor
    func testMenuPopupTreeFiltersInheritedDebugOverlayConfiguration() {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowConfigurationTests.self, index: 2)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.configurationOverride = .init(
            activeFrameInterval: 0.01,
            displaySyncEnabled: false,
            drawDebugInfo: [.frameInfo, .thread],
            drawDebugInfoPosition: CGPoint(x: 23, y: 29),
            contentScaleFactor: 2
        )

        func makeMenuPopup() -> ContextMenuWindowController {
            ContextMenuWindowController(
                content: EmptyView(),
                environment: EnvironmentValues(),
                viewPhase: ViewGraphHost.Phase(),
                scene: scene,
                anchor: .zero,
                items: [],
                actions: ContextMenuPopupActions(),
                usesPlatformWindow: true,
                session: ContextMenuPresentationSession()
            )
        }

        let menu = makeMenuPopup()
        root.addPresentationChild(child: menu)
        let submenu = makeMenuPopup()
        menu.addPresentationChild(child: submenu)

        for controller in [menu, submenu] {
            XCTAssertEqual(controller.configurationOverride.activeFrameInterval, 0.01)
            XCTAssertEqual(controller.configurationOverride.displaySyncEnabled, false)
            XCTAssertNil(controller.configurationOverride.drawDebugInfo)
            XCTAssertNil(controller.configurationOverride.drawDebugInfoPosition)
            XCTAssertTrue(controller.configuration.drawDebugInfo.isEmpty)
            XCTAssertEqual(
                controller.configuration.drawDebugInfoPosition,
                CGPoint(x: 5, y: 5)
            )
            XCTAssertEqual(
                controller.configuration.backgroundColor,
                BackendColor(white: 0.96)
            )
            XCTAssertEqual(controller.configurationOverride.contentScaleFactor, 2)
        }

        var menuBaseConfiguration = menu.baseConfiguration
        menuBaseConfiguration.drawDebugInfo = [.resourceTiming]
        menuBaseConfiguration.drawDebugInfoPosition = CGPoint(x: 2, y: 3)
        menu.baseConfiguration = menuBaseConfiguration
        XCTAssertEqual(menu.configuration.drawDebugInfo, [.resourceTiming])
        XCTAssertEqual(
            menu.configuration.drawDebugInfoPosition,
            CGPoint(x: 2, y: 3)
        )

        root.configurationOverride = .init(
            inactiveFrameInterval: 0.2,
            displaySyncEnabled: true,
            drawDebugInfo: [.queue, .windowState],
            drawDebugInfoPosition: CGPoint(x: 31, y: 37),
            contentScaleFactor: 3
        )

        for controller in [menu, submenu] {
            XCTAssertNil(controller.configurationOverride.activeFrameInterval)
            XCTAssertEqual(controller.configurationOverride.inactiveFrameInterval, 0.2)
            XCTAssertEqual(controller.configurationOverride.displaySyncEnabled, true)
            XCTAssertEqual(controller.configurationOverride.contentScaleFactor, 3)
        }
        XCTAssertNil(menu.configurationOverride.drawDebugInfo)
        XCTAssertNil(menu.configurationOverride.drawDebugInfoPosition)
        XCTAssertEqual(menu.configuration.drawDebugInfo, [.resourceTiming])
        XCTAssertEqual(
            menu.configuration.drawDebugInfoPosition,
            CGPoint(x: 2, y: 3)
        )
        XCTAssertNil(submenu.configurationOverride.drawDebugInfo)
        XCTAssertNil(submenu.configurationOverride.drawDebugInfoPosition)
        XCTAssertTrue(submenu.configuration.drawDebugInfo.isEmpty)
        XCTAssertEqual(
            submenu.configuration.drawDebugInfoPosition,
            CGPoint(x: 5, y: 5)
        )
    }

    @MainActor
    func testPlatformModalChildrenInheritAndTrackConfigurationOverride() {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowConfigurationTests.self, index: 1)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.configurationOverride = .init(
            displaySyncEnabled: false,
            drawDebugInfo: [.windowState],
            drawDebugInfoPosition: CGPoint(x: 41, y: 43)
        )

        let content = AnyView(EmptyView())
        let child = root.viewGraph.data.withCurrent {
            let sourceGraph = root.viewGraph.data.graph
            let contentAttribute: Attribute<AnyView> = sourceGraph.makeInput(value: content)
            return ModalWindowController(
                crossGraphContent: contentAttribute,
                sourceGraph: sourceGraph,
                scene: scene,
                parentController: root,
                usesPlatformWindow: true
            )
        }
        root.addModal(
            child: child,
            session: .sheet(SheetPreference(
                content: content,
                onDismiss: nil,
                namespaceID: Namespace.ID(id: 92_001),
                itemID: nil,
                drawsBackground: true,
                placement: .automatic,
                activeInspector: nil,
                usesPlatformWindow: true
            ))
        )
        XCTAssertEqual(child.configurationOverride.displaySyncEnabled, false)
        XCTAssertFalse(child.configuration.displaySyncEnabled)
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.windowState])
        XCTAssertEqual(
            child.configurationOverride.drawDebugInfoPosition,
            CGPoint(x: 41, y: 43)
        )

        root.configurationOverride = .init(
            activeFrameInterval: 0.02,
            displaySyncEnabled: true,
            drawDebugInfo: [.appState],
            drawDebugInfoPosition: CGPoint(x: 47, y: 53)
        )

        XCTAssertEqual(child.configurationOverride.activeFrameInterval, 0.02)
        XCTAssertEqual(child.configurationOverride.displaySyncEnabled, true)
        XCTAssertTrue(child.configuration.displaySyncEnabled)
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.appState])
        XCTAssertEqual(
            child.configurationOverride.drawDebugInfoPosition,
            CGPoint(x: 47, y: 53)
        )
    }
}
