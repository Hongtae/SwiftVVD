//
//  File: LocalizationResolver.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Resolves the localization format subset consumed by localized text
/// storage on platforms whose Foundation port does not provide the localized
/// String and AttributedString initializers.
///
/// The resolver preserves translated positional argument indices instead of
/// flattening the whole format at once. Rich text consumers use those indices
/// to substitute retained Text and AttributedString values after formatting.
struct LocalizationResolver {
    /// Preserves whether formatting must apply replacement metadata to the
    /// entire result. A strings-dictionary variable resolves as one attributed
    /// replacement run even when its selected leaf contains surrounding text.
    struct LocalizedPattern {
        let value: String
        let formatsWholeReplacement: Bool
        /// Language metadata for the template, before retained rich arguments are substituted.
        var languageIdentifier: String? = nil
    }

    /// Distinguishes an absent strings-dictionary entry from an entry whose
    /// shape is outside the compatibility subset. Unsupported entries must not
    /// fall through to the native non-Darwin lookup path because that path
    /// cannot bridge dictionary values as localized format strings.
    enum StringsDictionaryLookup {
        case missing
        case resolved(LocalizedPattern)
        case unsupported
    }

    /// Carries only the localized run metadata consumed by VUI. Keeping this
    /// representation independent of Foundation's attributed-run storage lets
    /// non-Darwin clients resolve rich placeholders without depending on
    /// unavailable localized initializers or private attributed-string types.
    struct Result {
        struct Run {
            var text: String
            let replacementIndex: Int?
            let presentationIntent: _InlinePresentationIntent?
        }

        private(set) var runs: [Run] = []
        let languageIdentifier: String?

        var string: String {
            runs.reduce(into: String()) { $0.append($1.text) }
        }

        fileprivate mutating func append(
            _ text: String,
            replacementIndex: Int? = nil,
            presentationIntent: _InlinePresentationIntent? = nil
        ) {
            guard !text.isEmpty else { return }
            if let last = runs.last,
               last.replacementIndex == replacementIndex,
               last.presentationIntent == presentationIntent {
                runs[runs.count - 1].text.append(text)
            } else {
                runs.append(Run(
                    text: text,
                    replacementIndex: replacementIndex,
                    presentationIntent: presentationIntent
                ))
            }
        }

        /// Materializes the compatibility initializer result without
        /// enumerating Foundation attributed runs. VUI's non-Darwin localized
        /// text path consumes `runs` directly instead.
        func attributedString() -> AttributedString {
            var result = AttributedString()
            for run in runs {
                var segment = AttributedString(run.text)
                guard !segment.characters.isEmpty else { continue }
                let range = segment.startIndex..<segment.endIndex
                segment[range].languageIdentifier = languageIdentifier
                if let replacementIndex = run.replacementIndex {
                    segment[range].replacementIndex = replacementIndex
                }
                if let presentationIntent = run.presentationIntent {
                    segment[range][_InlinePresentationIntentAttribute.self] =
                        presentationIntent
                }
                result.append(segment)
            }
            return result
        }
    }

    private struct Placeholder {
        var endIndex: String.Index
        var argumentIndex: Int
        var format: String
    }

    static func resolve(
        pattern: LocalizedPattern,
        replacements: [any CVarArg],
        locale: Locale,
        applyReplacementIndexAttribute: Bool
    ) -> Result {
        var result = Result(languageIdentifier: pattern.languageIdentifier)
        let value = pattern.value

        // A value constructed without interpolation treats percent signs as
        // ordinary key text. Parsing is only needed when replacements exist.
        guard !replacements.isEmpty else {
            result.append(value)
            return result
        }

        // Native Foundation retains strings-dictionary context in its format
        // value. The compatibility loader instead selects a supported leaf and
        // carries this flag so both routes retain the same whole-result run.
        if pattern.formatsWholeReplacement || value.contains("%#@") {
            let formatted = String(
                format: value,
                locale: locale,
                arguments: replacements
            )
            result.append(
                formatted,
                replacementIndex:
                    applyReplacementIndexAttribute && replacements.count == 1
                    ? 1
                    : nil
            )
            return result
        }

        var literal = String()
        var cursor = value.startIndex
        var sequentialArgumentIndex = 0

        func appendLiteral() {
            guard !literal.isEmpty else { return }
            result.append(literal)
            literal.removeAll(keepingCapacity: true)
        }

        while cursor < value.endIndex {
            guard value[cursor] == "%" else {
                literal.append(value[cursor])
                cursor = value.index(after: cursor)
                continue
            }

            let next = value.index(after: cursor)
            guard next < value.endIndex else {
                literal.append("%")
                break
            }

            if value[next] == "%" {
                literal.append("%")
                cursor = value.index(after: next)
                continue
            }

            guard let placeholder = placeholder(
                in: value,
                startingAt: cursor,
                sequentialArgumentIndex: &sequentialArgumentIndex
            ) else {
                literal.append("%")
                cursor = next
                continue
            }

            guard replacements.indices.contains(placeholder.argumentIndex) else {
                literal.append(contentsOf: value[cursor...placeholder.endIndex])
                cursor = value.index(after: placeholder.endIndex)
                continue
            }

            let markdown = markdownIntent(
                before: &literal,
                after: placeholder.endIndex,
                in: value
            )
            let closingMarkerEnd = markdown.closingMarkerEnd
            appendLiteral()

            let replacement = replacements[placeholder.argumentIndex]
            let formatted = String(
                format: placeholder.format,
                locale: locale,
                arguments: [replacement]
            )
            result.append(
                formatted,
                replacementIndex: applyReplacementIndexAttribute
                    ? placeholder.argumentIndex + 1
                    : nil,
                presentationIntent: markdown.intent
            )
            cursor = closingMarkerEnd ?? value.index(after: placeholder.endIndex)
        }

        appendLiteral()
        return result
    }

    static func localizedPattern(
        forKey key: String,
        table: String?,
        bundle: Bundle,
        locale: Locale,
        replacements: [any CVarArg]
    ) -> LocalizedPattern {
        let candidates = localizationCandidates(
            from: bundle.localizations,
            for: locale
        )
        let lookupBundle: Bundle
        if let localization = candidates.first,
           let path = bundle.path(forResource: localization, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            lookupBundle = localizedBundle
        } else {
            lookupBundle = bundle
        }
        let tableName = table ?? "Localizable"
        let hasTable = lookupBundle.url(forResource: tableName, withExtension: "strings") != nil
            || lookupBundle.url(forResource: tableName, withExtension: "stringsdict") != nil
        let languageIdentifier: String?
        if hasTable {
            languageIdentifier = candidates.first
        } else {
#if canImport(Darwin)
            languageIdentifier = bundle.developmentLocalization
#else
            // Corelibs Foundation force-unwraps a missing development region.
            // Preserve its metadata rules without calling the trapping getter.
            let region = bundle.infoDictionary?["CFBundleDevelopmentRegion"] as? String
            languageIdentifier = region.flatMap { $0.isEmpty ? nil : $0 }
#endif
        }

#if !canImport(Darwin)
        switch stringsDictionaryLookup(
            forKey: key,
            table: table,
            bundle: lookupBundle,
            localization: nil,
            locale: locale,
            replacements: replacements
        ) {
        case var .resolved(pattern):
            pattern.languageIdentifier = languageIdentifier
            return pattern
        case .unsupported:
            return LocalizedPattern(
                value: key,
                formatsWholeReplacement: false,
                languageIdentifier: languageIdentifier
            )
        case .missing:
            break
        }
#endif

        let value = lookupBundle.localizedString(forKey: key, value: key, table: table)
        return LocalizedPattern(
            value: value,
            formatsWholeReplacement: value.contains("%#@"),
            languageIdentifier: languageIdentifier
        )
    }

    /// Returns the requested localization before platform-preferred fallbacks.
    ///
    /// Some non-Darwin Foundation ports enumerate `.lproj` directories but
    /// ignore the explicit preference during bundle negotiation. Match the
    /// requested locale against those enumerated identifiers first; retain the
    /// platform result afterward for development-language fallback behavior.
    static func localizationCandidates(
        from availableLocalizations: [String],
        for locale: Locale
    ) -> [String] {
        var candidates: [String] = []

#if !canImport(Darwin)
        if let explicit = explicitLocalization(
            from: availableLocalizations,
            for: locale
        ) {
            candidates.append(explicit)
        }
#endif

        for localization in Bundle.preferredLocalizations(
            from: availableLocalizations,
            forPreferences: [locale.identifier]
        ) where !candidates.contains(localization) {
            candidates.append(localization)
        }
        return candidates
    }

    /// Matches the exact identifier first, then the closest available variant
    /// of the same language. Script and region matches rank ahead of unrelated
    /// variants while source order resolves otherwise equal candidates.
    static func explicitLocalization(
        from availableLocalizations: [String],
        for locale: Locale
    ) -> String? {
        let requested = LocalizationIdentifier(locale.identifier)
        guard let requestedLanguage = requested.language else {
            return nil
        }

        let available = availableLocalizations.map {
            ($0, LocalizationIdentifier($0))
        }
        if let exact = available.first(where: {
            $0.1.canonicalIdentifier == requested.canonicalIdentifier
        }) {
            return exact.0
        }

        var best: (localization: String, score: Int)?
        for (localization, identifier) in available
        where identifier.language == requestedLanguage {
            var score = 0
            if identifier.script == requested.script {
                score += 4
            }
            if identifier.region == requested.region {
                score += 2
            } else if identifier.region != nil, requested.region != nil {
                score -= 1
            }
            if let current = best {
                if score > current.score {
                    best = (localization, score)
                }
            } else {
                best = (localization, score)
            }
        }
        return best?.localization
    }

    /// Loads the narrow strings-dictionary subset currently consumed by VUI.
    /// A single numeric variable may use an `other`-only table or the sampled
    /// English `one`/`other` rule. Other category sets and multiple variables
    /// remain unsupported until a focused native contract is added.
    static func stringsDictionaryLookup(
        forKey key: String,
        table: String?,
        bundle: Bundle,
        localization: String?,
        locale: Locale,
        replacements: [any CVarArg]
    ) -> StringsDictionaryLookup {
        let tableName = table ?? "Localizable"
        let tableURL: URL?
        if let localization {
            tableURL = bundle.url(
                forResource: tableName,
                withExtension: "stringsdict",
                subdirectory: nil,
                localization: localization
            )
        } else {
            tableURL = bundle.url(
                forResource: tableName,
                withExtension: "stringsdict"
            )
        }
        guard let tableURL else {
            return .missing
        }
        guard let data = try? Data(contentsOf: tableURL),
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let table = propertyList as? [String: Any] else {
            return .unsupported
        }
        guard let rawEntry = table[key] else {
            return .missing
        }
        guard let entry = rawEntry as? [String: Any] else {
            return .unsupported
        }

        guard replacements.count == 1,
              let localizedFormat =
                entry["NSStringLocalizedFormatKey"] as? String,
              let variable = stringsDictionaryVariable(
                in: localizedFormat
              ),
              let rule = entry[variable.name] as? [String: Any],
              rule["NSStringFormatSpecTypeKey"] as? String ==
                "NSStringPluralRuleType",
              let valueType =
                rule["NSStringFormatValueTypeKey"] as? String,
              integerPluralValueTypes.contains(valueType),
              let numericValue = numericValue(of: replacements[0]) else {
            return .unsupported
        }

        let reservedKeys: Set<String> = [
            "NSStringFormatSpecTypeKey",
            "NSStringFormatValueTypeKey",
        ]
        let categories = Set(rule.keys).subtracting(reservedKeys)
        let category: String
        if categories == ["other"] {
            category = "other"
        } else if categories.isSubset(of: ["one", "other"]),
                  categories.contains("other"),
                  locale.language.languageCode?.identifier == "en" {
            category = numericValue == 1 ? "one" : "other"
        } else {
            return .unsupported
        }

        guard let selectedFormat = rule[category] as? String else {
            return .unsupported
        }
        let value = localizedFormat.replacingOccurrences(
            of: variable.token,
            with: selectedFormat
        )
        guard !value.contains("%#@") else {
            return .unsupported
        }
        return .resolved(LocalizedPattern(
            value: value,
            formatsWholeReplacement: true
        ))
    }

    private struct LocalizationIdentifier {
        let canonicalIdentifier: String
        let language: String?
        let script: String?
        let region: String?

        init(_ identifier: String) {
            canonicalIdentifier = Locale.canonicalLanguageIdentifier(
                from: identifier
            ).lowercased()
            let locale = Locale(identifier: identifier)
            language = locale.language.languageCode?.identifier.lowercased()
            script = locale.language.script?.identifier.lowercased()
            region = locale.region?.identifier.lowercased()
        }
    }

    private static let integerPluralValueTypes: Set<String> = [
        "d", "i", "ld", "li", "lld", "lli",
        "u", "lu", "llu",
    ]

    private static func stringsDictionaryVariable(
        in format: String
    ) -> (token: String, name: String)? {
        guard let start = format.range(of: "%#@"),
              let end = format[start.upperBound...].firstIndex(of: "@") else {
            return nil
        }
        let name = String(format[start.upperBound..<end])
        guard !name.isEmpty else { return nil }
        let tokenEnd = format.index(after: end)
        return (String(format[start.lowerBound..<tokenEnd]), name)
    }

    private static func numericValue(of value: any CVarArg) -> Double? {
        switch value {
        case let value as Int:
            return Double(value)
        case let value as Int8:
            return Double(value)
        case let value as Int16:
            return Double(value)
        case let value as Int32:
            return Double(value)
        case let value as Int64:
            return Double(value)
        case let value as UInt:
            return Double(value)
        case let value as UInt8:
            return Double(value)
        case let value as UInt16:
            return Double(value)
        case let value as UInt32:
            return Double(value)
        case let value as UInt64:
            return Double(value)
        case let value as Float:
            return Double(value)
        case let value as Double:
            return value
        case let value as CGFloat:
            return Double(value)
        default:
            return nil
        }
    }

    private static func placeholder(
        in pattern: String,
        startingAt start: String.Index,
        sequentialArgumentIndex: inout Int
    ) -> Placeholder? {
        let conversions = "diouxXfFeEgGaAcCsSp@"
        var cursor = pattern.index(after: start)
        var positionalArgumentIndex: Int?
        var formatStart = cursor

        let digitsStart = cursor
        while cursor < pattern.endIndex, pattern[cursor].isNumber {
            cursor = pattern.index(after: cursor)
        }
        if cursor > digitsStart,
           cursor < pattern.endIndex,
           pattern[cursor] == "$",
           let position = Int(pattern[digitsStart..<cursor]),
           position > 0 {
            positionalArgumentIndex = position - 1
            cursor = pattern.index(after: cursor)
            formatStart = cursor
        } else {
            cursor = digitsStart
        }

        while cursor < pattern.endIndex {
            let character = pattern[cursor]
            if conversions.contains(character) {
                let argumentIndex: Int
                if let positionalArgumentIndex {
                    argumentIndex = positionalArgumentIndex
                } else {
                    argumentIndex = sequentialArgumentIndex
                    sequentialArgumentIndex += 1
                }
                let suffix = pattern[formatStart...cursor]
                return Placeholder(
                    endIndex: cursor,
                    argumentIndex: argumentIndex,
                    format: "%" + suffix
                )
            }
            cursor = pattern.index(after: cursor)
        }
        return nil
    }

    private static func markdownIntent(
        before literal: inout String,
        after placeholderEnd: String.Index,
        in pattern: String
    ) -> (
        intent: _InlinePresentationIntent?,
        closingMarkerEnd: String.Index?
    ) {
        let after = pattern.index(after: placeholderEnd)
        for markerLength in [3, 2, 1] {
            let marker = String(repeating: "*", count: markerLength)
            guard literal.hasSuffix(marker),
                  pattern[after...].hasPrefix(marker) else {
                continue
            }

            literal.removeLast(markerLength)
            var closingMarkerEnd = after
            for _ in 1..<markerLength {
                closingMarkerEnd = pattern.index(after: closingMarkerEnd)
            }

            var intent = _InlinePresentationIntent()
            if markerLength >= 2 {
                intent.insert(.stronglyEmphasized)
            }
            if markerLength == 1 || markerLength == 3 {
                intent.insert(.emphasized)
            }
            return (intent, pattern.index(after: closingMarkerEnd))
        }
        return (nil, nil)
    }
}
