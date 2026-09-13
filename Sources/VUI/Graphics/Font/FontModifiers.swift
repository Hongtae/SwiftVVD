//
//  File: FontModifiers.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

protocol FontModifier: Hashable, CodableByProxy {
    var tag: Font.DynamicModifierTag { get }
    func modify(descriptor: inout FontDescriptor, in context: Font.Context)
    func modify(traits: inout Font.ResolvedTraits)
}

extension FontModifier {
    func modify(traits: inout Font.ResolvedTraits) {}
}

protocol StaticFontModifier {
    static var tag: Font.StaticModifierTag { get }
    static func modify(descriptor: inout FontDescriptor, in context: Font.Context)
    static func modify(traits: inout Font.ResolvedTraits)
}

extension StaticFontModifier {
    static func modify(traits: inout Font.ResolvedTraits) {}
}

protocol UndoableStaticFontModifier: StaticFontModifier {
    static var undoableTag: Font.UndoableStaticModifierTag { get }
    static func undo(descriptor: inout FontDescriptor, in context: Font.Context)
    static func undo(traits: inout Font.ResolvedTraits)
}

extension UndoableStaticFontModifier {
    static var tag: Font.StaticModifierTag { .do(undoableTag) }
    static func undo(traits: inout Font.ResolvedTraits) {}
}

class AnyFontModifier: Hashable, @unchecked Sendable {
    private static let staticModifiers = Mutex<[ObjectIdentifier: AnyFontModifier]>([:])

    static func `static`<M: StaticFontModifier>(_ type: M.Type) -> AnyFontModifier {
        staticModifiers.withLock { values in
            let key = ObjectIdentifier(type)
            if let value = values[key] { return value }
            let value = AnyStaticFontModifier<M>()
            values[key] = value
            return value
        }
    }

    static func monospaced(_ active: Bool) -> AnyFontModifier {
        active ? .static(Font.MonospacedModifier.self) : .static(Font.UndoModifier<Font.MonospacedModifier>.self)
    }

    static var monospacedDigit: AnyFontModifier { .static(Font.MonospacedDigitModifier.self) }

    static func dynamic<M: FontModifier>(_ modifier: M) -> AnyFontModifier {
        AnyDynamicFontModifier(modifier)
    }

    var modifierType: ObjectIdentifier { preconditionFailure("Abstract font modifier") }

    var monospacedValue: Bool? {
        if self is AnyStaticFontModifier<Font.MonospacedModifier> { return true }
        if self is AnyStaticFontModifier<Font.UndoModifier<Font.MonospacedModifier>> { return false }
        return nil
    }

    var isMonospacedDigit: Bool { self is AnyStaticFontModifier<Font.MonospacedDigitModifier> }

    func modify(descriptor: inout FontDescriptor, in context: Font.Context) { preconditionFailure("Abstract font modifier") }
    func modify(traits: inout Font.ResolvedTraits) { preconditionFailure("Abstract font modifier") }
    func isEqual(to other: AnyFontModifier) -> Bool { preconditionFailure("Abstract font modifier") }
    func hash(into hasher: inout Hasher) { preconditionFailure("Abstract font modifier") }
    static func == (lhs: AnyFontModifier, rhs: AnyFontModifier) -> Bool { lhs.isEqual(to: rhs) }
}

final class AnyStaticFontModifier<M: StaticFontModifier>: AnyFontModifier, @unchecked Sendable {
    override var modifierType: ObjectIdentifier { ObjectIdentifier(M.self) }
    override func modify(descriptor: inout FontDescriptor, in context: Font.Context) { M.modify(descriptor: &descriptor, in: context) }
    override func modify(traits: inout Font.ResolvedTraits) { M.modify(traits: &traits) }
    override func isEqual(to other: AnyFontModifier) -> Bool { other is AnyStaticFontModifier<M> }
    override func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(M.self)) }
}

final class AnyDynamicFontModifier<M: FontModifier>: AnyFontModifier, @unchecked Sendable {
    override var modifierType: ObjectIdentifier { ObjectIdentifier(M.self) }
    let modifier: M
    init(_ modifier: M) { self.modifier = modifier }
    override func modify(descriptor: inout FontDescriptor, in context: Font.Context) { modifier.modify(descriptor: &descriptor, in: context) }
    override func modify(traits: inout Font.ResolvedTraits) { modifier.modify(traits: &traits) }
    override func isEqual(to other: AnyFontModifier) -> Bool { (other as? AnyDynamicFontModifier<M>)?.modifier == modifier }
    override func hash(into hasher: inout Hasher) { modifier.hash(into: &hasher) }
}

protocol FontWrapperProvider {
    var baseFont: Font { get }
}

extension Font {
    struct ModifierProvider<Modifier: FontModifier>: FontProvider, CodableByProxy, FontWrapperProvider {
        var base: Font
        var modifier: Modifier
        var baseFont: Font { base }
        var tag: ProviderTag { .modifier(modifier.tag) }
        var codingProxy: ModifierDefinition<Modifier> { ModifierDefinition(font: base, modifier: modifier) }

        func resolveDescriptor(in context: Context) -> FontDescriptor {
            var descriptor = base.resolveDescriptor(in: context)
            modifier.modify(descriptor: &descriptor, in: context)
            return descriptor
        }

        func removing<T: StaticFontModifier>(modifier: T.Type) -> any FontProvider {
            Self(base: base.removing(modifier: modifier), modifier: self.modifier)
        }
    }

    struct StaticModifierProvider<Modifier: StaticFontModifier>: FontProvider, CodableByProxy, FontWrapperProvider {
        var base: Font
        var baseFont: Font { base }
        var tag: ProviderTag { .staticModifier(Modifier.tag) }
        var codingProxy: CodingProxy { base.codingProxy }
        static func unwrap(codingProxy: CodingProxy) -> Self { Self(base: codingProxy.base) }

        func hash(into hasher: inout Hasher) { base.hash(into: &hasher) }

        func resolveDescriptor(in context: Context) -> FontDescriptor {
            var descriptor = base.resolveDescriptor(in: context)
            Modifier.modify(descriptor: &descriptor, in: context)
            return descriptor
        }

        func removing<T: StaticFontModifier>(modifier: T.Type) -> any FontProvider {
            let base = base.removing(modifier: modifier)
            if Modifier.self == T.self { return base.provider.baseProvider }
            return Self(base: base)
        }
    }

    struct WeightModifier: FontModifier {
        var weight: Weight
        var tag: DynamicModifierTag { .weight }
        var codingProxy: CodableFontWeight { weight.codingProxy }
        static func unwrap(codingProxy: CodableFontWeight) -> Self { Self(weight: codingProxy.base) }
        func modify(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.weight(weight) }
        func modify(traits: inout ResolvedTraits) { traits.weight = weight.value }
    }

    struct WidthModifier: FontModifier {
        var width: CGFloat
        var tag: DynamicModifierTag { .width }
        var codingProxy: CGFloat { width }
        static func unwrap(codingProxy: CGFloat) -> Self { Self(width: codingProxy) }
        func modify(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.width(width) }
        func modify(traits: inout ResolvedTraits) { traits.width = width }
    }

    struct StylisticAlternativeModifier: FontModifier {
        var alternative: _StylisticAlternative
        var tag: DynamicModifierTag { ._stylisticAlternative }
        var codingProxy: RawRepresentableProxy<_StylisticAlternative> { alternative.codingProxy }
        static func unwrap(codingProxy: RawRepresentableProxy<_StylisticAlternative>) -> Self {
            Self(alternative: codingProxy.base)
        }

        func modify(descriptor: inout FontDescriptor, in context: Context) {
            guard !context.shouldRedactContent else { return }
            let value = UInt32(alternative.rawValue)
            // Encode the selected set as the four-byte ss01...ss20 tag.
            let tag: UInt32 = 0x7373_3030 + (value / 10) * 256 + value % 10
            descriptor = descriptor.adding(features: [TypefaceShapingFeature(tag: tag)])
        }
    }

    struct BoldModifier: UndoableStaticFontModifier {
        static var undoableTag: UndoableStaticModifierTag { .bold }
        static func modify(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.symbolicTrait(2, active: true) }
        static func undo(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.symbolicTrait(2, active: false) }
        static func modify(traits: inout ResolvedTraits) { traits.weight = 0.4 }
        static func undo(traits: inout ResolvedTraits) { traits.weight = 0 }
    }

    struct ItalicModifier: UndoableStaticFontModifier {
        static var undoableTag: UndoableStaticModifierTag { .italic }
        static func modify(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.symbolicTrait(1, active: true) }
        static func undo(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.symbolicTrait(1, active: false) }
    }

    struct MonospacedModifier: UndoableStaticFontModifier {
        static var undoableTag: UndoableStaticModifierTag { .monospaced }
        static func modify(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.monospaced(true) }
        static func undo(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.monospaced(false) }
    }

    struct MonospacedDigitModifier: StaticFontModifier {
        static var tag: StaticModifierTag { .monospacedDigit }
        static let shapingFeatures = [TypefaceShapingFeature(tag: 0x746e_756d)]
        static func modify(descriptor: inout FontDescriptor, in context: Context) { descriptor = descriptor.adding(features: shapingFeatures) }
    }

    struct UndoModifier<Modifier: UndoableStaticFontModifier>: StaticFontModifier {
        static var tag: StaticModifierTag { .undo(Modifier.undoableTag) }
        static func modify(descriptor: inout FontDescriptor, in context: Context) { Modifier.undo(descriptor: &descriptor, in: context) }
    }
}

/// Supplies a text language when the font descriptor has none.
struct LanguageFontModifier: FontModifier {
    var identifier: String
    var tag: Font.DynamicModifierTag { .language }
    var codingProxy: String { identifier }
    static func unwrap(codingProxy: String) -> Self { Self(identifier: codingProxy) }
    func modify(descriptor: inout FontDescriptor, in context: Font.Context) {
        guard descriptor.language == nil else { return }
        descriptor = descriptor.withTypesetting(language: identifier)
    }
}

/// Retains the requested typesetting ratio on the font descriptor.
struct LanguageAwareLineHeightRatioFontModifier: FontModifier {
    let ratio: Double
    var tag: Font.DynamicModifierTag { .lineHeightRatio }
    var codingProxy: Double { ratio }
    static func unwrap(codingProxy: Double) -> Self { Self(ratio: codingProxy) }
    func modify(descriptor: inout FontDescriptor, in context: Font.Context) {
        descriptor = descriptor.withTypesetting(lineHeightRatio: ratio)
    }
}
