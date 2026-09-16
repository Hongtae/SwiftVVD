//
//  File: TextSuffixModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct TextSuffixModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var suffix: Text.Suffix

    struct OptionalText: Rule {
        var _modifier: Attribute<TextSuffixModifier>

        var value: Text? { _modifier.value.suffix.text }
    }

    struct ResolvedTextSuffixFilter: Rule {
        var _modifier: Attribute<TextSuffixModifier>
        var _text: Attribute<ResolvedStyledText?>

        var value: ResolvedTextSuffix {
            _modifier.value.suffix.resolve(text: _text.value)
        }
    }

    struct ChildEnvironment: Rule {
        var _suffix: Attribute<ResolvedTextSuffix>
        var _environment: Attribute<EnvironmentValues>

        var value: EnvironmentValues {
            var environment = _environment.value.trackingCopy()
            environment[TextSuffixKey.self] = _suffix.value
            return environment
        }
    }

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("TextSuffixModifier._makeInputs requires an active _AGGraph context.")
        }
        let environment = inputs.cachedEnvironment.value.environment
        let text = graph.makeRule(OptionalText(_modifier: modifier._attribute))
        let resolved = graph.makeStatefulRule(ResolvedOptionalTextFilter(
            _text: text, _environment: environment,
            helper: ResolvedTextHelper(
                _time: inputs.time, _referenceDate: inputs[ReferenceDateInput.self],
                includeDefaultAttributes: true, allowsKeyColors: true,
                archiveOptions: inputs[ArchivedViewInput.self], features: .produceTextLayout)))
        let suffix = graph.makeRule(ResolvedTextSuffixFilter(_modifier: modifier._attribute, _text: resolved))
        let child = graph.makeRule(ChildEnvironment(_suffix: suffix, _environment: environment))
        inputs.cachedEnvironment = MutableBox(CachedEnvironment(environment: child))
        inputs.changedDebugProperties |= 0x20
    }
}

extension View {
    func textSuffix(_ suffix: Text.Suffix) -> some View {
        modifier(TextSuffixModifier(suffix: suffix))
    }
}
