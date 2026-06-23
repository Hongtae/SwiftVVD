import XCTest
@testable import VUI

final class LocationStorageTests: XCTestCase {
    override func tearDown() {
        GraphHost.flushGlobalTransactions()
        super.tearDown()
    }

    func testStoredLocationBaseUpdateMarksReadAndReturnsTrue() {
        let location = StoredLocationBase<Int>(initialValue: 5)

        XCTAssertFalse(location.wasRead)

        let update = location.update()

        XCTAssertEqual(update.0, 5)
        XCTAssertTrue(update.1)
        XCTAssertTrue(location.wasRead)
    }

    func testStoredLocationUpdateUsesSignalValidity() {
        let host = GraphHost()
        var signal: AGWeakAttribute!
        var signalSubgraph: AGSubgraph!

        host.data.withCurrent {
            signalSubgraph = AGSubgraph()
            AGSubgraph.$current.withValue(signalSubgraph) {
                signal = host.data.graph.makeInput(value: ()).asWeak().raw
            }
        }

        let location = StoredLocation<Int>(
            initialValue: 2,
            host: host,
            signal: signal
        )

        var update = location.update()
        XCTAssertEqual(update.0, 2)
        XCTAssertTrue(update.1)
        XCTAssertTrue(location.wasRead)

        host.data.withCurrent {
            signalSubgraph.invalidate()
        }

        update = location.update()
        XCTAssertEqual(update.0, 2)
        XCTAssertFalse(update.1)
    }

    func testStoredLocationReadHookPreservesAttributeDependency() {
        let graph = AttributeGraph()
        var derived: Attribute<Int>!
        var location: StoredLocation<Int>!

        AttributeGraph.$current.withValue(graph) {
            let sourceAttribute = graph.makeInput(value: 1)
            let inbox = graph.inbox
            location = StoredLocation<Int>(
                initialValue: 1,
                readValue: {
                    if AttributeGraph.current === graph {
                        return sourceAttribute.value
                    }
                    return 1
                },
                onCommit: { value, transaction in
                    let valueBox = UnsafeBox(value)
                    let transactionBox = UnsafeBox(transaction)
                    inbox.enqueue {
                        sourceAttribute.setValue(valueBox.value, transaction: transactionBox.value)
                    }
                }
            )
            derived = graph.makeRule {
                location.getValue() + 10
            }

            XCTAssertEqual(derived.value, 11)
            XCTAssertTrue(location.wasRead)
        }

        location.setValue(7, transaction: Transaction())

        AttributeGraph.$current.withValue(graph) {
            graph.inbox.drain()
            XCTAssertEqual(derived.value, 17)
        }
    }

    func testStoredLocationWithHostQueuesBeginUpdateUntilHostFlush() {
        let host = GraphHost()
        var commits: [Int] = []
        let location = StoredLocation<Int>(
            initialValue: 1,
            host: host,
            signal: nil,
            onCommit: { value, _ in
                commits.append(value)
            }
        )

        location.setValue(3, transaction: Transaction())

        XCTAssertEqual(location.getValue(), 3)
        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertTrue(commits.isEmpty)

        host.flushTransactions()

        XCTAssertEqual(commits, [3])
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testObservableLocationMutationHostUsesFirstLiveObserverHost() {
        let first = GraphHost()
        let second = GraphHost()
        let firstSignal = makeSignal(in: first)
        let secondSignal = makeSignal(in: second)
        let location = ObservableLocation(0, onValueUpdated: { _ in })

        XCTAssertNil(location.mutationHost)

        location.addObserver(host: first, signal: firstSignal)
        location.addObserver(host: second, signal: secondSignal)

        XCTAssertTrue(location.mutationHost === first)

        location.removeObserver(signal: firstSignal)

        XCTAssertTrue(location.mutationHost === second)
    }

    func testObservableLocationSetUpdatesValueAndNotifiesTrackers() {
        let location = ObservableLocation(1, onValueUpdated: { _ in })
        let key = AnyLocationBase.TrackerKey(id: ObjectIdentifier(self), offset: 0)
        var updates: [Int] = []
        var trackerCount = 0
        location.addTracker(key: key) {
            trackerCount += 1
            updates.append(location.getValue())
        }

        location.setValue(2, transaction: Transaction())
        location.setValue(2, transaction: Transaction())
        location.setValue(4, transaction: Transaction())

        XCTAssertEqual(trackerCount, 2)
        XCTAssertEqual(updates, [2, 4])
    }

    private func makeSignal(in host: GraphHost) -> AGWeakAttribute {
        var signal: AGWeakAttribute!
        host.data.withCurrent {
            signal = host.data.graph.makeInput(value: ()).asWeak().raw
        }
        return signal
    }
}
