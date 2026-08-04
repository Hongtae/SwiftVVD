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
        base.contentScaleFactorOverride = 1.5

        let override = WindowConfiguration.Override(
            activeFrameInterval: 0.01,
            displaySyncEnabled: false,
            drawEveryFrames: false,
            drawDebugInfo: [.thread],
            contentScaleFactor: 2
        )
        let resolved = base.applying(override)

        XCTAssertEqual(resolved.activeFrameInterval, 0.01)
        XCTAssertEqual(resolved.inactiveFrameInterval, 0.2)
        XCTAssertFalse(resolved.displaySyncEnabled)
        XCTAssertFalse(resolved.drawEveryFrames)
        XCTAssertEqual(resolved.backgroundColor, base.backgroundColor)
        XCTAssertEqual(resolved.drawDebugInfo, [.thread])
        XCTAssertEqual(resolved.contentScaleFactorOverride, 2)
    }

    func testEmptyOverridePreservesBaseConfiguration() {
        var base = WindowConfiguration()
        base.activeFrameInterval = 0.1
        base.inactiveFrameInterval = 0.2
        base.displaySyncEnabled = false
        base.drawEveryFrames = false
        base.drawDebugInfo = [.queue, .windowState]
        base.contentScaleFactorOverride = 1.5

        let resolved = base.applying(.init())

        XCTAssertEqual(resolved.activeFrameInterval, base.activeFrameInterval)
        XCTAssertEqual(resolved.inactiveFrameInterval, base.inactiveFrameInterval)
        XCTAssertEqual(resolved.displaySyncEnabled, base.displaySyncEnabled)
        XCTAssertEqual(resolved.drawEveryFrames, base.drawEveryFrames)
        XCTAssertEqual(resolved.backgroundColor, base.backgroundColor)
        XCTAssertEqual(resolved.drawDebugInfo, base.drawDebugInfo)
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

    func testOverridePreferenceReductionUsesLastScalarAndUnionsDebugInfo() {
        var value = WindowConfiguration.Override(
            activeFrameInterval: 0.1,
            displaySyncEnabled: true,
            drawDebugInfo: [.frameInfo],
            contentScaleFactor: 1
        )

        WindowConfiguration.Override.Key.reduce(value: &value) {
            WindowConfiguration.Override(
                activeFrameInterval: 0.01,
                inactiveFrameInterval: 0.2,
                displaySyncEnabled: false,
                drawEveryFrames: false,
                drawDebugInfo: [.thread],
                contentScaleFactor: 3
            )
        }

        XCTAssertEqual(value.activeFrameInterval, 0.01)
        XCTAssertEqual(value.inactiveFrameInterval, 0.2)
        XCTAssertEqual(value.displaySyncEnabled, false)
        XCTAssertEqual(value.drawEveryFrames, false)
        XCTAssertEqual(value.drawDebugInfo, [.frameInfo, .thread])
        XCTAssertEqual(value.contentScaleFactor, 3)
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
            contentScaleFactor: 3
        )

        for controller in [child, nestedChild] {
            XCTAssertNil(controller.configurationOverride.activeFrameInterval)
            XCTAssertEqual(controller.configurationOverride.inactiveFrameInterval, 0.2)
            XCTAssertEqual(controller.configurationOverride.displaySyncEnabled, true)
            XCTAssertEqual(controller.configurationOverride.drawDebugInfo, [.thread, .queue])
            XCTAssertEqual(controller.configurationOverride.contentScaleFactor, 3)
        }
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
            drawDebugInfo: [.windowState]
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

        root.configurationOverride = .init(
            activeFrameInterval: 0.02,
            displaySyncEnabled: true,
            drawDebugInfo: [.appState]
        )

        XCTAssertEqual(child.configurationOverride.activeFrameInterval, 0.02)
        XCTAssertEqual(child.configurationOverride.displaySyncEnabled, true)
        XCTAssertTrue(child.configuration.displaySyncEnabled)
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.appState])
    }
}
