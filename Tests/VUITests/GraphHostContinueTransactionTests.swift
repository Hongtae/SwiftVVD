import XCTest
@testable import VUI

final class GraphHostContinueTransactionTests: XCTestCase {
    func testContinueTransactionQueuesOnUpdatingHostUntilFinish() {
        let host = GraphHost()
        var events: [String] = []

        host.runTransaction {
            host.continueTransaction(
                ContinueRecordingGraphMutation {
                    XCTAssertTrue(host.isUpdating)
                    events.append("mutation")
                }
            )

            XCTAssertTrue(events.isEmpty)
            XCTAssertTrue(host.hasPendingGraphMutations)
            XCTAssertTrue(host.needsTransaction)
        }

        XCTAssertEqual(events, ["mutation"])
        XCTAssertFalse(host.hasPendingGraphMutations)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.isUpdating)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionCombinesWithLastQueuedMutation() {
        let host = GraphHost()
        let storage = ContinueCombineStorage()

        host.runTransaction {
            host.continueTransaction(CombiningContinueMutation(name: "first", storage: storage))
            host.continueTransaction(CombiningContinueMutation(name: "second", storage: storage))

            XCTAssertEqual(storage.events, ["combine:first+second"])
            XCTAssertTrue(host.hasPendingGraphMutations)
        }

        XCTAssertEqual(storage.events, ["combine:first+second", "apply:first+second"])
        XCTAssertFalse(host.hasPendingGraphMutations)
        XCTAssertFalse(host.needsTransaction)
    }

    func testContinueTransactionWalksToUpdatingParentHost() {
        let parent = GraphHost()
        let child = ChildGraphHost(parent: parent)
        var events: [String] = []

        parent.runTransaction {
            child.continueTransaction(
                ContinueRecordingGraphMutation {
                    XCTAssertTrue(parent.isUpdating)
                    XCTAssertFalse(child.isUpdating)
                    events.append("parent")
                }
            )

            XCTAssertTrue(parent.hasPendingGraphMutations)
            XCTAssertFalse(child.hasPendingGraphMutations)
        }

        XCTAssertEqual(events, ["parent"])
        XCTAssertFalse(parent.hasPendingGraphMutations)
        XCTAssertFalse(parent.needsTransaction)
    }

    func testContinueTransactionWithoutUpdatingHostUsesUpdateActionFallback() {
        let host = GraphHost()
        var events: [String] = []

        host.continueTransaction(
            ContinueRecordingGraphMutation {
                events.append(Update.isActive ? "active" : "inactive")
            }
        )

        XCTAssertEqual(events, [])
        XCTAssertFalse(host.hasPendingGraphMutations)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertEqual(host.data.transactionSeed, 0)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(events, ["active"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionWithoutUpdatingHostFallbackQueuesExpectedReason() {
        let host = GraphHost()
        var events: [String] = []

        Update.begin()
        defer {
            if Update.isActive {
                Update.end()
            }
        }

        host.continueTransaction(
            ContinueRecordingGraphMutation {
                events.append(Update.isActive ? "active" : "inactive")
            }
        )

        XCTAssertEqual(Update.queuedActionReasons, [0x11])
        XCTAssertEqual(events, [])

        Update.end()

        XCTAssertEqual(events, [])
        XCTAssertFalse(host.hasPendingGraphMutations)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertEqual(host.data.transactionSeed, 0)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        XCTAssertEqual(events, ["active"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionWithoutUpdatingHostFallbackAppliesInHostGraphContext() {
        let host = GraphHost()
        var attribute: Attribute<Int>!
        var weakAttribute: WeakAttribute<Int>!
        host.data.withCurrent {
            attribute = host.data.graph.makeInput(value: 1)
            weakAttribute = attribute.asWeak()
        }

        host.continueTransaction(setting: weakAttribute, to: 2)

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 1)
        }
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 2)
        }
        XCTAssertFalse(host.hasPendingGraphMutations)
        XCTAssertFalse(host.needsTransaction)
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionWithoutUpdatingHostFallbackBatchesThroughAsyncTransaction() {
        let host = GraphHost()
        var events: [String] = []

        host.continueTransaction(
            ContinueRecordingGraphMutation {
                XCTAssertTrue(host.isUpdating)
                events.append("first")
            }
        )
        host.continueTransaction(
            ContinueRecordingGraphMutation {
                XCTAssertTrue(host.isUpdating)
                events.append("second")
            }
        )

        XCTAssertTrue(host.hasPendingTransactions)
        XCTAssertEqual(events, [])

        host.flushTransactions()

        XCTAssertEqual(events, ["first", "second"])
        XCTAssertFalse(host.hasPendingTransactions)
        XCTAssertEqual(host.data.transactionSeed, 1)
    }

    func testContinueTransactionSettingWeakAttributeAppliesWhenTransactionFinishes() {
        let host = GraphHost()
        var attribute: Attribute<Int>!
        var weakAttribute: WeakAttribute<Int>!
        host.data.withCurrent {
            attribute = host.data.graph.makeInput(value: 1)
            weakAttribute = attribute.asWeak()
        }

        host.runTransaction {
            host.continueTransaction(setting: weakAttribute, to: 2)
            XCTAssertEqual(attribute.value, 1)
            XCTAssertTrue(host.needsTransaction)
        }

        host.data.withCurrent {
            XCTAssertEqual(attribute.value, 2)
        }
    }

    func testContinueTransactionInvalidatingWeakAttributeMarksDependentsDirtyAtFinish() {
        let host = GraphHost()
        var input: Attribute<Int>!
        var output: Attribute<Int>!
        var weakInput: AGWeakAttribute!
        var evaluations = 0

        host.data.withCurrent {
            input = host.data.graph.makeInput(value: 3)
            output = host.data.graph.makeRule {
                evaluations += 1
                return input.value * 2
            }
            weakInput = input.asWeak().raw

            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 1)
        }

        host.runTransaction {
            host.continueTransaction(invalidating: weakInput)
            XCTAssertEqual(evaluations, 1)
        }

        host.data.withCurrent {
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(evaluations, 2)
        }
    }
}

private final class ChildGraphHost: GraphHost {
    weak var parent: GraphHost?

    init(parent: GraphHost) {
        self.parent = parent
        super.init()
    }

    override var parentHost: GraphHost? {
        parent
    }
}

private struct ContinueRecordingGraphMutation: GraphMutation {
    var body: () -> Void

    func apply() {
        body()
    }
}

private final class ContinueCombineStorage {
    var events: [String] = []
}

private struct CombiningContinueMutation: GraphMutation {
    var name: String
    var storage: ContinueCombineStorage

    func apply() {
        storage.events.append("apply:\(name)")
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? CombiningContinueMutation else {
            return false
        }
        storage.events.append("combine:\(name)+\(mutation.name)")
        name += "+\(mutation.name)"
        return true
    }
}
