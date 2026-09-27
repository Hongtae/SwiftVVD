import XCTest
@testable import VUI

final class ModalWindowCompletionTests: XCTestCase {
    func testOverlayShadowUsesAQuieterDarkAppearance() {
        for (scheme, expectedOpacity) in [
            (ColorScheme.light, Float(0.33)),
            (.dark, Float(0.18)),
        ] {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            let filter = ModalPresentationContext.shadowFilter(
                in: environment
            )
            guard case let .shadow(
                color,
                radius,
                offset,
                blendMode,
                options
            ) = filter.style else {
                return XCTFail("expected an overlay shadow filter")
            }
            let resolved = color.resolve(in: environment)
            XCTAssertEqual(resolved.red, 0, accuracy: 0.000_001)
            XCTAssertEqual(resolved.green, 0, accuracy: 0.000_001)
            XCTAssertEqual(resolved.blue, 0, accuracy: 0.000_001)
            XCTAssertEqual(
                resolved.opacity,
                expectedOpacity,
                accuracy: 0.000_001
            )
            XCTAssertEqual(radius, 8)
            XCTAssertEqual(offset, .zero)
            XCTAssertEqual(blendMode, .normal)
            XCTAssertEqual(options.rawValue, 0)
        }
    }

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
        XCTAssertTrue(updateAnimation(context, delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
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
        XCTAssertTrue(updateAnimation(context, delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
        XCTAssertEqual(events, ["cleanup", "removed", "logical"])
    }

    func testDismissRequestedDuringPresentationKeepsDismissCompletionRegistered() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var presentTransaction = Transaction(animation: .linear(duration: 0.20))
        presentTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("present removed")
        }
        presentTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("present logical")
        }

        context.beginPresentAnimation(
            controller: parent,
            transaction: presentTransaction
        )
        finalizeAnimationCompletions(
            in: presentTransaction,
            animation: presentTransaction.effectiveAnimation
        )

        XCTAssertTrue(updateAnimation(context, delta: 0.20))
        XCTAssertEqual(events, [])

        var dismissTransaction = Transaction(animation: .linear(duration: 0.20))
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("dismiss removed")
        }
        dismissTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("dismiss logical")
        }

        XCTAssertTrue(
            context.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                events.append("cleanup")
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        waitForMainQueue(until: { events.count > 0 })
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.29))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
        XCTAssertEqual(events, ["present removed", "present logical"])
        XCTAssertTrue(updateAnimation(context, delta: 0.18))
        XCTAssertEqual(events, ["present removed", "present logical"])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
        XCTAssertEqual(
            events,
            [
                "present removed",
                "present logical",
                "cleanup",
                "dismiss removed",
                "dismiss logical",
            ]
        )
    }

    func testNonFiniteDismissRequestedDuringPresentationKeepsRemovedCompletionsPending() {
        let cases: [(name: String, animation: Animation)] = [
            (
                "repeatForever",
                .linear(duration: 0.20).repeatForever(autoreverses: false)
            ),
            ("speed0", .linear(duration: 0.20).speed(0)),
            ("speedNegative", .linear(duration: 0.20).speed(-1)),
        ]

        for testCase in cases {
            let parent = makeParentController()
            let context = ModalPresentationContext(parentController: parent)
            var presentRemoved = false
            var presentLogical = false
            var dismissRemoved = false
            var dismissLogical = false
            var cleanupCount = 0

            var presentTransaction = Transaction(
                animation: .linear(duration: 0.20)
            )
            presentTransaction.addAnimationCompletion(criteria: .removed) {
                presentRemoved = true
            }
            presentTransaction.addAnimationCompletion(
                criteria: .logicallyComplete
            ) {
                presentLogical = true
            }
            context.beginPresentAnimation(
                controller: parent,
                transaction: presentTransaction
            )
            finalizeAnimationCompletions(
                in: presentTransaction,
                animation: presentTransaction.effectiveAnimation
            )

            XCTAssertTrue(updateAnimation(context, delta: 0.20), testCase.name)

            var dismissTransaction = Transaction(animation: testCase.animation)
            dismissTransaction.addAnimationCompletion(criteria: .removed) {
                dismissRemoved = true
            }
            dismissTransaction.addAnimationCompletion(
                criteria: .logicallyComplete
            ) {
                dismissLogical = true
            }
            XCTAssertTrue(
                context.requestDismissal(
                    controller: parent,
                    reason: .dismissed,
                    transaction: dismissTransaction
                ) {
                    cleanupCount += 1
                },
                testCase.name
            )
            finalizeAnimationCompletions(
                in: dismissTransaction,
                animation: dismissTransaction.effectiveAnimation
            )

            waitForMainQueue(timeout: 0.05, until: {
                presentRemoved || presentLogical || dismissRemoved ||
                    dismissLogical
            })
            XCTAssertFalse(presentRemoved, testCase.name)
            XCTAssertFalse(presentLogical, testCase.name)
            XCTAssertFalse(dismissRemoved, testCase.name)
            XCTAssertFalse(dismissLogical, testCase.name)
            XCTAssertEqual(cleanupCount, 0, testCase.name)

            XCTAssertTrue(updateAnimation(context, delta: 0.29), testCase.name)
            XCTAssertFalse(presentLogical, testCase.name)
            XCTAssertTrue(updateAnimation(context, delta: 0.02), testCase.name)
            XCTAssertTrue(presentLogical, testCase.name)
            XCTAssertFalse(presentRemoved, testCase.name)
            XCTAssertFalse(dismissRemoved, testCase.name)
            XCTAssertFalse(dismissLogical, testCase.name)
            XCTAssertEqual(cleanupCount, 1, testCase.name)
            XCTAssertFalse(updateAnimation(context, delta: 1.0), testCase.name)

            withExtendedLifetime((presentTransaction, dismissTransaction)) {}
        }
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
        XCTAssertTrue(updateAnimation(context, delta: 0.29))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
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
        XCTAssertTrue(updateAnimation(context, delta: 0.29))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
        XCTAssertEqual(events, ["cleanup", "removed"])
    }

    func testNoExplicitDismissRegistersBothCriteriaAtDefaultModalBoundary() {
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
        XCTAssertTrue(updateAnimation(context, delta: 0.29))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))
        XCTAssertEqual(events, ["cleanup", "removed", "logical"])
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
        XCTAssertTrue(updateAnimation(presentContext, delta: 0.29))
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(updateAnimation(presentContext, delta: 0.02))
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
        XCTAssertTrue(updateAnimation(dismissContext, delta: 0.29))
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(updateAnimation(dismissContext, delta: 0.02))
        XCTAssertEqual(dismissEvents, ["dismiss cleanup", "dismiss removed"])
    }

    func testNoExplicitDisablesAnimationsRegistersBothCriteriaAtDefaultModalBoundary() {
        let parent = makeParentController()
        let presentContext = ModalPresentationContext(parentController: parent)
        var presentEvents: [String] = []
        var presentTransaction = Transaction()
        presentTransaction.disablesAnimations = true
        presentTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            presentEvents.append("present logical")
        }
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
        XCTAssertTrue(updateAnimation(presentContext, delta: 0.29))
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(updateAnimation(presentContext, delta: 0.02))
        XCTAssertEqual(presentEvents, ["present removed", "present logical"])

        let dismissContext = ModalPresentationContext(parentController: parent)
        var dismissEvents: [String] = []
        var dismissTransaction = Transaction()
        dismissTransaction.disablesAnimations = true
        dismissTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            dismissEvents.append("dismiss logical")
        }
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
        XCTAssertTrue(updateAnimation(dismissContext, delta: 0.29))
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(updateAnimation(dismissContext, delta: 0.02))
        XCTAssertEqual(
            dismissEvents,
            ["dismiss cleanup", "dismiss removed", "dismiss logical"]
        )
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
        XCTAssertTrue(updateAnimation(presentContext, delta: 0.49))
        XCTAssertEqual(presentEvents, [])
        XCTAssertTrue(updateAnimation(presentContext, delta: 0.02))
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
        XCTAssertTrue(updateAnimation(dismissContext, delta: 0.49))
        XCTAssertEqual(dismissEvents, [])
        XCTAssertTrue(updateAnimation(dismissContext, delta: 0.02))
        XCTAssertEqual(dismissEvents, ["dismiss cleanup", "dismiss removed"])
    }

    func testPositivePresentationDurationSweepUsesAnimationDurationPlusModalTail() {
        let parent = makeParentController()
        let durations = [0.10, 0.30, 0.50, 0.80, 1.20]

        for duration in durations {
            let context = ModalPresentationContext(parentController: parent)
            var events: [String] = []
            var transaction = Transaction(animation: .linear(duration: duration))
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("duration \(duration) removed")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("duration \(duration) logical")
            }

            context.beginPresentAnimation(
                controller: parent,
                transaction: transaction
            )
            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.effectiveAnimation
            )

            XCTAssertEqual(events, [], "duration \(duration)")
            waitForMainQueue(timeout: 0.05, until: { !events.isEmpty })
            XCTAssertEqual(events, [], "duration \(duration)")
            XCTAssertTrue(
                updateAnimation(context, delta: duration + 0.29),
                "duration \(duration)"
            )
            XCTAssertEqual(events, [], "duration \(duration)")
            XCTAssertTrue(updateAnimation(context, delta: 0.02), "duration \(duration)")
            XCTAssertEqual(
                events,
                [
                    "duration \(duration) removed",
                    "duration \(duration) logical",
                ],
                "duration \(duration)"
            )
        }
    }

    func testPositiveDismissalDurationSweepUsesAnimationDurationPlusModalTail() {
        let parent = makeParentController()
        let durations = [0.10, 0.30, 0.50, 0.80, 1.20]

        for duration in durations {
            let context = ModalPresentationContext(parentController: parent)
            var events: [String] = []
            var transaction = Transaction(animation: .linear(duration: duration))
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("duration \(duration) removed")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("duration \(duration) logical")
            }

            XCTAssertTrue(
                context.requestDismissal(
                    controller: parent,
                    reason: .dismissed,
                    transaction: transaction
                ) {
                    events.append("duration \(duration) cleanup")
                },
                "duration \(duration)"
            )
            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.effectiveAnimation
            )

            XCTAssertEqual(events, [], "duration \(duration)")
            waitForMainQueue(timeout: 0.05, until: { !events.isEmpty })
            XCTAssertEqual(events, [], "duration \(duration)")
            XCTAssertTrue(
                updateAnimation(context, delta: duration + 0.29),
                "duration \(duration)"
            )
            XCTAssertEqual(events, [], "duration \(duration)")
            XCTAssertTrue(updateAnimation(context, delta: 0.02), "duration \(duration)")
            XCTAssertEqual(
                events,
                [
                    "duration \(duration) cleanup",
                    "duration \(duration) removed",
                    "duration \(duration) logical",
                ],
                "duration \(duration)"
            )
        }
    }

    func testExplicitNilPresentationAndDismissalUseImmediateFallback() {
        let parent = makeParentController()
        let presentContext = ModalPresentationContext(parentController: parent)
        var presentEvents: [String] = []
        var presentTransaction = Transaction(animation: nil)
        presentTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            presentEvents.append("present logical")
        }
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

        waitForMainQueue(until: {
            presentEvents == ["present logical", "present removed"]
        })
        XCTAssertEqual(presentEvents, ["present logical", "present removed"])
        XCTAssertFalse(updateAnimation(presentContext, delta: 1.0))

        let dismissContext = ModalPresentationContext(parentController: parent)
        var dismissEvents: [String] = []
        var dismissTransaction = Transaction(animation: nil)
        dismissTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            dismissEvents.append("dismiss logical")
        }
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

        waitForMainQueue(until: {
            dismissEvents == ["cleanup", "dismiss logical", "dismiss removed"]
        })
        XCTAssertEqual(
            dismissEvents,
            ["cleanup", "dismiss logical", "dismiss removed"]
        )
        XCTAssertFalse(updateAnimation(dismissContext, delta: 1.0))
    }

    func testExplicitZeroPresentationUsesImmediateFallbackForBothCriteria() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0))
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

        waitForMainQueue(until: { events == ["removed", "logical"] })
        XCTAssertEqual(events, ["removed", "logical"])
        XCTAssertFalse(updateAnimation(context, delta: 1.0))
    }

    func testExplicitZeroDismissalDefersCleanupUntilImmediateFallbackDrains() {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0))
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

        waitForMainQueue(until: { events == ["removed", "logical", "cleanup"] })
        XCTAssertEqual(events, ["removed", "logical", "cleanup"])
        XCTAssertFalse(updateAnimation(context, delta: 1.0))
    }

    func testNonFinitePresentationUsesSampledModalCompletionFallbacks() {
        let parent = makeParentController()
        let pendingCases: [(name: String, animation: Animation)] = [
            ("repeatForever", .linear(duration: 0.20).repeatForever(autoreverses: false)),
            ("speed0", .linear(duration: 0.20).speed(0)),
        ]

        for testCase in pendingCases {
            let context = ModalPresentationContext(parentController: parent)
            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            context.beginPresentAnimation(
                controller: parent,
                transaction: transaction
            )
            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.effectiveAnimation
            )

            withExtendedLifetime(transaction) {
                waitForMainQueue(timeout: 0.05, until: { !events.isEmpty })
                XCTAssertEqual(events, [], testCase.name)
                XCTAssertFalse(updateAnimation(context, delta: 1.0), testCase.name)
            }
        }

        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.20).speed(-1))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("negative logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("negative removed")
        }

        context.beginPresentAnimation(
            controller: parent,
            transaction: transaction
        )
        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.effectiveAnimation
        )

        waitForMainQueue(until: {
            events == ["negative removed", "negative logical"]
        })
        XCTAssertEqual(events, ["negative removed", "negative logical"])
        XCTAssertFalse(updateAnimation(context, delta: 1.0))
    }

    func testNonFiniteDismissalCleansUpAndLeavesModalCompletionsPending() {
        let parent = makeParentController()
        let cases: [(name: String, animation: Animation)] = [
            ("repeatForever", .linear(duration: 0.20).repeatForever(autoreverses: false)),
            ("speed0", .linear(duration: 0.20).speed(0)),
            ("speedNegative", .linear(duration: 0.20).speed(-1)),
        ]

        for testCase in cases {
            let context = ModalPresentationContext(parentController: parent)
            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            XCTAssertTrue(
                context.requestDismissal(
                    controller: parent,
                    reason: .dismissed,
                    transaction: transaction
                ) {
                    events.append("\(testCase.name) cleanup")
                }
            )
            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.effectiveAnimation
            )

            withExtendedLifetime(transaction) {
                waitForMainQueue(timeout: 0.05, until: { events.count > 1 })
                XCTAssertEqual(events, ["\(testCase.name) cleanup"], testCase.name)
                XCTAssertFalse(updateAnimation(context, delta: 1.0), testCase.name)
            }
        }
    }

    func testSheetUpdateDismissDeliversOnDismissBeforeDismissCompletionBoundary() {
        Transaction.dispatchPendingListeners()

        let parent = makeParentController()
        let namespaceID = Namespace.ID(id: 90_001)
        var events: [String] = []
        let preference = SheetPreference(
            content: AnyView(EmptyView()),
            onDismiss: {
                events.append("onDismiss")
            },
            namespaceID: namespaceID,
            itemID: nil,
            drawsBackground: true,
            placement: .automatic,
            activeInspector: nil,
            usesPlatformWindow: false
        )

        parent.viewGraph.data.withCurrent {
            parent.updateSheetPresentation(
                .single(preference),
                transaction: Transaction(animation: nil),
                viewPhase: ViewGraphHost.Phase()
            )
        }
        XCTAssertEqual(events, [])

        var dismissTransaction = Transaction(animation: .linear(duration: 0.20))
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("dismiss removed")
        }
        dismissTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("dismiss logical")
        }

        parent.viewGraph.data.withCurrent {
            parent.updateSheetPresentation(
                .keyed([namespaceID: dismissTransaction]),
                transaction: dismissTransaction,
                viewPhase: ViewGraphHost.Phase()
            )
        }

        XCTAssertEqual(events, ["onDismiss"])
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )
        waitForMainQueue(timeout: 0.05, until: { events.count > 1 })
        XCTAssertEqual(events, ["onDismiss"])

        withExtendedLifetime(dismissTransaction) {}
    }

    func testDismissalCleanupDrainsRetainedLogicalContentBeforeDismissRemovedCompletion() throws {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []

        var contentTransaction = Transaction(animation: .linear(duration: 0.80))
        contentTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("content logical")
        }
        let contentLogicalToken = AnimationCompletionToken(
            listener: try XCTUnwrap(contentTransaction.animationLogicalListener)
        )
        contentLogicalToken.start()
        finalizeAnimationCompletions(
            in: contentTransaction,
            animation: contentTransaction.effectiveAnimation
        )

        var dismissTransaction = Transaction(animation: .linear(duration: 0.20))
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("dismiss removed")
        }

        XCTAssertTrue(
            context.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                events.append("onDismiss cleanup")
                contentLogicalToken.finish()
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))

        waitForMainQueue(until: { events.count == 3 })
        XCTAssertEqual(
            events,
            [
                "onDismiss cleanup",
                "content logical",
                "dismiss removed",
            ]
        )
    }

    func testDismissalCleanupDrainsRetainedRemovedContentBeforeDismissLogicalCompletion() throws {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []

        var contentTransaction = Transaction(animation: .linear(duration: 0.80))
        contentTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("content removed")
        }
        let contentRemovedToken = AnimationCompletionToken(
            listener: try XCTUnwrap(contentTransaction.animationListener)
        )
        contentRemovedToken.start()
        finalizeAnimationCompletions(
            in: contentTransaction,
            animation: contentTransaction.effectiveAnimation
        )

        var dismissTransaction = Transaction(animation: .linear(duration: 0.20))
        dismissTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("dismiss logical")
        }

        XCTAssertTrue(
            context.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                events.append("onDismiss cleanup")
                contentRemovedToken.finish()
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))

        waitForMainQueue(until: { events.count == 3 })
        XCTAssertEqual(
            events,
            [
                "onDismiss cleanup",
                "content removed",
                "dismiss logical",
            ]
        )
    }

    func testDismissalCleanupDrainsRetainedContentListenersBeforeDismissCompletions() throws {
        let parent = makeParentController()
        let context = ModalPresentationContext(parentController: parent)
        var events: [String] = []

        var contentTransaction = Transaction(animation: .linear(duration: 0.80))
        contentTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("content logical")
        }
        contentTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("content removed")
        }
        let contentRemovedToken = AnimationCompletionToken(
            listener: try XCTUnwrap(contentTransaction.animationListener)
        )
        let contentLogicalToken = AnimationCompletionToken(
            listener: try XCTUnwrap(contentTransaction.animationLogicalListener)
        )
        contentRemovedToken.start()
        contentLogicalToken.start()
        finalizeAnimationCompletions(
            in: contentTransaction,
            animation: contentTransaction.effectiveAnimation
        )

        var dismissTransaction = Transaction(animation: .linear(duration: 0.20))
        dismissTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("dismiss logical")
        }
        dismissTransaction.addAnimationCompletion(criteria: .removed) {
            events.append("dismiss removed")
        }

        XCTAssertTrue(
            context.requestDismissal(
                controller: parent,
                reason: .dismissed,
                transaction: dismissTransaction
            ) {
                events.append("onDismiss cleanup")
                contentRemovedToken.finish()
                contentLogicalToken.finish()
            }
        )
        finalizeAnimationCompletions(
            in: dismissTransaction,
            animation: dismissTransaction.effectiveAnimation
        )

        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.49))
        XCTAssertEqual(events, [])
        XCTAssertTrue(updateAnimation(context, delta: 0.02))

        waitForMainQueue(until: { events.count == 5 })
        XCTAssertEqual(
            events,
            [
                "onDismiss cleanup",
                "content removed",
                "content logical",
                "dismiss removed",
                "dismiss logical",
            ]
        )
    }

    private func makeParentController() -> WindowController {
        WindowController(
            content: EmptyView(),
            scene: WindowKey(namespace: .app, sceneID: SceneID(EmptyView.self))
        )
    }

    private func updateAnimation(
        _ context: ModalPresentationContext,
        delta: Double
    ) -> Bool {
        var result = false
        Update.ensure {
            result = context.updateAnimation(delta: delta)
        }
        return result
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
