import XCTest
@testable import VUI

final class LocationObserverNotificationTests: XCTestCase {
    override func tearDown() {
        GraphHost.flushGlobalTransactions()
        super.tearDown()
    }

    func testStoredLocationInvalidatesSignalWhenQueuedBeginUpdateApplies() {
        let host = GraphHost()
        var signal: AGWeakAttribute!
        var output: Attribute<Int>!
        var evaluations = 0

        host.data.withCurrent {
            let signalInput = host.data.graph.makeInput(value: ())
            signal = signalInput.asWeak().base
            output = host.data.graph.makeRule {
                evaluations += 1
                _ = signalInput.value
                return 1
            }

            XCTAssertEqual(output.value, 1)
            XCTAssertEqual(evaluations, 1)
        }

        let location = StoredLocation<Int>(
            initialValue: 1,
            host: host,
            signal: signal
        )

        location.setValue(2, transaction: Transaction())

        XCTAssertEqual(evaluations, 1)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(output.value, 1)
            XCTAssertEqual(evaluations, 2)
        }
    }

    func testQueuedBeginUpdatesCoalesceToLatestCommittedValueBeforeCallback() {
        let host = GraphHost()
        var location: StoredLocation<Int>!
        var committedValues: [Int] = []
        var visibleValuesDuringCommit: [Int] = []

        location = StoredLocation<Int>(
            initialValue: 1,
            host: host,
            signal: nil,
            onCommit: { value, _ in
                committedValues.append(value)
                visibleValuesDuringCommit.append(location.getValue())
            }
        )

        location.setValue(2, transaction: Transaction())
        location.setValue(3, transaction: Transaction())

        XCTAssertEqual(location.getValue(), 3)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(committedValues, [3])
        XCTAssertEqual(visibleValuesDuringCommit, [3])
        XCTAssertEqual(location.getValue(), 3)
    }

    func testQueuedBeginUpdatesWithDifferentTransactionsCommitSeparately() {
        let host = GraphHost()
        var location: StoredLocation<Int>!
        var committedValues: [Int] = []
        var visibleValuesDuringCommit: [Int] = []
        var first = Transaction()
        var second = Transaction()
        first[LocationQueueMergeFlagKey.self] = true
        second[LocationQueueMergeFlagKey.self] = false

        location = StoredLocation<Int>(
            initialValue: 1,
            host: host,
            signal: nil,
            onCommit: { value, _ in
                committedValues.append(value)
                visibleValuesDuringCommit.append(location.getValue())
            }
        )

        location.setValue(2, transaction: first)
        location.setValue(3, transaction: second)

        XCTAssertEqual(location.getValue(), 3)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(committedValues, [2, 3])
        XCTAssertEqual(visibleValuesDuringCommit, [2, 3])
        XCTAssertEqual(location.getValue(), 3)
    }

    func testObservableLocationInvalidatesAllLiveObserverSignalsAfterGlobalFlush() {
        let firstHost = GraphHost()
        let secondHost = GraphHost()
        var firstSignal: AGWeakAttribute!
        var secondSignal: AGWeakAttribute!
        var firstOutput: Attribute<Int>!
        var secondOutput: Attribute<Int>!
        var firstEvaluations = 0
        var secondEvaluations = 0

        firstHost.data.withCurrent {
            let signalInput = firstHost.data.graph.makeInput(value: ())
            firstSignal = signalInput.asWeak().base
            firstOutput = firstHost.data.graph.makeRule {
                firstEvaluations += 1
                _ = signalInput.value
                return 1
            }

            XCTAssertEqual(firstOutput.value, 1)
            XCTAssertEqual(firstEvaluations, 1)
        }

        secondHost.data.withCurrent {
            let signalInput = secondHost.data.graph.makeInput(value: ())
            secondSignal = signalInput.asWeak().base
            secondOutput = secondHost.data.graph.makeRule {
                secondEvaluations += 1
                _ = signalInput.value
                return 2
            }

            XCTAssertEqual(secondOutput.value, 2)
            XCTAssertEqual(secondEvaluations, 1)
        }

        let location = ObservableLocation(1, onValueUpdated: { _ in })
        location.addObserver(host: firstHost, signal: firstSignal)
        location.addObserver(host: secondHost, signal: secondSignal)

        location.setValue(2, transaction: Transaction())

        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertEqual(firstEvaluations, 1)
        XCTAssertEqual(secondEvaluations, 1)

        GraphHost.flushGlobalTransactions()

        firstHost.data.withCurrent {
            XCTAssertEqual(firstOutput.value, 1)
            XCTAssertEqual(firstEvaluations, 2)
        }
        secondHost.data.withCurrent {
            XCTAssertEqual(secondOutput.value, 2)
            XCTAssertEqual(secondEvaluations, 2)
        }
    }

    func testObservableLocationGlobalBeginUpdatesCoalesceToLatestCommittedValue() {
        let host = GraphHost()
        let signal = makeSignal(in: host)
        var committedValues: [Int] = []
        let location = ObservableLocation(1, onValueUpdated: { committedValues.append($0) })
        location.addObserver(host: host, signal: signal)

        location.setValue(2, transaction: Transaction())
        location.setValue(3, transaction: Transaction())

        XCTAssertEqual(location.getValue(), 3)
        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertTrue(committedValues.isEmpty)

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(committedValues, [3])
        XCTAssertEqual(location.getValue(), 3)
    }

    func testObservableLocationGlobalBeginUpdatesWithDifferentTransactionsCommitSeparately() {
        let host = GraphHost()
        let signal = makeSignal(in: host)
        var committedValues: [Int] = []
        var first = Transaction()
        var second = Transaction()
        first[LocationQueueMergeFlagKey.self] = true
        second[LocationQueueMergeFlagKey.self] = false
        let location = ObservableLocation(1, onValueUpdated: { committedValues.append($0) })
        location.addObserver(host: host, signal: signal)

        location.setValue(2, transaction: first)
        location.setValue(3, transaction: second)

        XCTAssertEqual(location.getValue(), 3)
        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertTrue(committedValues.isEmpty)

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(committedValues, [2, 3])
        XCTAssertEqual(location.getValue(), 3)
    }

    func testDifferentStoredLocationsDoNotCombineBeginUpdates() {
        let host = GraphHost()
        var firstCommittedValues: [Int] = []
        var secondCommittedValues: [Int] = []
        let first = StoredLocation<Int>(
            initialValue: 1,
            host: host,
            signal: nil,
            onCommit: { value, _ in firstCommittedValues.append(value) }
        )
        let second = StoredLocation<Int>(
            initialValue: 10,
            host: host,
            signal: nil,
            onCommit: { value, _ in secondCommittedValues.append(value) }
        )

        first.setValue(2, transaction: Transaction())
        second.setValue(20, transaction: Transaction())

        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(firstCommittedValues, [2])
        XCTAssertEqual(secondCommittedValues, [20])
    }

    func testObservableLocationDropsInvalidSignalObserversDuringNotification() {
        let staleHost = GraphHost()
        let liveHost = GraphHost()
        var staleSignal: AGWeakAttribute!
        var staleSubgraph: AGSubgraph!
        let liveSignal = makeSignal(in: liveHost)
        let location = ObservableLocation(1, onValueUpdated: { _ in })

        staleHost.data.withCurrent {
            staleSubgraph = AGSubgraph()
            AGSubgraph.withCurrent(staleSubgraph) {
                staleSignal = staleHost.data.graph.makeInput(value: ()).asWeak().base
            }
        }

        location.addObserver(host: staleHost, signal: staleSignal)
        location.addObserver(host: liveHost, signal: liveSignal)

        XCTAssertTrue(location.mutationHost === staleHost)

        staleHost.data.withCurrent {
            staleSubgraph.invalidate()
        }

        location.setValue(2, transaction: Transaction())
        GraphHost.flushGlobalTransactions()

        XCTAssertTrue(location.mutationHost === liveHost)
    }

    private func makeSignal(in host: GraphHost) -> AGWeakAttribute {
        var signal: AGWeakAttribute!
        host.data.withCurrent {
            signal = host.data.graph.makeInput(value: ()).asWeak().base
        }
        return signal
    }
}

private struct LocationQueueMergeFlagKey: TransactionKey {
    static let defaultValue = false
}
