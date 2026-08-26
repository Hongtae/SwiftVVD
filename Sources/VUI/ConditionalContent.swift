//
//  File: ConditionalContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct _ConditionalContent<TrueContent, FalseContent> {
    enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }
    let storage: Storage
}

/// Adapts conditional child construction to the input and output channels of
/// one graph-producing protocol.
protocol ConditionalContentProvider {
    associatedtype TrueContent
    associatedtype FalseContent
    associatedtype Inputs
    associatedtype Outputs

    var inputs: Inputs { get }
    var outputs: Outputs { get }

    func detachOutputs()
    func attachOutputs(to outputs: Outputs)
    func makeChildInputs() -> Inputs
    func makeTrueOutputs(
        child: Attribute<TrueContent>,
        inputs: Inputs
    ) -> Outputs
    func makeFalseOutputs(
        child: Attribute<FalseContent>,
        inputs: Inputs
    ) -> Outputs
}

extension _ConditionalContent {
    /// Retains the selected value together with the graph nodes that were
    /// created for that branch.
    struct Info {
        var content: _ConditionalContent
        var subgraph: AGSubgraphRef

        func matches(_ other: _ConditionalContent) -> Bool {
            switch (content.storage, other.storage) {
            case (.trueContent, .trueContent),
                 (.falseContent, .falseContent):
                return true
            default:
                return false
            }
        }
    }

    /// Owns the active branch and rewires protocol-specific outputs when the
    /// conditional changes cases.
    struct Container<Provider: ConditionalContentProvider>:
        StatefulRule,
        AsyncAttribute
    where Provider.TrueContent == TrueContent,
          Provider.FalseContent == FalseContent {
        typealias Value = Info

        var _content: Attribute<_ConditionalContent>
        var provider: Provider
        var parentSubgraph: AGSubgraphRef

        init(
            content: Attribute<_ConditionalContent>,
            provider: Provider
        ) {
            guard let parentSubgraph = AGSubgraph.current else {
                fatalError(
                    "_ConditionalContent.Container requires a current parent subgraph"
                )
            }
            self._content = content
            self.provider = provider
            self.parentSubgraph = parentSubgraph
        }

        mutating func updateValue() {
            guard let graph = _AGGraph.current else {
                fatalError(
                    "_ConditionalContent.Container evaluated outside _AGGraph context"
                )
            }

            let nextContent = _content.value
            if let current = _AGGraph.currentStatefulOutput(Info.self) {
                if current.matches(nextContent) {
                    _AGGraph.setStatefulOutput(
                        Info(
                            content: nextContent,
                            subgraph: current.subgraph
                        )
                    )
                    return
                }

                provider.detachOutputs()
                current.subgraph.willRemove()
                current.subgraph.invalidate()
                graph.drainActionOutbox()
                current.subgraph.removeFromParent()
            }

            _AGGraph.setStatefulOutput(makeInfo(nextContent, graph: graph))
        }

        private func makeInfo(
            _ content: _ConditionalContent,
            graph: _AGGraph
        ) -> Info {
            let subgraph = AGSubgraph.withCurrent(parentSubgraph) {
                AGSubgraph()
            }
            let childInputs = provider.makeChildInputs()
            let childOutputs = AGSubgraph.withCurrent(subgraph) {
                switch content.storage {
                case .trueContent(let value):
                    let child: Attribute<TrueContent> = graph.makeStatefulRule(
                        TrueChild(_info: attribute)
                    )
                    child.setValue(value)
                    return provider.makeTrueOutputs(
                        child: child,
                        inputs: childInputs
                    )
                case .falseContent(let value):
                    let child: Attribute<FalseContent> = graph.makeStatefulRule(
                        FalseChild(_info: attribute)
                    )
                    child.setValue(value)
                    return provider.makeFalseOutputs(
                        child: child,
                        inputs: childInputs
                    )
                }
            }
            provider.attachOutputs(to: childOutputs)
            return Info(content: content, subgraph: subgraph)
        }
    }

    struct TrueChild: StatefulRule, AsyncAttribute {
        typealias Value = TrueContent

        var _info: Attribute<Info>

        mutating func updateValue() {
            guard case let .trueContent(content) = _info.value.content.storage else {
                return
            }
            _AGGraph.setStatefulOutput(content)
        }
    }

    struct FalseChild: StatefulRule, AsyncAttribute {
        typealias Value = FalseContent

        var _info: Attribute<Info>

        mutating func updateValue() {
            guard case let .falseContent(content) = _info.value.content.storage else {
                return
            }
            _AGGraph.setStatefulOutput(content)
        }
    }
}
