import XCTest
@testable import VVD
@testable import VUI

final class MenuResponderLayoutTests: XCTestCase {
    // ASSERTIONS responderGeometryRuleOwnershipObserved menuPlatformResponderGeometryOwnershipObserved
    @MainActor
    func testConditionalPrimaryActionMenuBuildsWithoutParentLayoutCycle() throws {
        let controller = WindowController(
            content: ConditionalPrimaryActionMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalPrimaryActionMenuRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        XCTAssertNotNil(controller.viewGraph.rootLayoutComputer)
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let menuResponders = responderTree(rootResponder)
            .compactMap { $0 as? MenuControlResponder }
        XCTAssertEqual(menuResponders.count, 2)
        var menuCenters: [CGPoint] = []
        for responder in menuResponders {
            XCTAssertGreaterThan(responder.helper.size.width, 0)
            XCTAssertGreaterThan(responder.helper.size.height, 0)
            var points = [CGPoint(
                x: responder.helper.size.width / 2,
                y: responder.helper.size.height / 2
            )]
            responder.helper.transform.convertGlobal(
                from: .local,
                points: &points
            )
            let center = try XCTUnwrap(points.first)
            menuCenters.append(center)
            XCTAssertTrue(
                rootResponder.respondersContaining(point: center).contains {
                    $0 === responder
                }
            )
        }
        XCTAssertNotEqual(menuCenters[0], menuCenters[1])
        XCTAssertTrue(menuCenters.allSatisfy { $0.x > 20 && $0.y > 20 })
        let hoverResponders = responderTree(rootResponder)
            .compactMap { $0 as? HoverResponder }
        XCTAssertFalse(hoverResponders.isEmpty)
        for responder in hoverResponders {
            guard case .nonSpatial = responder.callback else {
                XCTFail("Menu hover responder must use the non-spatial callback")
                continue
            }
            XCTAssertGreaterThan(responder.size.width, 0)
            XCTAssertGreaterThan(responder.size.height, 0)
        }
    }

    // ASSERTIONS menuPlatformResponderGeometryOwnershipObserved menuControlPopupAnchorObserved
    @MainActor
    func testMenuResponderGeometryRoutesPointerToControlOwner() throws {
        let controller = WindowController(
            content: ConditionalPrimaryActionMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalPrimaryActionMenuRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? MenuControlResponder
            }.last
        )
        var points = [CGPoint(
            x: responder.helper.size.width / 2,
            y: responder.helper.size.height / 2
        )]
        responder.helper.transform.convertGlobal(
            from: .local,
            points: &points
        )
        let center = try XCTUnwrap(points.first)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: center,
            timestamp: 0
        )))
        XCTAssertTrue(responder.menuIsOpen)
        let popup = try XCTUnwrap(firstMenuPopup(in: controller))
        let expectedAnchor = menuControlPoint(
            responder,
            localPoint: CGPoint(
                x: 0,
                y: responder.helper.size.height
            )
        )
        assertPoint(
            popup.presentationPointInParent(forLocalPoint: .zero),
            equals: expectedAnchor
        )
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: center,
            timestamp: 0
        )))
        responder.dismissMenu()
    }

    // ASSERTIONS menuPlatformControlLifecycleObserved menuPlatformResponderGeometryOwnershipObserved menuControlPopupAnchorObserved
    @MainActor
    func testPrimaryActionMenuControlOwnsSplitPointerSession() throws {
        let recorder = MenuControlRecorder()
        let controller = WindowController(
            content: PrimaryActionMenuControlRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PrimaryActionMenuControlRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? MenuControlResponder
            }.first
        )
        XCTAssertNotNil(responder.primaryAction)
        XCTAssertEqual(responder.menuIndicatorWidth, 24)
        let initialIdentity = ObjectIdentifier(responder)
        let primaryPoint = menuControlPoint(
            responder,
            localX: max(
                1,
                (responder.helper.size.width - responder.menuIndicatorWidth) / 2
            )
        )
        let indicatorPoint = menuControlPoint(
            responder,
            localX: responder.helper.size.width -
                responder.menuIndicatorWidth / 2
        )
        let outsidePoint = CGPoint(
            x: primaryPoint.x + responder.helper.size.width + 40,
            y: primaryPoint.y + responder.helper.size.height + 40
        )

        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: primaryPoint,
            timestamp: 1
        ))
        XCTAssertTrue(responder.isPrimaryPressing)
        XCTAssertTrue(sendPointer(
            .move,
            to: controller,
            at: outsidePoint,
            timestamp: 1.1
        ))
        XCTAssertFalse(responder.isPrimaryPressing)
        XCTAssertTrue(sendPointer(
            .move,
            to: controller,
            at: primaryPoint,
            timestamp: 1.2
        ))
        XCTAssertTrue(responder.isPrimaryPressing)
        XCTAssertTrue(sendPointer(
            .buttonUp,
            to: controller,
            at: primaryPoint,
            timestamp: 1.3
        ))
        XCTAssertFalse(responder.isPrimaryPressing)
        XCTAssertEqual(recorder.primaryActionCount, 1)
        XCTAssertEqual(recorder.outerTapCount, 0)

        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: primaryPoint,
            timestamp: 2
        ))
        XCTAssertTrue(sendPointer(
            .move,
            to: controller,
            at: indicatorPoint,
            timestamp: 2.1
        ))
        XCTAssertTrue(sendPointer(
            .buttonUp,
            to: controller,
            at: indicatorPoint,
            timestamp: 2.2
        ))
        XCTAssertEqual(recorder.primaryActionCount, 1)
        XCTAssertFalse(responder.menuIsOpen)
        XCTAssertEqual(recorder.outerTapCount, 0)

        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: indicatorPoint,
            timestamp: 3
        ))
        XCTAssertTrue(responder.menuIsOpen)
        XCTAssertTrue(responder.isMenuPressing)
        XCTAssertEqual(recorder.outerTapCount, 0)
        let popup = try XCTUnwrap(firstMenuPopup(in: controller))
        let expectedAnchor = menuControlPoint(
            responder,
            localPoint: CGPoint(
                x: responder.helper.size.width -
                    responder.menuIndicatorWidth,
                y: max(0, responder.helper.size.height - 3)
            )
        )
        assertPoint(
            popup.presentationPointInParent(forLocalPoint: .zero),
            equals: expectedAnchor
        )
        XCTAssertTrue(sendPointer(
            .buttonUp,
            to: controller,
            at: indicatorPoint,
            timestamp: 3.1
        ))
        XCTAssertEqual(recorder.outerTapCount, 0)

        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: primaryPoint,
            timestamp: 3.2
        ))
        XCTAssertFalse(responder.menuIsOpen)
        XCTAssertFalse(responder.isMenuPressing)
        XCTAssertEqual(recorder.outerTapCount, 0)
        XCTAssertTrue(sendPointer(
            .buttonUp,
            to: controller,
            at: primaryPoint,
            timestamp: 3.3
        ))
        XCTAssertEqual(recorder.primaryActionCount, 1)
        XCTAssertEqual(recorder.outerTapCount, 0)

        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: primaryPoint,
            timestamp: 4
        ))
        controller.resetGestureHandlers()
        XCTAssertFalse(responder.isPrimaryPressing)
        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: primaryPoint,
            timestamp: 4.1
        ))
        XCTAssertTrue(sendPointer(
            .buttonUp,
            to: controller,
            at: primaryPoint,
            timestamp: 4.2
        ))
        XCTAssertEqual(recorder.primaryActionCount, 2)
        XCTAssertEqual(recorder.outerTapCount, 0)

        controller.updateView(
            tick: 1,
            delta: 0.1,
            date: controller.date.addingTimeInterval(0.1),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        let updatedRootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let updatedResponder = try XCTUnwrap(
            responderTree(updatedRootResponder).compactMap {
                $0 as? MenuControlResponder
            }.first
        )
        XCTAssertEqual(ObjectIdentifier(updatedResponder), initialIdentity)

        let updatedIndicatorPoint = menuControlPoint(
            updatedResponder,
            localX: updatedResponder.helper.size.width -
                updatedResponder.menuIndicatorWidth / 2
        )
        XCTAssertTrue(sendPointer(
            .buttonDown,
            to: controller,
            at: updatedIndicatorPoint,
            timestamp: 5
        ))
        XCTAssertTrue(updatedResponder.menuIsOpen)
        XCTAssertTrue(sendPointer(
            .buttonUp,
            to: controller,
            at: updatedIndicatorPoint,
            timestamp: 5.1
        ))
        updatedResponder.dismissMenu()
    }

    // ASSERTIONS menuPlatformControlLifecycleObserved
    @MainActor
    func testMenuControlPreservesDirectTouchCarrierRouting() throws {
        let recorder = MenuControlRecorder()
        let controller = WindowController(
            content: PrimaryActionMenuControlRoot(recorder: recorder),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(MenuControlTouchProbe.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? MenuControlResponder
            }.first
        )
        let primaryPoint = menuControlPoint(
            responder,
            localX: max(
                1,
                (responder.helper.size.width - responder.menuIndicatorWidth) / 2
            )
        )
        let indicatorPoint = menuControlPoint(
            responder,
            localX: responder.helper.size.width -
                responder.menuIndicatorWidth / 2
        )

        XCTAssertTrue(sendTouchPointer(
            .buttonDown,
            to: controller,
            at: primaryPoint,
            timestamp: 1
        ))
        XCTAssertTrue(sendTouchPointer(
            .buttonUp,
            to: controller,
            at: primaryPoint,
            timestamp: 1.1
        ))
        XCTAssertEqual(recorder.primaryActionCount, 1)
        XCTAssertEqual(recorder.outerTapCount, 0)

        XCTAssertTrue(sendTouchPointer(
            .buttonDown,
            to: controller,
            at: indicatorPoint,
            timestamp: 2
        ))
        XCTAssertTrue(responder.menuIsOpen)
        XCTAssertTrue(sendTouchPointer(
            .buttonUp,
            to: controller,
            at: indicatorPoint,
            timestamp: 2.1
        ))
        XCTAssertEqual(recorder.outerTapCount, 0)
        responder.dismissMenu()
    }

    // ASSERTIONS resolvedMenuStyleReentryObserved nestedMenuSourcePrecedenceObserved
    func testStandaloneMenuCollectsNestedMenuLabelAndChildren() throws {
        let controller = WindowController(
            content: NestedMenuItemCollectionRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NestedMenuItemCollectionRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? MenuControlResponder
            }.first
        )
        controller.viewGraph.data.withCurrent {
            let items = responder.itemList.value.items
            XCTAssertEqual(
                items.map { ($0.label ?? $0.text)?.string },
                ["First", "Submenu", "Submenu2"]
            )
            XCTAssertEqual(items[1].children?.items.count, 2)
            XCTAssertEqual(items[2].children?.items.count, 2)
            guard case .menu? = items[1].systemItem,
                  case .menu? = items[2].systemItem else {
                return XCTFail("Nested Menu items must retain their menu role")
            }
            XCTAssertEqual(
                items[1].children?.items.map { ($0.label ?? $0.text)?.string },
                ["Submenu Child 1", "Submenu Child 2"]
            )
        }
    }

    // ASSERTIONS resolvedMenuStyleReentryObserved nestedMenuSourcePrecedenceObserved
    func testContextMenuCollectsNestedMenuLabelAndChildren() throws {
        let controller = WindowController(
            content: NestedContextMenuItemCollectionRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NestedContextMenuItemCollectionRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }.first
        )
        var itemList: PlatformItemList?
        controller.viewGraph.data.withCurrent {
            itemList = responder.itemList.value
        }
        let items = try XCTUnwrap(itemList).items
        XCTAssertEqual(
            items.map { ($0.label ?? $0.text)?.string },
            ["First", "Submenu", "Plain Submenu"]
        )
        XCTAssertEqual(
            items[1].children?.items.map { ($0.label ?? $0.text)?.string },
            ["Submenu Child 1", "Submenu Child 2"]
        )
        guard case .menu? = items[1].systemItem else {
            return XCTFail("The context-menu child must retain its menu role")
        }
        XCTAssertEqual(
            items[2].children?.items.map { ($0.label ?? $0.text)?.string },
            ["Plain Child 1", "Plain Child 2"]
        )
        guard case .menu? = items[2].systemItem else {
            return XCTFail("The plain context-menu child must retain its menu role")
        }
    }

    // ASSERTIONS nestedMenuPrimaryActionDispatchObserved nestedMenuPopupFrontOrderingObserved
    @MainActor
    func testPlainSubmenuParentClickLeavesCompleteMenuTreeOpen() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        openSubmenuBeforeParentClick(harness)
        let parentPoint = harness.popup.presentationPointInParent(
            forLocalPoint: harness.rowCenter
        )

        try pressPopupRow(in: harness.parent, at: parentPoint)
        XCTAssertEqual(presentationChildCount(in: harness.parent), 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        try releasePopupRow(in: harness.parent, at: parentPoint)
        XCTAssertEqual(presentationChildCount(in: harness.parent), 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS nestedMenuPrimaryActionDispatchObserved
    @MainActor
    func testPrimaryActionSubmenuParentClickDismissesTreeBeforeAction() throws {
        let recorder = SubmenuPrimaryActionRecorder()
        let harness = try makeSubmenuPopupHarness {
            recorder.recordAction()
        }
        recorder.parent = harness.parent
        recorder.popup = harness.popup
        openSubmenuBeforeParentClick(harness)
        let parentPoint = harness.popup.presentationPointInParent(
            forLocalPoint: harness.rowCenter
        )

        try pressPopupRow(in: harness.parent, at: parentPoint)
        XCTAssertEqual(presentationChildCount(in: harness.parent), 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        try releasePopupRow(in: harness.parent, at: parentPoint)
        XCTAssertEqual(recorder.actionCount, 1)
        XCTAssertEqual(recorder.parentChildCountAtAction, 0)
        XCTAssertEqual(recorder.popupChildCountAtAction, 0)
        XCTAssertEqual(presentationChildCount(in: harness.parent), 0)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)

        // A platform submenu can finish one last frame after the primary action
        // ends tracking. Its already-queued hover callback must not reactivate
        // the closed tree or reinterpret the stale ID as a live-session fault.
        harness.popup.openSubmenu(
            harness.item,
            at: CGPoint(x: 200, y: 0)
        )
        XCTAssertEqual(presentationChildCount(in: harness.parent), 0)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testSubmenuHoverActivationTransfersAcrossPopupTree() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        let outsidePoint = CGPoint(x: -100, y: -100)
        var tick: UInt64 = 2

        // The parent popup is the last menu entered. Its child stays alive for
        // one controller-input handoff, then closes if no child entered.
        _ = harness.popup.handleMouseHover(
            at: harness.rowCenter,
            deviceID: 31,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        enqueuePopupHover(
            in: harness.popup,
            at: outsidePoint,
            deviceID: 31,
            time: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)

        // A platform parent exit can be processed one update before the child
        // enter. The deferred exit must retain the branch after the child
        // becomes the activated popup.
        _ = harness.popup.handleMouseHover(
            at: harness.rowCenter,
            deviceID: 31,
            isTopMost: true,
            at: Time(seconds: 3)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))
        let submenuPoint = try popupHoverPoint(in: submenu)

        enqueuePopupHover(
            in: harness.popup,
            at: outsidePoint,
            deviceID: 31,
            time: Time(seconds: 4)
        )
        enqueuePopupHover(
            in: submenu,
            at: submenuPoint,
            deviceID: 31,
            time: Time(seconds: 5)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertFalse(harness.popup.isActivated)
        XCTAssertTrue(submenu.isActivated)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        enqueuePopupHover(
            in: submenu,
            at: outsidePoint,
            deviceID: 31,
            time: Time(seconds: 6)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertFalse(harness.popup.isActivated)
        XCTAssertTrue(submenu.isActivated)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        // Returning to the parent makes it active again. Its next exit closes
        // the child because no activated descendant remains.
        enqueuePopupHover(
            in: harness.popup,
            at: harness.rowCenter,
            deviceID: 31,
            time: Time(seconds: 7)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertFalse(submenu.isActivated)

        enqueuePopupHover(
            in: harness.popup,
            at: outsidePoint,
            deviceID: 31,
            time: Time(seconds: 8)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testPopupPanelHoverCoversPaddingAndSubmenuFramesOverlap() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.popup.handleMouseHover(
            at: harness.rowCenter,
            deviceID: 32,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))

        let parentPanelHover = try popupPanelHoverResponder(
            in: harness.popup
        )
        let childPanelHover = try popupPanelHoverResponder(in: submenu)
        XCTAssertEqual(parentPanelHover.size, harness.popup.cachedContentSize)
        XCTAssertEqual(childPanelHover.size, submenu.cachedContentSize)

        let childOrigin = submenu.presentationPointInParent(
            forLocalPoint: .zero
        )
        XCTAssertLessThan(
            childOrigin.x,
            harness.popup.cachedContentSize.width,
            "The child popup frame must overlap its parent tracking frame"
        )

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testPopupBoundaryReactivatesParentAfterHoverBindingReset() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.popup.handleMouseHover(
            at: harness.rowCenter,
            deviceID: 33,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))

        // Platform-window inactivation clears the dispatcher binding without
        // synthesizing a hover exit, leaving the parent panel responder active.
        harness.popup.eventBindingManager.reset(
            resetForwardedEventDispatchers: true
        )
        _ = submenu.handleMouseHover(
            at: try popupHoverPoint(in: submenu),
            deviceID: 33,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertFalse(harness.popup.isActivated)
        XCTAssertTrue(submenu.isActivated)

        // Re-entering the same active HoverResponder cannot emit another
        // onHover(true). The popup's raw tracking boundary must still restore
        // parent ownership and its accent-colored submenu row.
        _ = harness.popup.handleMouseHover(
            at: harness.rowCenter,
            deviceID: 33,
            isTopMost: true,
            at: Time(seconds: 3)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertFalse(submenu.isActivated)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testSiblingSubmenuOpensAfterChildReturnsActivationToParent() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var secondItem = harness.item
        secondItem.id = .init(
            source: .platformIdentifier("submenu-2"),
            role: .item
        )
        secondItem.item.platformIdentifier = "submenu-2"
        secondItem.item.text = NSAttributedString(string: "Submenu 2")
        harness.popup.replaceMenuItems([harness.item, secondItem])

        var tick: UInt64 = 2
        updateSubmenuPopupHarness(harness, tick: &tick)
        let rowPoints = try popupRowHoverPoints(in: harness.popup)
        XCTAssertEqual(rowPoints.count, 2)

        _ = harness.popup.handleMouseHover(
            at: try XCTUnwrap(rowPoints.first),
            deviceID: 35,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let firstSubmenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))
        _ = firstSubmenu.handleMouseHover(
            at: try popupHoverPoint(in: firstSubmenu),
            deviceID: 35,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertFalse(harness.popup.isActivated)
        XCTAssertTrue(firstSubmenu.isActivated)

        // Returning through another submenu row must reactivate the parent
        // before that row replaces the old child. The new branch starts with
        // the parent active rather than inheriting the old gray child state.
        _ = harness.popup.handleMouseHover(
            at: try XCTUnwrap(rowPoints.last),
            deviceID: 35,
            isTopMost: true,
            at: Time(seconds: 3)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let secondSubmenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))

        XCTAssertFalse(secondSubmenu === firstSubmenu)
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertFalse(firstSubmenu.isActivated)
        XCTAssertFalse(secondSubmenu.isActivated)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testSubmenuRowHoverExtendsHorizontallyIntoPanelPadding() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: harness.rowCenter
            ),
            deviceID: 37,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))
        let rowHover = try popupRowHoverResponder(in: harness.popup)

        // The highlighted ink stays inset, but native row tracking reaches the
        // popup's horizontal edges. Hover and submenu opening must therefore
        // share that wider row rectangle rather than leaving a chrome-only gap.
        let leftPaddingPoint = CGPoint(
            x: 1,
            y: harness.rowCenter.y
        )
        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: leftPaddingPoint
            ),
            deviceID: 37,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 3)

        if case .active = rowHover.currentPhase {
            // Expected: the horizontally expanded row remains hovered.
        } else {
            XCTFail("Submenu row hover ended inside horizontal panel padding")
        }
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertFalse(submenu.isActivated)
        XCTAssertTrue(firstMenuPopup(in: harness.popup) === submenu)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testSubmenuRowExitIntoVerticalPanelPaddingClosesChild() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: harness.rowCenter
            ),
            deviceID: 38,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertNotNil(firstMenuPopup(in: harness.popup))

        let bottomPaddingPoint = CGPoint(
            x: harness.rowCenter.x,
            y: harness.popup.cachedContentSize.height - 1
        )
        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: bottomPaddingPoint
            ),
            deviceID: 38,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 3)

        XCTAssertNil(firstMenuPopup(in: harness.popup))
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testProvisionalSubmenuClosesAfterRootRoutedExit() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: harness.rowCenter
            ),
            deviceID: 36,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)

        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))
        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertFalse(submenu.isActivated)

        _ = harness.parent.handleMouseHover(
            at: CGPoint(x: -100, y: -100),
            deviceID: 36,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 3)

        XCTAssertNil(firstMenuPopup(in: harness.popup))
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testSubmenuPopupPaddingOwnsOverlayTransition() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.popup.handleMouseHover(
            at: harness.rowCenter,
            deviceID: 34,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))

        let childPaddingPoint = CGPoint(
            x: 1,
            y: submenu.cachedContentSize.height / 2
        )
        let childPointInPopup = submenu.presentationPointInParent(
            forLocalPoint: childPaddingPoint
        )
        let childPointInRoot = harness.popup.presentationPointInParent(
            forLocalPoint: childPointInPopup
        )
        // This overlap point is inside the parent's trailing edge and the
        // child's left panel padding. Root routing visits the parent first and
        // the topmost child second; a delayed parent responder refresh must not
        // overwrite that newer child-boundary input or close the branch.
        for sample in 0..<24 {
            _ = harness.parent.handleMouseHover(
                at: childPointInRoot,
                deviceID: 34,
                isTopMost: true,
                at: Time(seconds: 2 + Double(sample) / 60)
            )
            updateSubmenuPopupHarness(harness, tick: &tick, turns: 1)

            XCTAssertFalse(harness.popup.isActivated)
            XCTAssertTrue(submenu.isActivated)
            XCTAssertTrue(firstMenuPopup(in: harness.popup) === submenu)
        }

        // Crossing the shared edge into the parent row must transfer the
        // highlight without letting a stale overlap exit tear down and rebuild
        // the already-open child.
        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: harness.rowCenter
            ),
            deviceID: 34,
            isTopMost: true,
            at: Time(seconds: 3)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 2)

        XCTAssertTrue(harness.popup.isActivated)
        XCTAssertFalse(submenu.isActivated)
        XCTAssertTrue(firstMenuPopup(in: harness.popup) === submenu)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testOverlaySubmenuBridgeUsesPlacementOverlap() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: harness.rowCenter
            ),
            deviceID: 39,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)

        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))
        let childOrigin = submenu.presentationPointInParent(
            forLocalPoint: .zero
        )
        let placementOverlap = harness.popup.cachedContentSize.width -
            childOrigin.x
        XCTAssertGreaterThan(placementOverlap, 0)

        let childRowHover = try popupRowHoverResponder(in: submenu)
        var childRowBottomPoints = [CGPoint(
            x: childRowHover.size.width / 2,
            y: childRowHover.size.height - 0.25
        )]
        childRowHover.transform.convertGlobal(
            from: .local,
            points: &childRowBottomPoints
        )
        var childBridgePoint = try XCTUnwrap(childRowBottomPoints.first)
        childBridgePoint.x = -placementOverlap / 2

        let pointInParentPopup = submenu.presentationPointInParent(
            forLocalPoint: childBridgePoint
        )
        XCTAssertGreaterThan(
            pointInParentPopup.y,
            harness.rowCenter.y,
            "The bridge probe must exercise the lower diagonal transition"
        )
        XCTAssertLessThan(
            pointInParentPopup.y,
            harness.popup.cachedContentSize.height
        )

        // The point is outside the child frame but inside the same horizontal
        // overlap used to place it. Overlay routing treats that transition
        // strip as the adjacent child row instead of leaving an unowned seam.
        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: pointInParentPopup
            ),
            deviceID: 39,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 3)

        if case .active = childRowHover.currentPhase {
            // Expected: the external transition strip routes into this row.
        } else {
            XCTFail("Submenu row hover ended inside the overlay bridge")
        }
        XCTAssertFalse(harness.popup.isActivated)
        XCTAssertTrue(submenu.isActivated)
        XCTAssertTrue(firstMenuPopup(in: harness.popup) === submenu)
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS menuSubmenuActivationTransferObserved
    @MainActor
    func testOverlaySubmenuCornerExitClosesOpenedBranch() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: nil)
        var tick: UInt64 = 2

        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: harness.rowCenter
            ),
            deviceID: 40,
            isTopMost: true,
            at: Time(seconds: 1)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)

        let submenu = try XCTUnwrap(firstMenuPopup(in: harness.popup))
        let childHoverPoint = try popupHoverPoint(in: submenu)
        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: submenu.presentationPointInParent(
                    forLocalPoint: childHoverPoint
                )
            ),
            deviceID: 40,
            isTopMost: true,
            at: Time(seconds: 2)
        )
        updateSubmenuPopupHarness(harness, tick: &tick)
        XCTAssertFalse(harness.popup.isActivated)
        XCTAssertTrue(submenu.isActivated)

        let childOrigin = submenu.presentationPointInParent(
            forLocalPoint: .zero
        )
        let placementOverlap = harness.popup.cachedContentSize.width -
            childOrigin.x
        XCTAssertGreaterThan(placementOverlap, 0)

        let childRowHover = try popupRowHoverResponder(in: submenu)
        var childRowBottomPoints = [CGPoint(
            x: childRowHover.size.width / 2,
            y: childRowHover.size.height
        )]
        childRowHover.transform.convertGlobal(
            from: .local,
            points: &childRowBottomPoints
        )
        var cornerExitPoint = try XCTUnwrap(childRowBottomPoints.first)
        cornerExitPoint.x = -min(1, placementOverlap / 2)
        cornerExitPoint.y += 0.75
        XCTAssertLessThan(cornerExitPoint.x, 0)
        XCTAssertLessThan(
            cornerExitPoint.y,
            submenu.cachedContentSize.height
        )

        // This point is just beyond both the child row's leading and bottom
        // edges. The parent popup owns the new sample, but no parent row owns
        // it, so the formerly active child branch must close rather than stay
        // visible without any highlighted row.
        _ = harness.parent.handleMouseHover(
            at: harness.popup.presentationPointInParent(
                forLocalPoint: submenu.presentationPointInParent(
                    forLocalPoint: cornerExitPoint
                )
            ),
            deviceID: 40,
            isTopMost: true,
            at: Time(seconds: 3)
        )
        updateSubmenuPopupHarness(harness, tick: &tick, turns: 3)

        XCTAssertNil(firstMenuPopup(in: harness.popup))
        XCTAssertEqual(presentationChildCount(in: harness.popup), 0)

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS nestedMenuParentRowHitRegionObserved
    @MainActor
    func testSubmenuParentButtonHitRegionCoversHoverRowCorners() throws {
        let harness = try makeSubmenuPopupHarness(primaryAction: {})
        let rootResponder = try XCTUnwrap(
            harness.popup.viewGraph.responderNode as? MultiViewResponder
        )
        let hover = try XCTUnwrap(
            responderTree(rootResponder)
                .compactMap { $0 as? HoverResponder }
                .min { lhs, rhs in
                    lhs.size.width * lhs.size.height <
                        rhs.size.width * rhs.size.height
                }
        )
        let gesture = try XCTUnwrap(
            responderTree(rootResponder).first {
                $0 is any AnyGestureResponder
            }
        )
        let inset: CGFloat = 0.25
        var points = [
            CGPoint(x: inset, y: inset),
            CGPoint(x: hover.size.width - inset, y: inset),
            CGPoint(x: inset, y: hover.size.height - inset),
            CGPoint(
                x: hover.size.width - inset,
                y: hover.size.height - inset
            ),
        ]
        hover.transform.convertGlobal(from: .local, points: &points)

        let hoverHits = hover.containsGlobalPoints(
            points,
            cacheKey: nil,
            options: [.includeHoverResponders, .uncached]
        )
        let gestureHits = gesture.containsGlobalPoints(
            points,
            cacheKey: nil,
            options: [.uncached]
        )
        for index in points.indices {
            XCTAssertTrue(hoverHits.mask[index])
            XCTAssertTrue(
                gestureHits.mask[index],
                "The parent-row gesture must cover hover corner \(index)"
            )
        }

        harness.parent.dismissAllPresentationChildren()
    }

    // ASSERTIONS resolvedMenuStyleReentryObserved nestedMenuSourcePrecedenceObserved propertyListBidirectionalTailMergeObserved
    func testCompositeContextMenuRetainsNestedMenuRolesAndChildren() throws {
        let controller = WindowController(
            content: CompositeContextMenuItemCollectionRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(CompositeContextMenuItemCollectionRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 680, height: 360),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        let responder = try XCTUnwrap(
            responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }.first
        )
        var itemList: PlatformItemList?
        controller.viewGraph.data.withCurrent {
            itemList = responder.itemList.value
        }
        let items = try XCTUnwrap(itemList).items
        let disabledMore = try XCTUnwrap(items.first {
            ($0.label ?? $0.text)?.string == "Disabled More"
        })
        let more = try XCTUnwrap(items.first {
            ($0.label ?? $0.text)?.string == "More"
        })

        guard case .menu? = disabledMore.systemItem else {
            return XCTFail("Disabled More must retain its menu role")
        }
        XCTAssertEqual(
            disabledMore.children?.items.map { ($0.label ?? $0.text)?.string },
            ["Disabled Nested"]
        )
        guard case .menu? = more.systemItem else {
            return XCTFail("More must retain its menu role")
        }
        XCTAssertEqual(
            more.children?.items.map { ($0.label ?? $0.text)?.string },
            ["Nested Live 0", "Rename", "Developer Mode"]
        )
    }

    // ASSERTIONS responderGeometryRuleOwnershipObserved
    @MainActor
    func testConditionalContinuousHoverPublishesItsInitialResponderState() throws {
        let controller = WindowController(
            content: ConditionalContinuousHoverRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConditionalContinuousHoverRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? ViewResponder
        )
        let hoverResponder = try XCTUnwrap(
            responderTree(rootResponder).compactMap { $0 as? HoverResponder }.first
        )
        guard case .spatial = hoverResponder.callback else {
            return XCTFail("Continuous hover must publish a spatial callback")
        }
        XCTAssertGreaterThan(hoverResponder.size.width, 0)
        XCTAssertGreaterThan(hoverResponder.size.height, 0)
    }

    // ASSERTIONS contextMenuEventBindingRouteObserved contextMenuResponderFilterOwnershipObserved contextMenuLongPressDriverThresholdsObserved
    @MainActor
    func testContextMenuEventBindsPositionedResponderAndLongPressTarget() throws {
        let controller = WindowController(
            content: PositionedContextMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PositionedContextMenuRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        try controller.viewGraph.data.withCurrent {
            let contextResponders = responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }
            XCTAssertEqual(contextResponders.count, 2)
            var hitPoints: [ObjectIdentifier: [CGPoint]] = [:]
            for y in stride(from: CGFloat(10), through: 230, by: 10) {
                for x in stride(from: CGFloat(10), through: 410, by: 10) {
                    let point = CGPoint(x: x, y: y)
                    let event = ContextMenuEvent(
                        timestamp: .zero,
                        binding: nil,
                        location: .zero,
                        globalLocation: point
                    )
                    if let responder = rootResponder
                        .bindEvent(event)?
                        .firstAncestor(ofType: ContextMenuResponder.self) {
                        hitPoints[ObjectIdentifier(responder), default: []]
                            .append(point)
                    }
                }
            }

            XCTAssertEqual(hitPoints.count, 2)
            for responder in contextResponders {
                XCTAssertFalse(
                    hitPoints[ObjectIdentifier(responder), default: []].isEmpty
                )
            }

            let policies = contextResponders.map {
                $0.resolvedTriggerPolicy(for: .genericMouse, buttonID: 0)
            }
            XCTAssertEqual(policies.filter { $0 == .secondaryDown }.count, 1)
            XCTAssertEqual(policies.filter { $0 == .longPress }.count, 1)

            let longPressResponder = try XCTUnwrap(contextResponders.first {
                $0.resolvedTriggerPolicy(for: .genericMouse, buttonID: 0)
                    == .longPress
            })
            let longPressPoint = try XCTUnwrap(
                hitPoints[ObjectIdentifier(longPressResponder)]?.first
            )
            var recognizer = ContextMenuRecognizer()
            var scheduledSession: UInt64?
            var scheduledDelay: TimeInterval?
            var openedResponder: ContextMenuResponder?
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .buttonDown,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: longPressPoint,
                    timestamp: 1
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { sessionID, delay in
                    scheduledSession = sessionID
                    scheduledDelay = delay
                },
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertNil(openedResponder)
            XCTAssertEqual(scheduledDelay, 0.15)
            let withinPointerTolerance = CGPoint(
                x: longPressPoint.x + 3,
                y: longPressPoint.y
            )
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .move,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: withinPointerTolerance,
                    timestamp: 1.1
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { _, _ in
                    XCTFail("An active long press must not schedule twice")
                },
                open: { _, _ in
                    XCTFail("Movement inside the tolerance must not open early")
                }
            ))
            XCTAssertTrue(recognizer.fireLongPress(
                sessionID: try XCTUnwrap(scheduledSession),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertTrue(openedResponder === longPressResponder)

            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .buttonUp,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: withinPointerTolerance,
                    timestamp: 1.2
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { _, _ in },
                open: { _, _ in }
            ))

            var cancelledSession: UInt64?
            openedResponder = nil
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .buttonDown,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: longPressPoint,
                    timestamp: 2
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { sessionID, _ in
                    cancelledSession = sessionID
                },
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertTrue(recognizer.handleMouseEvent(
                MouseEvent(
                    type: .move,
                    device: .genericMouse,
                    deviceID: 3,
                    buttonID: 0,
                    location: CGPoint(
                        x: longPressPoint.x + 4,
                        y: longPressPoint.y
                    ),
                    timestamp: 2.1
                ),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                scheduleLongPress: { _, _ in },
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertFalse(recognizer.fireLongPress(
                sessionID: try XCTUnwrap(cancelledSession),
                viewGraph: controller.viewGraph,
                rootResponder: rootResponder,
                open: { responder, _ in
                    openedResponder = responder
                }
            ))
            XCTAssertNil(openedResponder)
        }
    }

    // ASSERTIONS contextMenuEventBindingRouteObserved contextMenuPointerPopupAnchorObserved
    @MainActor
    func testSecondaryClickContextMenuUsesPointerAsRootAnchor() throws {
        let controller = WindowController(
            content: PositionedContextMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PositionedContextMenuRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }
        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        var sampledClickPoint: CGPoint?
        controller.viewGraph.data.withCurrent {
            for y in stride(from: CGFloat(10), through: 230, by: 10) {
                for x in stride(from: CGFloat(10), through: 410, by: 10) {
                    let point = CGPoint(x: x, y: y)
                    let event = ContextMenuEvent(
                        timestamp: .zero,
                        binding: nil,
                        location: .zero,
                        globalLocation: point
                    )
                    guard let responder = rootResponder
                        .bindEvent(event)?
                        .firstAncestor(ofType: ContextMenuResponder.self),
                          responder.resolvedTriggerPolicy(
                            for: .genericMouse,
                            buttonID: 1
                          ) == .secondaryDown else {
                        continue
                    }
                    sampledClickPoint = point
                    return
                }
            }
        }
        let clickPoint = try XCTUnwrap(sampledClickPoint)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 1,
            location: clickPoint,
            timestamp: 1
        )))
        let popup = try XCTUnwrap(firstMenuPopup(in: controller))
        assertPoint(
            popup.presentationPointInParent(forLocalPoint: .zero),
            equals: clickPoint
        )
        controller.dismissAllPresentationChildren()
    }

    // ASSERTIONS contextMenuEventBindingRouteObserved contextMenuLongPressDriverThresholdsObserved
    @MainActor
    func testWindowControllerLongPressDeadlineOpensPresentationChild() async throws {
        let controller = WindowController(
            content: PositionedContextMenuRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PositionedContextMenuRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        let rootResponder = try XCTUnwrap(
            controller.viewGraph.responderNode as? MultiViewResponder
        )
        var sampledLongPressResponder: ContextMenuResponder?
        controller.viewGraph.data.withCurrent {
            sampledLongPressResponder = responderTree(rootResponder).compactMap {
                $0 as? ContextMenuResponder
            }.first {
                $0.resolvedTriggerPolicy(for: .genericMouse, buttonID: 0)
                    == .longPress
            }
        }
        let longPressResponder = try XCTUnwrap(sampledLongPressResponder)
        var sampledLongPressPoint: CGPoint?
        controller.viewGraph.data.withCurrent {
            for y in stride(from: CGFloat(10), through: 230, by: 10) {
                for x in stride(from: CGFloat(10), through: 410, by: 10) {
                    let point = CGPoint(x: x, y: y)
                    let event = ContextMenuEvent(
                        timestamp: .zero,
                        binding: nil,
                        location: .zero,
                        globalLocation: point
                    )
                    if rootResponder.bindEvent(event)?.firstAncestor(
                        ofType: ContextMenuResponder.self
                    ) === longPressResponder {
                        sampledLongPressPoint = point
                        return
                    }
                }
            }
        }
        let longPressPoint = try XCTUnwrap(sampledLongPressPoint)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 3,
            buttonID: 0,
            location: longPressPoint,
            timestamp: 1
        )))

        try await Task.sleep(nanoseconds: 250_000_000)
        controller.updateView(
            tick: 1,
            delta: 0.25,
            date: controller.date.addingTimeInterval(0.25),
            contentSize: CGSize(width: 420, height: 240),
            redraw: &redraw
        ) { _, _ in }

        var presentationChildCount = 0
        controller.forEachPresentationChild { _ in
            presentationChildCount += 1
        }
        XCTAssertEqual(presentationChildCount, 1)

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 3,
            buttonID: 0,
            location: longPressPoint,
            timestamp: 1.25
        )))
        controller.dismissAllPresentationChildren()
    }

    private func responderTree(_ responder: ViewResponder) -> [ViewResponder] {
        [responder] + responder.children.flatMap(responderTree)
    }

    private func menuControlPoint(
        _ responder: MenuControlResponder,
        localX: CGFloat
    ) -> CGPoint {
        menuControlPoint(
            responder,
            localPoint: CGPoint(
                x: localX,
                y: responder.helper.size.height / 2
            )
        )
    }

    private func menuControlPoint(
        _ responder: MenuControlResponder,
        localPoint: CGPoint
    ) -> CGPoint {
        var points = [localPoint]
        responder.helper.transform.convertGlobal(from: .local, points: &points)
        return points[0]
    }

    private func firstMenuPopup(
        in controller: WindowController
    ) -> ContextMenuWindowController? {
        var popup: ContextMenuWindowController?
        controller.forEachPresentationChild { child in
            if popup == nil {
                popup = child as? ContextMenuWindowController
            }
        }
        return popup
    }

    private func assertPoint(
        _ actual: CGPoint,
        equals expected: CGPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
    }

    @discardableResult
    private func sendPointer(
        _ type: MouseEventType,
        to controller: WindowController,
        at location: CGPoint,
        timestamp: TimeInterval
    ) -> Bool {
        controller.handleMouseEvent(event: MouseEvent(
            type: type,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: location,
            timestamp: timestamp
        ))
    }

    @discardableResult
    private func sendTouchPointer(
        _ type: MouseEventType,
        to controller: WindowController,
        at location: CGPoint,
        timestamp: TimeInterval
    ) -> Bool {
        controller.handleMouseEvent(event: MouseEvent(
            type: type,
            device: .touch,
            deviceID: 17,
            buttonID: 0,
            location: location,
            timestamp: timestamp
        ))
    }

    @MainActor
    private func makeSubmenuPopupHarness(
        primaryAction: (() -> Void)?
    ) throws -> (
        parent: WindowController,
        popup: ContextMenuWindowController,
        item: ContextMenuPresentationItem,
        rowCenter: CGPoint
    ) {
        var child = PlatformItemList.Item(systemItem: .button)
        child.text = NSAttributedString(string: "Child")
        child.selectionBehavior = .init(
            isMomentary: true,
            isContainerSelection: true,
            yieldsToContainerSelection: false,
            isPickerOption: false,
            visualStyle: .plain,
            onSelect: {},
            onDeselect: nil,
            springLoadingBehavior: .automatic
        )
        var submenu = PlatformItemList.Item(systemItem: .menu)
        submenu.text = NSAttributedString(string: "Submenu")
        submenu.platformIdentifier = "submenu"
        submenu.children = PlatformItemList(items: [child])
        if let primaryAction {
            submenu.selectionBehavior = .init(
                isMomentary: true,
                isContainerSelection: true,
                yieldsToContainerSelection: false,
                isPickerOption: false,
                visualStyle: .plain,
                onSelect: primaryAction,
                onDeselect: nil,
                springLoadingBehavior: .automatic
            )
        }
        let items = contextMenuPresentationItems([submenu])
        let actions = ContextMenuPopupActions()
        let session = ContextMenuPresentationSession()
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(SubmenuPopupActionProbe.self)
        )
        let parent = WindowController(content: EmptyView(), scene: scene)
        let popup = ContextMenuWindowController(
            content: contextMenuPopupContent(items: items, actions: actions),
            environment: EnvironmentValues(),
            viewPhase: ViewGraphHost.Phase(),
            scene: scene,
            anchor: .zero,
            items: items,
            actions: actions,
            usesPlatformWindow: false,
            session: session
        )
        session.root = popup
        actions.openSubmenu = { [weak popup] item, origin in
            popup?.openSubmenu(item, at: origin)
        }
        actions.closeSubmenus = { [weak popup] in
            popup?.closeSubmenus()
        }
        actions.dismiss = { [weak session] in
            session?.dismissAll()
        }
        parent.addPresentationChild(child: popup)

        var redraw = false
        for tick in 0..<2 {
            parent.updateView(
                tick: UInt64(tick),
                delta: 0,
                date: parent.date,
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw
            ) { _, _ in }
        }
        let rootResponder = try XCTUnwrap(
            popup.viewGraph.responderNode as? MultiViewResponder
        )
        var hitPoints: [CGPoint] = []
        for y in stride(from: CGFloat(2), through: 238, by: 4) {
            for x in stride(from: CGFloat(2), through: 418, by: 4) {
                let point = CGPoint(x: x, y: y)
                if rootResponder.respondersContaining(point: point).contains(
                    where: { $0 is any AnyGestureResponder }
                ) {
                    hitPoints.append(point)
                }
            }
        }
        let firstHit = try XCTUnwrap(hitPoints.first)
        let hitBounds = hitPoints.dropFirst().reduce(
            CGRect(origin: firstHit, size: .zero)
        ) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
        return (
            parent,
            popup,
            items[0],
            CGPoint(x: hitBounds.midX, y: hitBounds.midY)
        )
    }

    @MainActor
    private func openSubmenuBeforeParentClick(
        _ harness: (
            parent: WindowController,
            popup: ContextMenuWindowController,
            item: ContextMenuPresentationItem,
            rowCenter: CGPoint
        )
    ) {
        harness.popup.openSubmenu(
            harness.item,
            at: CGPoint(x: 200, y: 0)
        )
        var redraw = false
        for tick in 2..<4 {
            harness.parent.updateView(
                tick: UInt64(tick),
                delta: 0,
                date: harness.parent.date,
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw
            ) { _, _ in }
        }
        XCTAssertEqual(presentationChildCount(in: harness.popup), 1)
    }

    @MainActor
    private func updateSubmenuPopupHarness(
        _ harness: (
            parent: WindowController,
            popup: ContextMenuWindowController,
            item: ContextMenuPresentationItem,
            rowCenter: CGPoint
        ),
        tick: inout UInt64,
        turns: Int = 2
    ) {
        var redraw = false
        for _ in 0..<turns {
            harness.parent.updateView(
                tick: tick,
                delta: 0,
                date: harness.parent.date,
                contentSize: CGSize(width: 420, height: 240),
                redraw: &redraw
            ) { _, _ in }
            tick &+= 1
        }
    }

    private func enqueuePopupHover(
        in popup: ContextMenuWindowController,
        at location: CGPoint,
        deviceID: Int,
        time: Time
    ) {
        popup.enqueueInputAction { [weak popup] in
            guard let popup else { return }
            _ = popup.handleMouseHover(
                at: location,
                deviceID: deviceID,
                isTopMost: true,
                at: time
            )
        }
    }

    private func popupHoverPoint(
        in popup: ContextMenuWindowController
    ) throws -> CGPoint {
        let hover = try popupRowHoverResponder(in: popup)
        var points = [CGPoint(
            x: hover.size.width / 2,
            y: hover.size.height / 2
        )]
        hover.transform.convertGlobal(from: .local, points: &points)
        return try XCTUnwrap(points.first)
    }

    private func popupRowHoverResponder(
        in popup: ContextMenuWindowController
    ) throws -> HoverResponder {
        let rootResponder = try XCTUnwrap(
            popup.viewGraph.responderNode as? MultiViewResponder
        )
        return try XCTUnwrap(
            responderTree(rootResponder)
                .compactMap { $0 as? HoverResponder }
                .min { lhs, rhs in
                    lhs.size.width * lhs.size.height <
                        rhs.size.width * rhs.size.height
                }
        )
    }

    private func popupRowHoverPoints(
        in popup: ContextMenuWindowController
    ) throws -> [CGPoint] {
        let rootResponder = try XCTUnwrap(
            popup.viewGraph.responderNode as? MultiViewResponder
        )
        let hoverResponders = responderTree(rootResponder)
            .compactMap { $0 as? HoverResponder }
        let panel = try XCTUnwrap(
            hoverResponders.max { lhs, rhs in
                lhs.size.width * lhs.size.height <
                    rhs.size.width * rhs.size.height
            }
        )
        return hoverResponders.compactMap { hover -> CGPoint? in
            guard hover !== panel else { return nil }
            var points = [CGPoint(
                x: hover.size.width / 2,
                y: hover.size.height / 2
            )]
            hover.transform.convertGlobal(from: .local, points: &points)
            return points.first
        }.sorted { lhs, rhs in
            lhs.y < rhs.y
        }
    }

    private func popupPanelHoverResponder(
        in popup: ContextMenuWindowController
    ) throws -> HoverResponder {
        let rootResponder = try XCTUnwrap(
            popup.viewGraph.responderNode as? MultiViewResponder
        )
        return try XCTUnwrap(
            responderTree(rootResponder)
                .compactMap { $0 as? HoverResponder }
                .max { lhs, rhs in
                    lhs.size.width * lhs.size.height <
                        rhs.size.width * rhs.size.height
                }
        )
    }

    @MainActor
    private func pressPopupRow(
        in controller: WindowController,
        at point: CGPoint
    ) throws {
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: point,
            timestamp: 0
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
    }

    @MainActor
    private func releasePopupRow(
        in controller: WindowController,
        at point: CGPoint
    ) throws {
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            location: point,
            timestamp: 0.01
        )))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
    }

    private func presentationChildCount(
        in controller: WindowController
    ) -> Int {
        var count = 0
        controller.forEachPresentationChild { _ in count += 1 }
        return count
    }

}

private enum SubmenuPopupActionProbe {}

private final class SubmenuPrimaryActionRecorder {
    weak var parent: WindowController?
    weak var popup: ContextMenuWindowController?
    var actionCount = 0
    var parentChildCountAtAction: Int?
    var popupChildCountAtAction: Int?

    func recordAction() {
        actionCount += 1
        parentChildCountAtAction = childCount(in: parent)
        popupChildCountAtAction = childCount(in: popup)
    }

    private func childCount(in controller: WindowController?) -> Int {
        var count = 0
        controller?.forEachPresentationChild { _ in count += 1 }
        return count
    }
}

private struct ConditionalContinuousHoverRoot: View {
    var body: some View {
        HStack {
            hoverRegion(isVisible: true)
            Text("Sibling")
        }
        .padding(20)
    }

    @ViewBuilder
    private func hoverRegion(isVisible: Bool) -> some View {
        if isVisible {
            Text("Hover")
                .padding(8)
                .onContinuousHover { _ in }
        } else {
            EmptyView()
        }
    }
}

private struct ConditionalPrimaryActionMenuRoot: View {
    var body: some View {
        HStack {
            menu("Menu Action") {}
            menu("Open Menu")
        }
        .padding(20)
    }

    @ViewBuilder
    private func menu(
        _ title: String,
        primaryAction: (() -> Void)? = nil
    ) -> some View {
        if let primaryAction {
            Menu(title) {
                Button("Menu Item") {}
            } primaryAction: {
                primaryAction()
            }
        } else {
            Menu(title) {
                Button("Menu Item") {}
            }
        }
    }
}

private final class MenuControlRecorder {
    var primaryActionCount = 0
    var outerTapCount = 0
}

private enum MenuControlTouchProbe {
}

private struct PrimaryActionMenuControlRoot: View {
    let recorder: MenuControlRecorder

    var body: some View {
        Menu("Primary Menu") {
            Button("Menu Item") {}
        } primaryAction: {
            recorder.primaryActionCount += 1
        }
        .onTapGesture {
            recorder.outerTapCount += 1
        }
        .padding(20)
    }
}

private struct NestedMenuItemCollectionRoot: View {
    var body: some View {
        Menu("Open Menu") {
            Button("First") {}
            Menu("Submenu") {
                Button("Submenu Child 1") {}
                Button("Submenu Child 2") {}
            } primaryAction: {}
            Menu("Submenu2") {
                Button("Submenu2 Child 1") {}
                Button("Submenu2 Child 2") {}
            } primaryAction: {}
        }
    }
}

private struct NestedContextMenuItemCollectionRoot: View {
    var body: some View {
        Text("Target")
            .contextMenu {
                VStack {
                    Button("First") {}
                    Menu("Submenu") {
                        Button("Submenu Child 1") {}
                        Button("Submenu Child 2") {}
                    } primaryAction: {}
                    Menu("Plain Submenu") {
                        Button("Plain Child 1") {}
                        Button("Plain Child 2") {}
                    }
                }
            }
    }
}

private struct CompositeContextMenuItemCollectionRoot: View {
    @State private var toggle = true
    @State private var liveCount = 0

    var body: some View {
        Text("Target")
            .contextMenu {
                CompositeContextMenuItems(
                    toggle: $toggle,
                    liveCount: liveCount
                )
            }
            .styleContext(.sheet)
    }
}

private struct CompositeContextMenuItems: View {
    @Binding var toggle: Bool
    let liveCount: Int

    var body: some View {
        VStack {
            Text("Live Count \(liveCount)")
            Button("Live Enabled \(liveCount)") {}
                .environment(\.isEnabled, liveCount.isMultiple(of: 2))
            Toggle("Live Toggle \(liveCount)", isOn: $toggle)
            if liveCount > 0 {
                Button("Inserted Live \(liveCount)") {}
            }
            if liveCount < 6 {
                Button("Removed Live \(liveCount)") {}
            }
            Divider()
            Text("1234")
            Label("Static Label", systemImage: "star.fill")
            Button {} label: {
                Label("Disabled Image", systemImage: "star.fill")
            }
            .environment(\.isEnabled, false)
            Button("Disabled Shortcut") {}
                .keyboardShortcut("d", modifiers: [.command, .option])
                .environment(\.isEnabled, false)
            Toggle("Disabled Toggle", isOn: .constant(true))
                .environment(\.isEnabled, false)
            Menu("Disabled More") {
                Button("Disabled Nested") {}
            }
            .environment(\.isEnabled, false)
            Button("Menu1") {}
            Button("Shortcut Menu") {}
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Toggle("Toggle Menu", isOn: $toggle)
            Divider()
            Section("Section Header") {
                Button("Section Action") {}
            }
            Button("Menu2") {}
            Menu("More") {
                Button("Nested Live \(liveCount)") {}
                Button("Rename") {}
                Button("Developer Mode") {}
            }
        }
    }
}

private struct PositionedContextMenuRoot: View {
    var body: some View {
        HStack(spacing: 80) {
            Color.blue.opacity(0.2)
                .frame(width: 100, height: 40)
                .contextMenu {
                    Button("First") {}
                }
            Color.green.opacity(0.2)
                .frame(width: 100, height: 40)
                .contextMenu {
                    Button("Second") {}
                }
                .environment(\.contextMenuTriggerPolicy, .longPress)
        }
    }
}
