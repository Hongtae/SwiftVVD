import Foundation
import XCTest
import VVD
@testable import VUI

// ASSERTIONS textAccessibilitySpeechPublic27Observed

final class TextAccessibilitySpeechOwnerTests: XCTestCase {
    private let punctuationKey = NSAttributedString.Key("AXPunctuation")
    private let spellOutKey = NSAttributedString.Key("AXSpellOut")
    private let pitchKey = NSAttributedString.Key("AXPitch")
    private let priorityKey = NSAttributedString.Key("AXAnnouncementPriority")
    private let headingKey = NSAttributedString.Key("AXHeadingLevel")
    private let contextKey = NSAttributedString.Key("AXTextualContext")
    private let labelKey = NSAttributedString.Key("SwiftUI.accessibilityLabel")
    private var previousApp: (any AppContext)?
    private var bundleURLs: [URL] = []

    override func setUp() {
        previousApp = appContext
        appContext = StyleTestAppContext()
    }

    override func tearDown() {
        appContext = previousApp
        previousApp = nil
        for url in bundleURLs {
            try? FileManager.default.removeItem(at: url)
        }
        bundleURLs.removeAll()
    }

    func testProducersRetainFieldLocalCarriersAndObservedMergeDirections() throws {
        let combined = Text(verbatim: "Hg")
            .speechAlwaysIncludesPunctuation()
            .speechSpellsOutCharacters()
            .speechAdjustedPitch(0.75)
            .speechAnnouncementsQueued()
        let combinedStyle = style(combined)
        XCTAssertEqual(combined.modifiers.count, 4)
        XCTAssertEqual(combinedStyle.speech?.alwaysIncludesPunctuation, true)
        XCTAssertEqual(combinedStyle.speech?.spellsOutCharacters, true)
        XCTAssertEqual(combinedStyle.speech?.adjustedPitch, 0.75)
        XCTAssertEqual(combinedStyle.speech?.announcementsPriority, .low)

        XCTAssertEqual(
            style(
                Text(verbatim: "Hg")
                    .speechAdjustedPitch(0.75)
                    .speechAdjustedPitch(1.25)
            ).speech?.adjustedPitch,
            0.75
        )
        XCTAssertEqual(
            style(
                Text(verbatim: "Hg").speechAnnouncementsQueued(false)
            ).speech?.announcementsPriority,
            .default
        )

        var speechParent = style(
            Text(verbatim: "Hg").speechAlwaysIncludesPunctuation()
        )
        apply(
            Text(verbatim: "Hg").speechAlwaysIncludesPunctuation(false),
            to: &speechParent
        )
        XCTAssertEqual(speechParent.speech?.alwaysIncludesPunctuation, false)

        var accessibilityParent = style(
            Text(verbatim: "Hg")
                .accessibilityTextContentType(.narrative)
                .accessibilityHeading(.h2)
                .accessibilityLabel(Text(verbatim: "parent spoken"))
        )
        apply(
            Text(verbatim: "Hg")
                .accessibilityTextContentType(.sourceCode)
                .accessibilityHeading(.h4)
                .accessibilityLabel(Text(verbatim: "child spoken")),
            to: &accessibilityParent
        )
        XCTAssertEqual(
            accessibilityParent.accessibility?.contentType?.rawValue,
            .narrative
        )
        XCTAssertEqual(accessibilityParent.accessibility?.headingLevel, .h2)
        XCTAssertEqual(
            accessibilityParent.accessibility?.label?._resolveText(in: .init()),
            "parent spoken"
        )

        let speechModifier = try boxedModifier(
            Text(verbatim: "Hg").speechAdjustedPitch(0.75)
        )
        let accessibilityModifier = try boxedModifier(
            Text(verbatim: "Hg").accessibilityHeading(.h2)
        )
        for modifier in [speechModifier, accessibilityModifier] {
            XCTAssertFalse(modifier.isStyled(options: []))
            XCTAssertTrue(modifier.isStyled(options: .includeAccessibility))
        }
    }

    func testPublicationUsesObservedKeysAndCurrentLocale() throws {
        let text = Text(verbatim: "Hg")
            .speechAlwaysIncludesPunctuation(false)
            .speechSpellsOutCharacters()
            .speechAdjustedPitch(0.75)
            .speechAnnouncementsQueued()
            .accessibilityTextContentType(.sourceCode)
            .accessibilityHeading(.h2)
            .accessibilityLabel(Text(verbatim: "Text spoken"))

        let omitted = published(text, includeAccessibility: false)
        for key in [
            punctuationKey, spellOutKey, pitchKey, priorityKey,
            headingKey, contextKey, labelKey,
        ] {
            XCTAssertNil(omitted[key])
        }

        let attributes = published(text, includeAccessibility: true)
        XCTAssertEqual(attributes[punctuationKey] as? Bool, false)
        XCTAssertEqual(attributes[spellOutKey] as? Bool, true)
        XCTAssertEqual(attributes[pitchKey] as? Double, 1.75)
        XCTAssertEqual(attributes[priorityKey] as? String, "low")
        XCTAssertEqual(attributes[headingKey] as? UInt, 2)
        XCTAssertEqual(
            attributes[contextKey] as? String,
            "AXTextualContextSourceCode"
        )
        XCTAssertEqual(attributes[labelKey] as? String, "Text spoken")

        let contentTypes: [(AccessibilityTextContentType, String?)] = [
            (.plain, nil),
            (.console, "AXTextualContextConsole"),
            (.fileSystem, "AXTextualContextFileSystem"),
            (.messaging, "AXTextualContextMessaging"),
            (.narrative, "AXTextualContextNarrative"),
            (.sourceCode, "AXTextualContextSourceCode"),
            (.spreadsheet, "AXTextualContextSpreadsheet"),
            (.wordProcessing, "AXTextualContextWordProcessing"),
        ]
        for (contentType, expected) in contentTypes {
            XCTAssertEqual(
                published(
                    Text(verbatim: "Hg")
                        .accessibilityTextContentType(contentType),
                    includeAccessibility: true
                )[contextKey] as? String,
                expected
            )
        }
        for level in UInt(0)...6 {
            let heading = try XCTUnwrap(AccessibilityHeadingLevel(rawValue: level))
            XCTAssertEqual(
                published(
                    Text(verbatim: "Hg").accessibilityHeading(heading),
                    includeAccessibility: true
                )[headingKey] as? UInt,
                level
            )
        }

        let bundle = try localizationBundle()
        let localizedLabel = Text(verbatim: "Hg").accessibilityLabel(
            Text("spoken", bundle: bundle)
        )
        XCTAssertEqual(
            published(
                localizedLabel,
                locale: Locale(identifier: "en_US"),
                includeAccessibility: true
            )[labelKey] as? String,
            "English spoken"
        )
        XCTAssertEqual(
            published(
                localizedLabel,
                locale: Locale(identifier: "fr_FR"),
                includeAccessibility: true
            )[labelKey] as? String,
            "French spoken"
        )
        let resource = LocalizedStringResource(
            "spoken",
            locale: Locale(identifier: "en_US"),
            bundle: .atURL(bundle.bundleURL)
        )
        XCTAssertEqual(
            published(
                Text(verbatim: "Hg").accessibilityLabel(resource),
                locale: Locale(identifier: "fr_FR"),
                includeAccessibility: true
            )[labelKey] as? String,
            "French spoken"
        )
        let generic = "Generic spoken"[...]
        XCTAssertEqual(
            published(
                Text(verbatim: "Hg").accessibilityLabel(generic),
                includeAccessibility: true
            )[labelKey] as? String,
            "Generic spoken"
        )
    }

    func testNestedAndConcatenatedRunsKeepParentAndChildOwnership() throws {
        let interpolatedSpeech = Text(
            "before \(Text(verbatim: "child").speechAdjustedPitch(1.25)) after"
        ).speechAdjustedPitch(0.75)
        let concatenatedSpeech = (
            Text(verbatim: "before ")
                + Text(verbatim: "child").speechAdjustedPitch(1.25)
                + Text(verbatim: " after")
        ).speechAdjustedPitch(0.75)
        for text in [interpolatedSpeech, concatenatedSpeech] {
            let runs = try resolvedAttributes(text)
            XCTAssertEqual(runs.count, 3)
            XCTAssertEqual(
                runs.map { $0.nsAttributes[pitchKey] as? Double },
                [1.75, 2.25, 1.75]
            )
        }

        let interpolatedLabel = Text(
            "before \(Text(verbatim: "child").accessibilityLabel(Text(verbatim: "child spoken"))) after"
        ).accessibilityLabel(Text(verbatim: "parent spoken"))
        let concatenatedLabel = (
            Text(verbatim: "before ")
                + Text(verbatim: "child").accessibilityLabel(
                    Text(verbatim: "child spoken")
                )
                + Text(verbatim: " after")
        ).accessibilityLabel(Text(verbatim: "parent spoken"))
        for text in [interpolatedLabel, concatenatedLabel] {
            let runs = try resolvedAttributes(text)
            XCTAssertEqual(runs.count, 3)
            XCTAssertEqual(
                runs.map { $0.nsAttributes[labelKey] as? String },
                ["parent spoken", "parent spoken", "parent spoken"]
            )
        }
    }

    func testRepresentationHelperForwardsAccessibilityOption() throws {
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: host
        )
        host.storage = viewGraph
        var helper = ResolvedTextHelper(
            includeDefaultAttributes: false,
            allowsAccessibilityAttributes: true
        )
        let text = Text(verbatim: "Hg")
            .speechAlwaysIncludesPunctuation()
            .accessibilityHeading(.h2)

        try viewGraph.data.withCurrent {
            let resolved = try XCTUnwrap(
                helper.resolve(text, with: environment(), sizeFitting: false)
            )
            let source = try XCTUnwrap(resolved.resolvedText)
            let attributes = try XCTUnwrap(runAttributes(source).first)
                .nsAttributes
            XCTAssertEqual(attributes[punctuationKey] as? Bool, true)
            XCTAssertEqual(attributes[headingKey] as? UInt, 2)
        }
    }

    private func style(
        _ text: Text,
        parent: Text.Style = .init(),
        environment: EnvironmentValues = .init()
    ) -> Text.Style {
        var result = parent
        apply(text, to: &result, environment: environment)
        return result
    }

    private func apply(
        _ text: Text,
        to style: inout Text.Style,
        environment: EnvironmentValues = .init()
    ) {
        for modifier in text.modifiers.reversed() {
            modifier.modify(style: &style, environment: environment)
        }
    }

    private func boxedModifier(_ text: Text) throws -> AnyTextModifier {
        guard case let .anyTextModifier(modifier)? = text.modifiers.first else {
            throw TextAccessibilitySpeechTestError.missingModifier
        }
        return modifier
    }

    private func published(
        _ text: Text,
        locale: Locale = Locale(identifier: "en_US"),
        includeAccessibility: Bool
    ) -> [NSAttributedString.Key: Any] {
        var environment = EnvironmentValues()
        environment.locale = locale
        var properties = Text.ResolvedProperties()
        return style(text, environment: environment).nsAttributes(
            in: environment,
            properties: &properties,
            options: includeAccessibility ? .includeAccessibility : [],
            includeDefaultAttributes: false
        ).nsAttributes
    }

    private func resolvedAttributes(
        _ text: Text
    ) throws -> [_ResolvedTextRunAttributes] {
        let source = try XCTUnwrap(text._resolve(
            context: GraphTextResolutionContext(
                environment: environment(),
                sceneResources: SceneResources()
            ),
            referenceDate: Date(timeIntervalSince1970: 0),
            options: .includeAccessibility
        ))
        return runAttributes(source)
    }

    private func runAttributes(
        _ source: ResolvedTextSource
    ) -> [_ResolvedTextRunAttributes] {
        source.runs.compactMap {
            if case let .styledText(_, _, _, attributes) = $0 {
                return attributes
            }
            return nil
        }
    }

    private func environment() -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.font = .system(size: 23)
        environment.defaultFontRenderingMode = .vector()
        environment.locale = Locale(identifier: "en_US")
        return environment
    }

    private func localizationBundle() throws -> Bundle {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bundle")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        bundleURLs.append(url)
        let info: [String: Any] = [
            "CFBundleIdentifier": "test." + UUID().uuidString,
            "CFBundleDevelopmentRegion": "en",
            "CFBundleLocalizations": ["en", "fr"],
        ]
        try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        ).write(to: url.appendingPathComponent("Info.plist"))
        for (language, value) in [
            ("en", "English spoken"),
            ("fr", "French spoken"),
        ] {
            let folder = url.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
            try "\"spoken\" = \"\(value)\";\n".write(
                to: folder.appendingPathComponent("Localizable.strings"),
                atomically: true,
                encoding: .utf8
            )
        }
        return try XCTUnwrap(Bundle(url: url))
    }
}

private enum TextAccessibilitySpeechTestError: Error {
    case missingModifier
}
