//
//  File: RendererLeafView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol RendererLeafView: ContentResponder, PrimitiveView, UnaryView {
    /// Ignored because the framework does not use `MainActor`.
    static var requiresMainThread: Bool { get }
    func content() -> DisplayList.Content.Value
}

extension RendererLeafView {
    static var requiresMainThread: Bool { false }

    static func makeLeafView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self).makeLeafView called outside an active _AGGraph context.")
        }

        var outputs = _ViewOutputs()

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value

        if inputs.preferences.keys.contains(DisplayList.Key.self) {
            let position = cachedEnvironment.animatedPosition(for: inputs)
            let size = cachedEnvironment.animatedCGSize(for: inputs)
            cachedEnvironmentAttribute.value = cachedEnvironment
            let displayList = graph.makeStatefulRule(
                LeafDisplayList(
                    identity: .none,
                    _view: view._attribute,
                    _position: position,
                    _size: size,
                    _containerPosition: inputs.containerPosition,
                    options: inputs[DisplayList.Options.self],
                    contentSeed: DisplayList.Seed()
                )
            )
            outputs.preferences.append(
                DisplayList.Key.self,
                node: displayList.identifier
            )
        }

        if inputs.preferences.keys.contains(ViewRespondersKey.self) {
            let size = cachedEnvironment.animatedSize(for: inputs)
            let position = cachedEnvironment.animatedPosition(for: inputs)
            cachedEnvironmentAttribute.value = cachedEnvironment
            let filter = LeafResponderFilter(
                _data: view._attribute,
                _size: size,
                _position: position,
                _transform: inputs.transform
            )
            let responders = graph.makeStatefulRule(filter)
            outputs.preferences.append(
                ViewRespondersKey.self,
                node: responders.identifier
            )
        }

        return outputs
    }
}

private struct LeafDisplayList<Content: RendererLeafView>: StatefulRule {
    typealias Value = DisplayList

    var identity: _DisplayList_Identity
    var _view: Attribute<Content>
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var _containerPosition: Attribute<CGPoint>
    var options: DisplayList.Options
    var contentSeed: DisplayList.Seed

    mutating func updateValue() {
        let view = _view.value
        let position = _position.value
        let containerPosition = _containerPosition.value
        let size = _size.value
        var list = DisplayList()

        guard size.width > 0, size.height > 0 else {
            _AGGraph.setStatefulOutput(list)
            return
        }

        let origin = CGPoint(
            x: position.x - containerPosition.x,
            y: position.y - containerPosition.y
        )
        let frame = CGRect(origin: origin, size: size)
        switch view.content() {
        case .color(let color):
            list.appendShapeItem(
                path: Path(frame),
                role: .fill,
                style: color.color,
                bounds: frame,
                fillStyle: FillStyle(antialiased: color.isAntialiased)
            )
        default:
            break
        }
        _AGGraph.setStatefulOutput(list)
    }
}

struct LeafResponderFilter<Data: ContentResponder>: StatefulRule {
    typealias Value = [ViewResponder]

    var _data: Attribute<Data>
    var _size: Attribute<ViewSize>
    var _position: Attribute<CGPoint>
    var _transform: Attribute<ViewTransform>
    lazy var responder = LeafViewResponder<Data>()

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        let dataChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_data.identifier)
        let sizeChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_size.identifier)
        let positionChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_position.identifier)
        let transformChanged = isInitialValue ||
            _AGGraph.currentStatefulInputChanged(_transform.identifier)

        responder.helper.update(
            data: (value: _data.value, changed: dataChanged),
            size: (value: _size.value, changed: sizeChanged),
            position: (value: _position.value, changed: positionChanged),
            transform: (value: _transform.value, changed: transformChanged),
            parent: responder
        )
        if isInitialValue {
            _AGGraph.setStatefulOutput([responder])
        }
    }
}
