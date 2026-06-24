//
//  File: GraphHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
#if canImport(CoreFoundation)
import CoreFoundation
#endif

protocol GraphMutation {
    func apply()
    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation
}

extension GraphMutation {
    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        false
    }
}

struct CustomGraphMutation: GraphMutation {
    var body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }

    func apply() {
        body()
    }
}

struct EmptyGraphMutation: GraphMutation {
    func apply() {}
}

struct InvalidatingGraphMutation: GraphMutation {
    var attribute: AGWeakAttribute

    func apply() {
        guard let graph = AttributeGraph.current,
              attribute.isValid(in: graph) else {
            return
        }
        graph.invalidateAttribute(attribute.toStrong())
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? InvalidatingGraphMutation else {
            return false
        }
        return attribute == mutation.attribute
    }
}

struct AssignmentGraphMutation<Value>: GraphMutation {
    var attribute: WeakAttribute<Value>
    var value: Value

    func apply() {
        guard let graph = AttributeGraph.current,
              attribute.isValid(in: graph) else {
            return
        }
        attribute.toStrong().setValue(value)
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? AssignmentGraphMutation<Value>,
              attribute == mutation.attribute else {
            return false
        }
        value = mutation.value
        return true
    }
}

enum _GraphMutation_Style: UInt8, Hashable {
    case immediate = 0
    case deferred = 1
}

// GraphHost is the root AttributeGraph-owning base class.
// `data` wraps the shared graph core with a per-host context pointer and the
// per-host seed attributes used by graph/update transaction bookkeeping.
// Multiple hosts can share one underlying AttributeGraph while each holds its
// own data wrapper.
class GraphHost {
    private static let maxTransactionUpdatePassCount = 8

    struct Data: @unchecked Sendable {
        private var ref: AttributeGraphRef

        private(set) var globalSubgraph: AGSubgraph
        private(set) var rootSubgraph: AGSubgraph
        private(set) var updateSeedAttribute: Attribute<UInt32>
        private(set) var transactionSeedAttribute: Attribute<UInt32>

        init(graph: AttributeGraph) {
            let ref = AttributeGraphRef(graph: graph)
            var globalSubgraph: AGSubgraph!
            var rootSubgraph: AGSubgraph!
            var updateSeedAttribute: Attribute<UInt32>!
            var transactionSeedAttribute: Attribute<UInt32>!
            ref.withCurrent {
                globalSubgraph = AGSubgraph()
                AGSubgraph.$current.withValue(globalSubgraph) {
                    rootSubgraph = AGSubgraph()
                }
                updateSeedAttribute = graph.makeInput(value: UInt32.zero)
                transactionSeedAttribute = graph.makeInput(value: UInt32.zero)
            }
            self.ref = ref
            self.globalSubgraph = globalSubgraph
            self.rootSubgraph = rootSubgraph
            self.updateSeedAttribute = updateSeedAttribute
            self.transactionSeedAttribute = transactionSeedAttribute
        }

        var graph: AttributeGraph {
            ref.graph
        }

        var context: AnyObject? {
            get { ref.context }
            set { ref.context = newValue }
        }

        var updateSeed: UInt32 {
            get { ref.withCurrent { updateSeedAttribute.value } }
            nonmutating set { ref.withCurrent { updateSeedAttribute.setValue(newValue) } }
        }

        var transactionSeed: UInt32 {
            get { ref.withCurrent { transactionSeedAttribute.value } }
            nonmutating set { ref.withCurrent { transactionSeedAttribute.setValue(newValue) } }
        }

        func incrementUpdateSeed() {
            updateSeed = updateSeed &+ 1
        }

        func incrementTransactionSeed() {
            transactionSeed = transactionSeed &+ 1
        }

        func withCurrent<R>(_ body: () throws -> R) rethrows -> R {
            try ref.withCurrent(body)
        }
    }

    var data: Data
    private(set) var isUpdating: Bool = false
    private(set) var needsTransaction: Bool = false
    private var mayDeferUpdateLatch: Bool = true
    private var pendingTransactions: [AsyncTransaction] = []
    private var pendingGraphMutations: [any GraphMutation] = []

    static var currentHost: GraphHost {
        guard let ref = AttributeGraphRef.current,
              let host = ref.context as? GraphHost else {
            fatalError("GraphHost.currentHost accessed outside an active graph host context.")
        }
        return host
    }

    /// Creates a new AttributeGraph core and wraps it in an AttributeGraphRef owned by self.
    init() {
        let graph = AttributeGraph()
        self.data = Data(graph: graph)
        self.data.context = self
    }

    /// Wraps an existing AttributeGraph core in a new AttributeGraphRef owned by self.
    /// Used when a second GraphHost (e.g. GestureGraph) shares the same core as another.
    init(graph: AttributeGraph) {
        self.data = Data(graph: graph)
        self.data.context = self
    }

    var hasPendingTransactions: Bool {
        !pendingTransactions.isEmpty
    }

    var hasPendingGraphMutations: Bool {
        !pendingGraphMutations.isEmpty
    }

    var mayDeferUpdate: Bool {
        mayDeferUpdateLatch
    }

    var parentHost: GraphHost? {
        nil
    }

    var graphDelegate: (any GraphDelegate)? {
        nil
    }

    func setNeedsUpdate(mayDeferUpdate: Bool, values: ViewGraphRootValues) {
        narrowMayDeferUpdate(mayDeferUpdate)
        _ = values

        if let viewGraph = self as? ViewGraph {
            viewGraph.viewDelegate?.setNeedsUpdate()
        }
    }

    @discardableResult
    func asyncTransaction<M>(
        _ transaction: Transaction = Transaction(),
        id: Transaction.ID = Transaction.id,
        mutation: M,
        style: _GraphMutation_Style = .deferred,
        mayDeferUpdate: Bool = true
    ) -> UInt32 where M: GraphMutation {
        let canDeferAsyncTransaction = style == .deferred || isUpdating
        narrowMayDeferUpdate(mayDeferUpdate)

        if let index = pendingTransactions.lastIndex(where: { pending in
            pending.id == id && pending.transaction.plist.isEqual(to: transaction.plist)
        }) {
            pendingTransactions[index].append(mutation)
            let traceID = pendingTransactions[index].traceID
            if !canDeferAsyncTransaction {
                let transaction = pendingTransactions.remove(at: index)
                flushTransactions()
                pendingTransactions.append(transaction)
            }
            return traceID
        }

        if !canDeferAsyncTransaction {
            flushTransactions()
        }

        if pendingTransactions.isEmpty {
            graphDelegate?.beginTransaction()
        }

        let traceID = Self.nextAsyncTransactionTrace()
        pendingTransactions.append(
            AsyncTransaction(
                transaction: transaction,
                id: id,
                mutations: [mutation],
                style: style,
                mayDeferUpdate: mayDeferUpdate,
                traceID: traceID
            )
        )
        return traceID
    }

    @discardableResult
    func asyncTransaction(
        _ transaction: Transaction = Transaction(),
        id: Transaction.ID = Transaction.id,
        _ body: @escaping () -> Void
    ) -> UInt32 {
        asyncTransaction(
            transaction,
            id: id,
            mutation: CustomGraphMutation(body),
            style: .deferred,
            mayDeferUpdate: true
        )
    }

    @discardableResult
    func emptyTransaction(_ transaction: Transaction = Transaction()) -> UInt32 {
        asyncTransaction(
            transaction,
            id: Transaction.id,
            mutation: EmptyGraphMutation(),
            style: .deferred,
            mayDeferUpdate: true
        )
    }

    func continueTransaction(invalidating attribute: AGWeakAttribute) {
        continueTransaction(InvalidatingGraphMutation(attribute: attribute))
    }

    func continueTransaction<Value>(setting attribute: WeakAttribute<Value>, to value: Value) {
        continueTransaction(AssignmentGraphMutation(attribute: attribute, value: value))
    }

    func continueTransaction<M>(_ mutation: M) where M: GraphMutation {
        guard let host = updatingMutationHost else {
            Update.enqueueAction(reason: 0x11) { [self] in
                asyncTransaction(
                    Transaction(),
                    id: Transaction.id,
                    mutation: mutation,
                    style: .deferred,
                    mayDeferUpdate: true
                )
            }
            return
        }

        host.appendGraphMutation(mutation)
        host.needsTransaction = true
    }

    var hasPendingGlobalTransactions: Bool {
        Self.hasPendingGlobalTransactions
    }

    static var hasPendingGlobalTransactions: Bool {
        globalTransactionState.withLock {
            !globalTransactionState.pendingTransactions.isEmpty
        }
    }

    static func globalTransaction<M>(
        _ transaction: Transaction = Transaction(),
        id: Transaction.ID = Transaction.id,
        mutation: M,
        hostProvider: any TransactionHostProvider
    ) where M: GraphMutation {
        globalTransactionState.withLock {
            let providerKey = TransactionHostProviderKey(hostProvider)
            if let index = globalTransactionState.pendingTransactions.lastIndex(where: { pending in
                pending.matches(providerKey: providerKey, id: id, transaction: transaction)
            }) {
                // Same provider identity, transaction id, and transaction plist
                // share one queued global transaction; only the mutation payload
                // grows. This keeps later equivalent commits in the same flush
                // lane instead of starting a second transaction update.
                globalTransactionState.pendingTransactions[index].append(mutation)
                return
            }

            let traceID = nextAsyncTransactionTrace()
            let wasEmpty = globalTransactionState.pendingTransactions.isEmpty
            globalTransactionState.pendingTransactions.append(
                GlobalTransaction(
                    providerKey: providerKey,
                    hostProvider: hostProvider,
                    asyncTransaction: AsyncTransaction(
                        transaction: transaction,
                        id: id,
                        mutations: [mutation],
                        style: .deferred,
                        mayDeferUpdate: true,
                        traceID: traceID
                    )
                )
            )
            if wasEmpty {
                scheduleGlobalTransactionFlush()
            }
        }
    }

    static func flushGlobalTransactions() {
        let transactions = globalTransactionState.withLock {
            let transactions = globalTransactionState.pendingTransactions
            globalTransactionState.pendingTransactions.removeAll()
            globalTransactionState.isFlushScheduled = false
            return transactions
        }

        for transaction in transactions {
            transaction.apply()
        }
    }

    func flushTransactions() {
        guard !pendingTransactions.isEmpty else { return }

        Update.begin()
        defer { Update.end() }

        let transactions = pendingTransactions
        pendingTransactions.removeAll()
        for transaction in transactions {
            runTransaction(transaction.transaction, id: transaction.id.value) {
                Transaction.withScopedThreadTransaction(transaction.transaction) {
                    transaction.apply()
                }
            }
        }
        graphDelegate?.graphDidChange()
        resetMayDeferUpdate()
    }

    func startTransactionUpdate(id: UInt32? = nil) {
        isUpdating = true
        data.incrementTransactionSeed()
    }

    func finishTransactionUpdate(id: UInt32? = nil) {
        finishTransactionUpdate(in: nil, postUpdate: { _ in }, id: id)
    }

    func finishTransactionUpdate(
        in subgraph: AGSubgraph? = nil,
        postUpdate: (Bool) -> Void = { _ in },
        id: UInt32? = nil
    ) {
        data.withCurrent {
            _ = id
            drainGraphMutationPasses(in: subgraph ?? data.rootSubgraph, postUpdate: postUpdate)
        }
        isUpdating = false
    }

    func runTransaction<R>(
        _ transaction: Transaction? = nil,
        id: UInt32? = nil,
        do body: () throws -> R
    ) rethrows -> R {
        try data.withCurrent {
            startTransactionUpdate(id: id)
            defer { finishTransactionUpdate(id: id) }
            return try body()
        }
    }

    @discardableResult
    func updatePreferences() -> Bool {
        false
    }

    private static func nextAsyncTransactionTrace() -> UInt32 {
        AsyncTransactionTraceState.nextTrace()
    }

    private func narrowMayDeferUpdate(_ value: Bool) {
        mayDeferUpdateLatch = mayDeferUpdateLatch && value
    }

    private func resetMayDeferUpdate() {
        mayDeferUpdateLatch = true
    }

    private var updatingMutationHost: GraphHost? {
        var host: GraphHost? = self
        while let candidate = host {
            if candidate.isUpdating {
                return candidate
            }
            host = candidate.parentHost
        }
        return nil
    }

    private func appendGraphMutation<M>(_ mutation: M) where M: GraphMutation {
        if !pendingGraphMutations.isEmpty {
            let lastIndex = pendingGraphMutations.index(before: pendingGraphMutations.endIndex)
            if pendingGraphMutations[lastIndex].combine(with: mutation) {
                return
            }
        }
        pendingGraphMutations.append(mutation)
    }

    private func drainGraphMutationPasses(in subgraph: AGSubgraph, postUpdate: (Bool) -> Void) {
        var passCount = 0

        repeat {
            drainGraphMutationPass()
            subgraph.update(flags: 1)

            let needsFollowUp = !pendingGraphMutations.isEmpty
            postUpdate(needsFollowUp)

            passCount += 1
            if !needsFollowUp {
                return
            }
        } while passCount < Self.maxTransactionUpdatePassCount
    }

    private func drainGraphMutationPass() {
        guard !pendingGraphMutations.isEmpty else { return }

        let mutations = pendingGraphMutations
        pendingGraphMutations = []
        needsTransaction = false

        for mutation in mutations {
            mutation.apply()
        }
    }

    private static let globalTransactionState = GlobalTransactionState()

    private static func scheduleGlobalTransactionFlush() {
        guard !globalTransactionState.isFlushScheduled else { return }
        globalTransactionState.isFlushScheduled = true
        MainRunLoopObserverScheduler.shared.schedule {
            Self.flushGlobalTransactions()
        }
    }

    private final class MainRunLoopObserverScheduler: @unchecked Sendable {
        static let shared = MainRunLoopObserverScheduler()

        private let lock = NSRecursiveLock()
        private var actions: [@Sendable () -> Void] = []

        #if canImport(CoreFoundation)
        private var observer: CFRunLoopObserver?
        #endif

        func schedule(_ action: @escaping @Sendable () -> Void) {
            #if canImport(CoreFoundation)
            if Thread.isMainThread {
                enqueueObserverAction(action)
            } else {
                RunLoop.main.perform(inModes: [.common], block: action)
            }
            #else
            RunLoop.main.perform(action)
            #endif
        }

        #if canImport(CoreFoundation)
        private func enqueueObserverAction(_ action: @escaping @Sendable () -> Void) {
            lock.lock()
            actions.append(action)
            ensureObserver()
            lock.unlock()
        }

        private func ensureObserver() {
            guard observer == nil else { return }

            var context = CFRunLoopObserverContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let activities = CFRunLoopActivity.beforeWaiting.rawValue |
                CFRunLoopActivity.exit.rawValue
            let observer = CFRunLoopObserverCreate(
                kCFAllocatorDefault,
                activities,
                true,
                0,
                { _, _, info in
                    guard let info else { return }
                    let scheduler = Unmanaged<MainRunLoopObserverScheduler>
                        .fromOpaque(info)
                        .takeUnretainedValue()
                    scheduler.flushObserverActions()
                },
                &context
            )
            guard let observer else { return }

            self.observer = observer
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        private func flushObserverActions() {
            while true {
                let actions = takeObserverActions()
                guard !actions.isEmpty else { return }

                Update.ensure {
                    actions.forEach { $0() }
                }
            }
        }

        private func takeObserverActions() -> [@Sendable () -> Void] {
            lock.lock()
            defer { lock.unlock() }

            let snapshot = actions
            actions.removeAll(keepingCapacity: true)
            return snapshot
        }
        #endif
    }

    private enum AsyncTransactionTraceState {
        private static let nextTraceID = Atomic<UInt32>(0)

        static func nextTrace() -> UInt32 {
            let rawID = nextTraceID.wrappingAdd(2, ordering: .relaxed).oldValue
            return (rawID &>> 1) &+ 1
        }
    }

    private final class GlobalTransactionState: @unchecked Sendable {
        private let lock = NSRecursiveLock()
        var pendingTransactions: [GlobalTransaction] = []
        var isFlushScheduled = false

        func withLock<R>(_ body: () throws -> R) rethrows -> R {
            lock.lock()
            defer { lock.unlock() }
            return try body()
        }
    }

    private enum TransactionHostProviderKey: Equatable {
        case object(ObjectIdentifier)
        case type(ObjectIdentifier)

        init(_ hostProvider: any TransactionHostProvider) {
            if Mirror(reflecting: hostProvider).displayStyle == .class {
                self = .object(ObjectIdentifier(hostProvider as AnyObject))
            } else {
                self = .type(ObjectIdentifier(Swift.type(of: hostProvider)))
            }
        }
    }

    private struct AsyncTransaction {
        var transaction: Transaction
        var id: Transaction.ID
        var mutations: [any GraphMutation]
        var style: _GraphMutation_Style
        var mayDeferUpdate: Bool
        var traceID: UInt32

        mutating func append<M>(_ mutation: M) where M: GraphMutation {
            if !mutations.isEmpty {
                let lastIndex = mutations.index(before: mutations.endIndex)
                if mutations[lastIndex].combine(with: mutation) {
                    return
                }
            }
            mutations.append(mutation)
        }

        func apply() {
            for mutation in mutations {
                mutation.apply()
            }
        }
    }

    private struct GlobalTransaction {
        var providerKey: TransactionHostProviderKey
        var hostProvider: any TransactionHostProvider
        var asyncTransaction: AsyncTransaction

        var traceID: UInt32 {
            asyncTransaction.traceID
        }

        func matches(
            providerKey: TransactionHostProviderKey,
            id: Transaction.ID,
            transaction: Transaction
        ) -> Bool {
            self.providerKey == providerKey &&
            asyncTransaction.id == id &&
            asyncTransaction.transaction.plist.isEqual(to: transaction.plist)
        }

        mutating func append<M>(_ mutation: M) where M: GraphMutation {
            asyncTransaction.append(mutation)
        }

        func apply() {
            if let host = hostProvider.mutationHost {
                // A live host owns graph context, transaction seed mutation, and
                // delegate notification for this global transaction.
                host.runTransaction(asyncTransaction.transaction, id: asyncTransaction.id.value) {
                    asyncTransaction.apply()
                }
                host.graphDelegate?.graphDidChange()
            } else {
                // Nil-host fallback still needs Transaction.current to reflect
                // the queued transaction while the mutation runs, then restore
                // the caller's thread-local box after the stored mutations drain.
                Transaction.withScopedThreadTransaction(asyncTransaction.transaction) {
                    asyncTransaction.apply()
                }
            }
        }
    }
}

// GraphDelegate provides transaction/update/change callbacks for graph hosts.
protocol GraphDelegate: AnyObject {
    func beginTransaction()
    func updateGraph<T>(body: (GraphHost) -> T) -> T
    func graphDidChange()
    func preferencesDidChange()
}

extension GraphDelegate {
    func beginTransaction() {}
    func preferencesDidChange() {}
}
