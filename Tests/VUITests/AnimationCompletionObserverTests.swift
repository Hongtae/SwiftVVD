import XCTest
@testable import VUI

final class AnimationCompletionObserverTests: XCTestCase {
    func testNoRegisteredSameCriteriaFallbackPreservesInsertionOrder() {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .logicallyComplete) {
            fired.append("logical1")
        }
        observer.add(criteria: .logicallyComplete) {
            fired.append("logical2")
        }
        observer.add(criteria: .logicallyComplete) {
            fired.append("logical3")
        }

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)
        observer.noRegisteredAnimationFallbackDidFire(
            usesAnimatedOrdering: false
        ).forEach { $0() }

        XCTAssertEqual(fired, ["logical1", "logical2", "logical3"])
    }

    func testNoRegisteredMixedFallbackReversesFirstCriteriaGroupOnly() {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .logicallyComplete) {
            fired.append("logical1")
        }
        observer.add(criteria: .removed) {
            fired.append("removed1")
        }
        observer.add(criteria: .logicallyComplete) {
            fired.append("logical2")
        }
        observer.add(criteria: .removed) {
            fired.append("removed2")
        }
        observer.add(criteria: .logicallyComplete) {
            fired.append("logical3")
        }
        observer.add(criteria: .removed) {
            fired.append("removed3")
        }

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)
        observer.noRegisteredAnimationFallbackDidFire(
            usesAnimatedOrdering: false
        ).forEach { $0() }

        XCTAssertEqual(
            fired,
            ["logical3", "logical2", "logical1", "removed1", "removed2", "removed3"]
        )
    }

    func testAnimatedFallbackDrainsRemovedBeforeLogical() {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .logicallyComplete) {
            fired.append("logical1")
        }
        observer.add(criteria: .removed) {
            fired.append("removed1")
        }
        observer.add(criteria: .logicallyComplete) {
            fired.append("logical2")
        }
        observer.add(criteria: .removed) {
            fired.append("removed2")
        }
        observer.add(criteria: .logicallyComplete) {
            fired.append("logical3")
        }
        observer.add(criteria: .removed) {
            fired.append("removed3")
        }

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)
        observer.noRegisteredAnimationFallbackDidFire(
            usesAnimatedOrdering: true
        ).forEach { $0() }

        XCTAssertEqual(
            fired,
            ["removed1", "removed2", "removed3", "logical1", "logical2", "logical3"]
        )
    }

    func testNoRegisteredZeroDurationExplicitAnimationUsesAnimatedOrdering() {
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.animation
        )

        waitForMainQueue(until: { events.count == 2 })
        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testNoRegisteredFiniteExplicitAnimationWaitsForAnimatedBoundary() {
        var events: [String] = []
        var transaction = Transaction(animation: .linear(duration: 0.03))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.animation
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        XCTAssertTrue(events.isEmpty)

        waitForMainQueue(until: { events.count == 2 })
        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testNoRegisteredFiniteWrapperExplicitAnimationsUseWrapperBoundary() {
        let cases: [(name: String, animation: Animation)] = [
            ("delay", .linear(duration: 0.02).delay(0.02)),
            ("speed", .linear(duration: 0.08).speed(2)),
            ("repeat", .linear(duration: 0.02).repeatCount(2, autoreverses: false)),
        ]

        for testCase in cases {
            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            XCTAssertTrue(events.isEmpty, testCase.name)

            waitForMainQueue(until: { events.count == 2 })
            XCTAssertEqual(
                events,
                ["\(testCase.name) removed", "\(testCase.name) logical"]
            )
        }
    }

    func testNoRegisteredSourceDefinedCustomExplicitAnimationWaitsForNilBoundary() {
        var events: [String] = []
        var transaction = Transaction(animation: Animation(UnitLinearAnimation(duration: 0.05)))
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.animation
        )

        XCTAssertGreaterThan(
            transaction.animation?.box.noRegisteredCompletionDelay() ?? 0,
            0.05
        )
        XCTAssertTrue(events.isEmpty)

        waitForMainQueue(until: { events.count == 2 })
        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testNoRegisteredSourceDefinedCustomWrappersUseWrapperNilBoundary() {
        let custom = Animation(UnitLinearAnimation(duration: 0.05))
        let cases: [(name: String, animation: Animation, earlyWait: TimeInterval)] = [
            ("delay", custom.delay(0.04), 0.08),
            ("speed", custom.speed(2), 0.02),
            ("repeat", custom.repeatCount(2, autoreverses: false), 0.12),
        ]

        for testCase in cases {
            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            XCTAssertGreaterThan(
                testCase.animation.box.noRegisteredCompletionDelay() ?? 0,
                testCase.earlyWait,
                testCase.name
            )
            XCTAssertTrue(events.isEmpty, testCase.name)

            waitForMainQueue(timeout: 0.40, until: { events.count == 2 })
            XCTAssertEqual(
                events,
                ["\(testCase.name) removed", "\(testCase.name) logical"]
            )
        }
    }

    func testNoRegisteredNonCustomInfiniteExplicitAnimationsStayPending() {
        let finiteBase = Animation.linear(duration: 0.02)
        let cases: [(name: String, animation: Animation)] = [
            ("repeatForever", finiteBase.repeatForever(autoreverses: false)),
            ("speed0", finiteBase.speed(0)),
            ("speedNegative", finiteBase.speed(-1)),
            ("delayRepeatForever", finiteBase.delay(0.02).repeatForever(autoreverses: false)),
            ("repeatForeverDelay", finiteBase.repeatForever(autoreverses: false).delay(0.02)),
        ]

        for testCase in cases {
            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            withExtendedLifetime(transaction) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
                XCTAssertTrue(events.isEmpty, testCase.name)
            }
        }
    }

    func testNoRegisteredCircularUnitCurveExplicitAnimationsUseFallbackFamilies() {
        let circular = Animation.timingCurve(.circularEaseInOut, duration: 0.02)
        let finiteCases: [(name: String, animation: Animation, shouldWait: Bool)] = [
            ("direct", circular, true),
            ("zero", .timingCurve(.circularEaseInOut, duration: 0), false),
            ("delay", circular.delay(0.02), true),
            ("speed", .timingCurve(.circularEaseInOut, duration: 0.08).speed(2), true),
            ("repeat", circular.repeatCount(2, autoreverses: false), true),
        ]

        for testCase in finiteCases {
            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            if testCase.shouldWait {
                XCTAssertGreaterThan(
                    testCase.animation.box.noRegisteredCompletionDelay() ?? 0,
                    0,
                    testCase.name
                )
                XCTAssertTrue(events.isEmpty, testCase.name)
            }

            waitForMainQueue(until: { events.count == 2 })
            XCTAssertEqual(
                events,
                ["\(testCase.name) removed", "\(testCase.name) logical"]
            )
        }

        var pendingEvents: [String] = []
        var pending = Transaction(
            animation: circular.repeatForever(autoreverses: false)
        )
        pending.addAnimationCompletion(criteria: .logicallyComplete) {
            pendingEvents.append("repeatForever logical")
        }
        pending.addAnimationCompletion(criteria: .removed) {
            pendingEvents.append("repeatForever removed")
        }

        finalizeAnimationCompletions(in: pending, animation: pending.animation)

        withExtendedLifetime(pending) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
            XCTAssertTrue(pendingEvents.isEmpty)
        }
    }

    func testNoRegisteredDirectSpringNegativeDelayUsesCriteriaSpecificScheduling() throws {
        let spring = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        let baseDelay = try XCTUnwrap(spring.box.noRegisteredCompletionDelay())
        let animation = spring.delay(0.04 - baseDelay)
        let logicalDelay = try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: .logicallyComplete)
        )
        let removedDelay = try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: .removed)
        )
        XCTAssertLessThan(logicalDelay, removedDelay)
        XCTAssertLessThan(removedDelay, 0.10)

        var events: [String] = []
        var logicalFirst = Transaction(animation: animation)
        logicalFirst.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical-first logical")
        }
        logicalFirst.addAnimationCompletion(criteria: .removed) {
            events.append("logical-first removed")
        }
        finalizeAnimationCompletions(
            in: logicalFirst,
            animation: logicalFirst.animation
        )
        waitForMainQueue(timeout: 0.30, until: { events.count == 2 })
        XCTAssertEqual(
            events,
            [
                "logical-first logical",
                "logical-first removed",
            ]
        )

        events.removeAll()
        var removedFirst = Transaction(animation: animation)
        removedFirst.addAnimationCompletion(criteria: .removed) {
            events.append("removed-first removed")
        }
        removedFirst.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("removed-first logical")
        }
        finalizeAnimationCompletions(
            in: removedFirst,
            animation: removedFirst.animation
        )
        waitForMainQueue(timeout: 0.30, until: { events.count == 2 })
        XCTAssertEqual(
            events,
            [
                "removed-first removed",
                "removed-first logical",
            ]
        )
    }

    func testNoRegisteredDirectSpringRepeatUsesCriteriaSpecificScheduling() throws {
        let spring = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        let repeated = spring.repeatCount(2, autoreverses: false)
        let repeatedRemovedDelay = try XCTUnwrap(
            repeated.box.noRegisteredCompletionDelay(for: .removed)
        )
        let animation = repeated.delay(0.04 - repeatedRemovedDelay)
        let logicalDelay = try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: .logicallyComplete)
        )
        let removedDelay = try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: .removed)
        )
        XCTAssertLessThan(logicalDelay, removedDelay)
        XCTAssertLessThan(removedDelay, 0.08)

        var events: [String] = []
        var logicalFirst = Transaction(animation: animation)
        logicalFirst.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical-first logical")
        }
        logicalFirst.addAnimationCompletion(criteria: .removed) {
            events.append("logical-first removed")
        }
        finalizeAnimationCompletions(
            in: logicalFirst,
            animation: logicalFirst.animation
        )
        waitForMainQueue(timeout: 0.30, until: { events.count == 2 })
        XCTAssertEqual(
            events,
            [
                "logical-first logical",
                "logical-first removed",
            ]
        )

        events.removeAll()
        var removedFirst = Transaction(animation: animation)
        removedFirst.addAnimationCompletion(criteria: .removed) {
            events.append("removed-first removed")
        }
        removedFirst.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("removed-first logical")
        }
        finalizeAnimationCompletions(
            in: removedFirst,
            animation: removedFirst.animation
        )
        waitForMainQueue(timeout: 0.30, until: { events.count == 2 })
        XCTAssertEqual(
            events,
            [
                "removed-first removed",
                "removed-first logical",
            ]
        )
    }

    func testNoRegisteredDirectSpringSingleCriteriaWrappersCompleteAfterAction() throws {
        let spring = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        let cases: [(name: String, animation: Animation, criteria: AnimationCompletionCriteria)] = [
            ("delay logical", spring.delay(0.20), .logicallyComplete),
            ("delay removed", spring.delay(0.20), .removed),
            ("repeat logical", spring.repeatCount(2, autoreverses: false), .logicallyComplete),
            ("repeat removed", spring.repeatCount(2, autoreverses: false), .removed),
            ("negative delay logical", spring.delay(-0.70), .logicallyComplete),
            ("negative delay removed", spring.delay(-0.70), .removed),
        ]
        let expectedEvents = cases.map(\.name).sorted()
        var events: [String] = []
        var transactions: [Transaction] = []
        var longestFallbackDelay: TimeInterval = 0

        for testCase in cases {
            let fallbackDelay = try XCTUnwrap(
                testCase.animation.box.noRegisteredCompletionDelay(for: testCase.criteria),
                testCase.name
            )
            XCTAssertGreaterThan(fallbackDelay, 0.10, testCase.name)
            longestFallbackDelay = max(longestFallbackDelay, fallbackDelay)

            let name = testCase.name
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: testCase.criteria) {
                events.append(name)
            }
            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )
            transactions.append(transaction)
        }

        withExtendedLifetime(transactions) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.10))
            XCTAssertTrue(events.isEmpty)

            waitForMainQueue(
                timeout: longestFallbackDelay + 0.50,
                until: { events.count == cases.count }
            )
        }
        XCTAssertEqual(events.count, cases.count)
        XCTAssertEqual(events.sorted(), expectedEvents)
    }

    func testNoRegisteredDirectSpringUsesAnimatedSameBoundaryWhenLogicalRegisteredFirst() throws {
        let animation = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        let logicalDelay = try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: .logicallyComplete)
        )
        let removedDelay = try XCTUnwrap(
            animation.box.noRegisteredCompletionDelay(for: .removed)
        )
        XCTAssertEqual(logicalDelay, removedDelay, accuracy: 0.000_000_1)

        var events: [String] = []
        var transaction = Transaction(animation: animation)
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("logical")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            events.append("removed")
        }

        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.animation
        )

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(events.isEmpty)

        waitForMainQueue(timeout: 2.0, until: { events.count == 2 })
        XCTAssertEqual(events, ["removed", "logical"])
    }

    func testNoRegisteredSpeedWrappedDirectSpringUsesAnimatedSameBoundaryWhenLogicalRegisteredFirst() throws {
        let spring = Animation.interpolatingSpring(
            mass: 1,
            stiffness: 100,
            damping: 10,
            initialVelocity: 0
        )
        let cases: [(name: String, animation: Animation)] = [
            ("speed", spring.speed(2)),
            ("speedRepeat", spring.speed(2).repeatCount(2, autoreverses: false)),
            ("repeatSpeed", spring.repeatCount(2, autoreverses: false).speed(2)),
        ]

        for testCase in cases {
            let logicalDelay = try XCTUnwrap(
                testCase.animation.box.noRegisteredCompletionDelay(for: .logicallyComplete),
                testCase.name
            )
            let removedDelay = try XCTUnwrap(
                testCase.animation.box.noRegisteredCompletionDelay(for: .removed),
                testCase.name
            )
            XCTAssertEqual(
                logicalDelay,
                removedDelay,
                accuracy: 0.000_000_1,
                testCase.name
            )

            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            XCTAssertTrue(events.isEmpty, testCase.name)

            waitForMainQueue(timeout: 2.0, until: { events.count == 2 })
            XCTAssertEqual(
                events,
                ["\(testCase.name) removed", "\(testCase.name) logical"],
                testCase.name
            )
        }
    }

    func testNoRegisteredFluidAndDefaultResidualWrapperChainsUseAnimatedSameBoundary() throws {
        let fluid = Animation.spring(
            response: 0.35,
            dampingFraction: 0.70,
            blendDuration: 0
        )
        let cases: [(name: String, animation: Animation)] = [
            (
                "fluidSpeedRepeat",
                fluid.speed(2).repeatCount(2, autoreverses: false)
            ),
            (
                "defaultSpeedRepeat",
                Animation.default.speed(2).repeatCount(2, autoreverses: false)
            ),
            ("fluidNegativeDelay", fluid.delay(-0.20)),
            ("defaultNegativeDelay", Animation.default.delay(-0.20)),
        ]

        for testCase in cases {
            let logicalDelay = try XCTUnwrap(
                testCase.animation.box.noRegisteredCompletionDelay(for: .logicallyComplete),
                testCase.name
            )
            let removedDelay = try XCTUnwrap(
                testCase.animation.box.noRegisteredCompletionDelay(for: .removed),
                testCase.name
            )
            XCTAssertEqual(
                logicalDelay,
                removedDelay,
                accuracy: 0.000_000_1,
                testCase.name
            )

            var events: [String] = []
            var transaction = Transaction(animation: testCase.animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            XCTAssertTrue(events.isEmpty, testCase.name)

            waitForMainQueue(timeout: 2.0, until: { events.count == 2 })
            XCTAssertEqual(
                events,
                ["\(testCase.name) removed", "\(testCase.name) logical"],
                testCase.name
            )
        }
    }

    func testNoRegisteredFluidAndDefaultResidualWrappersUseAnimatedBoundary() throws {
        let cases: [(name: String, base: Animation)] = [
            (
                "fluid",
                .spring(response: 0.35, dampingFraction: 0.70, blendDuration: 0)
            ),
            ("default", .default),
        ]

        for testCase in cases {
            let baseDelay = try XCTUnwrap(
                testCase.base.box.noRegisteredCompletionDelay()
            )
            let animation = testCase.base.delay(0.04 - baseDelay)
            let logicalDelay = try XCTUnwrap(
                animation.box.noRegisteredCompletionDelay(for: .logicallyComplete)
            )
            let removedDelay = try XCTUnwrap(
                animation.box.noRegisteredCompletionDelay(for: .removed)
            )
            XCTAssertEqual(logicalDelay, removedDelay, accuracy: 0.000_000_1)
            XCTAssertLessThan(removedDelay, 0.08)

            var events: [String] = []
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(testCase.name) logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(testCase.name) removed")
            }

            finalizeAnimationCompletions(
                in: transaction,
                animation: transaction.animation
            )

            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            XCTAssertTrue(events.isEmpty, testCase.name)

            waitForMainQueue(timeout: 0.30, until: { events.count == 2 })
            XCTAssertEqual(
                events,
                ["\(testCase.name) removed", "\(testCase.name) logical"]
            )
        }
    }

    func testRegisteredCriteriaFinishIndependently() throws {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .logicallyComplete) {
            fired.append("logical")
        }
        observer.add(criteria: .removed) {
            fired.append("removed")
        }

        let logicalListener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .logicallyComplete
        )
        let removedListener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .removed
        )
        let logicalToken = AnimationCompletionToken(
            listener: logicalListener,
            criteria: .logicallyComplete
        )
        let removedToken = AnimationCompletionToken(
            listener: removedListener,
            criteria: .removed
        )
        logicalToken.start()
        removedToken.start()

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)

        logicalToken.finish().forEach { $0() }
        XCTAssertEqual(fired, ["logical"])

        removedToken.finish().forEach { $0() }
        XCTAssertEqual(fired, ["logical", "removed"])
    }

    func testRegisteredSameBoundaryCallerDrainsRemovedBeforeLogical() throws {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .logicallyComplete) {
            fired.append("logical")
        }
        observer.add(criteria: .removed) {
            fired.append("removed")
        }

        let logicalListener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .logicallyComplete
        )
        let removedListener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .removed
        )
        let logicalToken = AnimationCompletionToken(
            listener: logicalListener,
            criteria: .logicallyComplete
        )
        let removedToken = AnimationCompletionToken(
            listener: removedListener,
            criteria: .removed
        )
        logicalToken.start()
        removedToken.start()

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)

        removedToken.finish().forEach { $0() }
        logicalToken.finish().forEach { $0() }

        XCTAssertEqual(fired, ["removed", "logical"])
    }

    func testCopiedRegisteredTokenFinishesOnlyOnce() throws {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .removed) {
            fired.append("removed")
        }
        let listener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .removed
        )
        let token = AnimationCompletionToken(listener: listener, criteria: .removed)
        token.start()

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)

        token.finish().forEach { $0() }
        token.finish().forEach { $0() }

        XCTAssertEqual(fired, ["removed"])
    }

    func testRegisteredCriteriaWaitsForAllActiveTokens() throws {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .removed) {
            fired.append("removed")
        }
        let listener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .removed
        )
        let firstToken = AnimationCompletionToken(listener: listener, criteria: .removed)
        let secondToken = AnimationCompletionToken(listener: listener, criteria: .removed)
        firstToken.start()
        secondToken.start()

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)

        firstToken.finish().forEach { $0() }
        XCTAssertTrue(fired.isEmpty)

        secondToken.finish().forEach { $0() }
        XCTAssertEqual(fired, ["removed"])
    }

    func testRegisteredFallbackDoesNotFinishWhileTokenIsActive() throws {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .removed) {
            fired.append("removed")
        }
        let listener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .removed
        )
        let token = AnimationCompletionToken(listener: listener, criteria: .removed)
        token.start()

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)
        XCTAssertTrue(
            observer.noRegisteredAnimationFallbackDidFire(
                usesAnimatedOrdering: true
            ).isEmpty
        )

        token.finish().forEach { $0() }
        XCTAssertEqual(fired, ["removed"])
    }

    func testRegisteredCriteriaCountsAreIndependent() throws {
        var fired: [String] = []
        let observer = AnimationCompletionObserver(criteria: .logicallyComplete) {
            fired.append("logical")
        }
        observer.add(criteria: .removed) {
            fired.append("removed")
        }

        let logicalListener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .logicallyComplete
        )
        let removedListener = AllFinishedAnimationListener(
            observer: observer,
            criteria: .removed
        )
        let firstLogicalToken = AnimationCompletionToken(
            listener: logicalListener,
            criteria: .logicallyComplete
        )
        let secondLogicalToken = AnimationCompletionToken(
            listener: logicalListener,
            criteria: .logicallyComplete
        )
        let removedToken = AnimationCompletionToken(
            listener: removedListener,
            criteria: .removed
        )
        firstLogicalToken.start()
        secondLogicalToken.start()
        removedToken.start()

        XCTAssertTrue(observer.bodyDidFinish().isEmpty)

        removedToken.finish().forEach { $0() }
        XCTAssertEqual(fired, ["removed"])

        firstLogicalToken.finish().forEach { $0() }
        XCTAssertEqual(fired, ["removed"])

        secondLogicalToken.finish().forEach { $0() }
        XCTAssertEqual(fired, ["removed", "logical"])
    }

    func testListenerPairObjectRegistrationForwardsAddRemoveInOrder() {
        var fired: [String] = []
        let firstObserver = AnimationCompletionObserver(criteria: .removed) {
            fired.append("first")
        }
        let secondObserver = AnimationCompletionObserver(criteria: .removed) {
            fired.append("second")
        }
        let first = AllFinishedAnimationListener(
            observer: firstObserver,
            criteria: .removed
        )
        let second = AllFinishedAnimationListener(
            observer: secondObserver,
            criteria: .removed
        )
        let pair = ListenerPair(first: first, second: second)

        pair.animationWasAdded()
        XCTAssertTrue(firstObserver.bodyDidFinish().isEmpty)
        XCTAssertTrue(secondObserver.bodyDidFinish().isEmpty)

        pair.animationWasRemoved().forEach { $0() }

        XCTAssertEqual(fired, ["first", "second"])
    }

    func testTransactionCompletionCriteriaInstallSeparateListenerBuckets() throws {
        var removedTransaction = Transaction()
        removedTransaction.addAnimationCompletion(criteria: .removed) {}
        let removedListener = try XCTUnwrap(removedTransaction.animationListener)
        XCTAssertNil(removedTransaction.animationLogicalListener)
        XCTAssertTrue(removedTransaction.combinedAnimationListener === removedListener)

        var logicalTransaction = Transaction()
        logicalTransaction.addAnimationCompletion(criteria: .logicallyComplete) {}
        let logicalListener = try XCTUnwrap(logicalTransaction.animationLogicalListener)
        XCTAssertNil(logicalTransaction.animationListener)
        XCTAssertTrue(logicalTransaction.combinedAnimationListener === logicalListener)

        var fired: [String] = []
        var mixedTransaction = Transaction()
        mixedTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical")
        }
        mixedTransaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed")
        }

        let mixedRemovedListener = try XCTUnwrap(mixedTransaction.animationListener)
        let mixedLogicalListener = try XCTUnwrap(mixedTransaction.animationLogicalListener)
        XCTAssertFalse(mixedRemovedListener === mixedLogicalListener)
        XCTAssertTrue(mixedTransaction.combinedAnimationListener is ListenerPair)

        mixedLogicalListener.animationWasAdded()
        mixedRemovedListener.animationWasAdded()
        XCTAssertTrue(
            try XCTUnwrap(mixedTransaction.animationCompletionObserver)
                .bodyDidFinish()
                .isEmpty
        )
        XCTAssertEqual(fired, [])

        mixedLogicalListener.animationWasRemoved().forEach { $0() }
        XCTAssertEqual(fired, ["logical"])

        mixedRemovedListener.animationWasRemoved().forEach { $0() }
        XCTAssertEqual(fired, ["logical", "removed"])
    }

    func testTransactionSameCriteriaCompletionsInstallListenerPair() throws {
        var fired: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("first")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("second")
        }

        let listener = try XCTUnwrap(transaction.animationListener)
        XCTAssertTrue(listener is ListenerPair)
        XCTAssertTrue(
            try XCTUnwrap(transaction.animationCompletionObserver)
                .bodyDidFinish()
                .isEmpty
        )

        listener.animationWasAdded()
        listener.animationWasRemoved().forEach { $0() }

        XCTAssertEqual(fired, ["first", "second"])
    }

    func testTransactionSameLogicalCompletionsInstallListenerPair() throws {
        var fired: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("first")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("second")
        }

        let listener = try XCTUnwrap(transaction.animationLogicalListener)
        XCTAssertTrue(listener is ListenerPair)
        XCTAssertTrue(
            try XCTUnwrap(transaction.animationCompletionObserver)
                .bodyDidFinish()
                .isEmpty
        )

        listener.animationWasAdded()
        listener.animationWasRemoved().forEach { $0() }

        XCTAssertEqual(fired, ["first", "second"])
    }

    func testCombinedAnimationListenerPairsRegularBeforeLogical() throws {
        var fired: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical")
        }

        let listener = try XCTUnwrap(transaction.combinedAnimationListener)
        XCTAssertTrue(listener is ListenerPair)
        XCTAssertTrue(
            try XCTUnwrap(transaction.animationCompletionObserver)
                .bodyDidFinish()
                .isEmpty
        )

        listener.animationWasAdded()
        listener.animationWasRemoved().forEach { $0() }

        XCTAssertEqual(fired, ["removed", "logical"])
    }

    func testRegisteredMixedCriteriaCompletionsPreserveGroupInsertionOrder() throws {
        var fired: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical1")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed1")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical2")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed2")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical3")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed3")
        }

        let listener = try XCTUnwrap(transaction.combinedAnimationListener)
        XCTAssertTrue(listener is ListenerPair)
        XCTAssertTrue(
            try XCTUnwrap(transaction.animationCompletionObserver)
                .bodyDidFinish()
                .isEmpty
        )

        listener.animationWasAdded()
        listener.animationWasRemoved().forEach { $0() }

        XCTAssertEqual(
            fired,
            [
                "removed1",
                "removed2",
                "removed3",
                "logical1",
                "logical2",
                "logical3",
            ]
        )
    }

    func testRegisteredSplitCriteriaPreservesInsertionOrderAtEachBoundary() throws {
        var fired: [String] = []
        var transaction = Transaction()
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical1")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed1")
        }
        transaction.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("logical2")
        }
        transaction.addAnimationCompletion(criteria: .removed) {
            fired.append("removed2")
        }

        let logicalListener = try XCTUnwrap(transaction.animationLogicalListener)
        let removedListener = try XCTUnwrap(transaction.animationListener)
        logicalListener.animationWasAdded()
        removedListener.animationWasAdded()
        XCTAssertTrue(
            try XCTUnwrap(transaction.animationCompletionObserver)
                .bodyDidFinish()
                .isEmpty
        )

        logicalListener.animationWasRemoved().forEach { $0() }
        XCTAssertEqual(fired, ["logical1", "logical2"])

        removedListener.animationWasRemoved().forEach { $0() }
        XCTAssertEqual(fired, ["logical1", "logical2", "removed1", "removed2"])
    }

    func testRetainedTransitionRemovalListenerUsesAnimatedNoRegisteredFallback() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        var seed: Attribute<UInt32>!
        ref.withCurrent {
            seed = graph.makeInput(value: UInt32(0))
        }

        let listener = DynamicContainer.TransitionRemovalListener(
            seed: seed,
            inbox: graph.inbox
        )
        var transaction = Transaction(animation: .linear(duration: 0.02))
        XCTAssertNotNil(listener.installCompletion(into: &transaction))

        ref.withCurrent {
            listener.readSeed()
            XCTAssertEqual(seed.value, 0)
        }

        finalizeAnimationCompletions(
            in: transaction,
            animation: transaction.animation
        )

        XCTAssertFalse(listener.isComplete)
        XCTAssertGreaterThan(
            transaction.animation?.box.noRegisteredCompletionDelay() ?? 0,
            0
        )

        waitForMainQueue(until: { listener.isComplete })
        XCTAssertTrue(listener.isComplete)

        ref.withCurrent {
            graph.inbox.drain()
            XCTAssertEqual(seed.value, 1)
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        ref.withCurrent {
            graph.inbox.drain()
            XCTAssertEqual(seed.value, 1)
        }
    }

    func testRetainedTransitionRemovalListenerInstallsCompletionOnlyOnce() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        var seed: Attribute<UInt32>!
        ref.withCurrent {
            seed = graph.makeInput(value: UInt32(0))
        }

        let listener = DynamicContainer.TransitionRemovalListener(
            seed: seed,
            inbox: graph.inbox
        )
        var firstTransaction = Transaction(animation: .linear(duration: 0.02))
        XCTAssertNotNil(listener.installCompletion(into: &firstTransaction))

        var secondTransaction = Transaction(animation: .linear(duration: 0.02))
        XCTAssertNil(listener.installCompletion(into: &secondTransaction))

        finalizeAnimationCompletions(
            in: secondTransaction,
            animation: secondTransaction.animation
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertFalse(listener.isComplete)
        ref.withCurrent {
            listener.readSeed()
            graph.inbox.drain()
            XCTAssertEqual(seed.value, 0)
        }

        finalizeAnimationCompletions(
            in: firstTransaction,
            animation: firstTransaction.animation
        )
        waitForMainQueue(until: { listener.isComplete })

        ref.withCurrent {
            graph.inbox.drain()
            XCTAssertEqual(seed.value, 1)
        }
    }

    func testStandaloneTransactionCompletionDispatchesPendingListeners() {
        var fired: [String] = []
        func XCTAssertFiredBefore(
            _ earlier: String,
            _ later: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            guard let earlierIndex = fired.firstIndex(of: earlier),
                  let laterIndex = fired.firstIndex(of: later) else {
                XCTFail("Missing events \(earlier) or \(later): \(fired)", file: file, line: line)
                return
            }
            XCTAssertLessThan(earlierIndex, laterIndex, file: file, line: line)
        }

        var retained = Transaction(animation: .linear(duration: 0.20))
        retained.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("retained logical")
        }
        retained.addAnimationCompletion(criteria: .removed) {
            fired.append("retained removed")
        }
        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("first logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("first removed")
            }
        }

        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        XCTAssertTrue(fired.contains("retained logical"))
        XCTAssertTrue(fired.contains("retained removed"))
        XCTAssertTrue(fired.contains("first logical"))
        XCTAssertTrue(fired.contains("first removed"))
        XCTAssertFiredBefore("retained logical", "retained removed")
        XCTAssertFiredBefore("first logical", "first removed")

        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("second logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("second removed")
            }
        }

        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        XCTAssertEqual(
            Array(fired.suffix(2)),
            ["second logical", "second removed"]
        )
    }

    func testRetainedStandaloneTransactionCompletionWaitsForScheduledPendingDrain() {
        var fired: [String] = []
        var retained: Transaction? = Transaction(animation: .linear(duration: 0.20))
        retained?.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("retained logical")
        }
        retained?.addAnimationCompletion(criteria: .removed) {
            fired.append("retained removed")
        }

        XCTAssertEqual(fired, [])
        waitForMainQueue(until: { fired.count == 2 })
        XCTAssertEqual(fired, ["retained logical", "retained removed"])

        retained = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(fired, ["retained logical", "retained removed"])
    }

    func testRetainedAndDroppedStandaloneTransactionsSplitScheduledAndScopeExitTiming() {
        var fired: [String] = []
        var retained: Transaction? = Transaction(animation: .linear(duration: 0.20))
        retained?.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("retained logical")
        }
        retained?.addAnimationCompletion(criteria: .removed) {
            fired.append("retained removed")
        }

        do {
            var dropped = Transaction(animation: .linear(duration: 0.20))
            dropped.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("dropped logical")
            }
            dropped.addAnimationCompletion(criteria: .removed) {
                fired.append("dropped removed")
            }
        }

        XCTAssertEqual(fired, ["dropped logical", "dropped removed"])

        waitForMainQueue(until: { fired.count == 4 })
        XCTAssertEqual(
            fired,
            [
                "dropped logical",
                "dropped removed",
                "retained logical",
                "retained removed",
            ]
        )

        retained = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(
            fired,
            [
                "dropped logical",
                "dropped removed",
                "retained logical",
                "retained removed",
            ]
        )
    }

    func testRetainedStandaloneTransactionCompletionSchedulesLaterCycleAfterDrain() {
        var fired: [String] = []
        var first: Transaction? = Transaction(animation: .linear(duration: 0.20))
        first?.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("first logical")
        }
        first?.addAnimationCompletion(criteria: .removed) {
            fired.append("first removed")
        }

        waitForMainQueue(until: { fired.count == 2 })
        XCTAssertEqual(fired, ["first logical", "first removed"])

        var second: Transaction? = Transaction(animation: .linear(duration: 0.20))
        second?.addAnimationCompletion(criteria: .logicallyComplete) {
            fired.append("second logical")
        }
        second?.addAnimationCompletion(criteria: .removed) {
            fired.append("second removed")
        }

        waitForMainQueue(until: { fired.count == 4 })
        XCTAssertEqual(
            fired,
            [
                "first logical",
                "first removed",
                "second logical",
                "second removed",
            ]
        )

        first = nil
        second = nil
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(
            fired,
            [
                "first logical",
                "first removed",
                "second logical",
                "second removed",
            ]
        )
    }

    func testPendingListenerDispatchFinalizesInsideUpdateScope() {
        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        var events: [String] = []
        let listener = PendingFinalizeProbeListener {
            events.append("finalize update=\(Update.isActive)")
            return [
                {
                    events.append("completion update=\(Update.isActive)")
                },
            ]
        }

        Transaction.addPendingListener(listener)

        let actions = Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        )
        XCTAssertEqual(events, ["finalize update=true"])
        XCTAssertEqual(actions.count, 1)

        actions.forEach { $0() }
        XCTAssertEqual(
            events,
            [
                "finalize update=true",
                "completion update=false",
            ]
        )
    }

    func testPendingListenerStorageDropsReleasedWeakListeners() {
        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        var events: [String] = []
        do {
            let listener = PendingFinalizeProbeListener {
                events.append("finalize")
                return [
                    {
                        events.append("completion")
                    },
                ]
            }
            Transaction.addPendingListener(listener)
        }

        let actions = Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        )

        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(events, [])
    }

    func testWithAnimationCompletionIsNotDrainedByStandalonePendingDispatchDuringBody() {
        Transaction.dispatchPendingListeners(
            finalizingStandalonePending: true
        ).forEach { $0() }

        var events: [String] = []
        withAnimation(
            .linear(duration: 0.20),
            completionCriteria: .logicallyComplete
        ) {
            events.append("body start")
            Transaction.dispatchPendingListeners(
                finalizingStandalonePending: true
            ).forEach { $0() }
            events.append("body after pending drain")
        } completion: {
            events.append("completion")
        }
        events.append("returned")

        XCTAssertEqual(
            events,
            [
                "body start",
                "body after pending drain",
                "completion",
                "returned",
            ]
        )
    }

    func testStandaloneTransactionCompletionScopeExitDrainsDroppedListeners() {
        var fired: [String] = []
        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("dropped logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("dropped removed")
            }
        }

        XCTAssertEqual(fired, ["dropped logical", "dropped removed"])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(fired, ["dropped logical", "dropped removed"])

        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("second logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("second removed")
            }
        }

        XCTAssertEqual(
            fired,
            [
                "dropped logical",
                "dropped removed",
                "second logical",
                "second removed",
            ]
        )
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(
            fired,
            [
                "dropped logical",
                "dropped removed",
                "second logical",
                "second removed",
            ]
        )
    }

    func testObservedMutationSuppressesScopeExitNoRegisteredFallback() {
        var fired: [String] = []

        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("logical")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("removed")
            }
            transaction.markAnimationCompletionMutation()
        }

        XCTAssertEqual(fired, [])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(fired, [])
    }

    func testStandaloneTransactionCompletionReentrantPendingDrainInterleavesBeforeRemainingListener() {
        var fired: [String] = []

        do {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("first logical")
                var nested = Transaction(animation: .linear(duration: 0.20))
                nested.addAnimationCompletion(criteria: .logicallyComplete) {
                    fired.append("nested logical")
                }
                nested.addAnimationCompletion(criteria: .removed) {
                    fired.append("nested removed")
                }
                fired.append("nested registered")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("first removed")
            }
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(
            fired,
            [
                "first logical",
                "nested registered",
                "nested logical",
                "nested removed",
                "first removed",
            ]
        )
    }

    func testRetainedStandaloneTransactionReentrantPendingDrainWaitsForRemainingOuterListener() {
        var fired: [String] = []
        var retainedTransactions: [Transaction] = []

        func makeRetainedTransaction(
            label: String,
            registersNestedInLogical: Bool = false
        ) {
            var transaction = Transaction(animation: .linear(duration: 0.20))
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                fired.append("\(label) logical")
                if registersNestedInLogical {
                    makeRetainedTransaction(label: "nested")
                }
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                fired.append("\(label) removed")
            }
            retainedTransactions.append(transaction)
            fired.append("\(label) registered")
        }

        makeRetainedTransaction(
            label: "outer",
            registersNestedInLogical: true
        )

        waitForMainQueue(until: { fired.contains("nested removed") })
        XCTAssertEqual(
            fired,
            [
                "outer registered",
                "outer logical",
                "nested registered",
                "outer removed",
                "nested logical",
                "nested removed",
            ]
        )

        retainedTransactions.removeAll()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(
            fired,
            [
                "outer registered",
                "outer logical",
                "nested registered",
                "outer removed",
                "nested logical",
                "nested removed",
            ]
        )
    }

    func testDirectWithTransactionNoMutationReentrantPendingDrainInterleavesBeforeRemainingFallback() {
        var events: [String] = []

        func makeDroppedTransaction(label: String) {
            var nested = Transaction(animation: .linear(duration: 0.20))
            nested.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical")
            }
            nested.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed")
            }
            events.append("\(label) registered")
        }

        func runCase(_ label: String, animation: Animation?) {
            var transaction = Transaction(animation: animation)
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) outer logical")
                makeDroppedTransaction(label: "\(label) nested")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) outer removed")
            }

            withTransaction(transaction) {
                events.append("\(label) body")
            }
            events.append("\(label) returned")
        }

        runCase("nil", animation: nil)
        runCase("explicit", animation: .linear(duration: 0.20))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(
            events,
            [
                "nil body",
                "nil returned",
                "nil outer logical",
                "nil nested registered",
                "nil nested logical",
                "nil nested removed",
                "nil outer removed",
                "explicit body",
                "explicit returned",
                "explicit outer logical",
                "explicit nested registered",
                "explicit nested logical",
                "explicit nested removed",
                "explicit outer removed",
            ]
        )
    }

    func testDirectWithTransactionNoMutationCompletionOrdering() {
        var events: [String] = []

        func runCase(
            _ label: String,
            animation: Animation?,
            register: (inout Transaction) -> Void
        ) {
            var transaction = Transaction(animation: animation)
            register(&transaction)
            withTransaction(transaction) {
                events.append("body \(label)")
            }
            events.append("returned \(label)")
        }

        func registerLogicalSame(_ transaction: inout Transaction, label: String) {
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical1")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical2")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical3")
            }
        }

        func registerRemovedSame(_ transaction: inout Transaction, label: String) {
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed1")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed2")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed3")
            }
        }

        func registerLogicalFirstMixed(_ transaction: inout Transaction, label: String) {
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical1")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed1")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical2")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed2")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical3")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed3")
            }
        }

        func registerRemovedFirstMixed(_ transaction: inout Transaction, label: String) {
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed1")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical1")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed2")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical2")
            }
            transaction.addAnimationCompletion(criteria: .removed) {
                events.append("\(label) removed3")
            }
            transaction.addAnimationCompletion(criteria: .logicallyComplete) {
                events.append("\(label) logical3")
            }
        }

        runCase("nilLogicalSame", animation: nil) {
            registerLogicalSame(&$0, label: "nilLogicalSame")
        }
        runCase("nilRemovedSame", animation: nil) {
            registerRemovedSame(&$0, label: "nilRemovedSame")
        }
        runCase("nilLogicalFirstMixed", animation: nil) {
            registerLogicalFirstMixed(&$0, label: "nilLogicalFirstMixed")
        }
        runCase("nilRemovedFirstMixed", animation: nil) {
            registerRemovedFirstMixed(&$0, label: "nilRemovedFirstMixed")
        }
        runCase("explicitLogicalFirstMixed", animation: .linear(duration: 0.40)) {
            registerLogicalFirstMixed(&$0, label: "explicitLogicalFirstMixed")
        }

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(
            events,
            [
                "body nilLogicalSame",
                "returned nilLogicalSame",
                "nilLogicalSame logical1",
                "nilLogicalSame logical2",
                "nilLogicalSame logical3",
                "body nilRemovedSame",
                "returned nilRemovedSame",
                "nilRemovedSame removed1",
                "nilRemovedSame removed2",
                "nilRemovedSame removed3",
                "body nilLogicalFirstMixed",
                "returned nilLogicalFirstMixed",
                "nilLogicalFirstMixed logical3",
                "nilLogicalFirstMixed logical2",
                "nilLogicalFirstMixed logical1",
                "nilLogicalFirstMixed removed1",
                "nilLogicalFirstMixed removed2",
                "nilLogicalFirstMixed removed3",
                "body nilRemovedFirstMixed",
                "returned nilRemovedFirstMixed",
                "nilRemovedFirstMixed removed3",
                "nilRemovedFirstMixed removed2",
                "nilRemovedFirstMixed removed1",
                "nilRemovedFirstMixed logical1",
                "nilRemovedFirstMixed logical2",
                "nilRemovedFirstMixed logical3",
                "body explicitLogicalFirstMixed",
                "returned explicitLogicalFirstMixed",
                "explicitLogicalFirstMixed logical3",
                "explicitLogicalFirstMixed logical2",
                "explicitLogicalFirstMixed logical1",
                "explicitLogicalFirstMixed removed1",
                "explicitLogicalFirstMixed removed2",
                "explicitLogicalFirstMixed removed3",
            ]
        )
    }

    func testThrowingNoTokenCompletionsPreservePublicTimingSplit() {
        enum ProbeError: Error {
            case expected
        }

        var events: [String] = []

        func index(of event: String) -> Int {
            guard let index = events.firstIndex(of: event) else {
                XCTFail("Missing event \(event): \(events)")
                return -1
            }
            return index
        }

        func XCTAssertOrder(
            _ orderedEvents: [String],
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let indexes = orderedEvents.map(index(of:))
            guard indexes.allSatisfy({ $0 >= 0 }) else {
                return
            }
            for pair in zip(indexes, indexes.dropFirst()) {
                XCTAssertLessThan(pair.0, pair.1, file: file, line: line)
            }
        }

        do {
            try withAnimation(
                .linear(duration: 0.20),
                completionCriteria: .logicallyComplete
            ) {
                events.append("withAnimation throw body")
                throw ProbeError.expected
            } completion: {
                events.append("withAnimation throw completion")
            }
            XCTFail("throwing withAnimation returned normally")
        } catch ProbeError.expected {
            events.append("withAnimation throw catch")
        } catch {
            XCTFail("unexpected withAnimation error: \(error)")
        }

        withAnimation(
            .linear(duration: 0.20),
            completionCriteria: .logicallyComplete
        ) {
            events.append("withAnimation normal body")
        } completion: {
            events.append("withAnimation normal completion")
        }
        events.append("withAnimation normal returned")

        var throwingTransaction = Transaction(animation: .linear(duration: 0.20))
        throwingTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("withTransaction throw completion")
        }
        do {
            try withTransaction(throwingTransaction) {
                events.append("withTransaction throw body")
                throw ProbeError.expected
            }
            XCTFail("throwing withTransaction returned normally")
        } catch ProbeError.expected {
            events.append("withTransaction throw catch")
        } catch {
            XCTFail("unexpected withTransaction error: \(error)")
        }

        var normalTransaction = Transaction(animation: .linear(duration: 0.20))
        normalTransaction.addAnimationCompletion(criteria: .logicallyComplete) {
            events.append("withTransaction normal completion")
        }
        withTransaction(normalTransaction) {
            events.append("withTransaction normal body")
        }
        events.append("withTransaction normal returned")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertOrder([
            "withAnimation throw body",
            "withAnimation throw completion",
            "withAnimation throw catch",
        ])
        XCTAssertOrder([
            "withAnimation normal body",
            "withAnimation normal completion",
            "withAnimation normal returned",
        ])
        XCTAssertOrder([
            "withTransaction throw body",
            "withTransaction throw catch",
            "withTransaction throw completion",
        ])
        XCTAssertOrder([
            "withTransaction normal body",
            "withTransaction normal returned",
            "withTransaction normal completion",
        ])
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

private final class PendingFinalizeProbeListener: AnimationListener, @unchecked Sendable {
    private let onFinalize: () -> [() -> Void]

    init(onFinalize: @escaping () -> [() -> Void]) {
        self.onFinalize = onFinalize
    }

    override func finalizeTransaction() -> [() -> Void] {
        onFinalize()
    }

    override func finalizeStandalonePendingTransaction() -> [() -> Void] {
        onFinalize()
    }
}
