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

private struct HostGraphMutation<Mutation>: GraphMutation where Mutation: GraphMutation {
    weak var host: GraphHost?
    var mutation: Mutation

    func apply() {
        host?.data.withCurrent {
            mutation.apply()
        }
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? HostGraphMutation<Mutation>,
              let host,
              let nextHost = mutation.host,
              host === nextHost else {
            return false
        }
        return self.mutation.combine(with: mutation.mutation)
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

private struct EmptyGraphMutation: GraphMutation {
    func apply() {}
}

struct InvalidatingGraphMutation: GraphMutation {
    var attribute: AGWeakAttribute

    func apply() {
        guard let graph = _AGGraph.current,
              attribute.isValid(in: graph) else {
            return
        }
        let transaction = GraphHost.currentHost.data._transaction.value
        let transactionToPropagate = transaction.isEmpty ? nil : transaction
        graph.invalidateAttribute(
            attribute.toStrong(),
            transaction: transactionToPropagate,
            // A plain host transaction is still authoritative. Propagating
            // nil clears animation provenance left by an earlier invalidation.
            propagateTransaction: true
        )
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? InvalidatingGraphMutation else {
            return false
        }
        return attribute == mutation.attribute
    }
}

struct AssignmentGraphMutation<Value>: GraphMutation {
    var target: WeakAttribute<Value>?
    var newValue: Value

    init(_ target: WeakAttribute<Value>?, newValue: Value) {
        self.target = target
        self.newValue = newValue
    }

    func apply() {
        guard let graph = _AGGraph.current,
              let target,
              target.isValid(in: graph) else {
            return
        }
        target.toStrong().setValue(newValue, transaction: Transaction.current)
    }

    mutating func combine<M>(with mutation: M) -> Bool where M: GraphMutation {
        guard let mutation = mutation as? AssignmentGraphMutation<Value>,
              target == mutation.target else {
            return false
        }
        newValue = mutation.newValue
        return true
    }
}

enum _GraphMutation_Style: Hashable {
    case immediate
    case deferred
}

private struct ConstantKey: Hashable {
    var type: Any.Type
    var id: GraphHost.ConstantID

    static func == (lhs: ConstantKey, rhs: ConstantKey) -> Bool {
        lhs.type == rhs.type && lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(type))
        hasher.combine(id)
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
    var transactionID: Transaction.ID
    var traceID: UInt32
    var mutations: [any GraphMutation]

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
    var hostProvider: any TransactionHostProvider
    var base: AsyncTransaction

    func matches(
        hostProvider: any TransactionHostProvider,
        id: Transaction.ID,
        transaction: Transaction
    ) -> Bool {
        TransactionHostProviderKey(self.hostProvider) ==
            TransactionHostProviderKey(hostProvider) &&
        base.transactionID == id &&
        base.transaction.plist.isEqual(to: transaction.plist)
    }

    mutating func append<M>(_ mutation: M) where M: GraphMutation {
        base.append(mutation)
    }

    func apply() {
        if let host = hostProvider.mutationHost {
            host.runTransaction(
                base.transaction,
                do: { base.apply() },
                id: base.transactionID.value
            )
            host.graphDelegate?.graphDidChange()
        } else {
            Transaction.withScopedThreadTransaction(base.transaction) {
                base.apply()
            }
        }
    }
}

class GraphHost: CustomReflectable {
    private static let maxTransactionUpdatePassCount = 8

    struct RemovedState: OptionSet {
        let rawValue: UInt8

        static let unattached = RemovedState(rawValue: 1 << 0)
        static let hiddenForReuse = RemovedState(rawValue: 1 << 1)
    }

    enum ConstantID: Int8, Hashable {
        case defaultValue
        case implicitViewRoot
        case trueValue
        case defaultValue3D
        case failedValue
        case placeholder
        case preferenceKeyDefault
    }

    struct Data {
        private var graphRef: AGGraphRef?
        var globalSubgraph: AGSubgraphRef
        var rootSubgraph: AGSubgraphRef
        var isRemoved: Bool
        var isHiddenForReuse: Bool
        var _time: Attribute<Time>
        var _environment: Attribute<EnvironmentValues>
        var _phase: Attribute<_GraphInputs.Phase>
        var _hostPreferenceKeys: Attribute<PreferenceKeys>
        var _transaction: Attribute<Transaction>
        var _updateSeed: Attribute<UInt32>
        var _transactionSeed: Attribute<UInt32>
        var inputs: _GraphInputs

        init() {
            let graph = _AGGraph()
            var globalSubgraph: AGSubgraphRef!
            var rootSubgraph: AGSubgraphRef!
            var time: Attribute<Time>!
            var environment: Attribute<EnvironmentValues>!
            var phase: Attribute<_GraphInputs.Phase>!
            var hostPreferenceKeys: Attribute<PreferenceKeys>!
            var transaction: Attribute<Transaction>!
            var updateSeed: Attribute<UInt32>!
            var transactionSeed: Attribute<UInt32>!
            _AGGraph.withCurrent(graph) {
                globalSubgraph = AGSubgraph()
                AGSubgraph.withCurrent(globalSubgraph) {
                    rootSubgraph = AGSubgraph()
                }
                time = graph.makeInput(value: Time.zero)
                environment = graph.makeInput(value: EnvironmentValues())
                phase = graph.makeInput(value: _GraphInputs.Phase())
                hostPreferenceKeys = graph.makeInput(value: PreferenceKeys())
                transaction = graph.makeInput(value: Transaction())
                updateSeed = graph.makeInput(value: UInt32.zero)
                transactionSeed = graph.makeInput(value: UInt32.zero)
            }
            self.graphRef = graph
            self.globalSubgraph = globalSubgraph
            self.rootSubgraph = rootSubgraph
            self.isRemoved = false
            self.isHiddenForReuse = false
            self._time = time
            self._environment = environment
            self._phase = phase
            self._hostPreferenceKeys = hostPreferenceKeys
            self._transaction = transaction
            self._updateSeed = updateSeed
            self._transactionSeed = transactionSeed
            self.inputs = _GraphInputs(
                time: time,
                phase: phase,
                environment: environment,
                transaction: transaction
            )
        }

        var time: Time {
            get { withCurrent { _time.value } }
            set { withCurrent { _time.setValue(newValue) } }
        }

        var environment: EnvironmentValues {
            get { withCurrent { _environment.value } }
            set { withCurrent { _environment.setValue(newValue) } }
        }

        var phase: _GraphInputs.Phase {
            get { withCurrent { _phase.value } }
            set { withCurrent { _phase.setValue(newValue) } }
        }

        var hostPreferenceKeys: PreferenceKeys {
            get { withCurrent { _hostPreferenceKeys.value } }
            set { withCurrent { _hostPreferenceKeys.setValue(newValue) } }
        }

        var transaction: Transaction {
            get { withCurrent { _transaction.value } }
            set { withCurrent { _transaction.setValue(newValue) } }
        }

        var updateSeed: UInt32 {
            get { withCurrent { _updateSeed.value } }
            set { withCurrent { _updateSeed.setValue(newValue) } }
        }

        var transactionSeed: UInt32 {
            get { withCurrent { _transactionSeed.value } }
            set { withCurrent { _transactionSeed.setValue(newValue) } }
        }

        var graph: AGGraphRef {
            guard let graphRef else {
                fatalError("GraphHost.Data used after invalidation.")
            }
            return graphRef
        }

        var isValid: Bool {
            graphRef != nil
        }

        mutating func invalidate() {
            guard graphRef != nil else { return }
            withCurrent {
                globalSubgraph.invalidate()
            }
            graphRef = nil
        }

        @discardableResult
        func withCurrent<R>(_ body: () throws -> R) rethrows -> R {
            guard let graph = graphRef else {
                fatalError("GraphHost.Data used after invalidation.")
            }
            return try _AGGraphContext(graph: graph).withCurrent(body)
        }
    }

    var data: Data
    private var constants: [ConstantKey: AGAttribute] = [:]
    private(set) var isInstantiated: Bool = false
    var hostPreferenceValues = WeakAttribute<PreferenceValues>()
    var lastHostPreferencesSeed = VersionSeed()
    private var pendingTransactions: [AsyncTransaction] = []
    private var inTransaction: Bool = false
    private var continuations: [any GraphMutation] = []
    private(set) var mayDeferUpdate: Bool = true
    var removedState: RemovedState = [] {
        didSet {
            updateRemovedState()
        }
    }

    static var currentHost: GraphHost {
        guard let graph = _AGGraph.current,
              let host = AGGraphGetContext(graph) as? GraphHost else {
            fatalError("GraphHost.currentHost accessed outside an active graph host context.")
        }
        return host
    }

    public var customMirror: Swift.Mirror {
        Swift.Mirror(self, children: EmptyCollection<(label: String?, value: Any)>())
    }

    init(data: Data) {
        self.data = data
        AGGraphSetContext(data.graph, self)
    }

    var hasPendingTransactions: Bool {
        !pendingTransactions.isEmpty
    }

    static var isUpdating: Bool {
        _AGGraph.currentlyUpdatingGraphs?.isEmpty == false
    }

    var isUpdating: Bool {
        inTransaction
    }

    var isUpdatingGraph: Bool {
        data.isValid && data.graph.isUpdatingOnCurrentThread
    }

    var needsTransaction: Bool {
        !continuations.isEmpty
    }

    var isValid: Bool {
        data.isValid
    }

    var graph: AGGraphRef {
        data.graph
    }

    var globalSubgraph: AGSubgraphRef {
        data.globalSubgraph
    }

    var rootSubgraph: AGSubgraphRef {
        data.rootSubgraph
    }

    var graphInputs: _GraphInputs {
        data.inputs
    }

    var environment: EnvironmentValues {
        data.environment
    }

    var parentHost: GraphHost? {
        nil
    }

    var graphDelegate: (any GraphDelegate)? {
        nil
    }

    func instantiateOutputs() {}

    func uninstantiateOutputs() {}

    func timeDidChange() {}

    func instantiateIfNeeded() {
        if !isInstantiated {
            instantiate()
        }
    }

    func instantiate() {
        guard !isInstantiated else { return }
        if let graphDelegate {
            graphDelegate.updateGraph { _ in
                data.withCurrent {
                    AGSubgraph.withCurrent(rootSubgraph) {
                        instantiateOutputs()
                    }
                }
            }
        } else {
            data.withCurrent {
                AGSubgraph.withCurrent(rootSubgraph) {
                    instantiateOutputs()
                }
            }
        }
        isInstantiated = true
    }

    func uninstantiate() {
        uninstantiate(immediately: false)
    }

    func uninstantiate(immediately: Bool) {
        guard isInstantiated else { return }
        let oldRoot = data.rootSubgraph
        data.withCurrent {
            uninstantiateOutputs()
            oldRoot.willRemove()
            data.inputs.cachedEnvironment = MutableBox(
                CachedEnvironment(environment: data._environment)
            )
            AGSubgraph.withCurrent(data.globalSubgraph) {
                data.rootSubgraph = AGSubgraph()
            }
        }
        isInstantiated = false

        let invalidateOldRoot = { [data] in
            data.withCurrent {
                oldRoot.invalidate()
                oldRoot.removeFromParent()
            }
        }
        if immediately {
            invalidateOldRoot()
        } else {
            Update.enqueueAction(invalidateOldRoot)
        }
    }

    func invalidate() {
        if isInstantiated {
            data.withCurrent {
                rootSubgraph.willRemove()
            }
            isInstantiated = false
        }
        data.invalidate()
    }

    func setTime(_ time: Time) {
        data.withCurrent {
            guard data._time.value != time else { return }
            data._time.setValue(time)
            timeDidChange()
        }
    }

    func setEnvironment(_ environment: EnvironmentValues) {
        data.withCurrent {
            data._environment.setValue(environment)
        }
    }

    func intern<Value>(
        _ value: Value,
        for type: Any.Type,
        id: ConstantID
    ) -> Attribute<Value> {
        let key = ConstantKey(type: type, id: id)
        if let attribute = constants[key] {
            return Attribute<Value>(attribute)
        }
        let attribute = data.withCurrent {
            graph.makeInput(value: value)
        }
        constants[key] = attribute.identifier
        return attribute
    }

    func preferenceValues() -> PreferenceValues {
        instantiateIfNeeded()
        return data.withCurrent {
            guard hostPreferenceValues.isValid(in: graph) else {
                return PreferenceValues()
            }
            return hostPreferenceValues.toStrong().value
        }
    }

    func isHiddenForReuseDidChange() {}

    func hostKind() -> CustomEventTrace.InstantiationEventType.Kind {
        .graph
    }

    func graphInvalidation(from attribute: AGAttribute?) {
        guard let attribute else {
            graphDelegate?.graphDidChange()
            return
        }

        // This callback forwards the source host's transaction into this host;
        // the dependency walk has already invalidated the source attribute.
        // Re-invalidating it here would create a second mutation cycle.
        let sourceGraph = AGGraphGetAttributeGraph(attribute)
        guard let sourceHost = AGGraphGetContext(sourceGraph) as? GraphHost else {
            fatalError(
                "GraphHost.graphInvalidation(from:) requires the source graph to have a GraphHost context."
            )
        }
        let transaction = sourceHost.data._transaction.value

        // Cross-host invalidation cannot become more deferrable than its
        // source. This latch is narrowed even when there is no transaction to
        // forward.
        narrowMayDeferUpdate(sourceHost.mayDeferUpdate)
        guard !transaction.isEmpty else { return }

        emptyTransaction(transaction)
    }

    func setPhase(_ phase: _GraphInputs.Phase) {
        data.withCurrent {
            data._phase.setValue(phase)
        }
    }

    func incrementPhase() {
        data.withCurrent {
            var phase = data._phase.value
            phase.resetSeed &+= 1
            data._phase.setValue(phase)
        }
        graphDelegate?.graphDidChange()
    }

    func updateRemovedState() {
        let sourceState: RemovedState
        let nextRemoved: Bool

        if !removedState.isEmpty {
            sourceState = removedState
            nextRemoved = true
        } else if let parentHost {
            sourceState = parentHost.removedState
            nextRemoved = sourceState.contains(.hiddenForReuse)
        } else {
            sourceState = []
            nextRemoved = false
        }

        if nextRemoved != data.isRemoved {
            data.withCurrent {
                if nextRemoved {
                    data.rootSubgraph.willRemove()
                } else {
                    data.rootSubgraph.didReinsert()
                }
            }
            data.isRemoved = nextRemoved
        }

        let nextHiddenForReuse = sourceState.contains(.hiddenForReuse)
        if nextHiddenForReuse != data.isHiddenForReuse {
            data.isHiddenForReuse = nextHiddenForReuse
            isHiddenForReuseDidChange()
        }
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
            pending.transactionID == id &&
                pending.transaction.plist.isEqual(to: transaction.plist)
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
                transactionID: id,
                traceID: traceID,
                mutations: [mutation]
            )
        )
        return traceID
    }

    @discardableResult
    func asyncTransaction<Value>(
        _ transaction: Transaction = Transaction(),
        id: Transaction.ID = Transaction.id,
        setting target: WeakAttribute<Value>,
        to newValue: Value,
        style: _GraphMutation_Style = .deferred,
        mayDeferUpdate: Bool = true
    ) -> UInt32 {
        asyncTransaction(
            transaction,
            id: id,
            mutation: AssignmentGraphMutation(
                target,
                newValue: newValue
            ),
            style: style,
            mayDeferUpdate: mayDeferUpdate
        )
    }

    @discardableResult
    func asyncTransaction<Value>(
        _ transaction: Transaction = Transaction(),
        id: Transaction.ID = Transaction.id,
        invalidating target: WeakAttribute<Value>,
        style: _GraphMutation_Style = .deferred,
        mayDeferUpdate: Bool = true
    ) -> UInt32 {
        asyncTransaction(
            transaction,
            id: id,
            mutation: InvalidatingGraphMutation(attribute: target.base),
            style: style,
            mayDeferUpdate: mayDeferUpdate
        )
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
        let mutation = InvalidatingGraphMutation(attribute: attribute)
        guard let host = updatingMutationHost else {
            let transaction = Transaction.current
            let id = Transaction.id
            Update.enqueueAction { [self] in
                asyncTransaction(
                    transaction,
                    id: id,
                    mutation: mutation,
                    style: .deferred,
                    mayDeferUpdate: true
                )
                if Self.isFlushingGlobalTransactions {
                    flushTransactions()
                }
            }
            return
        }

        host.appendGraphMutation(mutation, from: self)
    }

    func continueTransaction<Value>(setting attribute: WeakAttribute<Value>, to value: Value) {
        continueTransaction(
            AssignmentGraphMutation(attribute, newValue: value)
        )
    }

    func continueTransaction<M>(_ mutation: M) where M: GraphMutation {
        guard let host = updatingMutationHost else {
            Update.enqueueAction { [self] in
                asyncTransaction(
                    Transaction(),
                    id: Transaction.id,
                    mutation: mutation,
                    style: .deferred,
                    mayDeferUpdate: true
                )
                if Self.isFlushingGlobalTransactions {
                    flushTransactions()
                }
            }
            return
        }

        host.appendGraphMutation(mutation, from: self)
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
            if let index = globalTransactionState.pendingTransactions.lastIndex(where: { pending in
                pending.matches(
                    hostProvider: hostProvider,
                    id: id,
                    transaction: transaction
                )
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
                    hostProvider: hostProvider,
                    base: AsyncTransaction(
                        transaction: transaction,
                        transactionID: id,
                        traceID: traceID,
                        mutations: [mutation]
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
            globalTransactionState.isFlushing = true
            return transactions
        }
        defer {
            globalTransactionState.withLock {
                globalTransactionState.isFlushing = false
            }
        }

        for transaction in transactions {
            transaction.apply()
        }
        // Observer invalidations can enqueue ordinary host transactions while a
        // global transaction is being applied. Drain those fallback actions
        // before leaving the global flush boundary so all live observers see
        // the same completed mutation pass.
        Update.dispatchActions()
    }

    func flushTransactions() {
        flushTransactions(afterEach: {})
    }

    // Backend hosts can consume transaction-owned work, such as deferred
    // resources, before the next queued transaction begins.
    func flushTransactions(afterEach body: () -> Void) {
        guard !pendingTransactions.isEmpty else { return }

        Update.begin()
        defer { Update.end() }

        let transactions = pendingTransactions
        pendingTransactions.removeAll()
        for transaction in transactions {
            runTransaction(
                transaction.transaction,
                do: {
                    Transaction.withScopedThreadTransaction(transaction.transaction) {
                        transaction.apply()
                    }
                },
                id: transaction.transactionID.value
            )
            body()
        }
        graphDelegate?.graphDidChange()
        resetMayDeferUpdate()
    }

    func startTransactionUpdate(id: UInt32? = nil) {
        inTransaction = true
        data.transactionSeed &+= 1
    }

    func finishTransactionUpdate(
        in subgraph: AGSubgraphRef,
        postUpdate: (Bool) -> Void,
        id: UInt32?
    ) {
        data.withCurrent {
            _ = id
            drainGraphMutationPasses(in: subgraph, postUpdate: postUpdate)
        }
        inTransaction = false
    }

    func runTransaction(
        _ transaction: Transaction?,
        do body: () -> Void,
        id: UInt32?
    ) {
        instantiateIfNeeded()
        data.withCurrent {
            if let transaction {
                data._transaction.setValue(transaction)
            }
            startTransactionUpdate(id: id)
            body()
            finishTransactionUpdate(
                in: data.rootSubgraph,
                postUpdate: { _ in },
                id: id
            )
            if transaction != nil {
                data._transaction.setValue(Transaction())
            }
        }
    }

    func runTransaction() {
        runTransaction(nil, do: {}, id: nil)
    }

    func addPreference<Key>(_ key: Key.Type) where Key: HostPreferenceKey {
        data.withCurrent {
            var keys = data.hostPreferenceKeys
            keys.add(key)
            data.hostPreferenceKeys = keys
        }
    }

    func removePreference<Key>(_ key: Key.Type) where Key: HostPreferenceKey {
        data.withCurrent {
            var keys = data.hostPreferenceKeys
            keys.remove(key)
            data.hostPreferenceKeys = keys
        }
    }

    func preferenceValue<Key>(_ key: Key.Type) -> Key.Value
    where Key: HostPreferenceKey {
        let wasRegistered = data.hostPreferenceKeys.contains(key)
        if !wasRegistered {
            addPreference(key)
        }
        defer {
            if !wasRegistered {
                removePreference(key)
            }
        }
        return preferenceValues().value(for: key).value
    }

    @discardableResult
    func updatePreferences() -> Bool {
        let seed = data.withCurrent { () -> VersionSeed in
            guard hostPreferenceValues.isValid(in: graph) else {
                return .empty
            }
            return hostPreferenceValues.toStrong().value.seed
        }
        let changed = !lastHostPreferencesSeed.matches(seed)
        lastHostPreferencesSeed = seed
        return changed
    }

    private static func nextAsyncTransactionTrace() -> UInt32 {
        AsyncTransactionTraceState.nextTrace()
    }

    private func narrowMayDeferUpdate(_ value: Bool) {
        mayDeferUpdate = mayDeferUpdate && value
    }

    private func resetMayDeferUpdate() {
        mayDeferUpdate = true
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
        if !continuations.isEmpty {
            let lastIndex = continuations.index(before: continuations.endIndex)
            if continuations[lastIndex].combine(with: mutation) {
                return
            }
        }
        continuations.append(mutation)
    }

    private func appendGraphMutation<M>(
        _ mutation: M,
        from sourceHost: GraphHost
    ) where M: GraphMutation {
        if self === sourceHost {
            appendGraphMutation(mutation)
        } else {
            appendGraphMutation(
                HostGraphMutation(host: sourceHost, mutation: mutation)
            )
        }
    }

    private func drainGraphMutationPasses(
        in subgraph: AGSubgraphRef,
        postUpdate: (Bool) -> Void
    ) {
        var passCount = 0

        repeat {
            drainGraphMutationPass()
            subgraph.update(flags: 1)

            let needsFollowUp = !continuations.isEmpty
            postUpdate(needsFollowUp)

            passCount += 1
            if !needsFollowUp {
                return
            }
        } while passCount < Self.maxTransactionUpdatePassCount
    }

    private func drainGraphMutationPass() {
        guard !continuations.isEmpty else { return }

        let mutations = continuations
        continuations = []

        for mutation in mutations {
            mutation.apply()
        }
    }

    private static let globalTransactionState = GlobalTransactionState()

    private static var isFlushingGlobalTransactions: Bool {
        globalTransactionState.withLock {
            globalTransactionState.isFlushing
        }
    }

    private static func scheduleGlobalTransactionFlush() {
        guard !globalTransactionState.isFlushScheduled else { return }
        globalTransactionState.isFlushScheduled = true
        scheduleMainRunLoopObserver {
            Self.flushGlobalTransactions()
        }
    }

    fileprivate static func scheduleMainRunLoopObserver(
        _ action: @escaping @Sendable () -> Void
    ) {
        MainRunLoopObserverScheduler.shared.schedule(action)
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
                let scheduler = self
                RunLoop.main.perform(inModes: [.common]) {
                    scheduler.enqueueObserverAction(action)
                }
            }
            #else
            RunLoop.main.perform {
                Update.ensure {
                    action()
                }
            }
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
        var isFlushing = false

        func withLock<R>(_ body: () throws -> R) rethrows -> R {
            lock.lock()
            defer { lock.unlock() }
            return try body()
        }
    }

}

// GraphDelegate provides transaction/update/change callbacks for graph hosts.
protocol GraphDelegate: AnyObject {
    func updateGraph<T>(body: (GraphHost) -> T) -> T
    func graphDidChange()
    func preferencesDidChange()
    func beginTransaction()
}

private final class GraphDelegateBox: @unchecked Sendable {
    let value: any GraphDelegate

    init(_ value: any GraphDelegate) {
        self.value = value
    }
}

extension GraphDelegate {
    func beginTransaction() {
        let delegate = GraphDelegateBox(self)
        GraphHost.scheduleMainRunLoopObserver {
            delegate.value.updateGraph { host in
                host.flushTransactions()
            }
        }
    }

    func preferencesDidChange() {}
}
