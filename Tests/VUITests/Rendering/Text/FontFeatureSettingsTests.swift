import Foundation
import XCTest
import VVD
@testable import VUI

final class FontFeatureSettingsTests: XCTestCase {
    private func font(_ index: Int) throws -> VVD.Font {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let name = index == 0 ? "Roboto/Roboto-VariableFont_wdth,wght.ttf"
                              : "NotoSansKR/NotoSansKR-VariableFont_wght.ttf"
        let font = try XCTUnwrap(VVD.Font(path: root.appendingPathComponent(
            "Sources/VUI/Resources/Fonts/" + name).path))
        font.setPointSize(23, dpi: (72, 72))
        return font
    }

    private func request(_ tag: String, _ value: UInt32) -> TypefaceShapingFeature {
        TypefaceShapingFeature(tag: tag, value: value)!
    }

    // ASSERTIONS fontCascadeRequestFlags27Observed fontFallbackInputs27Observed textAttributedCharacterOwner27Observed
    func testDefaultFallbackFlagsUseSelectedExtrasAndReachOriginalTailComparison() throws {
        let roboto = VectorTypeface(font: try font(0))
        let noto = VectorTypeface(font: try font(1))
        for (requests, hasExtras): ([TypefaceShapingFeature], Bool) in [
            ([], false), ([request("tnum", 1)], false),
            ([request("liga", 1)], false), ([request("liga", 0)], true),
            ([request("dlig", 1)], true)
        ] {
            let primary = ShapingFeatureTypeface(noto, features: requests)
            for isDefault in [false, true] {
                let cascade = TypefaceCascade(ordinaryFaces: [roboto, primary], missingGlyphFace: nil,
                    primaryIndex: 1, defaultFallbackIndices: isDefault ? IndexSet(integer: 0) : [])
                let fallback = cascade.runFaces[0]
                let font = try XCTUnwrap(fallback.selectedFont)
                let equal = !isDefault || hasExtras
                XCTAssertEqual(font.flags, equal ? 192 : 200)
                XCTAssertFalse(font.hasExtras)
                XCTAssertEqual(font.isEqual(to: try XCTUnwrap(roboto.selectedFont)), equal)
                let source = ResolvedTextSource(runs: [
                    .text([roboto], "e\u{301}"), .text([fallback], "\u{323}")
                ], scaleFactor: 1)
                let line = try XCTUnwrap(source.makeGlyphLayout(maxWidth: 500, maximumHeight: 500).lines.first)
                XCTAssertEqual(line.glyphs.map(\.glyphIndex), [1107, 65535, equal ? 169 : 65535])
                XCTAssertEqual(line.glyphs.map(\.characterIndex), [0, 1, 2])
            }
        }
    }

    private func descriptorSelectionControls() throws -> [Typeface] {
        let roboto = VectorTypeface(font: try font(0))
        let noto = VectorTypeface(font: try font(1))
        let requests: [[(String, UInt32)]?] = [
            nil, [], [("liga", 0)], [("liga", 1)], [("liga", 2)],
            [("dlig", 0)], [("dlig", 1)], [("dlig", 2)],
            [("tnum", 0)], [("tnum", 1)], [("tnum", 2)],
            [("ss01", 1)], [("ss01", 2)], [("xxxx", 1)],
            [("liga", 0), ("dlig", 1)], [("dlig", 1), ("liga", 0)],
            [("liga", 0), ("liga", 1)], [("liga", 1), ("liga", 0)],
            [("liga", 0), ("liga", 0)], [("liga", 1), ("liga", 1)],
            [("xxxx", 1), ("liga", 1)]
        ]
        func direct(_ base: Typeface) -> [Typeface] {
            requests.map { values in
                guard let values else { return base }
                return ShapingFeatureTypeface(base, features: values.map(request))
            }
        }
        let ordinary = direct(roboto)
        var faces = ordinary
        faces += ordinary.map {
            TypefaceCascade(ordinaryFaces: [noto, $0], missingGlyphFace: nil).runFaces[1]
        }
        for own in direct(noto) {
            for original in [[], [request("liga", 1)]] {
                faces.append(TypefaceCascade(ordinaryFaces: [roboto, own], missingGlyphFace: nil,
                    isSystemFont: true, shapingFeatures: original, fallbackFeatures: original).runFaces[1])
            }
        }
        return faces + direct(noto)
    }

    // ASSERTIONS fontDescriptorSelection27Observed fontFallbackInputs27Observed
    func testSelectedDescriptorsPreserveRequestArraysAndSystemOwnership() throws {
        let faces = try descriptorSelectionControls()
        // Fixed equality classes for the direct, ordinary fallback, system
        // fallback and second direct face controls, in construction order.
        let groups = [
            0, 0, 2, 0, 0, 0, 6, 6, 0, 9, 9, 11, 11, 0, 14, 14, 0, 2, 2, 0, 0,
            0, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41,
            42, 42, 44, 44, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57,
            58, 59, 60, 61, 62, 63, 64, 64, 66, 66, 68, 68, 70, 71, 72, 73,
            74, 75, 76, 77, 78, 79, 80, 81, 82, 83,
            84, 84, 86, 84, 84, 84, 90, 90, 84, 84, 84, 84, 84, 84, 98, 98, 84, 86, 86, 84, 84
        ]
        XCTAssertEqual(faces.count, groups.count)
        let fonts = try faces.map { try XCTUnwrap($0.selectedFont) }
        for i in fonts.indices {
            for j in fonts.indices {
                XCTAssertEqual(fonts[i].isEqual(to: fonts[j]), groups[i] == groups[j], "\(i),\(j)")
            }
        }
        XCTAssertNil(fonts[0].descriptor.featureRequests)
        XCTAssertEqual(fonts[22].descriptor.featureRequests, [])
        XCTAssertTrue(fonts[42].descriptor.isSystemFont)
        XCTAssertFalse(fonts[84].descriptor.isSystemFont)
        XCTAssertEqual(fonts[46].originalFeatures, [request("liga", 0)])
        XCTAssertTrue(fonts[47].originalFeatures.isEmpty)
        XCTAssertEqual(fonts[46].descriptor, fonts[47].descriptor)
        XCTAssertFalse(faces[2].isEqual(to: faces[23]))
        XCTAssertFalse(faces[42].isEqual(to: faces[84]))
    }

    // ASSERTIONS fontDescriptorSelection27Observed textAttributedCharacterOwner27Observed
    func testRetainedDescriptorRequestsReachOriginalTailComposition() throws {
        let faces = try descriptorSelectionControls()
        let equal = Set([0, 1, 3, 4, 5, 8, 13, 16, 19, 20, 21])
        for index in 0..<42 {
            let source = ResolvedTextSource(runs: [
                .text([faces[0]], "e\u{301}"), .text([faces[index]], "\u{323}")
            ], scaleFactor: 1)
            let line = try XCTUnwrap(source.makeGlyphLayout(maxWidth: 500, maximumHeight: 500).lines.first)
            XCTAssertEqual(line.glyphs.map(\.glyphIndex), [1107, 65535, equal.contains(index) ? 169 : 65535],
                           "tail \(index)")
            XCTAssertEqual(line.glyphs.map(\.characterIndex), [0, 1, 2])
            let layout = source.makeLayout(in: .init(width: 500, height: 500), layoutDirection: .leftToRight)
            XCTAssertEqual(Set(layout.glyphAtoms().flatMap { Array($0.sourceRange) }), [0, 1, 2])
        }
    }

    // ASSERTIONS fontLanguageConstruction27Observed fontStructureInputs27Observed
    func testSelectedFontLanguagesKeepOriginalExtrasAndInheritedFlags() throws {
        let roboto = VectorTypeface(font: try font(0))
        let noto = VectorTypeface(font: try font(1))
        let controls: [(UInt32, [String?])] = [
            (0xc0, [
                nil, "", "en", "en-US", "ZH", "ZH-hant",
                "Zh-Hans", "zH-TW", "zhblah", "chi", "cmn", "nan",
                "hak", "und", "und-Hans", "und-Hant", "und-TW", "und-CN",
                "und-Hani", "en-Hans", "en-Hant", "en-TW", "ja", "ko",
                "bogus", " zh", "zh "
            ]),
            (0xe0, [
                "zh", "zh-Hans", "zh-Hant", "zh_TW", "zh_CN", "zh_HK",
                "zh_MO", "zh-US", "zh-Latn", "zh_Arab", "zho", "yue",
                "yue-Hans", "yue-Hant", "yue_CN", "yue_HK", "yue_MO", "YUE",
                "Yue-Hant", "wuu", "wuu-Hans", "wuu-Hant", "wuu_HK", "wuu_MO",
                "WUU", "zh-Zzzz", "yue-Zzzz", "wuu-Zzzz", "zh-", "zh_",
                "zh-Hans-HK", "zh-Hant-CN", "zh-abc", "yue-Latn", "wuu-Latn"
            ])
        ]
        var fallbacks: [(SelectedFont, UInt32)] = []
        for (flags, languages) in controls {
            for language in languages {
                let primary = ShapingFeatureTypeface(noto, features: [], fontLanguage: language)
                let selected = try XCTUnwrap(primary.selectedFont)
                XCTAssertEqual(selected.language, language)
                XCTAssertEqual(selected.flags, flags, language ?? "absent")
                XCTAssertNil(selected.descriptor.language)
                let faces = TypefaceCascade(ordinaryFaces: [roboto, primary], missingGlyphFace: nil,
                    primaryIndex: 1).runFaces
                let keptPrimary = try XCTUnwrap(faces[1].selectedFont)
                XCTAssertEqual(keptPrimary.language, language)
                XCTAssertEqual(keptPrimary.flags, flags)
                let fallback = try XCTUnwrap(faces[0].selectedFont)
                XCTAssertNil(fallback.language)
                XCTAssertEqual(fallback.flags, flags, language ?? "absent")
                fallbacks.append((fallback, flags))
            }
        }
        for (first, a) in fallbacks {
            for (second, b) in fallbacks {
                XCTAssertEqual(first.isEqual(to: second), a == b)
            }
        }
        let own = ShapingFeatureTypeface(roboto, features: [], fontLanguage: "en")
        let selected = try XCTUnwrap(TypefaceCascade(ordinaryFaces: [noto, own], missingGlyphFace: nil,
            fontLanguage: "zh").runFaces[1].selectedFont)
        XCTAssertEqual(selected.descriptor.language, "en")
        XCTAssertNil(selected.language)
        XCTAssertEqual(selected.flags, 0xe0)
    }

    // ASSERTIONS fontFallbackInputs27Observed
    func testCascadeRequestsPreserveCommonOriginalsBeforeFaceSelection() throws {
        let common = """
            abvf abvs afrc akhn blwf blws c2pc c2sc calt case ccmp cfar cjct clig cpsp dlig
            expt falt fin2 fin3 fina frac fwid half haln halt hist hkna hlig hngl hojo hwid
            init isol ital jp04 jp78 jp83 jp90 kern liga ljmo lnum locl ltra ltrm med2 medi
            mgrk mset nlck nukt onum ordn palt pcap pkna pnum pref pres pstf psts pwid qwid
            rkrf rlig rphf rtla rtlm ruby rvrn sinf smcp smpl subs sups titl tjmo tnam tnum
            trad twid unic valt vatu vert vhal vjmo vkna vkrn vpal vrt2 vrtr zero
            """.split(separator: " ").flatMap { $0.split(whereSeparator: \.isWhitespace) }
        for tag in common {
            let value = request(String(tag), 1)
            XCTAssertEqual(VVD.FontFeatures.cascadeRequests([value]), [value], String(tag))
        }
        for tag in ["aalt", "abvm", "blwm", "cswh", "curs", "dist", "mark", "mkmk",
                    "rclt", "size", "swsh", "numr", "cv01", "xxxx"] +
            (1...20).map({ String(format: "ss%02d", $0) }) {
            XCTAssertTrue(VVD.FontFeatures.cascadeRequests([request(tag, 1)]).isEmpty, tag)
        }
        for values: [UInt32] in [[0, 1, 0], [1, 0, 1], [0, 1, 0, 1], [1, 0, 1, 0]] {
            let requests = values.map { request("liga", $0) }
            XCTAssertEqual(VVD.FontFeatures.cascadeRequests(requests), Array(requests.prefix(2)))
        }
        let unsupported = request("fwid", 1)
        XCTAssertTrue(try font(0).featureCatalog.select([unsupported]).isEmpty)
        XCTAssertEqual(VVD.FontFeatures.cascadeRequests([unsupported]), [unsupported])
    }

    // ASSERTIONS fontFallbackInputs27Observed
    func testCascadeSeparatesPrimarySettingsFromFallbackDescriptorSettings() throws {
        let primary = VectorTypeface(font: try font(1))
        let fallback = VectorTypeface(font: try font(0))
        let disabled = request("liga", 0)
        let enabled = request("liga", 1)
        let ownFallback = ShapingFeatureTypeface(fallback, features: [disabled])
        func glyphs(_ face: Typeface) throws -> [UInt32] {
            try XCTUnwrap(face.shape("ffi", direction: nil, language: nil, features: [])).glyphs.map(\.index)
        }
        // A locale can place a configured fallback before the system primary.
        let ordinary = TypefaceCascade(ordinaryFaces: [fallback, primary], missingGlyphFace: fallback,
            primaryIndex: 1, shapingFeatures: [disabled])
        XCTAssertEqual(try ordinary.runFaces.map(glyphs), [[473], [71, 71, 74], [473]])
        let original = [disabled, enabled, disabled]
        let inherited = TypefaceCascade(ordinaryFaces: [ownFallback, primary], missingGlyphFace: ownFallback,
            primaryIndex: 1, shapingFeatures: original,
            fallbackFeatures: VVD.FontFeatures.cascadeRequests(original))
        XCTAssertEqual(try inherited.runFaces.map(glyphs), [[473], [71, 71, 74], [473]])
        let own = TypefaceCascade(ordinaryFaces: [primary, ownFallback], missingGlyphFace: nil,
            shapingFeatures: [enabled])
        XCTAssertEqual(try own.runFaces.map(glyphs), [[21582], [74, 74, 77]])
        let rows = inherited.runFaces
        XCTAssertTrue(try XCTUnwrap(rows[0].selectedFont).features.isEmpty)
        XCTAssertEqual(try XCTUnwrap(rows[1].selectedFont).features.first?.selector, 3)
        XCTAssertEqual(rows[0].shape("ffi", direction: nil, language: nil,
            features: [disabled])?.glyphs.map(\.index), [74, 74, 77])
    }

    // ASSERTIONS fontFeatureNormalization27Observed
    func testSelectedSettingEqualityIgnoresOrderAndMappedRawValues() throws {
        let catalog = try font(0).featureCatalog
        let a = catalog.select([request("tnum", 1), request("ss01", 1)])
        let b = catalog.select([request("ss01", 2), request("tnum", 2)])
        XCTAssertTrue(VVD.FontFeatures.settingsEqual(a, b))
        XCTAssertFalse(VVD.FontFeatures.settingsEqual(a, catalog.select([request("tnum", 1)])))
        XCTAssertFalse(VVD.FontFeatures.settingsEqual(catalog.select([request("numr", 1)]),
                                                     catalog.select([request("numr", 2)])))
        let face = VectorTypeface(font: try font(0))
        var artworkLoads = 0
        let deferred = DeferredGlyphTypeface(metrics: face) { artworkLoads += 1; return nil }
        let lhs = ShapingFeatureTypeface(deferred, features: [request("tnum", 1)])
        let rhs = ShapingFeatureTypeface(deferred, features: [request("tnum", 2)])
        XCTAssertFalse(lhs.isEqual(to: rhs))
        XCTAssertTrue(try XCTUnwrap(lhs.selectedFont).isEqual(to: XCTUnwrap(rhs.selectedFont)))
        XCTAssertEqual(artworkLoads, 0)
    }

    // ASSERTIONS fontFeaturePolicy27Observed fontFeatureNormalization27Observed
    func testSelectedSettingsPreserveMappedIdentifiersAndCustomValues() throws {
        let catalog = try font(0).featureCatalog
        for (tag, type, selector): (String, UInt16, UInt16) in [
            ("liga", 1, 3), ("tnum", 6, 0), ("ss01", 35, 2),
            ("smcp", 37, 1), ("pnum", 6, 1), ("dlig", 1, 4)
        ] {
            for value: UInt32 in tag == "liga" ? [0] : [1, 2, 3] {
                let selected = try XCTUnwrap(catalog.select([request(tag, value)]).first)
                XCTAssertEqual(selected.tag, request(tag, value).tag)
                XCTAssertEqual(selected.value, value)
                XCTAssertEqual(selected.type, type)
                XCTAssertEqual(selected.selector, selector)
            }
        }
        for tag in ["kern", "ccmp", "locl", "mark", "ss20", "xxxx"] {
            for value: UInt32 in [0, 1, 2] {
                XCTAssertTrue(catalog.select([request(tag, value)]).isEmpty, tag)
            }
        }
        for value: UInt32 in [1, 2] {
            let selected = try XCTUnwrap(catalog.select([request("numr", value)]).first)
            XCTAssertNil(selected.type)
            XCTAssertNil(selected.selector)
            XCTAssertEqual(selected.value, value)
        }
    }

    // ASSERTIONS fontFeaturePolicy27Observed
    func testAliasesRetainOriginalTagAndNumericAlternatesRejectInvalidRequest() throws {
        let catalog = try font(1).featureCatalog
        for (tags, selector): ([String], UInt16) in [
            (["palt", "vpal", "valt"], 5), (["pwid", "pkna"], 0), (["halt", "vhal"], 6)
        ] {
            for tag in tags {
                let selected = try XCTUnwrap(catalog.select([request(tag, 1)]).first)
                XCTAssertEqual(selected.type, 22)
                XCTAssertEqual(selected.selector, selector)
                XCTAssertEqual(selected.tag, request(tag, 1).tag)
            }
        }
        XCTAssertTrue(catalog.select([request("aalt", 3)]).isEmpty)
        XCTAssertEqual(catalog.select([request("aalt", 1), request("aalt", 3)]).first?.selector, 1)
        XCTAssertTrue(catalog.select([request("aalt", 2), request("aalt", 0)]).isEmpty)
        XCTAssertEqual(catalog.select([request("aalt", 2)]).first?.selector, 2)
        XCTAssertTrue(catalog.select([request("aalt", 65536)]).isEmpty)
        XCTAssertEqual(catalog.select([request("aalt", 65537)]).first?.selector, 1)
        XCTAssertEqual(catalog.select([request("aalt", 65538)]).first?.selector, 2)
        XCTAssertTrue(catalog.select([request("aalt", .max)]).isEmpty)
    }

    // ASSERTIONS fontFeaturePolicy27Observed fontFeatureNormalization27Observed
    func testNestedFontSettingsKeepFinalDefaultsSeparateFromPerCallFeatures() throws {
        let backend = try font(0)
        let ordinary = VectorTypeface(font: backend)
        let disabled = ShapingFeatureTypeface(ordinary, features: [request("liga", 0)])
        let enabled = ShapingFeatureTypeface(disabled, features: [request("liga", 1)])
        XCTAssertEqual(enabled.shape("ffi", direction: nil, language: nil, features: [])?.glyphs.map(\.index), [473])
        XCTAssertEqual(enabled.shape("ffi", direction: nil, language: nil,
            features: [request("liga", 0)])?.glyphs.map(\.index), [74, 74, 77])
        let descriptorKern = ShapingFeatureTypeface(ordinary, features: [request("kern", 0)])
        let baseline = try XCTUnwrap(ordinary.shape("AV", direction: nil, language: nil, features: []))
        let selected = try XCTUnwrap(descriptorKern.shape("AV", direction: nil, language: nil, features: []))
        let perCall = try XCTUnwrap(descriptorKern.shape("AV", direction: nil, language: nil,
            features: [request("kern", 0)]))
        XCTAssertEqual(selected.glyphs.map(\.advance), baseline.glyphs.map(\.advance))
        XCTAssertGreaterThan(perCall.glyphs.reduce(0) { $0 + $1.advance.width },
                             selected.glyphs.reduce(0) { $0 + $1.advance.width })
    }

    // ASSERTIONS fontFeaturePolicy27Observed
    func testOrientationAndTablePoliciesKeepOriginalTags() throws {
        let catalog = try font(1).featureCatalog
        func active(_ tag: String, vertical: Bool) -> Set<UInt32> {
            Set(catalog.shapingFeatures(catalog.select([request(tag, 1)]), vertical: vertical)
                .filter { $0.value != 0 }.map(\.tag))
        }
        for (horizontal, vertical) in [("palt", "vpal"), ("halt", "vhal")] {
            XCTAssertTrue(active(horizontal, vertical: false).contains(request(horizontal, 1).tag))
            XCTAssertFalse(active(horizontal, vertical: true).contains(request(horizontal, 1).tag))
            XCTAssertTrue(active(vertical, vertical: true).contains(request(vertical, 1).tag))
            XCTAssertFalse(active(vertical, vertical: false).contains(request(vertical, 1).tag))
        }
        XCTAssertFalse(active("pkna", vertical: false).contains(request("pwid", 1).tag))
        XCTAssertFalse(active("valt", vertical: true).contains(request("vpal", 1).tag))
        XCTAssertFalse(active("halt", vertical: false).contains(request("kern", 1).tag))
        XCTAssertFalse(active("vhal", vertical: true).contains(request("vkrn", 1).tag))
        XCTAssertTrue(active("fwid", vertical: false).contains(request("kern", 1).tag))
    }

    // ASSERTIONS fontFeaturePolicy27Observed
    func testFeatureCatalogFollowsTheLogicalShapingFace() throws {
        let rasterFont = try font(0)
        let logicalFont = try font(1)
        let face = VectorTypeface(font: rasterFont, layoutFont: logicalFont, renderScale: 2)
        let selected = try XCTUnwrap(face.featureCatalog).select([request("fwid", 1)])
        XCTAssertEqual(selected.first?.type, 22)
        XCTAssertEqual(selected.first?.selector, 1)
        XCTAssertTrue(rasterFont.featureCatalog.select([request("fwid", 1)]).isEmpty)
        let wrapped = ShapingFeatureTypeface(face, features: [request("fwid", 1)])
        XCTAssertEqual(wrapped.shape("A", direction: .leftToRight, language: nil, features: [])?
            .glyphs.map(\.index), [21684])
    }

    // ASSERTIONS fontFeaturePolicy27Observed
    func testHorizontalFontSettingsReachFixedASCIIGlyphsAndSources() throws {
        let backends = try [font(0), font(1)]
        let controls: [(Int, String, UInt32, [UInt32], [Int])] = [
            (0, "kern", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "kern", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "kern", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "liga", 0, [37, 58, 74, 74, 77, 21, 22, 23], [0, 1, 2, 3, 4, 5, 6, 7]),
            (0, "liga", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "liga", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "tnum", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "tnum", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "tnum", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "ss01", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "ss01", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "ss01", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "aalt", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "aalt", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "aalt", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "palt", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "palt", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "palt", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vpal", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vpal", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vpal", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "valt", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "valt", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "valt", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "pkna", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "pkna", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "pkna", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "pwid", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "pwid", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "pwid", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "halt", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "halt", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "halt", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vhal", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vhal", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vhal", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vert", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vert", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vert", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vrt2", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vrt2", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "vrt2", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "fwid", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "fwid", 1, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "fwid", 2, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "numr", 0, [37, 58, 473, 21, 22, 23], [0, 1, 2, 5, 6, 7]),
            (0, "numr", 1, [37, 58, 473, 122, 115, 116], [0, 1, 2, 5, 6, 7]),
            (0, "numr", 2, [37, 58, 473, 122, 115, 116], [0, 1, 2, 5, 6, 7]),
            (1, "kern", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "kern", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "kern", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "liga", 0, [34, 55, 71, 71, 74, 22523, 22524, 22525], [0, 1, 2, 3, 4, 5, 6, 7]),
            (1, "liga", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "liga", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "tnum", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "tnum", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "tnum", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "ss01", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "ss01", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "ss01", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "aalt", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "aalt", 1, [21684, 21705, 21721, 21721, 21724, 21668, 21669, 21670], [0, 1, 2, 3, 4, 5, 6, 7]),
            (1, "aalt", 2, [22566, 22587, 22603, 22603, 22606, 22550, 22551, 22552], [0, 1, 2, 3, 4, 5, 6, 7]),
            (1, "palt", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "palt", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "palt", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vpal", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vpal", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vpal", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "valt", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "valt", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "valt", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "pkna", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "pkna", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "pkna", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "pwid", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "pwid", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "pwid", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "halt", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "halt", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "halt", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vhal", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vhal", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vhal", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vert", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vert", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vert", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vrt2", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vrt2", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "vrt2", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "fwid", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "fwid", 1, [21684, 21705, 21582, 21668, 21669, 21670], [0, 1, 2, 5, 6, 7]),
            (1, "fwid", 2, [21684, 21705, 21582, 21668, 21669, 21670], [0, 1, 2, 5, 6, 7]),
            (1, "numr", 0, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "numr", 1, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
            (1, "numr", 2, [34, 55, 21582, 22523, 22524, 22525], [0, 1, 2, 5, 6, 7]),
        ]
        for (fontIndex, tag, value, glyphs, indices) in controls {
            let face = ShapingFeatureTypeface(VectorTypeface(font: backends[fontIndex]),
                features: [request(tag, value)])
            let result = try XCTUnwrap(face.shape("AVffi123e\u{301}\u{323}", direction: .leftToRight,
                language: nil, features: []))
            let label = "\(fontIndex)/\(tag)/\(value)"
            let selected = result.glyphs.filter { $0.sourceIndex < 8 }
            let expected = zip(glyphs, indices).filter { $0.1 < 8 }
            XCTAssertEqual(selected.map(\.index), expected.map { $0.0 }, label)
            XCTAssertEqual(selected.map(\.sourceIndex), expected.map { $0.1 }, label)
        }
    }
}
