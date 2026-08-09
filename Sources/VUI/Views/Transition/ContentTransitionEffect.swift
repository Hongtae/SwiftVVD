//
//  File: ContentTransitionEffect.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Modifier protocol for renderer effects that rewrite child DisplayList output.
protocol _RendererEffect: MultiViewModifier, PrimitiveViewModifier where Body == Never {
    func effectValue(size: CGSize) -> DisplayList.Effect
    static var isolatesChildPosition: Bool { get }
    static var disabledForFlattenedContent: Bool { get }
    static var preservesEmptyContent: Bool { get }
    static var isScrapeable: Bool { get }
    var scrapeableContent: ScrapeableContent.Content? { get }
}

extension _RendererEffect {
    static var isolatesChildPosition: Bool { false }
    static var disabledForFlattenedContent: Bool { false }
    static var preservesEmptyContent: Bool { false }
    static var isScrapeable: Bool { false }
    var scrapeableContent: ScrapeableContent.Content? { nil }
}

protocol RendererEffect: Animatable, _RendererEffect {}

extension RendererEffect {
    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _RendererEffectSupport.makeView(
            effect: modifier,
            inputs: inputs,
            body: body
        )
    }
}

struct _GeometryGroupEffect: Equatable, RendererEffect {
    typealias AnimatableData = EmptyAnimatableData
    typealias Body = Never

    static var isolatesChildPosition: Bool { true }

    func effectValue(size: CGSize) -> DisplayList.Effect {
        .geometryGroup
    }
}

private struct RendererEffectDisplayList<Effect: _RendererEffect>:
    Rule, AsyncAttribute {
    var identity: _DisplayList_Identity
    var _effect: Attribute<Effect>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _containerPosition: Attribute<CGPoint>
    var _environment: Attribute<EnvironmentValues>
    var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>
    var _content: OptionalAttribute<DisplayList>
    var options: DisplayList.Options
    var localID: ScrapeableID
    var parentID: ScrapeableID

    var value: DisplayList {
        let content = _content.value ?? DisplayList()
        guard !content.items.isEmpty || Effect.preservesEmptyContent else {
            return DisplayList()
        }

        let version = DisplayList.Version(forUpdate: ())
        let size = _size.value.value
        let effect: DisplayList.Effect
        if Effect.disabledForFlattenedContent,
           content.containsFlattenedContent {
            effect = .geometryGroup
        } else {
            let proxy = GeometryProxy(
                owner: context.attribute.identifier,
                size: _size,
                environment: _environment,
                transform: _transform,
                position: _position,
                safeAreaInsets: _safeAreaInsets.attribute,
                seed: UInt32(truncatingIfNeeded: version.value)
            )
            effect = ThreadGeometryProxyData.withValue(proxy) {
                _effect.value.effectValue(size: size)
            }
        }

        let position = _position.value
        let containerPosition = _containerPosition.value
        let origin = CGPoint(
            x: position.x - containerPosition.x,
            y: position.y - containerPosition.y
        )
        var item = DisplayList.Item(
            effect: effect,
            contents: content,
            frame: CGRect(origin: origin, size: size),
            identity: identity,
            version: version
        )
        item.canonicalize(options: options)

        var result = DisplayList()
        result.items.append(item)
        result.recordInterpolationBounds(item.frame)
        result.numericValue = content.numericValue
        return result
    }
}

struct ResetPositionTransform: Rule, AsyncAttribute {
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>

    var value: ViewTransform {
        var transform = _transform.value
        let position = _position.value
        transform.offsetPosition(
            by: CGSize(width: -position.x, height: -position.y)
        )
        return transform
    }
}

private extension DisplayList {
    var containsFlattenedContent: Bool {
        for item in items {
            switch item.value {
            case let .content(content):
                if case .flattened = content.value {
                    return true
                }
            case let .effect(_, contents):
                if contents.containsFlattenedContent {
                    return true
                }
            case let .states(states):
                if states.contains(where: { $0.1.containsFlattenedContent }) {
                    return true
                }
            case .empty:
                break
            }
        }
        return false
    }
}

// Shared _AGGraph plumbing for renderer-effect modifiers.
enum _RendererEffectSupport {
    static func makeView<Effect: _RendererEffect>(
        effect: _GraphValue<Effect>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Effect.self)._makeView called outside an active _AGGraph context.")
        }

        guard inputs.preferences.keys.contains(DisplayList.Key.self) else {
            return body(_Graph(), inputs)
        }

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let childPosition = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment

        var childInputs = inputs
        if Effect.isolatesChildPosition {
            childInputs.transform = graph.makeRule(
                ResetPositionTransform(
                    _position: childPosition,
                    _transform: inputs.transform
                )
            )
            guard let zeroPoint = ViewGraph.current.zeroPointAttr else {
                fatalError(
                    "RendererEffect requires an instantiated ViewGraph zero point."
                )
            }
            var environment = cachedEnvironmentAttribute.value
            let pixelLength = environment.attribute(
                id: .pixelLength,
                \.animationPixelLength
            )
            cachedEnvironmentAttribute.value = environment
            childInputs.position = zeroPoint
            childInputs.containerPosition = zeroPoint
            childInputs.size = graph.makeRule(
                RoundedSize(
                    _position: inputs.position,
                    _size: inputs.size,
                    _pixelLength: pixelLength
                )
            )
            childInputs.base.options.formUnion(
                _GraphInputs.Options(rawValue: 0x1c)
            )
        } else {
            childInputs.containerPosition = childPosition
        }

        let parentID = inputs.scrapeableParentID
        let localID: ScrapeableID
        let isScrapeable = Effect.isScrapeable && inputs.isScrapeable
        if isScrapeable {
            localID = ScrapeableID()
            childInputs.scrapeableParentID = localID
        } else {
            localID = .none
        }

        var outputs = body(_Graph(), childInputs)
        guard let content = outputs.preferences.reducedValue(
            for: DisplayList.Key.self,
            in: graph
        ) else {
            return outputs
        }

        cachedEnvironment = cachedEnvironmentAttribute.value
        let position = cachedEnvironment.animatedPosition(for: inputs)
        let size = cachedEnvironment.animatedSize(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment

        var identityInputs = inputs
        let displayList = graph.makeRule(
            RendererEffectDisplayList(
                identity: identityInputs.pushIdentity(),
                _effect: effect._attribute,
                _position: position,
                _size: size,
                _transform: inputs.transform,
                _containerPosition: inputs.containerPosition,
                _environment: cachedEnvironment.environment,
                _safeAreaInsets: inputs.safeAreaInsets,
                _content: OptionalAttribute(content),
                options: inputs[DisplayList.Options.self],
                localID: localID,
                parentID: parentID
            )
        )
        if isScrapeable {
            displayList.setFlags(.scrapeable, mask: .scrapeable)
        }
        outputs.preferences.setValue(
            displayList.identifier,
            for: DisplayList.Key.self
        )
        return outputs
    }

    static func makeViewList<Effect: _RendererEffect>(
        modifier: _GraphValue<Effect>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("\(Effect.self)._makeViewList called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }

}

// Renderer-effect modifier that marks a display list with an active content-transition state.
struct ContentTransitionEffect: _RendererEffect, MultiViewModifier {
    var state: ContentTransition.State

    init(state: ContentTransition.State) {
        self.state = state
    }

    func effectValue(size: CGSize) -> DisplayList.Effect {
        .contentTransition(state)
    }

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _RendererEffectSupport.makeView(
            effect: modifier,
            inputs: inputs,
            body: body
        )
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _RendererEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}
