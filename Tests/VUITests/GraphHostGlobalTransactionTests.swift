import XCTest
@testable import VUI

final class GraphHostGlobalTransactionTests: XCTestCase {
    override func tearDown() {
        GraphHost.flushGlobalTransactions()
        Semantics.overrides = Semantics.Overrides()
        super.tearDown()
    }

    func testGlobalTransactionQueuesUntilStaticFlushRunsProviderHost() {
        let host = GraphHost()
        let provider = GlobalTransactionHostProvider(host: host)
        var events: [String] = []

        GraphHost.globalTransaction(
            Transaction(),
            id: Transaction.ID(value: 100),
            mutation: GlobalRecordingGraphMutation {
                XCTAssertTrue(host.isUpdating)
                events.append("run")
            },
            hostProvider: provider
        )

        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 0)
        XCTAssertTrue(events.isEmpty)

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(events, ["run"])
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
        XCTAssertFalse(host.isUpdating)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testGlobalTransactionsWithSameProviderIDAndTransactionAppend() {
        let host = GraphHost()
        let provider = GlobalTransactionHostProvider(host: host)
        let id = Transaction.ID(value: 101)
        let transaction = Transaction()
        var events: [String] = []

        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: GlobalRecordingGraphMutation { events.append("first") },
            hostProvider: provider
        )
        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: GlobalRecordingGraphMutation { events.append("second") },
            hostProvider: provider
        )

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testGlobalTransactionsWithSameProviderIDAndTransactionCombineLastMutation() {
        let host = GraphHost()
        let provider = GlobalTransactionHostProvider(host: host)
        let id = Transaction.ID(value: 110)
        let transaction = Transaction()
        let storage = GlobalCombineStorage()

        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: CombiningGlobalMutation(name: "first", storage: storage),
            hostProvider: provider
        )
        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: CombiningGlobalMutation(name: "second", storage: storage),
            hostProvider: provider
        )

        XCTAssertEqual(storage.events, ["combine:first+second"])
        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertEqual(host.data.transactionSeed, 0)

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(storage.events, ["combine:first+second", "apply:first+second"])
        XCTAssertEqual(host.data.transactionSeed, 1)
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    func testGlobalTransactionsWithDifferentProviderObjectsRemainSeparate() {
        let host = GraphHost()
        let firstProvider = GlobalTransactionHostProvider(host: host)
        let secondProvider = GlobalTransactionHostProvider(host: host)
        let id = Transaction.ID(value: 102)
        let transaction = Transaction()
        var events: [String] = []

        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: GlobalRecordingGraphMutation { events.append("first") },
            hostProvider: firstProvider
        )
        GraphHost.globalTransaction(
            transaction,
            id: id,
            mutation: GlobalRecordingGraphMutation { events.append("second") },
            hostProvider: secondProvider
        )

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testGlobalTransactionsWithDifferentPropertyListsRemainSeparate() {
        let host = GraphHost()
        let provider = GlobalTransactionHostProvider(host: host)
        let id = Transaction.ID(value: 103)
        var first = Transaction()
        var second = Transaction()
        first[GlobalQueueMergeFlagKey.self] = true
        second[GlobalQueueMergeFlagKey.self] = false
        var events: [String] = []

        GraphHost.globalTransaction(
            first,
            id: id,
            mutation: GlobalRecordingGraphMutation { events.append("first") },
            hostProvider: provider
        )
        GraphHost.globalTransaction(
            second,
            id: id,
            mutation: GlobalRecordingGraphMutation { events.append("second") },
            hostProvider: provider
        )

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertEqual(host.data.transactionSeed, 2)
    }

    func testObservableLocationCommitUsesGlobalTransactionHostProvider() {
        let host = GraphHost()
        let signal = makeSignal(in: host)
        var updates: [Int] = []
        let location = ObservableLocation(1, onValueUpdated: { updates.append($0) })
        location.addObserver(host: host, signal: signal)

        location.setValue(2, transaction: Transaction())

        XCTAssertEqual(location.getValue(), 2)
        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertTrue(updates.isEmpty)
        XCTAssertEqual(host.data.transactionSeed, 0)

        GraphHost.flushGlobalTransactions()

        XCTAssertEqual(updates, [2])
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testNilHostGlobalTransactionFallbackUsesFlushThreadTransaction() {
        let provider = GlobalTransactionHostProvider(host: nil)
        var child = Transaction()
        child.isContinuous = true
        var observed: [(Bool, Bool, Bool)] = []

        GraphHost.globalTransaction(
            child,
            id: Transaction.ID(value: 104),
            mutation: GlobalRecordingGraphMutation {
                let current = Transaction.current
                observed.append((current.disablesAnimations, current.isContinuous, current[GlobalQueueMergeFlagKey.self]))
            },
            hostProvider: provider
        )

        var parent = Transaction()
        parent.disablesAnimations = true
        parent[GlobalQueueMergeFlagKey.self] = true
        withTransaction(parent) {
            GraphHost.flushGlobalTransactions()
            XCTAssertTrue(Transaction.current.disablesAnimations)
        }

        XCTAssertEqual(observed.map(\.0), [true])
        XCTAssertEqual(observed.map(\.1), [true])
        XCTAssertEqual(observed.map(\.2), [true])
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    func testNilHostGlobalTransactionExplicitChildValuesOverrideFlushThreadTransaction() {
        let provider = GlobalTransactionHostProvider(host: nil)
        var child = Transaction(animation: nil)
        child.disablesAnimations = false
        child[GlobalQueueMergeFlagKey.self] = false
        var observed: [(Animation?, Bool, Bool)] = []

        GraphHost.globalTransaction(
            child,
            id: Transaction.ID(value: 105),
            mutation: GlobalRecordingGraphMutation {
                let current = Transaction.current
                observed.append((current.animation, current.disablesAnimations, current[GlobalQueueMergeFlagKey.self]))
            },
            hostProvider: provider
        )

        var parent = Transaction(animation: .linear(duration: 1))
        parent.disablesAnimations = true
        parent[GlobalQueueMergeFlagKey.self] = true
        withTransaction(parent) {
            GraphHost.flushGlobalTransactions()
            XCTAssertNotNil(Transaction.current.animation)
            XCTAssertTrue(Transaction.current.disablesAnimations)
        }

        XCTAssertEqual(observed.count, 1)
        XCTAssertNil(observed[0].0)
        XCTAssertFalse(observed[0].1)
        XCTAssertFalse(observed[0].2)
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    func testNilHostGlobalTransactionFallbackRestoresFlushThreadTransaction() {
        let provider = GlobalTransactionHostProvider(host: nil)
        var child = Transaction()
        child.isContinuous = true
        var observedDuringMutation: [(Bool, Bool)] = []
        var observedAfterFlushInsideParent: (Bool, Bool)?

        GraphHost.globalTransaction(
            child,
            id: Transaction.ID(value: 106),
            mutation: GlobalRecordingGraphMutation {
                let current = Transaction.current
                observedDuringMutation.append((current.disablesAnimations, current.isContinuous))
            },
            hostProvider: provider
        )

        var parent = Transaction()
        parent.disablesAnimations = true
        withTransaction(parent) {
            GraphHost.flushGlobalTransactions()
            let current = Transaction.current
            observedAfterFlushInsideParent = (current.disablesAnimations, current.isContinuous)
        }

        XCTAssertEqual(observedDuringMutation.count, 1)
        XCTAssertEqual(observedDuringMutation[0].0, true)
        XCTAssertEqual(observedDuringMutation[0].1, true)
        XCTAssertEqual(observedAfterFlushInsideParent?.0, true)
        XCTAssertEqual(observedAfterFlushInsideParent?.1, false)
        XCTAssertFalse(Transaction.current.disablesAnimations)
        XCTAssertFalse(Transaction.current.isContinuous)
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    func testRuntimeOverridePreV5NilHostGlobalTransactionDirectInstallsChildWithoutFlushParentMerge() {
        Semantics.overrides = Semantics.Overrides(build: nil, runtime: .v4)
        let provider = GlobalTransactionHostProvider(host: nil)
        var child = Transaction()
        child.isContinuous = true
        var observedDuringMutation: [(Bool, Bool, Bool)] = []
        var observedAfterFlushInsideParent: (Bool, Bool)?

        GraphHost.globalTransaction(
            child,
            id: Transaction.ID(value: 109),
            mutation: GlobalRecordingGraphMutation {
                let current = Transaction.current
                observedDuringMutation.append((
                    current.disablesAnimations,
                    current.isContinuous,
                    current[GlobalQueueMergeFlagKey.self]
                ))
            },
            hostProvider: provider
        )

        var parent = Transaction()
        parent.disablesAnimations = true
        parent[GlobalQueueMergeFlagKey.self] = true
        withTransaction(parent) {
            GraphHost.flushGlobalTransactions()
            let current = Transaction.current
            observedAfterFlushInsideParent = (
                current.disablesAnimations,
                current[GlobalQueueMergeFlagKey.self]
            )
        }

        XCTAssertEqual(observedDuringMutation.count, 1)
        XCTAssertEqual(observedDuringMutation[0].0, false)
        XCTAssertEqual(observedDuringMutation[0].1, true)
        XCTAssertEqual(observedDuringMutation[0].2, false)
        XCTAssertEqual(observedAfterFlushInsideParent?.0, true)
        XCTAssertEqual(observedAfterFlushInsideParent?.1, true)
        XCTAssertFalse(Transaction.current.disablesAnimations)
        XCTAssertFalse(Transaction.current.isContinuous)
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    func testMainThreadGlobalTransactionFlushesFromRunLoopObserver() throws {
        guard Thread.isMainThread else {
            throw XCTSkip("Run-loop observer scheduling is only meaningful on the main test thread.")
        }

        let host = GraphHost()
        let provider = GlobalTransactionHostProvider(host: host)
        var events: [String] = []

        GraphHost.globalTransaction(
            Transaction(),
            id: Transaction.ID(value: 107),
            mutation: GlobalRecordingGraphMutation {
                XCTAssertTrue(Update.isActive)
                events.append("run")
            },
            hostProvider: provider
        )

        XCTAssertTrue(GraphHost.hasPendingGlobalTransactions)
        XCTAssertTrue(events.isEmpty)

        runMainLoopUntilGlobalTransactionsFlush()

        XCTAssertEqual(events, ["run"])
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    func testOffMainNilHostGlobalTransactionFlushesOnMainRunLoop() throws {
        guard Thread.isMainThread else {
            throw XCTSkip("Run-loop observer scheduling is only meaningful on the main test thread.")
        }

        let recorder = GlobalTransactionEventRecorder()
        let queued = expectation(description: "off-main global transaction queued")

        DispatchQueue.global().async {
            let provider = GlobalTransactionHostProvider(host: nil)
            var child = Transaction()
            child.isContinuous = true
            GraphHost.globalTransaction(
                child,
                id: Transaction.ID(value: 108),
                mutation: GlobalRecordingGraphMutation {
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertTrue(Transaction.current.isContinuous)
                    recorder.append("run")
                },
                hostProvider: provider
            )
            queued.fulfill()
        }

        wait(for: [queued], timeout: 1)
        runMainLoopUntilGlobalTransactionsFlush()

        XCTAssertEqual(recorder.events, ["run"])
        XCTAssertFalse(Transaction.current.isContinuous)
        XCTAssertFalse(GraphHost.hasPendingGlobalTransactions)
    }

    private func makeSignal(in host: GraphHost) -> AGWeakAttribute {
        var signal: AGWeakAttribute!
        host.data.withCurrent {
            signal = host.data.graph.makeInput(value: ()).asWeak().raw
        }
        return signal
    }

    private func runMainLoopUntilGlobalTransactionsFlush() {
        let deadline = Date().addingTimeInterval(1)
        while GraphHost.hasPendingGlobalTransactions && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }
}

private final class GlobalTransactionHostProvider: TransactionHostProvider {
    weak var host: GraphHost?

    init(host: GraphHost?) {
        self.host = host
    }

    var mutationHost: GraphHost? {
        host
    }
}

private struct GlobalRecordingGraphMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}

private final class GlobalCombineStorage {
    var events: [String] = []
}

private struct CombiningGlobalMutation: GraphMutation {
    var name: String
    var storage: GlobalCombineStorage

    func apply() {
        storage.events.append("apply:\(name)")
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? CombiningGlobalMutation else {
            return false
        }
        storage.events.append("combine:\(name)+\(mutation.name)")
        name += "+\(mutation.name)"
        return true
    }
}

private final class GlobalTransactionEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: String) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }
}

private struct GlobalQueueMergeFlagKey: TransactionKey {
    static let defaultValue = false
}
