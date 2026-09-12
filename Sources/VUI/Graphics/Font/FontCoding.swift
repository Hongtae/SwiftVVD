//
//  File: FontCoding.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension Font: CodableByProxy {
    var codingProxy: CodingProxy { CodingProxy(base: self) }

    struct CodingProxy: CodableProxy {
        var base: Font
        init(base: Font) { self.base = base }
        init(from decoder: any Decoder) throws { base = Font(provider: try AnyFontBox.decode(from: decoder)) }
        func encode(to encoder: any Encoder) throws { try base.provider.encode(to: encoder) }
    }

    enum DynamicModifierTag: String, Codable {
        case weight, width, language, lineHeightRatio
    }

    enum UndoableStaticModifierTag: Codable, Hashable {
        case bold, italic, monospaced
    }

    enum StaticModifierTag: Codable {
        case undo(UndoableStaticModifierTag)
        case `do`(UndoableStaticModifierTag)
        case monospacedDigit
    }

    enum ProviderTag: CodableBoxTag {
        typealias Box = AnyFontBox
        case modifier(DynamicModifierTag)
        case staticModifier(StaticModifierTag)
        case system, style, named, `default`
        case typeface

        var box: any CodableBox<AnyFontBox>.Type {
            switch self {
            case .system: FontBox<SystemProvider>.self
            case .style: FontBox<TextStyleProvider>.self
            case .named: FontBox<NamedProvider>.self
            case .default: FontBox<DefaultProvider>.self
            case .typeface: FontBox<TypefaceFontProvider>.self
            case .modifier(.weight): FontBox<ModifierProvider<WeightModifier>>.self
            case .modifier(.width): FontBox<ModifierProvider<WidthModifier>>.self
            case .modifier(.language): FontBox<ModifierProvider<LanguageFontModifier>>.self
            case .modifier(.lineHeightRatio): FontBox<ModifierProvider<LanguageAwareLineHeightRatioFontModifier>>.self
            case .staticModifier(.do(.bold)): FontBox<StaticModifierProvider<BoldModifier>>.self
            case .staticModifier(.do(.italic)): FontBox<StaticModifierProvider<ItalicModifier>>.self
            case .staticModifier(.do(.monospaced)): FontBox<StaticModifierProvider<MonospacedModifier>>.self
            case .staticModifier(.undo(.bold)): FontBox<StaticModifierProvider<UndoModifier<BoldModifier>>>.self
            case .staticModifier(.undo(.italic)): FontBox<StaticModifierProvider<UndoModifier<ItalicModifier>>>.self
            case .staticModifier(.undo(.monospaced)): FontBox<StaticModifierProvider<UndoModifier<MonospacedModifier>>>.self
            case .staticModifier(.monospacedDigit): FontBox<StaticModifierProvider<MonospacedDigitModifier>>.self
            }
        }
    }

    struct SystemFontDefinition: CodableProxy {
        var size: CGFloat
        @ProxyCodable var weight: Weight?
        @ProxyCodable var design: Design?
        var textStyle: TextStyle?
        var maximumSize: CGFloat?
        var base: SystemProvider {
            SystemProvider(size: size, weight: weight, design: design, textStyle: textStyle, maximumSize: maximumSize)
        }
    }

    struct StyleDefinition: CodableProxy {
        var style: TextStyle
        @ProxyCodable var design: Design?
        @ProxyCodable var weight: Weight?
        var base: TextStyleProvider { TextStyleProvider(style: style, design: design, weight: weight) }
    }

    struct NamedFontDefinition: CodableProxy {
        var name: String
        var size: CGFloat
        var textStyle: TextStyle?
        var base: NamedProvider { NamedProvider(name: name, size: size, textStyle: textStyle) }
    }

    struct ModifierDefinition<Modifier: FontModifier>: CodableProxy {
        @ProxyCodable var font: Font
        @ProxyCodable var modifier: Modifier
        var base: ModifierProvider<Modifier> { ModifierProvider(base: font, modifier: modifier) }
    }
}

extension Font.Design: CodableByProxy {
    var codingProxy: String {
        switch self {
        case .default: "NSCTFontUIFontDesignDefault"
        case .serif: "NSCTFontUIFontDesignSerif"
        case .rounded: "NSCTFontUIFontDesignRounded"
        case .monospaced: "NSCTFontUIFontDesignMonospaced"
        }
    }

    static func unwrap(codingProxy: String) -> Self {
        switch codingProxy {
        case "NSCTFontUIFontDesignSerif": .serif
        case "NSCTFontUIFontDesignRounded": .rounded
        case "NSCTFontUIFontDesignMonospaced": .monospaced
        default: .default
        }
    }
}
