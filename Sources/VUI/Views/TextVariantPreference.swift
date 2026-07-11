//
//  File: TextVariantPreference.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol TextVariantPreference {
    var _preference: _TextVariantPreference<Self> { get }
}

public struct _TextVariantPreference<Preference>: Sendable
where Preference: TextVariantPreference {
}

public struct FixedTextVariant: TextVariantPreference, Sendable {
    public var _preference: _TextVariantPreference<Self> {
        _TextVariantPreference()
    }
}

public struct SizeDependentTextVariant: TextVariantPreference, Sendable {
    public var _preference: _TextVariantPreference<Self> {
        _TextVariantPreference()
    }
}

extension TextVariantPreference where Self == FixedTextVariant {
    public static var fixed: FixedTextVariant {
        FixedTextVariant()
    }
}

extension TextVariantPreference where Self == SizeDependentTextVariant {
    public static var sizeDependent: SizeDependentTextVariant {
        SizeDependentTextVariant()
    }
}

extension Text {
    public func textVariant<V>(_ preference: V) -> some View
    where V: TextVariantPreference {
        preference._preference.body(self)
    }
}

extension _TextVariantPreference {
    @ViewBuilder
    func body<Content>(_ content: Content) -> some View
    where Content: View {
        if Preference.self == SizeDependentTextVariant.self {
            content.modifier(VariantThatFitsModifier())
        } else {
            content
        }
    }
}

struct VariantThatFitsFlag: GraphInput {
    typealias Value = Bool

    static var defaultValue: Bool {
        false
    }
}

struct VariantThatFitsModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[VariantThatFitsFlag.self] = true
    }
}
