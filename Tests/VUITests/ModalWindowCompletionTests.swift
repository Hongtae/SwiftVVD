import XCTest
@testable import VUI

final class ModalWindowCompletionTests: XCTestCase {
    func testPositivePresentAnimationStartsCompletionTokensAndFinishesAtBoundary() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        context.beginPresentAnimation(
            controller: parent,
            transaction: transaction
        )
        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        waitForMainQueue(until: { !events.isEmpty })
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.02))
        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testPositiveDismissAnimationStartsCompletionTokensAndFinishesAfterCleanup() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        XCTAssertTrue(
            context.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: transaction
            ) {
                events.append("cleanup")
            }
        )
        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        waitForMainQueue(until: { !events.isEmpty })
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.02))
        XCTAssertEqual(events, ["cleanup", "removed", "logical"])
    }

    func testNoExplicitPresentRegistersDefaultModalCompletionBoundary() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        context.beginPresentAnimation(
            controller: parent,
            transaction: transaction
        )
        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        waitForMainQueue(until: { !events.isEmpty })
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.29))
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.02))
        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testNoExplicitDismissRegistersDefaultModalCompletionBoundary() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        XCTAssertTrue(
            context.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: transaction
            ) {
                events.append("cleanup")
            }
        )
        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        waitForMainQueue(until: { !events.isEmpty })
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.29))
        XCTAssertEqual(events, [])
        XCTAssertTrue(context.updateAnimation(delta: 0.02))
        XCTAssertEqual(events, ["cleanup", "removed"])
    }

    func testNoExplicitDisablesAnimationsRegistersDefaultModalCompletionBoundary() {
        let parent = makeParentController()
        let presentContext = ModalPresentationContext(parentController: parent)
        var presentEvents: [String] = []
        var presentTransaction = Transaction()
        presentTransaction.disablesAnimations = true
        presentTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            presentEvents.append("present logical")
        }

        presentContext.beginPresentAnimation(
            controller: parent,
            transaction: presentTransaction
        )
        finalizeAnimationCompletions(
            in: presentTransaction,
            animation: presentTransaction.effectiveAnimation
        )

        XCTAssertEqual(presentEvents, [])
        waitForMainQueue(until: { !presentEvents.isEmpty })
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(presentContext.updateAnimation(delta: 0.29))
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(presentContext.updateAnimation(delta: 0.02))
        XCTAssertEqual(presentEvents, ["present logical"])

        let dismissContext = ModalPresentationContext(parentController: parent)
        var dismissEvents: [String] = []
        var dismissTransaction = Transaction()
        dismissTransaction.disablesAnimations = true
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            dismissEvents.append("dismiss removed")
        }

        XCTAssertTrue(
            dismissContext.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                dismissEvents.append("dismiss cleanup")
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        XCTAssertEqual(dismissEvents, [])
        waitForMainQueue(until: { !dismissEvents.isEmpty })
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(dismissContext.updateAnimation(delta: 0.29))
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(dismissContext.updateAnimation(delta: 0.02))
        XCTAssertEqual(dismissEvents, ["dismiss cleanup", "dismiss removed"])
    }

    func testDisablesAnimationsDoesNotSuppressExplicitModalCompletionBoundary() {
        let parent = makeParentController()
        let presentContext = ModalPresentationContext(parentController: parent)
        var presentEvents: [String] = []
        var presentTransaction = Transaction(animation: .linear(duration: 0.20))
        presentTransaction.disablesAnimations = true
        presentTransaction.addAnimationCompletion(criteria: .removed) {
            presentEvents.append("present removed")
        }

        presentContext.beginPresentAnimation(
            controller: parent,
            transaction: presentTransaction
        )
        finalizeAnimationCompletions(
            in: presentTransaction,
            animation: presentTransaction.effectiveAnimation
        )

        XCTAssertEqual(presentEvents, [])
        waitForMainQueue(until: { !presentEvents.isEmpty })
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(presentContext.updateAnimation(delta: 0.49))
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(presentContext.updateAnimation(delta: 0.02))
        XCTAssertEqual(presentEvents, ["present removed"])

        let dismissContext = ModalPresentationContext(parentController: parent)
        var dismissEvents: [String] = []
        var dismissTransaction = Transaction(animation: .linear(duration: 0.20))
        dismissTransaction.disablesAnimations = true
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            dismissEvents.append("dismiss removed")
        }

        XCTAssertTrue(
            dismissContext.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                dismissEvents.append("dismiss cleanup")
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        XCTAssertEqual(dismissEvents, [])
        waitForMainQueue(until: { !dismissEvents.isEmpty })
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(dismissContext.updateAnimation(delta: 0.49))
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(dismissContext.updateAnimation(delta: 0.02))
        XCTAssertEqual(dismissEvents, ["dismiss cleanup", "dismiss removed"])
    }

    func testExplicitNilPresentationAndDismissalUseImmediateFallback() {
        let parent = makeParentController()
        let presentContext = ModalPresentationContext(parentController: parent)
        var presentEvents: [String] = []
        var presentTransaction = Transaction(animation: nil)
        presentTransaction.addAnimationCompletion(criteria: .removed) {
            presentEvents.append("present removed")
        }

        presentContext.beginPresentAnimation(
            controller: parent,
            transaction: presentTransaction
        )
        finalizeAnimationCompletions(
            in: presentTransaction,
            animation: presentTransaction.effectiveAnimation
        )

        waitForMainQueue(until: { presentEvents == ["present removed"] })
        XCTAssertEqual(presentEvents, ["present removed"])
        XCTAssertFalse(presentContext.updateAnimation(delta: 1.0))

        let dismissContext = ModalPresentationContext(parentController: parent)
        var dismissEvents: [String] = []
        var dismissTransaction = Transaction(animation: nil)
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            dismissEvents.append("dismiss removed")
        }

        XCTAssertTrue(
            dismissContext.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                dismissEvents.append("cleanup")
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        waitForMainQueue(until: { dismissEvents == ["cleanup", "dismiss removed"] })
        XCTAssertEqual(dismissEvents, ["cleanup", "dismiss removed"])
        XCTAssertFalse(dismissContext.updateAnimation(delta: 1.0))
    }

    private func makeParentController() -> WindowController {
        WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(EmptyView.self))
        )
    }

    private func waitForMainQueue(
        timeout: TimeInterval = 0.20,
        until condition: () -> Bool
    ) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }
}
