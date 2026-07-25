import XCTest
@testable import VUI

final class LocationStorageTests: XCTestCase {
    override func tearDown() {
        GraphHost.flushGlobalTransactions()
        super.tearDown()
    }

    func testStoredLocationBaseUpdateMarksReadAndReturnsTrue() {
        let location = TestStoredLocation<Int>(initialValue: 5)

        XCTAssertFalse(location.wasRead)

        let update = location.update()

        XCTAssertEqual(update.0, 5)
        XCTAssertTrue(update.1)
        XCTAssertTrue(location.wasRead)
    }

    func testStoredLocationBaseRejectsWritesDuringGraphUpdate() {
        let location = TestStoredLocation<Int>(initialValue: 5)
        location.updating = true

        location.setValue(7, transaction: Transaction())

        XCTAssertEqual(location.getValue(), 5)
    }

    func testStoredLocationUsesHostGraphUpdateStateForWriteGate() {
        let host = GraphHost()
        let location = StoredLocation<Int>(
            initialValue: 5,
            host: host,
            signal: nil
        )
        var observedStaticUpdateState = false

        host.data.withCurrent {
            let output = host.data.graph.makeRule {
                observedStaticUpdateState = GraphHost.isUpdating
                location.setValue(7, transaction: Transaction())
                return 1
            }
            XCTAssertEqual(output.value, 1)
        }

        XCTAssertTrue(observedStaticUpdateState)
        XCTAssertEqual(location.getValue(), 5)
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testStoredLocationWithInvalidHostUpdatesCurrentValueWithoutQueuingCommit() {
        let host = GraphHost()
        var commits: [Int] = []
        let location = StoredLocation<Int>(
            initialValue: 1,
            host: host,
            signal: nil,
            onCommit: { value, _ in commits.append(value) }
        )
        host.invalidate()

        location.setValue(2, transaction: Transaction())

        XCTAssertEqual(location.getValue(), 2)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertFalse(host.hasPendingTransactions)
    }

    func testStoredLocationUpdateUsesSignalValidity() {
        let host = GraphHost()
        var signal: AGWeakAttribute!
        var signalSubgraph: AGSubgraph!

        host.data.withCurrent {
            signalSubgraph = AGSubgraph()
            AGSubgraph.withCurrent(signalSubgraph) {
                signal = host.data.graph.makeInput(value: ()).asWeak().base
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

    func testLocationBoxUpdateTracksCachedValueChanges() {
        var stored = 1
        let location = LocationBox(location: FunctionalLocation<Int>(
            get: { stored },
            set: { value, _ in stored = value },
            marksMutation: false
        ))

        var update = location.update()
        XCTAssertEqual(update.0, 1)
        XCTAssertFalse(update.1)

        stored = 3
        update = location.update()
        XCTAssertEqual(update.0, 3)
        XCTAssertTrue(update.1)

        update = location.update()
        XCTAssertEqual(update.0, 3)
        XCTAssertFalse(update.1)
    }

    func testObservationCenterStashesAccessAndRestoresOuterRecorder() {
        let center = ObservationCenter.current

        let outer = center._withObservationStashed {
            center.accessOccurred()

            let inner = center._withObservationStashed {
                7
            }
            XCTAssertEqual(inner.value, 7)
            XCTAssertFalse(inner.accessOccurred)

            center.accessOccurred()
            return 11
        }

        XCTAssertEqual(outer.value, 11)
        XCTAssertTrue(outer.accessOccurred)
    }

    func testObservationCenterReportsOnlyExplicitAccessDuringLocationUpdate() {
        var stored = 1
        let plain = LocationBox(location: FunctionalLocation<Int>(
            get: { stored },
            set: { value, _ in stored = value },
            marksMutation: false
        ))
        let tracked = LocationBox(location: ObservationAccessLocation<Int>(
            get: { stored },
            set: { value, _ in stored = value }
        ))

        let plainUpdate = ObservationCenter.current._withObservationStashed {
            plain.update()
        }
        XCTAssertEqual(plainUpdate.value.0, 1)
        XCTAssertFalse(plainUpdate.value.1)
        XCTAssertFalse(plainUpdate.accessOccurred)

        stored = 2
        let trackedUpdate = ObservationCenter.current._withObservationStashed {
            tracked.update()
        }
        XCTAssertEqual(trackedUpdate.value.0, 2)
        XCTAssertTrue(trackedUpdate.value.1)
        XCTAssertTrue(trackedUpdate.accessOccurred)
    }

    func testStoredLocationReadHookPreservesAttributeDependency() {
        let graph = _AGGraph()
        var derived: Attribute<Int>!
        var location: TestStoredLocation<Int>!

        _AGGraph.withCurrent(graph) {
            let sourceAttribute = graph.makeInput(value: 1)
            let inbox = graph.inbox
            location = TestStoredLocation<Int>(
                initialValue: 1,
                readValue: {
                    if _AGGraph.current === graph {
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

        _AGGraph.withCurrent(graph) {
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

    func testStoredLocationWriteScopesCurrentTransactionAroundCommit() {
        var commits: [LocationCommitSnapshot] = []
        let location = TestStoredLocation<Int>(
            initialValue: 1,
            onCommit: { value, transaction in
                commits.append(.init(
                    value: value,
                    marker: transaction[LocationProjectionTransactionKey.self],
                    tracksVelocity: transaction.tracksVelocity,
                    ambientMarker: transaction[LocationProjectionAmbientKey.self],
                    currentMarker: Transaction.current[LocationProjectionTransactionKey.self],
                    currentTracksVelocity: Transaction.current.tracksVelocity,
                    currentAmbientMarker: Transaction.current[LocationProjectionAmbientKey.self]
                ))
            }
        )
        var ambient = Transaction()
        ambient[LocationProjectionAmbientKey.self] = 7
        ambient.disablesAnimations = true
        var local = Transaction()
        local[LocationProjectionTransactionKey.self] = 66
        local.tracksVelocity = true

        withTransaction(ambient) {
            location.setValue(5, transaction: local)
        }

        XCTAssertEqual(location.getValue(), 5)
        XCTAssertEqual(commits, [
            .init(
                value: 5,
                marker: 66,
                tracksVelocity: true,
                ambientMarker: 7,
                currentMarker: 66,
                currentTracksVelocity: true,
                currentAmbientMarker: 7
            )
        ])
        XCTAssertEqual(Transaction.current[LocationProjectionAmbientKey.self], 0)
        XCTAssertFalse(Transaction.current.tracksVelocity)
    }

    func testProjectedLocationWriteForwardsTransactionToBaseLocation() {
        var commits: [LocationProjectionCommit] = []
        let location = TestStoredLocation<LocationProjectionPair>(
            initialValue: LocationProjectionPair(first: 1, second: 2),
            onCommit: { value, transaction in
                commits.append(.init(
                    value: value,
                    marker: transaction[LocationProjectionTransactionKey.self],
                    tracksVelocity: transaction.tracksVelocity,
                    currentMarker: Transaction.current[LocationProjectionTransactionKey.self],
                    currentTracksVelocity: Transaction.current.tracksVelocity,
                    currentAmbientMarker: Transaction.current[LocationProjectionAmbientKey.self]
                ))
            }
        )
        let projected = location.projecting(LocationProjectionFirst())
        var transaction = Transaction()
        transaction[LocationProjectionTransactionKey.self] = 44
        transaction.tracksVelocity = true

        projected.setValue(9, transaction: transaction)

        XCTAssertEqual(location.getValue(), LocationProjectionPair(first: 9, second: 2))
        XCTAssertEqual(commits, [
            .init(
                value: LocationProjectionPair(first: 9, second: 2),
                marker: 44,
                tracksVelocity: true,
                currentMarker: 44,
                currentTracksVelocity: true,
                currentAmbientMarker: 0
            )
        ])
        XCTAssertEqual(Transaction.current[LocationProjectionTransactionKey.self], 0)
        XCTAssertFalse(Transaction.current.tracksVelocity)
    }

    func testProjectedLocationWriteScopesCurrentTransactionAroundBaseLocation() {
        var commits: [LocationProjectionCommit] = []
        let location = TestStoredLocation<LocationProjectionPair>(
            initialValue: LocationProjectionPair(first: 1, second: 2),
            onCommit: { value, transaction in
                commits.append(.init(
                    value: value,
                    marker: transaction[LocationProjectionTransactionKey.self],
                    tracksVelocity: transaction.tracksVelocity,
                    currentMarker: Transaction.current[LocationProjectionTransactionKey.self],
                    currentTracksVelocity: Transaction.current.tracksVelocity,
                    currentAmbientMarker: Transaction.current[LocationProjectionAmbientKey.self]
                ))
            }
        )
        let projected = location.projecting(LocationProjectionFirst())
        var ambient = Transaction()
        ambient[LocationProjectionAmbientKey.self] = 7
        ambient.disablesAnimations = true
        var local = Transaction()
        local[LocationProjectionTransactionKey.self] = 55
        local.tracksVelocity = true

        withTransaction(ambient) {
            projected.setValue(10, transaction: local)
        }

        XCTAssertEqual(location.getValue(), LocationProjectionPair(first: 10, second: 2))
        XCTAssertEqual(commits, [
            .init(
                value: LocationProjectionPair(first: 10, second: 2),
                marker: 55,
                tracksVelocity: true,
                currentMarker: 55,
                currentTracksVelocity: true,
                currentAmbientMarker: 7
            )
        ])
        XCTAssertEqual(Transaction.current[LocationProjectionAmbientKey.self], 0)
    }

    private func makeSignal(in host: GraphHost) -> AGWeakAttribute {
        var signal: AGWeakAttribute!
        host.data.withCurrent {
            signal = host.data.graph.makeInput(value: ()).asWeak().base
        }
        return signal
    }
}

private struct LocationProjectionPair: Equatable {
    var first: Int
    var second: Int
}

private struct LocationProjectionFirst: Projection {
    func get(base: LocationProjectionPair) -> Int {
        base.first
    }

    func set(base: inout LocationProjectionPair, newValue: Int) {
        base.first = newValue
    }
}

private struct ObservationAccessLocation<Value>: _Location {
    var get: () -> Value
    var set: (Value, Transaction) -> Void

    func getValue() -> Value {
        ObservationCenter.current.accessOccurred()
        return get()
    }

    func setValue(_ value: Value, transaction: Transaction) {
        set(value, transaction)
    }
}

private struct LocationProjectionCommit: Equatable {
    var value: LocationProjectionPair
    var marker: Int
    var tracksVelocity: Bool
    var currentMarker: Int
    var currentTracksVelocity: Bool
    var currentAmbientMarker: Int
}

private struct LocationCommitSnapshot: Equatable {
    var value: Int
    var marker: Int
    var tracksVelocity: Bool
    var ambientMarker: Int
    var currentMarker: Int
    var currentTracksVelocity: Bool
    var currentAmbientMarker: Int
}

private struct LocationProjectionTransactionKey: TransactionKey {
    static let defaultValue = 0
}

private struct LocationProjectionAmbientKey: TransactionKey {
    static let defaultValue = 0
}
