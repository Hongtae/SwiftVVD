//
//  File: LimitedAvailabilityCommandContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Keeps an availability-limited command value behind a stable graph type.
/// The concrete command type is recovered only inside the retained child graph.
struct LimitedAvailabilityCommandContent: Commands {
    fileprivate var storage: LimitedAvailabilityCommandContentStorageBase

    init<Content: Commands>(erasing content: Content) {
        storage = LimitedAvailabilityCommandContentStorage(content: content)
    }

    typealias Body = Never

    var body: Never {
        fatalError("LimitedAvailabilityCommandContent may not have Body == Never")
    }

    nonisolated static func _makeCommands(
        content: _GraphValue<Self>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LimitedAvailabilityCommandContent._makeCommands called outside _AGGraph context")
        }
        guard let parentGraph = AGSubgraphRef.current else {
            fatalError("LimitedAvailabilityCommandContent._makeCommands requires a current parent subgraph")
        }

        let preferences = inputs.preferences.makeIndirectOutputs()
        let outputs = _CommandsOutputs(preferences: preferences)
        let indirect: Attribute<()> = graph.makeStatefulRule(
            IndirectOutputs(
                _content: content._attribute,
                parentGraph: parentGraph,
                inputs: inputs,
                outputs: outputs,
                childSubgraph: nil
            )
        )
        outputs.preferences.setIndirectDependency(indirect.identifier)
        return outputs
    }

    func _resolve(into resolved: inout _ResolvedCommands) {
        fatalError("LimitedAvailabilityCommandContent supports graph resolution only")
    }

    /// Lazily constructs the erased command's graph in a dedicated child
    /// subgraph, then connects its concrete preferences to stable placeholders.
    private struct IndirectOutputs: StatefulRule, AsyncAttribute {
        typealias Value = Void

        var _content: Attribute<LimitedAvailabilityCommandContent>
        var parentGraph: AGSubgraphRef
        var inputs: _CommandsInputs
        var outputs: _CommandsOutputs
        var childSubgraph: AGSubgraphRef?

        mutating func updateValue() {
            guard _AGGraph.current != nil else {
                fatalError("LimitedAvailabilityCommandContent.IndirectOutputs evaluated outside _AGGraph context")
            }
            guard childSubgraph == nil else { return }

            let childSubgraph = AGSubgraphRef(parent: parentGraph)
            self.childSubgraph = childSubgraph

            var childInputs = inputs
            childInputs.base.copyCaches()
            let childOutputs = AGSubgraphRef.withCurrent(childSubgraph) {
                let erased = _content.value
                return erased.storage.makeCommands(
                    content: _GraphValue(_attribute: _content),
                    inputs: childInputs
                )
            }
            childOutputs.preferences.attachIndirectOutputs(
                to: outputs.preferences
            )
            _AGGraph.setStatefulOutput(())
        }
    }
}

/// Abstract dispatch point retained by the erased command carrier.
fileprivate class LimitedAvailabilityCommandContentStorageBase {
    func makeCommands(
        content: _GraphValue<LimitedAvailabilityCommandContent>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        fatalError("abstract LimitedAvailabilityCommandContent storage")
    }
}

/// Recovers one concrete command type from the outer erased graph value.
fileprivate final class LimitedAvailabilityCommandContentStorage<Content: Commands>:
    LimitedAvailabilityCommandContentStorageBase
{
    var content: Content

    init(content: Content) {
        self.content = content
    }

    override func makeCommands(
        content: _GraphValue<LimitedAvailabilityCommandContent>,
        inputs: _CommandsInputs
    ) -> _CommandsOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LimitedAvailabilityCommandContent storage called outside _AGGraph context")
        }
        let child: Attribute<Content> = graph.makeRule(
            Child(_content: content._attribute)
        )
        return Content._makeCommands(
            content: _GraphValue(_attribute: child),
            inputs: inputs
        )
    }

    /// Projects this storage's concrete command from the erased graph value.
    private struct Child: Rule, AsyncAttribute {
        var _content: Attribute<LimitedAvailabilityCommandContent>

        var value: Content {
            guard let storage = _content.value.storage
                as? LimitedAvailabilityCommandContentStorage<Content> else {
                fatalError("limited-availability command storage type changed")
            }
            return storage.content
        }
    }
}
