import XCTest
@testable import VUI

final class WindowConfigurationTests: XCTestCase {
    func testApplyingOverrideChangesOnlySpecifiedFields() {
        var base = WindowConfiguration()
        base.activeFrameInterval = 0.1
        base.inactiveFrameInterval = 0.2
        base.drawEveryFrames = true
        base.drawDebugInfo = [.frameInfo]

        let override = WindowConfiguration.Override(
            activeFrameInterval: 0.01,
            drawEveryFrames: false,
            drawDebugInfo: [.thread]
        )
        let resolved = base.applying(override)

        XCTAssertEqual(resolved.activeFrameInterval, 0.01)
        XCTAssertEqual(resolved.inactiveFrameInterval, 0.2)
        XCTAssertFalse(resolved.drawEveryFrames)
        XCTAssertEqual(resolved.backgroundColor, base.backgroundColor)
        XCTAssertEqual(resolved.drawDebugInfo, [.thread])
    }

    func testEmptyOverridePreservesBaseConfiguration() {
        var base = WindowConfiguration()
        base.activeFrameInterval = 0.1
        base.inactiveFrameInterval = 0.2
        base.drawEveryFrames = false
        base.drawDebugInfo = [.queue, .windowState]

        let resolved = base.applying(.init())

        XCTAssertEqual(resolved.activeFrameInterval, base.activeFrameInterval)
        XCTAssertEqual(resolved.inactiveFrameInterval, base.inactiveFrameInterval)
        XCTAssertEqual(resolved.drawEveryFrames, base.drawEveryFrames)
        XCTAssertEqual(resolved.backgroundColor, base.backgroundColor)
        XCTAssertEqual(resolved.drawDebugInfo, base.drawDebugInfo)
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
            drawDebugInfo: [.frameInfo]
        )

        WindowConfiguration.Override.Key.reduce(value: &value) {
            WindowConfiguration.Override(
                activeFrameInterval: 0.01,
                inactiveFrameInterval: 0.2,
                drawEveryFrames: false,
                drawDebugInfo: [.thread]
            )
        }

        XCTAssertEqual(value.activeFrameInterval, 0.01)
        XCTAssertEqual(value.inactiveFrameInterval, 0.2)
        XCTAssertEqual(value.drawEveryFrames, false)
        XCTAssertEqual(value.drawDebugInfo, [.frameInfo, .thread])
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
            drawDebugInfo: [.frameInfo]
        )

        let child = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: true
        )
        root.addPresentationChild(child: child)
        XCTAssertEqual(child.configurationOverride.activeFrameInterval, 0.01)
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.frameInfo])

        let nestedChild = PopupWindowController(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: true
        )
        child.addPresentationChild(child: nestedChild)

        root.configurationOverride = .init(
            inactiveFrameInterval: 0.2,
            drawDebugInfo: [.thread, .queue]
        )

        for controller in [child, nestedChild] {
            XCTAssertNil(controller.configurationOverride.activeFrameInterval)
            XCTAssertEqual(controller.configurationOverride.inactiveFrameInterval, 0.2)
            XCTAssertEqual(controller.configurationOverride.drawDebugInfo, [.thread, .queue])
        }
    }

    @MainActor
    func testModalChildrenInheritAndTrackConfigurationOverride() {
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(WindowConfigurationTests.self, index: 1)
        )
        let root = WindowController(content: EmptyView(), scene: scene)
        root.configurationOverride = .init(drawDebugInfo: [.windowState])

        let content = AnyView(EmptyView())
        let child = root.viewGraph.data.withCurrent {
            let sourceGraph = root.viewGraph.data.graph
            let contentAttribute: Attribute<AnyView> = sourceGraph.makeInput(value: content)
            return ModalWindowController(
                crossGraphContent: contentAttribute,
                sourceGraph: sourceGraph,
                scene: scene,
                parentController: root,
                usesPlatformWindow: false
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
                usesPlatformWindow: false
            ))
        )
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.windowState])

        root.configurationOverride = .init(
            activeFrameInterval: 0.02,
            drawDebugInfo: [.appState]
        )

        XCTAssertEqual(child.configurationOverride.activeFrameInterval, 0.02)
        XCTAssertEqual(child.configurationOverride.drawDebugInfo, [.appState])
    }
}
