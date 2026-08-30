//
//  File: ExternalMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// External menu contents are supplied by the presentation host. This view
// publishes only the stable source identity and its environment-resolved label.
struct ExternalMenu: View {
    var title: Text?
    var platformIdentifier: String

    init(
        _ titleKey: LocalizedStringKey,
        platformIdentifier: String
    ) {
        title = Text(titleKey)
        self.platformIdentifier = platformIdentifier
    }

    typealias Body = Never

    struct PlatformItemRepresentation: StatefulRule {
        typealias Value = PlatformItemList

        var _source: Attribute<ExternalMenu>
        var _environment: Attribute<EnvironmentValues>
        var tracker: PropertyList.Tracker

        mutating func updateValue() {
            let source = _source.value
            let environment = _environment.value
            if context.hasValue,
               !_AGGraph.currentStatefulInputChanged(_source.identifier),
               !tracker.hasDifferentUsedValues(environment._plist) {
                return
            }

            tracker.reset()
            let trackedEnvironment = EnvironmentValues(
                environment._plist,
                tracker: tracker
            )
            var item = PlatformItemList.Item(systemItem: .menu)
            item.platformIdentifier = source.platformIdentifier
            item.isExternal = true
            item.wantsPlatformInterfaceValidation = true
            if let title = source.title {
                item.label = NSAttributedString(
                    string: title._resolveText(in: trackedEnvironment)
                )
            }
            _AGGraph.setStatefulOutput(PlatformItemList(items: [item]))
        }
    }

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ExternalMenu._makeView called outside AG context")
        }
        var outputs = _ViewOutputs()
        guard inputs.preferences.keys.contains(PlatformItemList.Key.self) else {
            return outputs
        }
        let representation: Attribute<PlatformItemList> =
            graph.makeStatefulRule(
                PlatformItemRepresentation(
                    _source: view._attribute,
                    _environment:
                        inputs.base.cachedEnvironment.value.environment,
                    tracker: PropertyList.Tracker()
                )
            )
        outputs.writePlatformItemList(
            inputs: inputs,
            value: representation
        )
        return outputs
    }
}

extension ExternalMenu: PrimitiveView, UnaryView {}
