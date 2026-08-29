import XCTest
import VVD
@testable import VUI

final class ResolvedTextMissingGlyphTests: XCTestCase {
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

    func testBackendLoadsGlyphZeroForUnsupportedScalarInBothPaths() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let data = try Data(contentsOf: url)
        let font = try XCTUnwrap(VVD.Font(data: data))
        font.setStyle(
            pointSize: 17,
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

        XCTAssertEqual(configuration.version, 1)
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
        XCTAssertEqual(configuration.systemFont.rawValue, "Roboto")
        XCTAssertEqual(configuration.missingGlyphFont.rawValue, "LastResort")
    }

    func testBundledConfigurationRejectsTerminalFontInLocaleCascade() {
        let data = Data(#"""
        {
          "version": 1,
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
          "systemFont": "Roboto",
          "defaultLocale": "en",
          "locales": {
            "en": ["Roboto", "NotoSansCJK"]
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
          "version": 1,
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
          "systemFont": "Roboto",
          "defaultLocale": "ko",
          "locales": {
            "en": ["Roboto", "NotoSansCJK"]
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
          "version": 1,
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
          "systemFont": "Primary",
          "defaultLocale": "en",
          "locales": {
            "en": ["Primary"]
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
          "version": 1,
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
          "systemFont": "Primary",
          "defaultLocale": "en",
          "locales": {
            "en": ["Primary"]
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

    func testBundledCatalogMapsFontWeightsToStaticFiles() throws {
        let catalog = BundledFontCatalog.shared
        let locale = Locale(identifier: "en")

        func file(
            _ family: String,
            _ weight: VUI.Font.Weight
        ) throws -> String {
            try XCTUnwrap(catalog.resource(
                for: BundledFontID(family),
                locale: locale,
                weight: weight.value
            )).url.lastPathComponent
        }

        XCTAssertEqual(try file("Roboto", .ultraLight), "Roboto-Thin.ttf")
        XCTAssertEqual(try file("Roboto", .thin), "Roboto-Thin.ttf")
        XCTAssertEqual(try file("Roboto", .light), "Roboto-Light.ttf")
        XCTAssertEqual(try file("Roboto", .regular), "Roboto-Regular.ttf")
        XCTAssertEqual(try file("Roboto", .medium), "Roboto-Medium.ttf")
        XCTAssertEqual(try file("Roboto", .semibold), "Roboto-Bold.ttf")
        XCTAssertEqual(try file("Roboto", .bold), "Roboto-Bold.ttf")
        XCTAssertEqual(try file("Roboto", .heavy), "Roboto-Black.ttf")
        XCTAssertEqual(try file("Roboto", .black), "Roboto-Black.ttf")

        XCTAssertEqual(
            try file("NanumSquareNeo", .light),
            "NanumSquareNeo-aLt.ttf"
        )
        XCTAssertEqual(
            try file("NanumSquareNeo", .regular),
            "NanumSquareNeo-bRg.ttf"
        )
        XCTAssertEqual(
            try file("NanumSquareNeo", .semibold),
            "NanumSquareNeo-cBd.ttf"
        )
        XCTAssertEqual(
            try file("NanumSquareNeo", .heavy),
            "NanumSquareNeo-dEb.ttf"
        )
        XCTAssertEqual(
            try file("NanumSquareNeo", .black),
            "NanumSquareNeo-eHv.ttf"
        )

        XCTAssertEqual(
            try file("NanumGothic", .light),
            "NanumGothicLight.ttf"
        )
        XCTAssertEqual(
            try file("NanumGothic", .regular),
            "NanumGothic.ttf"
        )
        XCTAssertEqual(
            try file("NanumGothic", .bold),
            "NanumGothicBold.ttf"
        )
        XCTAssertEqual(
            try file("NanumGothic", .heavy),
            "NanumGothicExtraBold.ttf"
        )
        XCTAssertFalse(
            catalog.configuration.fonts(for: Locale(identifier: "ko"))
                .contains(BundledFontID("NanumGothic"))
        )
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

    init(identifier: String, supported: Set<UnicodeScalar>) {
        self.identifier = identifier
        self.supported = supported
    }

    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? { nil }

    func glyphMetrics(for c: UnicodeScalar) -> TypefaceGlyphMetrics? {
        guard hasGlyph(for: c) else { return nil }
        return TypefaceGlyphMetrics(
            advance: CGSize(width: 8, height: 10),
            ascender: 8,
            descender: -2
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

    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }

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
