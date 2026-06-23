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
}
