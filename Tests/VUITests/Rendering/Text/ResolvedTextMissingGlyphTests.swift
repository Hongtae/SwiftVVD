import Dispatch
import Synchronization
import XCTest
import VVD
@testable import VUI

final class ResolvedTextMissingGlyphTests: XCTestCase {
    func testBackendFontTypesAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}

        requireSendable(VVD.Font.self)
        requireSendable(VVD.TextureFont.self)
    }

    func testBackendFontSerializesConcurrentFaceAccessAndLifecycle() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let data = try Data(contentsOf: url)
        let font = try XCTUnwrap(VVD.Font(data: data))
        let failures = Mutex<[String]>([])

        DispatchQueue.concurrentPerform(iterations: 64) { iteration in
            switch iteration % 4 {
            case 0:
                font.setPointSize(
                    CGFloat(12 + iteration % 8),
                    dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
                )
            case 1:
                if font.glyphMetrics(for: UnicodeScalar("A")) == nil {
                    failures.withLock { $0.append("glyphMetrics") }
                }
            case 2:
                let loaded = font.withGlyphBitmap(
                    for: UnicodeScalar("B"),
                    embolden: 0,
                    outline: 0
                ) { _, _, _, _ in
                    _ = font.pointSize
                    _ = font.baseMetrics
                }
                if !loaded {
                    failures.withLock { $0.append("withGlyphBitmap") }
                }
            default:
                if !font.hasGlyph(for: UnicodeScalar("C")) {
                    failures.withLock { $0.append("hasGlyph") }
                }
            }
        }

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            guard let temporaryFont = VVD.Font(data: data),
                  temporaryFont.glyphMetrics(for: UnicodeScalar("A")) != nil else {
                failures.withLock { $0.append("faceLifecycle") }
                return
            }
        }

        XCTAssertTrue(
            failures.withLock { $0.isEmpty },
            failures.withLock { $0.joined(separator: ", ") }
        )
    }

    func testBackendTextureFontSerializesConcurrentGlyphCaching() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.TextureFont(
            deviceContext: deviceContext,
            data: Data(contentsOf: url)
        ))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )

        let textureIDs = Mutex<[ObjectIdentifier]>([])
        let failures = Mutex<[String]>([])
        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            guard let texture = font.glyphData(for: UnicodeScalar("A"))?.texture else {
                failures.withLock { $0.append("glyphData") }
                return
            }
            textureIDs.withLock { $0.append(ObjectIdentifier(texture)) }
        }

        XCTAssertTrue(
            failures.withLock { $0.isEmpty },
            failures.withLock { $0.joined(separator: ", ") }
        )
        XCTAssertEqual(Set(textureIDs.withLock { $0 }).count, 1)
    }

    // ASSERTIONS textZeroWidthScalarLineMetricsObserved
    func testUnsupportedBundledFontGlyphKeepsZeroWidthLineMetrics() throws {
        let provider = SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )
        let face = try XCTUnwrap(provider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ))
        let scalar = UnicodeScalar("ㄱ")

        XCTAssertFalse(face.hasGlyph(for: scalar))

        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], String(scalar))],
            scaleFactor: 1,
            drawMissingGlyphs: false
        )
        let line = try XCTUnwrap(resolved.makeGlyphs().first)

        XCTAssertEqual(line.glyphs.map(\.scalar), [scalar])
        XCTAssertEqual(line.width, 0)
        XCTAssertGreaterThan(line.height, 0)
        XCTAssertEqual(
            resolved.measure(in: CGSize(width: 200, height: 40)).width,
            0
        )
    }

    func testResolvedTextSearchesEveryTypefaceInCascadeOrder() throws {
        let latin = CascadeTestTypeface(
            identifier: "latin",
            supported: [UnicodeScalar("A")]
        )
        let korean = CascadeTestTypeface(
            identifier: "korean",
            supported: [UnicodeScalar("ㄱ")]
        )
        let cjk = CascadeTestTypeface(
            identifier: "cjk",
            supported: [UnicodeScalar("漢")]
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([latin, korean, cjk], "Aㄱ漢")],
            scaleFactor: 1
        )
        let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)

        XCTAssertEqual(glyphs.map(\.scalar), [
            UnicodeScalar("A"),
            UnicodeScalar("ㄱ"),
            UnicodeScalar("漢"),
        ])
        XCTAssertTrue(glyphs[0].face.isEqual(to: latin))
        XCTAssertTrue(glyphs[1].face.isEqual(to: korean))
        XCTAssertTrue(glyphs[2].face.isEqual(to: cjk))
    }

    // ASSERTIONS textFallbackPrimaryLineMetricsObserved
    func testFallbackRunMetricsDoNotExpandThePrimaryLineBox() throws {
        let primary = CascadeTestTypeface(
            identifier: "primary",
            supported: [UnicodeScalar("A")],
            ascender: 8,
            descender: -2
        )
        let fallback = CascadeTestTypeface(
            identifier: "fallback",
            supported: [UnicodeScalar("ㄱ")],
            ascender: 14,
            descender: -5
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([primary, fallback], "Aㄱ")],
            scaleFactor: 1
        )

        let lineGlyphs = try XCTUnwrap(resolved.makeGlyphs().first)
        XCTAssertEqual(lineGlyphs.glyphs.map(\.ascender), [8, 14])
        XCTAssertEqual(lineGlyphs.glyphs.map(\.descender), [-2, -5])
        XCTAssertEqual(lineGlyphs.ascender, 8)
        XCTAssertEqual(lineGlyphs.descender, -2)
        XCTAssertEqual(lineGlyphs.height, 10)

        let layout = resolved.makeLayout(
            in: CGSize(width: 100, height: 100),
            layoutDirection: .leftToRight
        )
        let line = try XCTUnwrap(layout.first)
        XCTAssertEqual(line.typographicBounds.ascent, 8)
        XCTAssertEqual(line.typographicBounds.descent, 2)
        XCTAssertEqual(line.count, 2)
        XCTAssertEqual(line[0].typographicBounds.ascent, 8)
        XCTAssertEqual(line[0].typographicBounds.descent, 2)
        XCTAssertEqual(line[1].typographicBounds.ascent, 14)
        XCTAssertEqual(line[1].typographicBounds.descent, 5)
    }

    // ASSERTIONS explicitFontRunExpandsLineMetricsObserved
    func testExplicitLargerFontRunExpandsTheLineBox() throws {
        let primary = CascadeTestTypeface(
            identifier: "primary",
            supported: [UnicodeScalar("A")],
            ascender: 8,
            descender: -2
        )
        let fallback = CascadeTestTypeface(
            identifier: "fallback",
            supported: [UnicodeScalar("ㄱ")],
            ascender: 14,
            descender: -5
        )
        let explicitlyLarge = CascadeTestTypeface(
            identifier: "explicit-large",
            supported: [UnicodeScalar("B")],
            ascender: 18,
            descender: -6
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [
                .text([primary, fallback], "ㄱ"),
                .text([explicitlyLarge], "B"),
            ],
            scaleFactor: 1
        )

        let line = try XCTUnwrap(resolved.makeGlyphs().first)
        XCTAssertEqual(line.ascender, 18)
        XCTAssertEqual(line.descender, -6)
        XCTAssertEqual(line.height, 24)
    }

    func testFallbackTruncationTokenKeepsTheSourcePrimaryLineBox() throws {
        let primary = CascadeTestTypeface(
            identifier: "primary",
            supported: [UnicodeScalar("A")],
            ascender: 8,
            descender: -2
        )
        let fallback = CascadeTestTypeface(
            identifier: "fallback",
            supported: [UnicodeScalar("ㄱ"), UnicodeScalar("…")],
            ascender: 14,
            descender: -5
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([primary, fallback], "ㄱㄱㄱ")],
            scaleFactor: 1
        )

        let line = try XCTUnwrap(resolved.makeGlyphs(
            maxWidth: 12,
            maxHeight: 100,
            lineLimit: 1,
            truncationMode: .tail
        ).first)
        let token = try XCTUnwrap(line.glyphs.first {
            $0.isTruncationToken
        })

        XCTAssertTrue(token.face.isEqual(to: fallback))
        XCTAssertEqual(token.ascender, 14)
        XCTAssertEqual(token.descender, -5)
        XCTAssertEqual(line.ascender, 8)
        XCTAssertEqual(line.descender, -2)
    }

    func testBackendLoadsGlyphZeroForUnsupportedScalarInBothPaths() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let data = try Data(contentsOf: url)
        let font = try XCTUnwrap(VVD.Font(data: data))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )
        let scalar = UnicodeScalar("\u{0378}")

        XCTAssertFalse(font.hasGlyph(for: scalar))
        XCTAssertEqual(font.glyphMetrics(for: scalar)?.index, 0)

        var bitmapIndex: UInt32?
        XCTAssertTrue(font.withGlyphBitmap(
            for: scalar,
            embolden: 0,
            outline: 0
        ) { _, metrics, _, _ in
            bitmapIndex = metrics.index
        })
        XCTAssertEqual(bitmapIndex, 0)

        var outlineCommands: [VVD.Font.OutlineCommand] = []
        let vectorMetrics = font.decomposeGlyphOutline(
            for: scalar
        ) { command in
            outlineCommands.append(command)
        }
        XCTAssertEqual(vectorMetrics?.index, 0)
        XCTAssertFalse(outlineCommands.isEmpty)
    }

    func testBackendAndBundledProviderSelectTrueTypeCollectionFaces() throws {
        let primaryURL = try XCTUnwrap(defaultFontURL)
        let fallbackURL = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID("NanumSquareNeo"),
            locale: Locale(identifier: "ko")
        )?.url)
        let collection = try makeTrueTypeCollection(fonts: [
            Data(contentsOf: primaryURL),
            Data(contentsOf: fallbackURL),
        ])
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ttc")
        try collection.write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let primary = try XCTUnwrap(VVD.Font(
            data: collection,
            faceIndex: 0
        ))
        let fallback = try XCTUnwrap(VVD.Font(
            data: collection,
            faceIndex: 1
        ))
        let pathFallback = try XCTUnwrap(VVD.Font(
            path: temporaryURL.path,
            faceIndex: 1
        ))
        let korean = UnicodeScalar("ㄱ")

        XCTAssertEqual(primary.faceIndex, 0)
        XCTAssertEqual(fallback.faceIndex, 1)
        XCTAssertEqual(primary.numFaces, 2)
        XCTAssertEqual(fallback.numFaces, 2)
        XCTAssertNotEqual(primary.familyName, fallback.familyName)
        XCTAssertFalse(primary.hasGlyph(for: korean))
        XCTAssertTrue(fallback.hasGlyph(for: korean))
        XCTAssertEqual(pathFallback.faceIndex, 1)
        XCTAssertEqual(pathFallback.numFaces, 2)
        XCTAssertEqual(pathFallback.familyName, fallback.familyName)
        XCTAssertNil(VVD.Font(data: collection, faceIndex: 2))
        XCTAssertNil(VVD.Font(data: collection, faceIndex: -1))

        let primaryResource = BundledFontResource(
            url: temporaryURL,
            faceIndex: 0
        )
        let fallbackResource = BundledFontResource(
            url: temporaryURL,
            faceIndex: 1
        )
        let primaryProvider = BundledFontProvider(
            resource: primaryResource,
            size: 17,
            weight: .regular,
            renderingMode: .vector()
        )
        let fallbackProvider = BundledFontProvider(
            resource: fallbackResource,
            size: 17,
            weight: .regular,
            renderingMode: .vector()
        )
        XCTAssertFalse(primaryProvider.isEqual(to: fallbackProvider))
        let primaryFont = VUI.Font(provider: AnyFontBox(primaryProvider))
        let fallbackFont = VUI.Font(provider: AnyFontBox(fallbackProvider))
        XCTAssertNotEqual(primaryFont, fallbackFont)
        XCTAssertEqual(Set([primaryFont, fallbackFont]).count, 2)

        let resolvedFallback = try XCTUnwrap(fallbackProvider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ))
        XCTAssertTrue(resolvedFallback.hasGlyph(for: korean))

        let directFallbackProvider = BundledFontProvider(
            resource: BundledFontResource(url: fallbackURL),
            size: 17,
            weight: .regular,
            renderingMode: .vector()
        )
        let directFallback = try XCTUnwrap(
            directFallbackProvider.makeTypeface(
                MissingGlyphTestAppContext(),
                dpi: UInt32(defaultDPI)
            ) as? VectorTypeface
        )
        let collectionFallback = try XCTUnwrap(
            resolvedFallback as? VectorTypeface
        )
        let directMetrics = try XCTUnwrap(
            directFallback.decorationMetrics
        )
        let collectionMetrics = try XCTUnwrap(
            collectionFallback.decorationMetrics
        )
        XCTAssertEqual(
            collectionMetrics.underlinePosition,
            directMetrics.underlinePosition,
            accuracy: 0.001
        )
        XCTAssertEqual(
            collectionMetrics.underlineThickness,
            directMetrics.underlineThickness,
            accuracy: 0.001
        )
    }

    func testBundledConfigurationResolvesExactLanguageAndDefaultLocale() {
        let configuration = BundledFontCatalog.shared.configuration

        XCTAssertEqual(configuration.version, 2)
        XCTAssertEqual(configuration.defaultLocale, "en")
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "en_US"))
                .map(\.rawValue),
            ["Roboto", "NotoSansCJK"]
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "ko_KR"))
                .map(\.rawValue),
            ["NanumSquareNeo", "NotoSansCJK"]
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "ja_JP"))
                .map(\.rawValue),
            ["NotoSansCJK", "Roboto"]
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "fr_FR"))
                .map(\.rawValue),
            ["Roboto", "NotoSansCJK"]
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "zh_Hans_CN"))
                .map(\.rawValue),
            ["NotoSansCJK", "Roboto"]
        )
        XCTAssertEqual(
            configuration.fonts(
                for: Locale(identifier: "ko_KR"),
                design: .monospaced
            ).map(\.rawValue),
            ["RobotoMono", "NotoSansMonoCJK"]
        )
        XCTAssertEqual(configuration.systemFont.rawValue, "Roboto")
        XCTAssertEqual(
            configuration.systemFont(for: .monospaced).rawValue,
            "RobotoMono"
        )
        XCTAssertEqual(
            configuration.systemFont(for: .rounded).rawValue,
            "Roboto"
        )
        XCTAssertEqual(configuration.missingGlyphFont.rawValue, "LastResort")
    }

    func testBundledConfigurationRejectsTerminalFontInLocaleCascade() {
        let data = Data(#"""
        {
          "version": 2,
          "fonts": {
            "Roboto": {
              "sources": [{
                "weight": 400,
                "file": "Roboto/Roboto-Regular.ttf",
                "faceIndex": 0
              }],
              "syntheticWeight": true
            },
            "NotoSansCJK": {
              "sources": [{
                "weight": 400,
                "file": "NotoSansCJK/NotoSansCJK-VF.otf.ttc",
                "faceIndex": 0
              }],
              "syntheticWeight": false
            }
          },
          "defaultLocale": "en",
          "designs": {
            "default": {
              "systemFont": "Roboto",
              "locales": {
                "en": ["Roboto", "NotoSansCJK"]
              }
            }
          },
          "missingGlyphFont": "Roboto"
        }
        """#.utf8)

        XCTAssertThrowsError(try FontFallbackConfiguration(data: data)) {
            XCTAssertEqual(
                $0 as? FontFallbackConfigurationError,
                .terminalFontInLocale("en")
            )
        }
    }

    func testBundledConfigurationRequiresDeclaredDefaultLocale() {
        let data = Data(#"""
        {
          "version": 2,
          "fonts": {
            "Roboto": {
              "sources": [{
                "weight": 400,
                "file": "Roboto/Roboto-Regular.ttf",
                "faceIndex": 0
              }],
              "syntheticWeight": true
            },
            "NotoSansCJK": {
              "sources": [{
                "weight": 400,
                "file": "NotoSansCJK/NotoSansCJK-VF.otf.ttc",
                "faceIndex": 0
              }],
              "syntheticWeight": false
            },
            "LastResort": {
              "sources": [{
                "weight": 400,
                "file": "LastResort/LastResort-Regular.ttf",
                "faceIndex": 0
              }],
              "syntheticWeight": false
            }
          },
          "defaultLocale": "ko",
          "designs": {
            "default": {
              "systemFont": "Roboto",
              "locales": {
                "en": ["Roboto", "NotoSansCJK"]
              }
            }
          },
          "missingGlyphFont": "LastResort"
        }
        """#.utf8)

        XCTAssertThrowsError(try FontFallbackConfiguration(data: data)) {
            XCTAssertEqual(
                $0 as? FontFallbackConfigurationError,
                .invalidDefaultLocale("ko")
            )
        }
    }

    func testBundledConfigurationLoadsFontFilesAndFacesFromData() throws {
        let data = Data(#"""
        {
          "version": 2,
          "fonts": {
            "Primary": {
              "sources": [{
                "file": "Example/Primary.ttc",
                "faceIndex": 3,
                "localeFaceIndices": {
                  "ko": 7
                },
                "weightAxis": {
                  "tag": "wght",
                  "minimum": 200,
                  "maximum": 800
                }
              }],
              "syntheticWeight": false
            },
            "Terminal": {
              "sources": [{
                "weight": 400,
                "file": "Example/Terminal.ttf",
                "faceIndex": 0
              }],
              "syntheticWeight": false
            }
          },
          "defaultLocale": "en",
          "designs": {
            "default": {
              "systemFont": "Primary",
              "locales": {
                "en": ["Primary"]
              }
            }
          },
          "missingGlyphFont": "Terminal"
        }
        """#.utf8)

        let configuration = try FontFallbackConfiguration(data: data)
        let primaryID = BundledFontID("Primary")
        let descriptor = try XCTUnwrap(
            configuration.fontDescriptors[primaryID]
        )
        let source = descriptor.source(for: 600)

        XCTAssertEqual(source.file, "Example/Primary.ttc")
        XCTAssertEqual(source.faceIndex, 3)
        XCTAssertEqual(
            source.faceIndex(for: Locale(identifier: "ko_KR")),
            7
        )
        XCTAssertEqual(source.weightAxis?.tag, 0x7767_6874)
        XCTAssertEqual(source.weightAxis?.minimum, 200)
        XCTAssertEqual(source.weightAxis?.maximum, 800)
        XCTAssertFalse(descriptor.appliesSyntheticWeight)
        XCTAssertEqual(configuration.systemFont, primaryID)
    }

    func testBundledConfigurationRejectsUnsafeFontFilePath() {
        let data = Data(#"""
        {
          "version": 2,
          "fonts": {
            "Primary": {
              "sources": [{
                "weight": 400,
                "file": "../Primary.ttf",
                "faceIndex": 0
              }],
              "syntheticWeight": true
            }
          },
          "defaultLocale": "en",
          "designs": {
            "default": {
              "systemFont": "Primary",
              "locales": {
                "en": ["Primary"]
              }
            }
          },
          "missingGlyphFont": "Primary"
        }
        """#.utf8)

        XCTAssertThrowsError(try FontFallbackConfiguration(data: data)) {
            XCTAssertEqual(
                $0 as? FontFallbackConfigurationError,
                .invalidFontFile(
                    BundledFontID("Primary"),
                    "../Primary.ttf"
                )
            )
        }
    }

    func testBundledCatalogMapsVariableWeightsAndItalicSources() throws {
        let catalog = BundledFontCatalog.shared
        let locale = Locale(identifier: "en")

        func file(
            _ family: String,
            _ weight: VUI.Font.Weight,
            isItalic: Bool = false
        ) throws -> String {
            try XCTUnwrap(catalog.resource(
                for: BundledFontID(family),
                locale: locale,
                weight: weight.value,
                isItalic: isItalic
            )).url.lastPathComponent
        }

        let weights: [VUI.Font.Weight] = [
            .ultraLight,
            .thin,
            .light,
            .regular,
            .medium,
            .semibold,
            .bold,
            .heavy,
            .black,
        ]
        for weight in weights {
            XCTAssertEqual(
                try file("Roboto", weight),
                "Roboto-VariableFont_wdth,wght.ttf"
            )
            XCTAssertEqual(
                try file("Roboto", weight, isItalic: true),
                "Roboto-Italic-VariableFont_wdth,wght.ttf"
            )
            XCTAssertEqual(
                try file("RobotoMono", weight),
                "RobotoMono-VariableFont_wght.ttf"
            )
            XCTAssertEqual(
                try file("RobotoMono", weight, isItalic: true),
                "RobotoMono-Italic-VariableFont_wght.ttf"
            )
            XCTAssertEqual(
                try file("NanumSquareNeo", weight),
                "NanumSquareNeo-Variable.ttf"
            )
        }
    }

    func testBundledCatalogSelectsLocaleSpecificNotoCollectionFaces() throws {
        let catalog = BundledFontCatalog.shared

        let japanese = try XCTUnwrap(catalog.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "ja")
        ))
        XCTAssertEqual(japanese.faceIndex, 0)
        XCTAssertEqual(try XCTUnwrap(catalog.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "ko")
        )).faceIndex, 1)
        XCTAssertEqual(try XCTUnwrap(catalog.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "zh-Hans")
        )).faceIndex, 2)
        XCTAssertEqual(try XCTUnwrap(catalog.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "zh-Hant")
        )).faceIndex, 3)
        XCTAssertEqual(try XCTUnwrap(catalog.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "zh-HK")
        )).faceIndex, 4)

        let data = try Data(contentsOf: japanese.url)
        let expectedFamilies = [
            "Noto Sans CJK JP",
            "Noto Sans CJK KR",
            "Noto Sans CJK SC",
            "Noto Sans CJK TC",
            "Noto Sans CJK HK",
        ]
        for (faceIndex, family) in expectedFamilies.enumerated() {
            let font = try XCTUnwrap(VVD.Font(
                data: data,
                faceIndex: faceIndex
            ))
            XCTAssertEqual(font.faceIndex, faceIndex)
            XCTAssertEqual(font.numFaces, expectedFamilies.count)
            XCTAssertEqual(font.familyName, family)
        }
    }

    func testBundledCatalogSelectsLocaleSpecificNotoMonoCollectionFaces()
        throws {
        let catalog = BundledFontCatalog.shared
        let family = BundledFontID("NotoSansMonoCJK")
        let localesAndIndices = [
            ("ja", 0),
            ("ko", 1),
            ("zh-Hans", 2),
            ("zh-Hant", 3),
            ("zh-HK", 4),
        ]
        for (locale, expectedIndex) in localesAndIndices {
            XCTAssertEqual(try XCTUnwrap(catalog.resource(
                for: family,
                locale: Locale(identifier: locale)
            )).faceIndex, expectedIndex)
        }

        let japanese = try XCTUnwrap(catalog.resource(
            for: family,
            locale: Locale(identifier: "ja")
        ))
        let data = try Data(contentsOf: japanese.url)
        let expectedFamilies = [
            "Noto Sans Mono CJK JP",
            "Noto Sans Mono CJK KR",
            "Noto Sans Mono CJK SC",
            "Noto Sans Mono CJK TC",
            "Noto Sans Mono CJK HK",
        ]
        for (faceIndex, familyName) in expectedFamilies.enumerated() {
            let font = try XCTUnwrap(VVD.Font(
                data: data,
                faceIndex: faceIndex
            ))
            XCTAssertEqual(font.faceIndex, faceIndex)
            XCTAssertEqual(font.numFaces, expectedFamilies.count)
            XCTAssertEqual(font.familyName, familyName)
        }
    }

    func testNotoVariableCollectionAcceptsWeightDesignCoordinates() throws {
        let resource = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "ko")
        ))
        let font = try XCTUnwrap(VVD.Font(
            data: Data(contentsOf: resource.url),
            faceIndex: resource.faceIndex
        ))
        let weightTag: UInt32 = 0x7767_6874
        let axis = try XCTUnwrap(font.variationAxes.first {
            $0.tag == weightTag
        })

        XCTAssertEqual(axis.minimumValue, 100)
        XCTAssertEqual(axis.defaultValue, 100)
        XCTAssertEqual(axis.maximumValue, 900)
        XCTAssertEqual(font.variationCoordinates[weightTag], 100)
        XCTAssertTrue(font.setVariationCoordinates([weightTag: 400]))
        XCTAssertEqual(font.variationCoordinates[weightTag], 400)
        XCTAssertFalse(font.setVariationCoordinates([0x6261_6421: 400]))
    }

    func testNotoMonoVariableCollectionClampsToAvailableWeightRange()
        throws {
        let catalog = BundledFontCatalog.shared
        let family = BundledFontID("NotoSansMonoCJK")
        let resource = try XCTUnwrap(catalog.resource(
            for: family,
            locale: Locale(identifier: "ko")
        ))
        let font = try XCTUnwrap(VVD.Font(
            data: Data(contentsOf: resource.url),
            faceIndex: resource.faceIndex
        ))
        let weightTag: UInt32 = 0x7767_6874
        let axis = try XCTUnwrap(font.variationAxes.first {
            $0.tag == weightTag
        })

        XCTAssertEqual(axis.minimumValue, 400)
        XCTAssertEqual(axis.defaultValue, 400)
        XCTAssertEqual(axis.maximumValue, 700)

        let light = try XCTUnwrap(BundledFontProvider(
            family: family,
            locale: Locale(identifier: "ko"),
            size: 17,
            weight: .light,
            renderingMode: .vector(),
            isItalic: false,
            catalog: catalog
        ))
        let black = try XCTUnwrap(BundledFontProvider(
            family: family,
            locale: Locale(identifier: "ko"),
            size: 17,
            weight: .black,
            renderingMode: .vector(),
            isItalic: false,
            catalog: catalog
        ))
        XCTAssertEqual(light.variations.first?.value, 400)
        XCTAssertEqual(black.variations.first?.value, 700)
    }

    func testBundledNotoProviderUsesVariableWeightWithoutSyntheticWeight() throws {
        let weightTag: UInt32 = 0x7767_6874
        let resource = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: Locale(identifier: "ko")
        ))
        let provider = BundledFontProvider(
            resource: resource,
            size: 17,
            weight: .bold,
            renderingMode: .vector(),
            variations: [BundledFontVariation(
                tag: weightTag,
                value: 700
            )],
            appliesSyntheticWeight: false
        )
        let face = try XCTUnwrap(provider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ) as? VectorTypeface)

        XCTAssertEqual(face.embolden, 0)
        XCTAssertEqual(face.font.variationCoordinates[weightTag], 700)
    }

    func testExternalFileFontLoadsOnlyLocalURLAndAppliesVariableWeight()
        throws {
        let resource = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID("RobotoMono"),
            locale: Locale(identifier: "en")
        ))
        let font = VUI.Font.file(
            resource.url,
            size: 17,
            weight: .bold,
            design: .monospaced,
            renderingMode: .vector()
        )
        let provider = try XCTUnwrap(
            font.provider.fontBox as? ExternalFontProvider
        )
        let face = try XCTUnwrap(provider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ) as? VectorTypeface)

        XCTAssertEqual(
            face.font.filePath,
            resource.url.standardizedFileURL.path
        )
        XCTAssertEqual(face.font.familyName, "Roboto Mono")
        XCTAssertEqual(face.font.variationCoordinates[0x7767_6874], 700)
        XCTAssertEqual(face.embolden, 0)

        let remote = VUI.Font.file(
            try XCTUnwrap(URL(string: "https://example.com/font.ttf")),
            size: 17,
            renderingMode: .vector()
        )
        let remoteProvider = try XCTUnwrap(
            remote.provider.fontBox as? ExternalFontProvider
        )
        XCTAssertNil(remoteProvider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ))
    }

    func testExternalDataFontRetainsCollectionFaceAndClampsVariableWeight()
        throws {
        let resource = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID("NotoSansMonoCJK"),
            locale: Locale(identifier: "ja")
        ))
        let data = try Data(contentsOf: resource.url)
        let font = VUI.Font.data(
            data,
            size: 17,
            weight: .black,
            design: .monospaced,
            faceIndex: 1,
            renderingMode: .vector()
        )
        let provider = try XCTUnwrap(
            font.provider.fontBox as? ExternalFontProvider
        )
        let face = try XCTUnwrap(provider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ) as? VectorTypeface)

        XCTAssertEqual(face.font.familyName, "Noto Sans Mono CJK KR")
        XCTAssertEqual(face.font.faceIndex, 1)
        XCTAssertNotNil(face.font.fontData)
        XCTAssertEqual(face.font.variationCoordinates[0x7767_6874], 700)
        XCTAssertEqual(face.embolden, 0)

        let retainedCopy = font
        XCTAssertEqual(font, retainedCopy)
        XCTAssertNotEqual(
            font,
            VUI.Font.data(
                data,
                size: 17,
                weight: .black,
                design: .monospaced,
                faceIndex: 1,
                renderingMode: .vector()
            )
        )
    }

    @MainActor
    func testExternalFontUsesSelectedDesignFallbackCascade() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        let resource = try XCTUnwrap(BundledFontCatalog.shared.resource(
            for: BundledFontID("RobotoMono"),
            locale: Locale(identifier: "en")
        ))
        let font = VUI.Font.file(
            resource.url,
            size: 17,
            weight: .regular,
            design: .monospaced,
            renderingMode: .vector()
        )
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "ko_KR")
        environment.defaultFontRenderingMode = .vector()
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )

        XCTAssertEqual(
            (cascade.ordinaryFaces.first as? VectorTypeface)?.font.familyName,
            "Roboto Mono"
        )
        XCTAssertTrue(cascade.ordinaryFaces.contains {
            $0.identifier == "deferred:NotoSansMonoCJK:1"
        })
        XCTAssertNotNil(cascade.missingGlyphFace)
    }

    @MainActor
    func testConfiguredFallbacksRemainDeferredForSupportedLatinText() throws {
        let previousAppContext = appContext
        let testContext = MissingGlyphTestAppContext()
        appContext = testContext
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, "A")],
            scaleFactor: 1,
            drawMissingGlyphs: true
        )

        XCTAssertGreaterThan(
            try XCTUnwrap(resolved.makeGlyphs().first?.width),
            0
        )
        let catalog = BundledFontCatalog.shared
        let secondaryURL = try XCTUnwrap(catalog.resource(
            for: BundledFontID("NotoSansCJK"),
            locale: environment.locale
        )?.url)
        let terminalURL = try XCTUnwrap(catalog.resource(
            for: BundledFontID("LastResort"),
            locale: environment.locale
        )?.url)
        XCTAssertFalse(testContext.loadedURLs.contains(secondaryURL))
        XCTAssertFalse(testContext.loadedURLs.contains(terminalURL))
    }

    // ASSERTIONS textCustomFontFallbackWidthObserved textCustomFontFallbackCascadeObserved
    @MainActor
    func testSystemFontBuildsConfiguredKoreanCascade() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "ko_KR")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )))
        let sceneResources = SceneResources()
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: sceneResources,
            contentScaleFactor: 1
        )
        let korean = UnicodeScalar("ㄱ")
        let han = UnicodeScalar("漢")

        XCTAssertEqual(cascade.ordinaryFaces.count, 2)
        XCTAssertTrue(cascade.ordinaryFaces[0].hasGlyph(for: korean))
        XCTAssertFalse(cascade.ordinaryFaces[0].hasGlyph(for: han))
        XCTAssertTrue(cascade.ordinaryFaces[1].hasGlyph(for: han))
        XCTAssertNotNil(cascade.missingGlyphFace)

        let faces = cascade.runFaces
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text(faces, "Aㄱ漢")],
            scaleFactor: 1
        )
        let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)

        XCTAssertEqual(glyphs.map(\.scalar), [
            UnicodeScalar("A"),
            korean,
            han,
        ])
        XCTAssertTrue(glyphs[0].face.isEqual(to: cascade.ordinaryFaces[0]))
        XCTAssertTrue(glyphs[1].face.isEqual(to: cascade.ordinaryFaces[0]))
        XCTAssertTrue(glyphs[2].face.isEqual(to: cascade.ordinaryFaces[1]))
        XCTAssertGreaterThan(resolved.measure().width, 0)
    }

    // ASSERTIONS textMonospacedFallbackNaturalAdvanceObserved
    // ASSERTIONS textFieldMonospacedFallbackStableHeightObserved
    // ASSERTIONS fontMonospacedModifierProviderObserved
    // ASSERTIONS fontMonospacedDigitModifierProviderObserved
    func testMonospacedFontModifiersPreserveProviderStructureAndOrder() throws {
        let base = VUI.Font.system(
            size: 17,
            weight: .regular,
            design: .default
        )
        let monospaced = base.monospaced()
        let inactive = base.monospaced(false)
        let digits = base.monospacedDigit()

        XCTAssertNotNil(monospaced.provider.fontBox as?
            VUI.Font.StaticModifierProvider<VUI.Font.MonospacedModifier>)
        XCTAssertNotNil(inactive.provider.fontBox as?
            VUI.Font.StaticModifierProvider<
                VUI.Font.UndoModifier<VUI.Font.MonospacedModifier>
            >)
        XCTAssertNotNil(digits.provider.fontBox as?
            VUI.Font.StaticModifierProvider<
                VUI.Font.MonospacedDigitModifier
            >)

        let environment = EnvironmentValues()
        let resolvedMonospaced = try XCTUnwrap(
            monospaced.resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )
        let resolvedInactive = try XCTUnwrap(
            inactive.resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )
        let resolvedTrueThenFalse = try XCTUnwrap(
            base.monospaced().monospaced(false)
                .resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )
        let resolvedFalseThenTrue = try XCTUnwrap(
            base.monospaced(false).monospaced()
                .resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )
        let resolvedExplicitDesign = try XCTUnwrap(
            VUI.Font.system(size: 17, design: .monospaced)
                .monospaced(false)
                .resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )
        let resolvedWeighted = try XCTUnwrap(
            monospaced.weight(.bold)
                .resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )

        XCTAssertEqual(resolvedMonospaced.design, .monospaced)
        XCTAssertEqual(resolvedInactive.design, .default)
        XCTAssertEqual(resolvedTrueThenFalse.design, .monospaced)
        XCTAssertEqual(resolvedFalseThenTrue.design, .monospaced)
        XCTAssertEqual(resolvedExplicitDesign.design, .monospaced)
        XCTAssertEqual(resolvedWeighted.design, .monospaced)
        XCTAssertEqual(resolvedWeighted.weight, .bold)
    }

    // ASSERTIONS monospacedDigitFeatureAvailabilityObserved
    func testSystemMonospacedDigitUsesBundledTabularAdvances() throws {
        let font = VUI.Font.system(size: 17).monospacedDigit()
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let provider = try XCTUnwrap(
            font.resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )
        let face = try XCTUnwrap(provider.makeTypeface(
            MissingGlyphTestAppContext(),
            dpi: UInt32(defaultDPI)
        ))
        let advances = try "0123456789".unicodeScalars.map { scalar in
            try XCTUnwrap(face.glyphMetrics(for: scalar)?.advance.width)
        }

        XCTAssertEqual(advances.count, 10)
        for advance in advances.dropFirst() {
            XCTAssertEqual(advance, advances[0], accuracy: 0.001)
        }
    }

    // ASSERTIONS viewMonospacedEnvironmentModifierObserved
    // ASSERTIONS viewMonospacedNearestModifierWinsObserved
    func testInheritedMonospacedModifierUsesContentNearestValue() throws {
        let base = VUI.Font.system(size: 17)
        var environment = EnvironmentValues()
        environment.fontModifiers = [
            .monospaced(false),
            .monospaced(true),
        ]
        let contentNearestTrue = try XCTUnwrap(
            base.resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )

        environment.fontModifiers = [
            .monospaced(true),
            .monospaced(false),
        ]
        let contentNearestFalse = try XCTUnwrap(
            base.resolved(in: environment).provider.fontBox as?
                SystemFontProvider
        )

        XCTAssertEqual(contentNearestTrue.design, .monospaced)
        XCTAssertEqual(contentNearestFalse.design, .default)

        let trueThenFalse = try recordedFontModifiers {
            $0.monospaced().monospaced(false)
        }
        let falseThenTrue = try recordedFontModifiers {
            $0.monospaced(false).monospaced()
        }
        let repeatedTrue = try recordedFontModifiers {
            $0.monospaced().monospaced()
        }
        let trueFalseTrue = try recordedFontModifiers {
            $0.monospaced().monospaced(false).monospaced()
        }
        let falseTrueFalse = try recordedFontModifiers {
            $0.monospaced(false).monospaced().monospaced(false)
        }
        XCTAssertEqual(
            trueThenFalse.compactMap(\.monospacedValue),
            [false, true]
        )
        XCTAssertEqual(
            falseThenTrue.compactMap(\.monospacedValue),
            [true, false]
        )
        XCTAssertEqual(
            repeatedTrue.compactMap(\.monospacedValue),
            [true]
        )
        XCTAssertEqual(
            trueFalseTrue.compactMap(\.monospacedValue),
            [false, true]
        )
        XCTAssertEqual(
            falseTrueFalse.compactMap(\.monospacedValue),
            [true, false]
        )
    }

    private func recordedFontModifiers<Content: View>(
        transform: (FontModifierEnvironmentProbe) -> Content
    ) throws -> [AnyFontModifier] {
        let recorder = FontModifierEnvironmentRecorder()
        let content = transform(FontModifierEnvironmentProbe(
            recorder: recorder
        ))
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)

        context.withCurrent {
            let source = graph.makeInput(value: content)
            let environment = graph.makeInput(value: EnvironmentValues())
            _ = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: _ViewInputs(
                    base: _GraphInputs(
                        time: graph.makeInput(value: Time(seconds: 0)),
                        phase: graph.makeInput(value: _GraphInputs.Phase()),
                        environment: environment,
                        transaction: graph.makeInput(value: Transaction())
                    ),
                    customInputs: PropertyList(),
                    preferences: PreferencesInputs(
                        keys: PreferenceKeys(),
                        hostKeys: graph.makeInput(value: PreferenceKeys())
                    ),
                    transform: graph.makeInput(value: ViewTransform()),
                    position: graph.makeInput(value: CGPoint.zero),
                    containerPosition: graph.makeInput(value: CGPoint.zero),
                    size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
                    safeAreaInsets: OptionalAttribute(),
                    containerSize: OptionalAttribute(),
                    stackOrientation: nil
                )
            )
        }
        return try XCTUnwrap(recorder.modifiers)
    }

    // ASSERTIONS textMonospacedModifierCarrierObserved
    // ASSERTIONS textMonospacedModifierFirstWinsObserved
    @MainActor
    func testTextMonospacedModifierUsesFirstLocalValue() throws {
        let trueThenFalse = Text(verbatim: "AiW")
            .monospaced()
            .monospaced(false)
        let falseThenTrue = Text(verbatim: "AiW")
            .monospaced(false)
            .monospaced()
        let digitText = Text(verbatim: "012").monospacedDigit()

        XCTAssertEqual(trueThenFalse.monospacedValue, true)
        XCTAssertEqual(falseThenTrue.monospacedValue, false)
        XCTAssertTrue(digitText.usesMonospacedDigits)
        XCTAssertTrue(trueThenFalse.modifiers.contains { modifier in
            guard case let .anyTextModifier(value) = modifier else {
                return false
            }
            return value is MonospacedTextModifier
        })
        XCTAssertTrue(digitText.modifiers.contains { modifier in
            guard case let .anyTextModifier(value) = modifier else {
                return false
            }
            return value is MonospacedDigitTextModifier
        })

        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        environment.fontModifiers = [.monospaced(true)]
        let inheritedTrueContext = GraphTextResolutionContext(
            environment: environment,
            sceneResources: SceneResources()
        )
        let localFalseText = try XCTUnwrap(
            Text(verbatim: "A")
                .font(.system(size: 17))
                .monospaced(false)
                ._resolve(
                    context: inheritedTrueContext,
                    referenceDate: Date()
                )
        )
        let localFalse = try XCTUnwrap(
            localFalseText
                .makeGlyphs()
                .first?.glyphs.first?.face as? VectorTypeface
        )
        XCTAssertEqual(localFalse.font.familyName, "Roboto")

        environment.fontModifiers = [.monospaced(false)]
        let inheritedFalseContext = GraphTextResolutionContext(
            environment: environment,
            sceneResources: SceneResources()
        )
        let localTrueText = try XCTUnwrap(
            Text(verbatim: "A")
                .font(.system(size: 17))
                .monospaced()
                ._resolve(
                    context: inheritedFalseContext,
                    referenceDate: Date()
                )
        )
        let localTrue = try XCTUnwrap(
            localTrueText
                .makeGlyphs()
                .first?.glyphs.first?.face as? VectorTypeface
        )
        XCTAssertEqual(localTrue.font.familyName, "Roboto Mono")
    }

    @MainActor
    func testSystemMonospacedFontBuildsConfiguredCJKCascade() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "ko_KR")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .bold,
            design: .monospaced,
            renderingMode: .vector()
        )))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let latin = UnicodeScalar("A")
        let korean = UnicodeScalar("한")

        XCTAssertEqual(cascade.ordinaryFaces.count, 2)
        XCTAssertTrue(cascade.ordinaryFaces[0].hasGlyph(for: latin))
        XCTAssertFalse(cascade.ordinaryFaces[0].hasGlyph(for: korean))
        XCTAssertTrue(cascade.ordinaryFaces[1].hasGlyph(for: korean))

        let primary = try XCTUnwrap(
            cascade.ordinaryFaces[0] as? VectorTypeface
        )
        XCTAssertEqual(primary.font.familyName, "Roboto Mono")
        XCTAssertEqual(
            primary.font.variationCoordinates[0x7767_6874],
            700
        )
        XCTAssertEqual(primary.embolden, 0)
        XCTAssertEqual(
            cascade.ordinaryFaces[1].identifier,
            "deferred:NotoSansMonoCJK:1"
        )

        let resolved = GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, "A한A")],
            scaleFactor: 1
        )
        let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)
        XCTAssertEqual(glyphs.map(\.scalar), [latin, korean, latin])
        XCTAssertTrue(glyphs[0].face.isEqual(to: cascade.ordinaryFaces[0]))
        XCTAssertTrue(glyphs[1].face.isEqual(to: cascade.ordinaryFaces[1]))
        XCTAssertEqual(glyphs[0].advance.width, glyphs[2].advance.width)
        XCTAssertNotEqual(glyphs[1].advance.width, glyphs[0].advance.width)

        let latinText = GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, "A")],
            scaleFactor: 1
        )
        let fallbackText = GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, "한")],
            scaleFactor: 1
        )
        XCTAssertEqual(resolved.measure().height, latinText.measure().height)
        XCTAssertEqual(
            fallbackText.measure().height,
            latinText.measure().height
        )
    }

    // ASSERTIONS textFallbackPrimaryLineMetricsObserved
    @MainActor
    func testConfiguredFallbackKeepsSystemPrimaryLineMetrics() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let primary = try XCTUnwrap(cascade.ordinaryFaces.first)
        let fallback = try XCTUnwrap(cascade.ordinaryFaces.dropFirst().first)
        let scalar = UnicodeScalar("ㄱ")

        XCTAssertFalse(primary.hasGlyph(for: scalar))
        XCTAssertTrue(fallback.hasGlyph(for: scalar))
        XCTAssertTrue(
            primary.ascender != fallback.ascender ||
                primary.descender != fallback.descender
        )

        let latin = try XCTUnwrap(GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, "A")],
            scaleFactor: 1
        ).makeGlyphs().first)
        let fallbackLine = try XCTUnwrap(GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, String(scalar))],
            scaleFactor: 1
        ).makeGlyphs().first)

        XCTAssertEqual(fallbackLine.glyphs.first?.ascender, fallback.ascender)
        XCTAssertEqual(fallbackLine.glyphs.first?.descender, fallback.descender)
        XCTAssertEqual(fallbackLine.ascender, primary.ascender)
        XCTAssertEqual(fallbackLine.descender, primary.descender)
        XCTAssertEqual(fallbackLine.height, latin.height)
    }

    // ASSERTIONS textLastResortGlyphObserved
    @MainActor
    func testUnsupportedScalarUsesExplicitLastResortTypeface() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en_US")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )))
        let sceneResources = SceneResources()
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: sceneResources,
            contentScaleFactor: 1
        )
        let fallback = try XCTUnwrap(cascade.missingGlyphFace)
        let terminal = try XCTUnwrap(
            cascade.runFaces.last as? TerminalFallbackTypeface
        )
        let scalar = UnicodeScalar("\u{0378}")

        XCTAssertTrue(cascade.ordinaryFaces.allSatisfy {
            !$0.hasGlyph(for: scalar)
        })
        XCTAssertTrue(fallback.hasGlyph(for: scalar))
        XCTAssertFalse(terminal.hasGlyph(for: scalar))

        let resolved = GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, String(scalar))],
            scaleFactor: 1,
            drawMissingGlyphs: true
        )
        let glyph = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs.first)

        XCTAssertTrue(glyph.face.isEqual(to: terminal))
        XCTAssertGreaterThan(glyph.advance.width, 0)
        XCTAssertGreaterThan(resolved.measure().width, 0)
        guard case .vector = try XCTUnwrap(terminal.glyph(for: scalar)) else {
            return XCTFail("Expected the terminal LastResort vector glyph")
        }
    }

    @MainActor
    func testLastResortRequiresMissingGlyphDrawing() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let scalar = UnicodeScalar("\u{0378}")
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text(cascade.runFaces, String(scalar))],
            scaleFactor: 1,
            drawMissingGlyphs: false
        )
        let line = try XCTUnwrap(resolved.makeGlyphs().first)

        XCTAssertEqual(line.width, 0)
        XCTAssertGreaterThan(line.height, 0)
    }

    // ASSERTIONS textZeroWidthScalarLineMetricsObserved
    @MainActor
    func testZeroWidthControlsDoNotBecomeLastResortGlyphs() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en")
        environment.defaultFontRenderingMode = .vector()
        let font = VUI.Font(provider: AnyFontBox(SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        )))
        let sceneResources = SceneResources()
        let faces = font.typefaceCascade(
            in: environment,
            forContext: sceneResources,
            contentScaleFactor: 1
        ).runFaces

        for scalar in [UnicodeScalar("\u{200B}"), UnicodeScalar("\u{200D}")] {
            let resolved = GraphicsContext.ResolvedText(
                runs: [.text(faces, String(scalar))],
                scaleFactor: 1,
                drawMissingGlyphs: true
            )
            let line = try XCTUnwrap(resolved.makeGlyphs().first)
            XCTAssertEqual(line.width, 0, "Unexpected width for \(scalar)")
            XCTAssertGreaterThan(line.height, 0)
        }
    }

    @MainActor
    func testUnmodifiedFormatStyleTextEnablesLastResortGlyph() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "en")
        environment.defaultFontRenderingMode = .vector()
        let context = GraphTextResolutionContext(
            environment: environment,
            sceneResources: SceneResources()
        )
        let resolved = try XCTUnwrap(Text(
            0,
            format: UnsupportedScalarStringStyle()
        )._resolve(context: context, referenceDate: Date()))
        let glyph = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs.first)

        XCTAssertEqual(glyph.scalar, UnicodeScalar("\u{0378}"))
        XCTAssertGreaterThan(glyph.advance.width, 0)
    }
}

private final class FontModifierEnvironmentRecorder {
    var modifiers: [AnyFontModifier]?
}

private struct FontModifierEnvironmentProbe: View, TestPrimitiveView {
    typealias Body = Never

    let recorder: FontModifierEnvironmentRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "FontModifierEnvironmentProbe._makeView called outside an active graph."
            )
        }
        view._attribute.value.recorder.modifiers =
            inputs.base.cachedEnvironment.value.environment.value.fontModifiers
        let layout = graph.makeInput(value: LayoutComputer.fixed(.zero))
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private enum TrueTypeCollectionError: Error {
    case invalidFont
    case sizeOverflow
}

private func makeTrueTypeCollection(fonts: [Data]) throws -> Data {
    guard !fonts.isEmpty,
          fonts.count <= Int(UInt32.max) else {
        throw TrueTypeCollectionError.invalidFont
    }

    let headerSize = 12 + fonts.count * 4
    var collection = Data(repeating: 0, count: alignedToFour(headerSize))
    var fontOffsets: [UInt32] = []

    for source in fonts {
        guard source.count >= 12 else {
            throw TrueTypeCollectionError.invalidFont
        }
        let numTables = Int(readUInt16BigEndian(source, at: 4))
        let directoryEnd = 12 + numTables * 16
        guard directoryEnd <= source.count else {
            throw TrueTypeCollectionError.invalidFont
        }

        appendAlignmentPadding(to: &collection)
        let fontOffset = collection.count
        guard fontOffset <= Int(UInt32.max) else {
            throw TrueTypeCollectionError.sizeOverflow
        }
        fontOffsets.append(UInt32(fontOffset))

        var embedded = source
        for tableIndex in 0..<numTables {
            let recordOffset = 12 + tableIndex * 16
            let tableOffsetPosition = recordOffset + 8
            let tableOffset = Int(readUInt32BigEndian(
                embedded,
                at: tableOffsetPosition
            ))
            let tableLength = Int(readUInt32BigEndian(
                embedded,
                at: recordOffset + 12
            ))
            guard tableOffset <= embedded.count,
                  tableLength <= embedded.count - tableOffset,
                  fontOffset <= Int(UInt32.max) - tableOffset else {
                throw TrueTypeCollectionError.invalidFont
            }
            writeUInt32BigEndian(
                UInt32(fontOffset + tableOffset),
                to: &embedded,
                at: tableOffsetPosition
            )
        }
        collection.append(embedded)
    }

    writeUInt32BigEndian(0x7474_6366, to: &collection, at: 0) // ttcf
    writeUInt32BigEndian(0x0001_0000, to: &collection, at: 4)
    writeUInt32BigEndian(UInt32(fonts.count), to: &collection, at: 8)
    for (index, offset) in fontOffsets.enumerated() {
        writeUInt32BigEndian(offset, to: &collection, at: 12 + index * 4)
    }
    return collection
}

private func alignedToFour(_ value: Int) -> Int {
    (value + 3) & ~3
}

private func appendAlignmentPadding(to data: inout Data) {
    let alignedCount = alignedToFour(data.count)
    if alignedCount > data.count {
        data.append(Data(repeating: 0, count: alignedCount - data.count))
    }
}

private func readUInt16BigEndian(_ data: Data, at offset: Int) -> UInt16 {
    (UInt16(data[offset]) << 8) |
        UInt16(data[offset + 1])
}

private func readUInt32BigEndian(_ data: Data, at offset: Int) -> UInt32 {
    (UInt32(data[offset]) << 24) |
        (UInt32(data[offset + 1]) << 16) |
        (UInt32(data[offset + 2]) << 8) |
        UInt32(data[offset + 3])
}

private func writeUInt32BigEndian(
    _ value: UInt32,
    to data: inout Data,
    at offset: Int
) {
    data[offset] = UInt8(truncatingIfNeeded: value >> 24)
    data[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
    data[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
    data[offset + 3] = UInt8(truncatingIfNeeded: value)
}

private struct UnsupportedScalarStringStyle: FormatStyle {
    func format(_ value: Int) -> String { "\u{0378}" }
}

private final class CascadeTestTypeface: Typeface {
    let identifier: String
    let supported: Set<UnicodeScalar>
    let ascender: CGFloat
    let descender: CGFloat

    init(
        identifier: String,
        supported: Set<UnicodeScalar>,
        ascender: CGFloat = 8,
        descender: CGFloat = -2
    ) {
        self.identifier = identifier
        self.supported = supported
        self.ascender = ascender
        self.descender = descender
    }

    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? { nil }

    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics? {
        guard hasGlyph(for: c) else { return nil }
        return TypefaceGlyphMetrics(
            advance: CGSize(width: 8, height: lineHeight),
            ascender: ascender,
            descender: descender
        )
    }

    func kernAdvance(
        left: UnicodeScalar,
        right: UnicodeScalar
    ) -> CGPoint {
        .zero
    }

    func hasGlyph(for scalar: UnicodeScalar) -> Bool {
        supported.contains(scalar)
    }

    var lineHeight: CGFloat { ascender - descender }

    func isEqual(to other: any Typeface) -> Bool {
        self === (other as AnyObject)
    }

    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

private final class MissingGlyphTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]
    private(set) var loadedURLs: [URL] = []

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
        if data != nil {
            loadedURLs.append(url)
        }
    }

    func checkWindowActivities() {
    }
}
