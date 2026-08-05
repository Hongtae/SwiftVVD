//
//  File: MergedInputs.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

// MARK: - Merged* AG Rules
// All three follow the same pattern: weak ref to self attr + strong raw of other attr.
// updateValue() reads both (registering AG dependencies), merges, returns result.
// When the weak ref is invalid (subgraph was deallocated), returns other's value unchanged.

// Merges two EnvironmentValues with the strong input taking priority over the weak fallback.
struct MergedEnvironment: Rule, AsyncAttribute {
    typealias Value = EnvironmentValues
    let selfWeak: AGWeakAttribute
    let otherRaw: UInt32

    var value: EnvironmentValues {
        let graph = _AGGraph.current!
        let otherAttr = Attribute<EnvironmentValues>(AGAttribute(rawValue: otherRaw))
        let otherEnv = otherAttr.value
        guard selfWeak.isValid(in: graph) else { return otherEnv.trackingCopy() }
        let selfEnv = Attribute<EnvironmentValues>(selfWeak.toStrong()).value
        var mergedList = otherEnv._plist
        mergedList.merge(selfEnv._plist)
        return EnvironmentValues.tracking(mergedList)
    }
}

// Merges two Transactions with the strong input taking priority over the weak fallback.
struct MergedTransaction: Rule, AsyncAttribute {
    typealias Value = Transaction
    let selfWeak: AGWeakAttribute
    let otherRaw: UInt32

    var value: Transaction {
        let graph = _AGGraph.current!
        let otherAttr = Attribute<Transaction>(AGAttribute(rawValue: otherRaw))
        let otherTx = otherAttr.value
        guard selfWeak.isValid(in: graph) else { return otherTx }
        let selfTx = Attribute<Transaction>(selfWeak.toStrong()).value
        var result = otherTx
        result.plist.merge(selfTx.plist)
        return result
    }
}

// Merges two Phases while preserving the receiver removal bit.
struct MergedPhase: Rule, AsyncAttribute {
    typealias Value = Phase
    let selfWeak: AGWeakAttribute
    let otherRaw: UInt32

    var value: Phase {
        let graph = _AGGraph.current!
        let otherAttr = Attribute<Phase>(AGAttribute(rawValue: otherRaw))
        let otherPhase = otherAttr.value
        guard selfWeak.isValid(in: graph) else { return otherPhase }
        var result = Attribute<Phase>(selfWeak.toStrong()).value
        result.merge(otherPhase)
        return result
    }
}
