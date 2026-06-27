import Foundation
import Synchronization
import XCTest
@testable import VUI

final class TransactionThreadStorageTests: XCTestCase {
    override func tearDown() {
        Transaction.ThreadStorage.currentBox = nil
        Transaction.ThreadStorage.resetCurrentIDForTesting()
        Semantics.overrides = Semantics.Overrides()
        super.tearDown()
    }

    func testTransactionStoresSinglePropertyListWord() {
        let labels = Mirror(reflecting: Transaction()).children.map(\.label)

        XCTAssertEqual(labels, ["plist"])
        XCTAssertEqual(MemoryLayout<Transaction>.size, MemoryLayout<UInt>.size)
        XCTAssertEqual(MemoryLayout<PropertyList>.size, MemoryLayout<UInt>.size)
    }

    func testTransactionIDFirstReadLazilyAllocatesStableThreadID() {
        Transaction.ThreadStorage.resetCurrentIDForTesting()

        let first = Transaction.id
        let second = Transaction.id

        XCTAssertNotEqual(first.value, 0)
        XCTAssertEqual(first, second)
    }

    func testTransactionCoreBarrierAdvancesThreadID() {
        Transaction.ThreadStorage.resetCurrentIDForTesting()

        let before = Transaction.id
        Transaction._core_barrier()
        let after = Transaction.id

        XCTAssertNotEqual(before.value, 0)
        XCTAssertNotEqual(after.value, 0)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after, Transaction.id)
    }

    func testTransactionIDIsThreadLocalAndGloballyAllocated() {
        Transaction.ThreadStorage.resetCurrentIDForTesting()

        let mainFirst = Transaction.id
        let mainSecond = Transaction.id
        XCTAssertNotEqual(mainFirst.value, 0)
        XCTAssertEqual(mainFirst, mainSecond)

        let semaphore = DispatchSemaphore(value: 0)
        let workerFirstID = Atomic<UInt32>(0)
        let workerSecondID = Atomic<UInt32>(0)
        let worker = Thread {
            Transaction.ThreadStorage.resetCurrentIDForTesting()
            let first = Transaction.id
            let second = Transaction.id
            Transaction.ThreadStorage.resetCurrentIDForTesting()
            workerFirstID.store(first.value, ordering: .relaxed)
            workerSecondID.store(second.value, ordering: .relaxed)
            semaphore.signal()
        }
        worker.start()

        XCTAssertEqual(semaphore.wait(timeout: .now() + 2), .success)
        let workerFirstIDValue = workerFirstID.load(ordering: .relaxed)
        let workerSecondIDValue = workerSecondID.load(ordering: .relaxed)
        XCTAssertNotEqual(workerFirstIDValue, 0)
        XCTAssertEqual(workerFirstIDValue, workerSecondIDValue)
        XCTAssertNotEqual(mainFirst.value, workerFirstIDValue)
        XCTAssertEqual(mainFirst, Transaction.id)
    }

    func testTransactionCurrentIsThreadLocal() {
        var mainTransaction = Transaction()
        mainTransaction[ThreadStorageParentOnlyKey.self] = 11

        let workerReady = DispatchSemaphore(value: 0)
        let releaseWorker = DispatchSemaphore(value: 0)
        let workerDone = DispatchSemaphore(value: 0)
        let workerInitialValue = Atomic<Int>(-1)
        let workerScopedValue = Atomic<Int>(-1)
        let workerWaitSucceeded = Atomic<Int>(0)
        let workerStillScopedValue = Atomic<Int>(-1)
        let workerStillParentValue = Atomic<Int>(-1)
        let workerAfterScopeValue = Atomic<Int>(-1)

        withTransaction(mainTransaction) {
            let worker = Thread {
                workerInitialValue.store(
                    Transaction.current[ThreadStorageParentOnlyKey.self],
                    ordering: .relaxed
                )

                var workerTransaction = Transaction()
                workerTransaction[ThreadStorageThrowingKey.self] = 22
                withTransaction(workerTransaction) {
                    workerScopedValue.store(
                        Transaction.current[ThreadStorageThrowingKey.self],
                        ordering: .relaxed
                    )
                    workerReady.signal()
                    let waitResult = releaseWorker.wait(timeout: .now() + 2)
                    workerWaitSucceeded.store(waitResult == .success ? 1 : -1, ordering: .relaxed)
                    workerStillScopedValue.store(
                        Transaction.current[ThreadStorageThrowingKey.self],
                        ordering: .relaxed
                    )
                    workerStillParentValue.store(
                        Transaction.current[ThreadStorageParentOnlyKey.self],
                        ordering: .relaxed
                    )
                }

                workerAfterScopeValue.store(
                    Transaction.current[ThreadStorageThrowingKey.self],
                    ordering: .relaxed
                )
                workerDone.signal()
            }
            worker.start()

            XCTAssertEqual(workerReady.wait(timeout: .now() + 2), .success)
            XCTAssertEqual(workerInitialValue.load(ordering: .relaxed), 0)
            XCTAssertEqual(workerScopedValue.load(ordering: .relaxed), 22)
            XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 11)
            XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 0)

            releaseWorker.signal()
            XCTAssertEqual(workerDone.wait(timeout: .now() + 2), .success)
            XCTAssertEqual(workerWaitSucceeded.load(ordering: .relaxed), 1)
            XCTAssertEqual(workerStillScopedValue.load(ordering: .relaxed), 22)
            XCTAssertEqual(workerStillParentValue.load(ordering: .relaxed), 0)
            XCTAssertEqual(workerAfterScopeValue.load(ordering: .relaxed), 0)
            XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 11)
        }

        XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 0)
    }

    func testEmptyStandaloneWithTransactionDoesNotInstallThreadStorageBox() {
        XCTAssertNil(Transaction.ThreadStorage.currentBox)

        withTransaction(Transaction()) {
            XCTAssertNil(Transaction.ThreadStorage.currentBox)
            XCTAssertTrue(Transaction.current.isEmpty)
        }

        XCTAssertNil(Transaction.ThreadStorage.currentBox)
    }

    func testEmptyNestedWithTransactionKeepsOuterThreadStorageBoxIdentity() throws {
        let outer = Transaction(animation: .linear(duration: 1))

        try withTransaction(outer) {
            let outerBox = try XCTUnwrap(Transaction.ThreadStorage.currentBox)

            withTransaction(Transaction()) {
                XCTAssertTrue(Transaction.ThreadStorage.currentBox === outerBox)
                XCTAssertNotNil(Transaction.current.animation)
            }

            XCTAssertTrue(Transaction.ThreadStorage.currentBox === outerBox)
        }

        XCTAssertNil(Transaction.ThreadStorage.currentBox)
    }

    func testEmptyNestedUnderCompletionParentKeepsSeparateCompletionState() throws {
        var outer = Transaction(animation: .linear(duration: 1))
        outer.addAnimationCompletion {}

        try withTransaction(outer) {
            let outerBox = try XCTUnwrap(Transaction.ThreadStorage.currentBox)

            try withTransaction(Transaction()) {
                let innerBox = try XCTUnwrap(Transaction.ThreadStorage.currentBox)
                XCTAssertFalse(innerBox === outerBox)
                XCTAssertNil(Transaction.current.animationCompletionObserver)
                XCTAssertNil(Transaction.current.animationListener)
                XCTAssertNil(Transaction.current.animationLogicalListener)
            }

            XCTAssertTrue(Transaction.ThreadStorage.currentBox === outerBox)
        }
    }

    func testThrowingStandaloneWithTransactionRestoresNilThreadStorageBeforeCatch() {
        var transaction = Transaction()
        transaction[ThreadStorageThrowingKey.self] = 9

        XCTAssertNil(Transaction.ThreadStorage.currentBox)

        do {
            try withTransaction(transaction) {
                XCTAssertNotNil(Transaction.ThreadStorage.currentBox)
                XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 9)
                throw ThreadStorageProbeError.expected
            }
            XCTFail("throwing withTransaction returned normally")
        } catch ThreadStorageProbeError.expected {
            XCTAssertNil(Transaction.ThreadStorage.currentBox)
            XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 0)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertNil(Transaction.ThreadStorage.currentBox)
    }

    func testThrowingNestedWithTransactionRestoresOuterThreadStorageBeforeCatch() throws {
        var parent = Transaction()
        parent[ThreadStorageThrowingKey.self] = 1
        var child = Transaction()
        child[ThreadStorageThrowingKey.self] = 2

        try withTransaction(parent) {
            let outerBox = try XCTUnwrap(Transaction.ThreadStorage.currentBox)

            do {
                try withTransaction(child) {
                    XCTAssertFalse(Transaction.ThreadStorage.currentBox === outerBox)
                    XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 2)
                    throw ThreadStorageProbeError.expected
                }
                XCTFail("throwing nested withTransaction returned normally")
            } catch ThreadStorageProbeError.expected {
                XCTAssertTrue(Transaction.ThreadStorage.currentBox === outerBox)
                XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 1)
            } catch {
                XCTFail("unexpected error: \(error)")
            }

            XCTAssertTrue(Transaction.ThreadStorage.currentBox === outerBox)
            XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 1)
        }

        XCTAssertNil(Transaction.ThreadStorage.currentBox)
    }

    func testCurrentSemanticsNestedTransactionMergesParentKeysWithChildPriority() {
        var parent = Transaction(animation: .linear(duration: 1))
        parent.disablesAnimations = true
        parent[ThreadStorageParentOnlyKey.self] = 1
        parent[ThreadStorageThrowingKey.self] = 10

        var child = Transaction()
        child.isContinuous = true
        child[ThreadStorageThrowingKey.self] = 2

        withTransaction(parent) {
            XCTAssertTrue(Transaction.current.disablesAnimations)
            XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 1)
            XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 10)

            withTransaction(child) {
                XCTAssertNotNil(Transaction.current.animation)
                XCTAssertTrue(Transaction.current.disablesAnimations)
                XCTAssertTrue(Transaction.current.isContinuous)
                XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 1)
                XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 2)
            }

            XCTAssertTrue(Transaction.current.disablesAnimations)
            XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 1)
            XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 10)
        }
    }

    func testCurrentSemanticsAlreadyInheritedChildKeepsChildPropertyStorage() {
        var parent = Transaction()
        parent[ThreadStorageParentOnlyKey.self] = 1

        var child = parent
        child[ThreadStorageThrowingKey.self] = 2

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertTrue(scoped.plist.isIdentical(to: child.plist))
        XCTAssertEqual(scoped[ThreadStorageParentOnlyKey.self], 1)
        XCTAssertEqual(scoped[ThreadStorageThrowingKey.self], 2)
    }

    func testCurrentSemanticsDisjointChildAllocatesMergedPropertyStorage() {
        var parent = Transaction()
        parent[ThreadStorageParentOnlyKey.self] = 1

        var child = Transaction()
        child[ThreadStorageThrowingKey.self] = 2

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertFalse(scoped.plist.isIdentical(to: child.plist))
        XCTAssertFalse(scoped.plist.isIdentical(to: parent.plist))
        XCTAssertTrue(scoped.plist.elements?.before === child.plist.elements)
        XCTAssertNil(scoped.plist.elements?.after)
        XCTAssertEqual(scoped[ThreadStorageParentOnlyKey.self], 1)
        XCTAssertEqual(scoped[ThreadStorageThrowingKey.self], 2)
    }

    func testCurrentSemanticsSameKeyChildAllocatesMergedPropertyStorage() {
        var parent = Transaction()
        parent[ThreadStorageParentOnlyKey.self] = 1

        var child = Transaction()
        child[ThreadStorageParentOnlyKey.self] = 2

        let scoped = child.scopedTransaction(inheritingFrom: parent)

        XCTAssertFalse(scoped.plist.isIdentical(to: child.plist))
        XCTAssertFalse(scoped.plist.isIdentical(to: parent.plist))
        XCTAssertTrue(scoped.plist.elements?.before === child.plist.elements)
        XCTAssertNil(scoped.plist.elements?.after)
        XCTAssertEqual(scoped[ThreadStorageParentOnlyKey.self], 2)
    }

    func testRuntimeOverridePreV5NestedTransactionDirectInstallsChildWithoutParentMerge() {
        Semantics.overrides = Semantics.Overrides(build: nil, runtime: .v4)
        var parent = Transaction(animation: .linear(duration: 1))
        parent.disablesAnimations = true
        parent[ThreadStorageParentOnlyKey.self] = 1
        var child = Transaction()
        child.isContinuous = true
        child[ThreadStorageThrowingKey.self] = 2

        withTransaction(parent) {
            XCTAssertTrue(Transaction.current.disablesAnimations)
            XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 1)

            withTransaction(child) {
                XCTAssertNil(Transaction.current.animation)
                XCTAssertFalse(Transaction.current.disablesAnimations)
                XCTAssertTrue(Transaction.current.isContinuous)
                XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 0)
                XCTAssertEqual(Transaction.current[ThreadStorageThrowingKey.self], 2)
            }

            XCTAssertTrue(Transaction.current.disablesAnimations)
            XCTAssertEqual(Transaction.current[ThreadStorageParentOnlyKey.self], 1)
        }
    }
}

private enum ThreadStorageProbeError: Error {
    case expected
}

private struct ThreadStorageThrowingKey: TransactionKey {
    static let defaultValue = 0
}

private struct ThreadStorageParentOnlyKey: TransactionKey {
    static let defaultValue = 0
}
