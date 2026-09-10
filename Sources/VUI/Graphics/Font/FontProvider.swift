//
//  File: FontProvider.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol FontProvider: Hashable, Serializable {
    var tag: Font.ProviderTag { get }
    func resolveDescriptor(in context: Font.Context) -> FontDescriptor
    func resolveTraits(in context: Font.Context) -> Font.ResolvedTraits
    func removing<T: StaticFontModifier>(modifier: T.Type) -> any FontProvider
}

extension FontProvider {
    func resolveTraits(in context: Font.Context) -> Font.ResolvedTraits {
        Font.ResolvedTraits(resolveDescriptor(in: context))
    }

    func removing<T: StaticFontModifier>(modifier: T.Type) -> any FontProvider { self }
}

class AnyFontBox: AnyCodableBox, @unchecked Sendable {
    typealias Box = AnyFontBox
    typealias Tag = Font.ProviderTag

    var tag: Tag { preconditionFailure("Abstract font box") }
    var baseProvider: any FontProvider { preconditionFailure("Abstract font box") }
    func isEqual(to other: AnyFontBox) -> Bool { preconditionFailure("Abstract font box") }
    func hash(into hasher: inout Hasher) { preconditionFailure("Abstract font box") }
    func resolveDescriptor(in context: Font.Context) -> FontDescriptor { preconditionFailure("Abstract font box") }
    func resolveTraits(in context: Font.Context) -> Font.ResolvedTraits { preconditionFailure("Abstract font box") }
    func removing<T: StaticFontModifier>(modifier: T.Type) -> any FontProvider { preconditionFailure("Abstract font box") }
}

final class FontBox<Provider: FontProvider>: AnyFontBox, CodableBox, @unchecked Sendable {
    let base: Provider

    init(_ base: Provider) { self.base = base }
    override var tag: Font.ProviderTag { base.tag }
    override var baseProvider: any FontProvider { base }

    override func isEqual(to other: AnyFontBox) -> Bool {
        guard let other = other as? FontBox<Provider> else { return false }
        return base == other.base
    }

    override func hash(into hasher: inout Hasher) { base.hash(into: &hasher) }
    override func resolveDescriptor(in context: Font.Context) -> FontDescriptor { base.resolveDescriptor(in: context) }
    override func resolveTraits(in context: Font.Context) -> Font.ResolvedTraits { base.resolveTraits(in: context) }
    override func removing<T: StaticFontModifier>(modifier: T.Type) -> any FontProvider { base.removing(modifier: modifier) }

    func serialize(to encoder: any Encoder) throws { try base.serialize(to: encoder) }
    static func deserialize(from decoder: any Decoder) throws -> FontBox<Provider> {
        FontBox(try Provider.deserialize(from: decoder))
    }
}

extension Font {
    struct SystemProvider: FontProvider, CodableByProxy {
        var size: CGFloat
        var weight: Weight?
        var design: Design?
        var textStyle: TextStyle?
        var maximumSize: CGFloat?

        var tag: ProviderTag { .system }
        var codingProxy: SystemFontDefinition {
            SystemFontDefinition(size: size, weight: weight, design: design, textStyle: textStyle, maximumSize: maximumSize)
        }

        func effectiveSize(in context: Context) -> CGFloat {
            guard textStyle != nil else { return size }
            let size = size.rounded()
            return maximumSize.map { min(size, $0) } ?? size
        }

        func resolveDescriptor(in context: Context) -> FontDescriptor {
            context.fontDefinition.base.resolveSystemFont(size: effectiveSize(in: context), design: design, weight: weight, in: context)
        }

        func resolveTraits(in context: Context) -> ResolvedTraits {
            ResolvedTraits(pointSize: effectiveSize(in: context), weight: weight?.value ?? 0)
        }
    }

    struct TextStyleProvider: FontProvider, CodableByProxy {
        var style: TextStyle
        var design: Design?
        var weight: Weight?

        var tag: ProviderTag { .style }
        var codingProxy: StyleDefinition { StyleDefinition(style: style, design: design, weight: weight) }

        func resolveDescriptor(in context: Context) -> FontDescriptor {
            context.fontDefinition.base.resolveTextStyleFont(textStyle: style, design: design, weight: weight, in: context)
        }

        func resolveTraits(in context: Context) -> ResolvedTraits {
            context.fontDefinition.base.resolveTextStyleFontInfo(textStyle: style, design: design, weight: weight, in: context)
        }
    }

    struct NamedProvider: FontProvider, CodableByProxy {
        var name: String
        var size: CGFloat
        var textStyle: TextStyle?

        var tag: ProviderTag { .named }
        var codingProxy: NamedFontDefinition { NamedFontDefinition(name: name, size: size, textStyle: textStyle) }

        func resolveDescriptor(in context: Context) -> FontDescriptor {
            context.fontDefinition.base.resolveCustomFont(name: name, size: size, textStyle: textStyle, in: context)
        }
    }

    struct DefaultProvider: FontProvider, EmptySerializable {
        var tag: ProviderTag { .default }
        func resolveDescriptor(in context: Context) -> FontDescriptor {
            context.effectiveFont.resolveDescriptor(in: context)
        }
        func resolveTraits(in context: Context) -> ResolvedTraits {
            context.effectiveFont.resolveTraits(in: context)
        }
    }
}

/// Bridges retained rendering requests without storing engine resources in logical providers.
struct TypefaceFontProvider: FontProvider {
    let base: any TypefaceProvider
    let features: [TypefaceShapingFeature]

    init(_ base: any TypefaceProvider, features: [TypefaceShapingFeature] = []) {
        self.base = base
        self.features = features
    }

    var tag: Font.ProviderTag { .typeface }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.features == rhs.features && lhs.base.isEqual(to: rhs.base)
    }

    func hash(into hasher: inout Hasher) {
        base.hash(into: &hasher)
        hasher.combine(features)
    }

    func resolveDescriptor(in context: Font.Context) -> FontDescriptor {
        FontDescriptor(source: .typeface(base), pointSize: base.pointSize, shapingFeatures: features)
    }

    func serialize(to encoder: any Encoder) throws {
        throw EncodingError.invalidValue(base, .init(codingPath: encoder.codingPath,
                                                    debugDescription: "Engine font resources cannot be archived as logical font requests."))
    }

    static func deserialize(from decoder: any Decoder) throws -> Self {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                               debugDescription: "Engine font resources require an explicit resource source."))
    }
}
