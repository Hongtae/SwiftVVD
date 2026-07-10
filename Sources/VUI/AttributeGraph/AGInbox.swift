//
//  File: AGInbox.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization

/// A thread-safe queue of work items to be run on the AG thread.
///
/// Owned by `_AGGraph` — access via `_AGGraph.current!.inbox` or a
/// pre-captured reference.  At the start of each render pass the host calls
/// `drain()` inside the active AG context, which executes all pending closures
/// with `_AGGraph.current` already bound.
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
/// // Render pass start (AG thread):
/// _AGGraph.withCurrent(graph) {
///     graph.inbox.drain()   // _AGGraph.current is already bound; closures can use it freely
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

    /// Enqueues a work item.  Safe to call from any thread.
    /// The closure runs on the AG thread with `_AGGraph.current` already bound.
    func enqueue(transaction: Transaction? = nil, _ work: @escaping @Sendable () -> Void) {
        pendingWork.withLock {
            $0.append(WorkItem(transaction: transaction.map(UnsafeBox.init), work: work))
        }
    }

    /// Runs all pending work items.
    /// Must be called on the AG thread inside an active `_AGGraph` context.
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
    /// Must be called on the AG thread inside an active `_AGGraph` context.
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
