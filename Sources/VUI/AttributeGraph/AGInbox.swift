//
//  File: AGInbox.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

/// A thread-safe queue of work items for a graph's serialized execution context.
///
/// Owned by `_AGGraph` — access via `_AGGraph.current!.inbox` or a
/// pre-captured reference. The owning graph drains it from an active graph
/// context at the appropriate update boundary.
///
/// Typical lifecycle:
/// ```
/// // @Observable onChange (arbitrary thread):
/// onChange: { [weak inbox] in
///     inbox?.enqueue {
///         _AGGraph.current?.markNeedsEvaluation(nodeID)
///     }
/// }
///
/// // Update boundary (serialized graph context):
/// _AGGraph.withCurrent(graph) {
///     graph.inbox.drain()
///     // … evaluate …
/// }
/// ```
final class AGInbox: @unchecked Sendable {
    private struct WorkItem: Sendable {
        var transaction: UnsafeBox<Transaction>?
        var work: @Sendable () -> Void
    }

    private let pendingWork: Mutex<[WorkItem]> = Mutex([])

    var hasPendingWork: Bool {
        pendingWork.withLock { !$0.isEmpty }
    }

    /// Returns the transaction attached to the next queued item without
    /// removing or executing it.
    var nextTransaction: Transaction? {
        pendingWork.withLock { work in
            guard let transaction = work.first?.transaction?.value,
                  !transaction.isEmpty else {
                return nil
            }
            return transaction
        }
    }

    /// Enqueues a work item. Safe to call from any thread.
    /// The closure runs when the owning graph drains this inbox.
    func enqueue(transaction: Transaction? = nil, _ work: @escaping @Sendable () -> Void) {
        pendingWork.withLock {
            $0.append(WorkItem(transaction: transaction.map(UnsafeBox.init), work: work))
        }
    }

    /// Runs the work items pending at the start of this call.
    /// Items enqueued during execution remain pending for the next drain.
    /// Must be called inside the owning graph's active `_AGGraph` context.
    @discardableResult
    func drain() -> Transaction? {
        guard _AGGraph.current != nil else {
            fatalError("AGInbox.drain() called outside an active _AGGraph context.")
        }
        let pending = pendingWork.withLock { work -> [WorkItem] in
            defer { work.removeAll() }
            return work
        }
        var transaction: Transaction?
        for item in pending {
            if let itemTransaction = item.transaction?.value,
               !itemTransaction.isEmpty {
                transaction = itemTransaction
            }
            item.work()
        }
        return transaction
    }

    /// Runs a single pending work item.
    /// Must be called inside the owning graph's active `_AGGraph` context.
    @discardableResult
    func drainOne() -> Transaction? {
        guard _AGGraph.current != nil else {
            fatalError("AGInbox.drainOne() called outside an active _AGGraph context.")
        }
        let item = pendingWork.withLock { work -> WorkItem? in
            guard !work.isEmpty else { return nil }
            return work.removeFirst()
        }
        guard let item else { return nil }
        let transaction = item.transaction?.value
        item.work()
        return transaction?.isEmpty == false ? transaction : nil
    }
}
