import Foundation
import Testing
import VVD
@testable import VUI

struct TypefaceDesignMetricsTests {
    private func resource(_ name: String) -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts").appendingPathComponent(name)
    }

    private func makeFont(data: Data? = nil) throws -> VVD.Font {
        let font = if let data {
            VVD.Font(data: data)
        } else {
            VVD.Font(path: resource("Roboto/Roboto-VariableFont_wdth,wght.ttf").path)
        }
        return try #require(font)
    }

    // ASSERTIONS fontLeadingBaseHeightProducerObserved
    // ASSERTIONS fontLeadingStyleGapDerivationObserved
    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    @Test
    func testDesignUnitsSurviveTypefaceScaleWithoutChangingRasterMetrics() throws {
        let layoutFont = try makeFont()
        let rasterFont = try makeFont()
        for size: CGFloat in [13, 17.25] {
            for scale: CGFloat in [1, 1.5, 2] {
                layoutFont.setPointSize(size, dpi: (72, 72))
                rasterFont.setPointSize(size, dpi: (UInt32(72 * scale), UInt32(72 * scale)))
                let face: Typeface = VectorTypeface(font: rasterFont, layoutFont: layoutFont, renderScale: scale)
                let rounded = face.resolvedMetrics
                let glyph = try #require(face.glyphMetrics(for: "A"))
                let metrics = try #require(face.designMetrics)
                let clipping = try #require(metrics.clipping)
                #expect(clipping.ascent == 1946)
                #expect(clipping.descent == 512)
                #expect(metrics.unitsPerEM == 2048)
                let components = [metrics.ascender, metrics.descender, metrics.height, metrics.lineGap]
                #expect(components == [1900, -500, 2400, 0])
                #expect(face.resolvedMetrics == rounded)
                #expect(face.glyphMetrics(for: "A")?.advance == glyph.advance)
                #expect(face.glyphMetrics(for: "A")?.ascender == glyph.ascender)
                #expect(face.glyphMetrics(for: "A")?.descender == glyph.descender)
                if size == 13 {
                    #expect(CGFloat(metrics.ascender) * size / CGFloat(metrics.unitsPerEM) == 12.060546875)
                    #expect(CGFloat(metrics.descender) * size / CGFloat(metrics.unitsPerEM) == -3.173828125)
                    #expect(CGFloat(clipping.ascent) * size / CGFloat(metrics.unitsPerEM) == 12.3525390625)
                    #expect(CGFloat(clipping.descent) * size / CGFloat(metrics.unitsPerEM) == 3.25)
                    #expect(rounded.ascender == 13 * scale)
                    #expect(rounded.descender == -4 * scale)
                }
            }
        }
    }

    // ASSERTIONS fontLeadingStyleGapDerivationObserved
    // ASSERTIONS fontLeadingExtraDataOwnershipObserved
    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    @Test
    func testSignedDesignGapPassesThroughFallbackWithoutLoadingGlyphArtwork() throws {
        let font = try makeFont(data: signedGapFixture())
        font.setPointSize(13, dpi: (72, 72))
        let raw: Typeface = VectorTypeface(font: font)
        var artworkLoads = 0
        let deferred = DeferredGlyphTypeface(metrics: raw) {
            artworkLoads += 1
            return nil
        }
        let cascade = TypefaceCascade(ordinaryFaces: [deferred], missingGlyphFace: raw,
            shapingFeatures: VUI.Font.MonospacedDigitModifier.shapingFeatures)
        let faces = cascade.runFaces
        let fontResource = VUI.Font.file(resource("Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 13)
            .platformFont(in: EnvironmentValues().fontResolutionContext)
        try #require(faces.count == 2)
        for face in faces {
            let metrics = try #require(face.designMetrics)
            #expect(metrics.clipping?.ascent == 2200)
            #expect(metrics.clipping?.descent == 710)
            #expect(metrics.unitsPerEM == 2048)
            let components = [metrics.ascender, metrics.descender, metrics.height, metrics.lineGap]
            #expect(components == [1900, -500, 2300, -100])
            #expect(face.resolvedMetrics.leading == 0)
            let resolved = try #require(fontResource.resolvedMetrics(for: face, scaleFactor: 1))
            #expect(resolved.outsets.top == 1.904296875)
            #expect(resolved.outsets.bottom == 1.3330078125)
        }
        #expect(artworkLoads == 0)
        #expect(!faces[1].hasGlyph(for: "A"))
        let copied = try #require(faces[0].designMetrics)
        font.setPointSize(31, dpi: (144, 96))
        #expect(copied.lineGap == -100)
        #expect(faces[0].designMetrics == copied)
    }

    // ASSERTIONS fontLeadingExtraDataOwnershipObserved
    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    @Test
    func testLayoutFaceOwnsDesignMetricsWhenArtworkUsesAnotherFace() throws {
        let layoutFont = try makeFont(data: signedGapFixture())
        let rasterFont = try makeFont()
        let face: Typeface = VectorTypeface(font: rasterFont, layoutFont: layoutFont, renderScale: 2)
        #expect(face.designMetrics?.lineGap == -100)
        #expect(rasterFont.designMetrics?.lineGap == 0)
        #expect(face.designMetrics?.clipping?.ascent == 2200)
        #expect(face.designMetrics?.clipping?.descent == 710)
        #expect(rasterFont.designMetrics?.clipping?.ascent == 1946)
        #expect(rasterFont.designMetrics?.clipping?.descent == 512)
    }

    // ASSERTIONS fontRawMetricFormatQuantizationObserved
    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    @Test
    func testOutlineFormatFollowsLogicalFaceThroughDeferredFallback() throws {
        let rasterFont = try makeFont()
        #expect(rasterFont.designMetrics?.outlineFormat == .trueType)
        let cases: [(String, VVD.Font.OutlineFormat)] = [
            ("NotoSansCJK/NotoSansCJK-VF.otf.ttc", .compactFontFormat),
            ("NanumSquareNeo/NanumSquareNeo-Variable.ttf", .trueType)
        ]
        for (name, format) in cases {
            let url = resource(name)
            let fileCandidate = VVD.Font(path: url.path)
            let memoryCandidate = VVD.Font(data: try Data(contentsOf: url))
            let file = try #require(fileCandidate)
            let memory = try #require(memoryCandidate)
            let expected = try #require(file.designMetrics)
            #expect(expected.outlineFormat == format)
            #expect(expected.unitsPerEM == 1000)
            #expect(expected.clipping?.ascent == (format == .trueType ? 850 : 1160))
            #expect(expected.clipping?.descent == (format == .trueType ? 255 : 288))
            for layoutFont in [file, memory] {
                for scale: CGFloat in [1, 2] {
                    let base: Typeface = VectorTypeface(font: rasterFont, layoutFont: layoutFont, renderScale: scale)
                    let deferred = DeferredGlyphTypeface(metrics: base) {
                        Issue.record("Metric format must not load glyph artwork")
                        return nil
                    }
                    let cascade = TypefaceCascade(ordinaryFaces: [deferred], missingGlyphFace: base,
                        shapingFeatures: VUI.Font.MonospacedDigitModifier.shapingFeatures)
                    for face in cascade.runFaces {
                        #expect(face.designMetrics == expected)
                        #expect(face.designMetrics?.outlineFormat == format)
                    }
                }
            }
        }
    }

    // ASSERTIONS textDrawingMarginClippingOutsetsObserved
    @Test
    func testAbsentClippingDoesNotBorrowArtworkMetricsOrDropNaturalMetrics() throws {
        let layoutFont = try makeFont(data: signedGapFixture(removeOS2: true))
        let rasterFont = try makeFont()
        let expected = try #require(layoutFont.designMetrics)
        #expect(expected.clipping == nil)
        #expect(rasterFont.designMetrics?.clipping != nil)
        let base: Typeface = VectorTypeface(font: rasterFont, layoutFont: layoutFont, renderScale: 2)
        let deferred = DeferredGlyphTypeface(metrics: base) {
            Issue.record("Absent clipping must not load glyph artwork")
            return nil
        }
        let cascade = TypefaceCascade(ordinaryFaces: [deferred], missingGlyphFace: base,
            shapingFeatures: VUI.Font.MonospacedDigitModifier.shapingFeatures)
        let fontResource = VUI.Font.file(resource("Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: 13)
            .platformFont(in: EnvironmentValues().fontResolutionContext)
        for face in cascade.runFaces {
            #expect(face.designMetrics == expected)
            #expect(face.designMetrics?.lineGap == -100)
            let resolved = try #require(fontResource.resolvedMetrics(for: face, scaleFactor: 2))
            #expect(resolved.ascender == 12.060546875)
            #expect(resolved.descender == -3.173828125)
            #expect(resolved.outsets == EdgeInsets())
        }
    }

    // ASSERTIONS fontLeadingBaseHeightProducerObserved
    @Test
    func testBitmapOnlyFaceRetainsAbsentDesignMetricsThroughDeferredArtwork() throws {
        let fontCandidate = VVD.Font(path: resource("NotoColorEmoji/NotoColorEmoji.ttf").path)
        let font = try #require(fontCandidate)
        let face: Typeface = VectorTypeface(font: font)
        #expect(!font.isScalable)
        let deferred = DeferredGlyphTypeface(metrics: face) {
            Issue.record("Design metrics must not load glyph artwork")
            return nil
        }
        let terminal: Typeface = TerminalFallbackTypeface(deferred)
        #expect(terminal.designMetrics == nil)
        #expect(terminal.resolvedMetrics == face.resolvedMetrics)
    }

    private func signedGapFixture(removeOS2: Bool = false) throws -> Data {
        var data = try Data(contentsOf: resource("Roboto/Roboto-VariableFont_wdth,wght.ttf"))
        func read16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        }
        func read32(_ offset: Int) -> Int {
            Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 |
                Int(data[offset + 2]) << 8 | Int(data[offset + 3])
        }
        var offsets: [String: Int] = [:]
        for index in 0..<Int(read16(4)) {
            let record = 12 + index * 16
            let tag = String(decoding: data[record..<record + 4], as: UTF8.self)
            offsets[tag] = read32(record + 8)
            if removeOS2 && tag == "OS/2" {
                // Keep the bytes but remove the table's recognized directory entry.
                data.replaceSubrange(record..<record + 4, with: "ZZZZ".utf8)
            }
        }
        let hhea = try #require(offsets["hhea"])
        let os2 = try #require(offsets["OS/2"])
        let selection = read16(os2 + 62) & ~UInt16(128)
        for (offset, value) in [(hhea + 8, UInt16(bitPattern: Int16(-100))), (os2 + 62, selection),
                               (os2 + 74, UInt16(2200)), (os2 + 76, UInt16(710))] {
            data[offset] = UInt8(truncatingIfNeeded: value >> 8)
            data[offset + 1] = UInt8(truncatingIfNeeded: value)
        }
        return data
    }
}
