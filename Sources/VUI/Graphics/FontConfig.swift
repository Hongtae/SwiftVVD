//
//  File: FontConfig.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct BundledFontID: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

struct BundledFontWeightAxis: Equatable, Sendable {
    let tag: UInt32
    let minimum: CGFloat
    let maximum: CGFloat
}

struct BundledFontSource: Equatable, Sendable {
    let file: String
    let faceIndex: Int
    let localeFaceIndices: [String: Int]
    let isItalic: Bool
    let weight: CGFloat?
    let weightAxis: BundledFontWeightAxis?

    func faceIndex(for locale: Locale) -> Int {
        for candidate in FontFallbackConfiguration.candidateIdentifiers(
            for: locale
        ) {
            if let faceIndex = localeFaceIndices[candidate] {
                return faceIndex
            }
        }
        return faceIndex
    }

    fileprivate func weightDistance(from requestedWeight: CGFloat) -> CGFloat {
        if let weight {
            return abs(requestedWeight - weight)
        }
        guard let weightAxis else { return .infinity }
        if requestedWeight < weightAxis.minimum {
            return weightAxis.minimum - requestedWeight
        }
        if requestedWeight > weightAxis.maximum {
            return requestedWeight - weightAxis.maximum
        }
        return 0
    }

    fileprivate func selectionPriority(for requestedWeight: CGFloat) -> Int {
        if weight == requestedWeight {
            return 0
        }
        return weightAxis == nil ? 2 : 1
    }
}

struct BundledFontDescriptor: Equatable, Sendable {
    let sources: [BundledFontSource]
    let appliesSyntheticWeight: Bool

    func source(
        for requestedWeight: CGFloat,
        isItalic: Bool = false
    ) -> BundledFontSource {
        let matchingStyle = sources.filter { $0.isItalic == isItalic }
        let candidates = matchingStyle.isEmpty
            ? sources.filter { !$0.isItalic }
            : matchingStyle
        let regularWeight = Font.Weight.regular.value
        let requestedWeight = requestedWeight.isFinite
            ? requestedWeight
            : regularWeight
        return candidates.enumerated().min { lhs, rhs in
            let lhsDistance = lhs.element.weightDistance(
                from: requestedWeight
            )
            let rhsDistance = rhs.element.weightDistance(
                from: requestedWeight
            )
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            let lhsPriority = lhs.element.selectionPriority(
                for: requestedWeight
            )
            let rhsPriority = rhs.element.selectionPriority(
                for: requestedWeight
            )
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if let lhsWeight = lhs.element.weight,
               let rhsWeight = rhs.element.weight,
               lhsWeight != rhsWeight {
                // Resolve an equidistant missing master toward lighter faces
                // through regular, and toward heavier faces above regular.
                if requestedWeight <= regularWeight {
                    return lhsWeight < rhsWeight
                }
                return lhsWeight > rhsWeight
            }
            return lhs.offset < rhs.offset
        }!.element
    }
}

enum FontFallbackConfigurationError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidFontIdentifier(String)
    case emptyFontSources(BundledFontID)
    case invalidFontFile(BundledFontID, String)
    case invalidFaceIndex(BundledFontID, Int)
    case invalidFaceLocale(BundledFontID, String)
    case invalidWeightConfiguration(BundledFontID)
    case invalidWeightAxis(BundledFontID)
    case invalidDesign(String)
    case missingDefaultDesign
    case undefinedFont(BundledFontID)
    case invalidSystemFont(BundledFontID)
    case invalidMissingGlyphFont(BundledFontID)
    case invalidDefaultLocale(String)
    case invalidLocale(String)
    case emptyLocale(String)
    case duplicateFont(String, BundledFontID)
    case terminalFontInLocale(String)
}

struct FontFallbackConfiguration: Sendable {
    private struct FontFileSource: Decodable {
        struct WeightAxis: Decodable {
            let tag: String
            let minimum: CGFloat
            let maximum: CGFloat
        }

        let file: String
        let faceIndex: Int
        let localeFaceIndices: [String: Int]?
        let italic: Bool?
        let weight: CGFloat?
        let weightAxis: WeightAxis?
    }

    private struct FontFamilySource: Decodable {
        let sources: [FontFileSource]
        let syntheticWeight: Bool
    }

    private struct DesignSource: Decodable {
        let systemFont: String
        let locales: [String: [String]]
    }

    private struct Source: Decodable {
        let version: Int
        let fonts: [String: FontFamilySource]
        let defaultLocale: String
        let designs: [String: DesignSource]
        let missingGlyphFont: String
    }

    let version: Int
    let fontDescriptors: [BundledFontID: BundledFontDescriptor]
    let defaultLocale: String
    let systemFonts: [Font.Design: BundledFontID]
    let designLocales: [Font.Design: [String: [BundledFontID]]]
    let missingGlyphFont: BundledFontID

    var systemFont: BundledFontID {
        systemFont(for: .default)
    }

    init(data: Data) throws {
        let source = try JSONDecoder().decode(Source.self, from: data)
        guard source.version == 2 else {
            throw FontFallbackConfigurationError.unsupportedVersion(
                source.version
            )
        }

        var fontDescriptors: [BundledFontID: BundledFontDescriptor] = [:]
        for (identifier, font) in source.fonts {
            let fontID = BundledFontID(identifier)
            guard !identifier.isEmpty else {
                throw FontFallbackConfigurationError.invalidFontIdentifier(
                    identifier
                )
            }
            guard !font.sources.isEmpty else {
                throw FontFallbackConfigurationError.emptyFontSources(fontID)
            }

            var sources: [BundledFontSource] = []
            for source in font.sources {
                guard Self.isValidResourcePath(source.file) else {
                    throw FontFallbackConfigurationError.invalidFontFile(
                        fontID,
                        source.file
                    )
                }
                guard source.faceIndex >= 0 else {
                    throw FontFallbackConfigurationError.invalidFaceIndex(
                        fontID,
                        source.faceIndex
                    )
                }

                var localeFaceIndices: [String: Int] = [:]
                for (localeIdentifier, faceIndex) in
                    source.localeFaceIndices ?? [:] {
                    let canonical = Self.canonicalIdentifier(localeIdentifier)
                    guard !canonical.isEmpty,
                          Locale(identifier: localeIdentifier)
                            .language.languageCode != nil else {
                        throw FontFallbackConfigurationError.invalidFaceLocale(
                            fontID,
                            localeIdentifier
                        )
                    }
                    guard faceIndex >= 0 else {
                        throw FontFallbackConfigurationError.invalidFaceIndex(
                            fontID,
                            faceIndex
                        )
                    }
                    guard localeFaceIndices.updateValue(
                        faceIndex,
                        forKey: canonical
                    ) == nil else {
                        throw FontFallbackConfigurationError.invalidFaceLocale(
                            fontID,
                            localeIdentifier
                        )
                    }
                }

                let weight: CGFloat?
                let weightAxis: BundledFontWeightAxis?
                switch (source.weight, source.weightAxis) {
                case let (.some(sourceWeight), .none):
                    guard sourceWeight.isFinite else {
                        throw FontFallbackConfigurationError
                            .invalidWeightConfiguration(fontID)
                    }
                    weight = sourceWeight
                    weightAxis = nil
                case let (.none, .some(sourceAxis)):
                    guard let tag = Self.openTypeTag(sourceAxis.tag),
                          sourceAxis.minimum.isFinite,
                          sourceAxis.maximum.isFinite,
                          sourceAxis.minimum <= sourceAxis.maximum else {
                        throw FontFallbackConfigurationError.invalidWeightAxis(
                            fontID
                        )
                    }
                    weight = nil
                    weightAxis = BundledFontWeightAxis(
                        tag: tag,
                        minimum: sourceAxis.minimum,
                        maximum: sourceAxis.maximum
                    )
                case (.none, .none), (.some, .some):
                    throw FontFallbackConfigurationError
                        .invalidWeightConfiguration(fontID)
                }

                sources.append(BundledFontSource(
                    file: source.file,
                    faceIndex: source.faceIndex,
                    localeFaceIndices: localeFaceIndices,
                    isItalic: source.italic ?? false,
                    weight: weight,
                    weightAxis: weightAxis
                ))
            }

            guard sources.contains(where: { !$0.isItalic }) else {
                throw FontFallbackConfigurationError
                    .invalidWeightConfiguration(fontID)
            }
            for styleSources in Dictionary(
                grouping: sources,
                by: \.isItalic
            ).values {
                let staticWeights = styleSources.compactMap(\.weight)
                guard Set(staticWeights).count == staticWeights.count else {
                    throw FontFallbackConfigurationError
                        .invalidWeightConfiguration(fontID)
                }
            }
            if font.syntheticWeight {
                for styleSources in Dictionary(
                    grouping: sources,
                    by: \.isItalic
                ).values {
                    guard styleSources.count == 1,
                          styleSources[0].weight ==
                            Font.Weight.regular.value else {
                        throw FontFallbackConfigurationError
                            .invalidWeightConfiguration(fontID)
                    }
                }
            }

            fontDescriptors[fontID] = BundledFontDescriptor(
                sources: sources,
                appliesSyntheticWeight: font.syntheticWeight
            )
        }

        let missingGlyphFont = BundledFontID(source.missingGlyphFont)
        guard fontDescriptors[missingGlyphFont] != nil else {
            throw FontFallbackConfigurationError.invalidMissingGlyphFont(
                missingGlyphFont
            )
        }

        let defaultLocale = Self.canonicalIdentifier(source.defaultLocale)
        var systemFonts: [Font.Design: BundledFontID] = [:]
        var designLocales: [Font.Design: [String: [BundledFontID]]] = [:]
        for (identifier, designSource) in source.designs {
            guard let design = Self.design(for: identifier) else {
                throw FontFallbackConfigurationError.invalidDesign(identifier)
            }
            let systemFont = BundledFontID(designSource.systemFont)
            guard fontDescriptors[systemFont] != nil else {
                throw FontFallbackConfigurationError.invalidSystemFont(
                    systemFont
                )
            }

            var locales: [String: [BundledFontID]] = [:]
            for (localeIdentifier, fonts) in designSource.locales {
                let canonical = Self.canonicalIdentifier(localeIdentifier)
                guard !canonical.isEmpty,
                      Locale(identifier: localeIdentifier)
                        .language.languageCode != nil else {
                    throw FontFallbackConfigurationError.invalidLocale(
                        localeIdentifier
                    )
                }
                guard !fonts.isEmpty else {
                    throw FontFallbackConfigurationError.emptyLocale(
                        localeIdentifier
                    )
                }
                let fontIDs = fonts.map { BundledFontID($0) }
                for fontID in fontIDs where fontDescriptors[fontID] == nil {
                    throw FontFallbackConfigurationError.undefinedFont(fontID)
                }
                guard fontIDs.allSatisfy({ $0 != missingGlyphFont }) else {
                    throw FontFallbackConfigurationError
                        .terminalFontInLocale(localeIdentifier)
                }

                var unique: Set<BundledFontID> = []
                for font in fontIDs where !unique.insert(font).inserted {
                    throw FontFallbackConfigurationError.duplicateFont(
                        localeIdentifier,
                        font
                    )
                }
                guard locales.updateValue(
                    fontIDs,
                    forKey: canonical
                ) == nil else {
                    throw FontFallbackConfigurationError.invalidLocale(
                        localeIdentifier
                    )
                }
            }
            guard locales[defaultLocale] != nil else {
                throw FontFallbackConfigurationError.invalidDefaultLocale(
                    source.defaultLocale
                )
            }
            systemFonts[design] = systemFont
            designLocales[design] = locales
        }
        guard systemFonts[.default] != nil else {
            throw FontFallbackConfigurationError.missingDefaultDesign
        }

        self.version = source.version
        self.fontDescriptors = fontDescriptors
        self.defaultLocale = defaultLocale
        self.systemFonts = systemFonts
        self.designLocales = designLocales
        self.missingGlyphFont = missingGlyphFont
    }

    func systemFont(for design: Font.Design) -> BundledFontID {
        systemFonts[design] ?? systemFonts[.default]!
    }

    func fonts(
        for locale: Locale,
        design: Font.Design = .default
    ) -> [BundledFontID] {
        let locales = designLocales[design] ?? designLocales[.default]!
        for candidate in Self.candidateIdentifiers(for: locale) {
            if let fonts = locales[candidate] {
                return fonts
            }
        }
        return locales[defaultLocale]!
    }

    private static func design(for identifier: String) -> Font.Design? {
        switch identifier {
        case "default": .default
        case "serif": .serif
        case "rounded": .rounded
        case "monospaced": .monospaced
        default: nil
        }
    }

    private static func isValidResourcePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.contains("\\") else {
            return false
        }
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !components.isEmpty,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
              }),
              components.first?.contains(":") == false else {
            return false
        }
        return true
    }

    private static func openTypeTag(_ string: String) -> UInt32? {
        let bytes = Array(string.utf8)
        guard bytes.count == 4,
              bytes.allSatisfy({ (0x20...0x7e).contains($0) }) else {
            return nil
        }
        return bytes.reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
    }

    fileprivate static func canonicalIdentifier(
        _ identifier: String
    ) -> String {
        Locale.canonicalLanguageIdentifier(from: identifier)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    fileprivate static func candidateIdentifiers(
        for locale: Locale
    ) -> [String] {
        let language = locale.language.languageCode?.identifier.lowercased()
        let script = locale.language.script?.identifier.lowercased()
        let region = locale.region?.identifier.lowercased()
        var candidates: [String] = []

        func append(_ candidate: String?) {
            guard let candidate, !candidate.isEmpty,
                  !candidates.contains(candidate) else {
                return
            }
            candidates.append(candidate)
        }

        append(canonicalIdentifier(locale.identifier))
        if let language, let script, let region {
            append("\(language)-\(script)-\(region)")
        }
        if let language, let script {
            append("\(language)-\(script)")
        }
        if let language, let region {
            append("\(language)-\(region)")
        }
        append(language)
        return candidates
    }
}

struct BundledFontCatalog: Sendable {
    static let shared: Self = {
        guard let url = Bundle.module.url(
            forResource: "font-config",
            withExtension: "json",
            subdirectory: "Fonts"
        ) else {
            fatalError("The bundled font configuration is missing.")
        }
        do {
            return Self(
                configuration: try FontFallbackConfiguration(
                    data: Data(contentsOf: url)
                )
            )
        } catch {
            fatalError("Invalid bundled font configuration: \(error)")
        }
    }()

    let configuration: FontFallbackConfiguration

    func resource(
        for family: BundledFontID,
        locale: Locale,
        weight: CGFloat = Font.Weight.regular.value,
        isItalic: Bool = false
    ) -> BundledFontResource? {
        guard let descriptor = configuration.fontDescriptors[family],
              let resourceURL = Bundle.module.resourceURL else {
            return nil
        }
        let source = descriptor.source(
            for: weight,
            isItalic: isItalic
        )
        let url = resourceURL
            .appendingPathComponent("Fonts", isDirectory: true)
            .appendingPathComponent(source.file, isDirectory: false)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return BundledFontResource(
            url: url,
            faceIndex: source.faceIndex(for: locale)
        )
    }
}
