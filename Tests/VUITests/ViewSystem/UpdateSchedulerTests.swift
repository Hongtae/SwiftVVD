import Foundation
import Synchronization
import XCTest
@testable import VUI

final class UpdateSchedulerTests: XCTestCase {
    func testEnqueueActionRunsUnderNestedUpdateDrainAndReturnsMonotonicIDs() {
        var events: [String] = []

        let firstID = Update.enqueueAction {
            events.append(Update.isActive ? "active" : "inactive")
            events.append(Update.threadIsUpdating ? "updating" : "dispatching")
        }
        let secondID = Update.enqueueAction {
            events.append("second")
        }

        XCTAssertEqual(secondID, firstID + 1)
        XCTAssertEqual(events, ["active", "dispatching", "second"])
        XCTAssertFalse(Update.isActive)
        XCTAssertFalse(Update.threadIsUpdating)
    }

    func testEnsureDefersQueuedActionsUntilOutermostEnd() {
        var events: [String] = []

        Update.ensure {
            events.append(Update.threadIsUpdating ? "outer-updating" : "outer-not-updating")

            Update.enqueueAction {
                events.append(Update.threadIsUpdating ? "action-updating" : "action-dispatching")
            }

            XCTAssertTrue(Update.canDispatch)
            XCTAssertEqual(events, ["outer-updating"])
            events.append("outer-end")
        }

        XCTAssertEqual(events, ["outer-updating", "outer-end", "action-dispatching"])
        XCTAssertFalse(Update.isActive)
        XCTAssertFalse(Update.threadIsUpdating)
    }

    func testQueuedActionReasonsReflectDeferredQueueOrder() {
        var events: [String] = []

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }

        Update.enqueueAction(reason: .gesture) {
            events.append("first")
        }
        Update.enqueueAction {
            events.append("second")
        }

        XCTAssertEqual(Update.queuedActionReasons, [.gesture, nil])
        XCTAssertEqual(events, [])

        Update.end()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertFalse(Update.isActive)
    }

    func testDispatchActionsSnapshotsAndLoopsForReentrantEnqueues() {
        var events: [String] = []

        Update.ensure {
            Update.enqueueAction {
                events.append("first")
                Update.enqueueAction {
                    events.append("second")
                }
                events.append("first-end")
            }

            XCTAssertEqual(events, [])
        }

        XCTAssertEqual(events, ["first", "first-end", "second"])
        XCTAssertFalse(Update.isActive)
    }

    func testDispatchImmediatelyRunsBodyNowAndDefersQueuedActionsToEnd() {
        var events: [String] = []

        let result = Update.dispatchImmediately {
            events.append(Update.threadIsUpdating ? "body-updating" : "body-dispatching")
            Update.enqueueAction {
                events.append("queued")
            }
            events.append("body-end")
            return 17
        }

        XCTAssertEqual(result, 17)
        XCTAssertEqual(events, ["body-dispatching", "body-end", "queued"])
        XCTAssertFalse(Update.isActive)
        XCTAssertFalse(Update.threadIsUpdating)
    }

    func testDispatchImmediatelyConsumesActionIDLane() {
        let firstID = Update.enqueueAction {}

        Update.dispatchImmediately {}

        let secondID = Update.enqueueAction {}

        XCTAssertEqual(secondID, firstID + 2)
    }

    func testLockedPreservesAmbientGraphWithoutOpeningAnUpdate() {
        let host = GraphHost()

        XCTAssertNil(_AGGraph.current)
        host.data.withCurrent {
            let currentGraph = _AGGraph.current
            let result = Update.locked {
                XCTAssertTrue(_AGGraph.current === currentGraph)
                XCTAssertFalse(Update.isActive)
                XCTAssertFalse(Update.threadIsUpdating)
                return 17
            }

            XCTAssertEqual(result, 17)
            XCTAssertTrue(_AGGraph.current === currentGraph)
        }
        XCTAssertNil(_AGGraph.current)
    }

    func testNestedGraphHostTransactionsShareTheCurrentThreadUpdateTurn() {
        let outerHost = GraphHost()
        let innerHost = GraphHost()
        var events: [String] = []

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }

        outerHost.runTransaction(nil, do: {
            Update.enqueueAction {
                events.append("action")
            }

            innerHost.runTransaction(nil, do: {
                XCTAssertTrue(Update.isActive)
                XCTAssertTrue(events.isEmpty)
            }, id: nil)

            XCTAssertTrue(events.isEmpty)
        }, id: nil)

        XCTAssertTrue(events.isEmpty)
        Update.end()

        XCTAssertEqual(events, ["action"])
        XCTAssertFalse(Update.isActive)
    }

    func testIndependentThreadsOwnIndependentUpdateTurns() {
        let workerFinished = DispatchSemaphore(value: 0)
        let workerInitiallyActive = Atomic<Bool>(true)
        let workerActionRan = Atomic<Bool>(false)
        let mainActionRan = Atomic<Bool>(false)

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }
        Update.enqueueAction {
            mainActionRan.store(true, ordering: .relaxed)
        }

        let worker = Thread {
            workerInitiallyActive.store(Update.isActive, ordering: .relaxed)
            Update.begin()
            Update.enqueueAction {
                workerActionRan.store(true, ordering: .relaxed)
            }
            Update.end()
            workerFinished.signal()
        }
        worker.start()

        XCTAssertEqual(workerFinished.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(workerInitiallyActive.load(ordering: .relaxed))
        XCTAssertTrue(workerActionRan.load(ordering: .relaxed))
        XCTAssertFalse(mainActionRan.load(ordering: .relaxed))

        Update.end()

        XCTAssertTrue(mainActionRan.load(ordering: .relaxed))
        XCTAssertFalse(Update.isActive)
    }

    // ASSERTIONS updateLockSurfaceObserved updateSheetHostScopeObserved
    // ASSERTIONS updatePopoverHostScopeObserved updateWindowGroupMultiWindowScopeObserved
    func testPresentationChildFramesShareRootHostContextAcrossThreads() {
        let parentEntered = DispatchSemaphore(value: 0)
        let releaseParent = DispatchSemaphore(value: 0)
        let parentFinished = DispatchSemaphore(value: 0)
        let childEntered = DispatchSemaphore(value: 0)
        let childFinished = DispatchSemaphore(value: 0)
        let independentRootEntered = DispatchSemaphore(value: 0)
        let independentRootFinished = DispatchSemaphore(value: 0)
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(UpdateSchedulerTests.self)
        )
        let parent = HostContextProbeController(
            entered: parentEntered,
            release: releaseParent,
            scene: scene
        )
        let child = HostContextProbeController(
            entered: childEntered,
            scene: scene
        )
        let independentRoot = HostContextProbeController(
            entered: independentRootEntered,
            scene: scene
        )
        child.parentWindow = parent

        let parentThread = Thread {
            parent.updateFrame(
                tick: 0,
                delta: 0,
                date: .now,
                contentSize: CGSize(width: 320, height: 240),
                shouldDrawFrame: false
            ) { _, _ in }
            parentFinished.signal()
        }
        parentThread.start()
        XCTAssertEqual(parentEntered.wait(timeout: .now() + 2), .success)

        // Detaching the weak parent link must not move the child's final frame
        // onto a fresh lane while the presenting root is still in its frame.
        child.parentWindow = nil

        let childThread = Thread {
            child.updateFrame(
                tick: 0,
                delta: 0,
                date: .now,
                contentSize: CGSize(width: 120, height: 80),
                shouldDrawFrame: false
            ) { _, _ in }
            childFinished.signal()
        }
        childThread.start()

        let independentRootThread = Thread {
            independentRoot.updateFrame(
                tick: 0,
                delta: 0,
                date: .now,
                contentSize: CGSize(width: 120, height: 80),
                shouldDrawFrame: false
            ) { _, _ in }
            independentRootFinished.signal()
        }
        independentRootThread.start()

        XCTAssertEqual(
            independentRootEntered.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(
            independentRootFinished.wait(timeout: .now() + 2),
            .success
        )
        XCTAssertEqual(childEntered.wait(timeout: .now() + 0.1), .timedOut)

        releaseParent.signal()

        XCTAssertEqual(parentFinished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(childEntered.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(childFinished.wait(timeout: .now() + 2), .success)
        XCTAssertFalse(Update.isActive)
    }

    func testNestedOverlayControllerDefersActionsUntilParentUpdateFrameEnds() {
        let probe = NestedUpdateScopeProbe()
        let scene = WindowKey(
            namespace: .app,
            sceneID: SceneID(UpdateSchedulerTests.self)
        )
        let parent = NestedUpdateScopeHostController(
            probe: probe,
            scene: scene
        )
        let child = NestedUpdateScopeChildController(
            probe: probe,
            scene: scene
        )
        parent.addPresentationChild(child: child)

        let withGC: WindowContext.WithGraphicsContext = { _, _ in }
        parent.updateFrame(
            tick: 0,
            delta: 0,
            date: .now,
            contentSize: CGSize(width: 320, height: 240),
            shouldDrawFrame: false,
            withGC
        )

        XCTAssertTrue(probe.childObservedActiveUpdate)
        XCTAssertTrue(probe.childDeferredAction)
        XCTAssertTrue(probe.parentObservedDeferredAction)
        XCTAssertTrue(probe.actionRan)
        XCTAssertFalse(Update.isActive)
    }
}

private final class HostContextProbeController: WindowController, @unchecked Sendable {
    private let entered: DispatchSemaphore
    private let release: DispatchSemaphore?

    init(
        entered: DispatchSemaphore,
        release: DispatchSemaphore? = nil,
        scene: WindowKey
    ) {
        self.entered = entered
        self.release = release
        super.init(content: EmptyView(), scene: scene)
    }

    override func updateView(
        tick: UInt64,
        delta: Double,
        date: Date,
        contentSize: CGSize,
        redraw: inout Bool,
        _ withGC: WindowContext.WithGraphicsContext
    ) {
        XCTAssertTrue(Update.isActive)
        entered.signal()
        release?.wait()
    }
}

private final class NestedUpdateScopeProbe {
    var actionRan = false
    var childObservedActiveUpdate = false
    var childDeferredAction = false
    var parentObservedDeferredAction = false
}

private final class NestedUpdateScopeHostController: WindowController, @unchecked Sendable {
    private let probe: NestedUpdateScopeProbe

    init(probe: NestedUpdateScopeProbe, scene: WindowKey) {
        self.probe = probe
        super.init(content: EmptyView(), scene: scene)
    }

    override func updateView(
        tick: UInt64,
        delta: Double,
        date: Date,
        contentSize: CGSize,
        redraw: inout Bool,
        _ withGC: WindowContext.WithGraphicsContext
    ) {
        super.updateView(
            tick: tick,
            delta: delta,
            date: date,
            contentSize: contentSize,
            redraw: &redraw,
            withGC
        )
        probe.parentObservedDeferredAction = !probe.actionRan
    }
}

private final class NestedUpdateScopeChildController: PresentationChildWindowController,
                                                       @unchecked Sendable {
    private let probe: NestedUpdateScopeProbe

    init(probe: NestedUpdateScopeProbe, scene: WindowKey) {
        self.probe = probe
        super.init(
            content: EmptyView(),
            scene: scene,
            usesPlatformWindow: false
        )
    }

    override func updateView(
        tick: UInt64,
        delta: Double,
        date: Date,
        contentSize: CGSize,
        redraw: inout Bool,
        _ withGC: WindowContext.WithGraphicsContext
    ) {
        super.updateView(
            tick: tick,
            delta: delta,
            date: date,
            contentSize: contentSize,
            redraw: &redraw,
            withGC
        )
        probe.childObservedActiveUpdate = Update.isActive
        Update.enqueueAction { [probe] in
            probe.actionRan = true
        }
        probe.childDeferredAction = !probe.actionRan
    }
}
