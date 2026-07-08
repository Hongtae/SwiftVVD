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
    private let pendingWork: Mutex<[@Sendable () -> Void]> = Mutex([])

    var hasPendingWork: Bool {
        pendingWork.withLock { !$0.isEmpty }
    }

    /// Enqueues a work item.  Safe to call from any thread.
    /// The closure runs on the AG thread with `_AGGraph.current` already bound.
    func enqueue(_ work: @escaping @Sendable () -> Void) {
        pendingWork.withLock { $0.append(work) }
    }

    /// Runs all pending work items.
    /// Must be called on the AG thread inside an active `_AGGraph` context.
    func drain() {
        guard _AGGraph.current != nil else {
            fatalError("AGInbox.drain() called outside an active _AGGraph context.")
        }
        let pending = pendingWork.withLock { work -> [@Sendable () -> Void] in
            defer { work.removeAll() }
            return work
        }
        for work in pending { work() }
    }
}
