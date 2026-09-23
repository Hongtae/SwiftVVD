import Dispatch
import Synchronization
import XCTest
import VVD
@testable import VUI

final class ResolvedTextMissingGlyphTests: XCTestCase {
    // ASSERTIONS fontPlatformRedaction27Observed
    @MainActor
    func testRedactedCascadeDoesNotRestoreResolvedOrEnvironmentFeatures() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let context = environment.fontResolutionContext
        let descriptor = VUI.Font.custom("Roboto-Regular", fixedSize: 23).resolveDescriptor(in: context)
            .adding(features: [TypefaceShapingFeature(tag: "liga", value: 0)!])
        let font = VUI.Font(provider: FontBox(VUI.Font.PlatformFontProvider(
            font: FontResource(descriptor: descriptor, in: context))))
        var redacted = environment
        redacted.shouldRedactContent = true
        for environmentDigits in [false, true] {
            redacted.fontModifiers = environmentDigits ? [.monospacedDigit] : []
            for applyModifiers in [false, true] {
                let cascade = font.typefaceCascade(in: redacted, forContext: SceneResources(),
                    contentScaleFactor: 1, applyEnvironmentModifiers: applyModifiers)
                let face = cascade.runFaces[try XCTUnwrap(cascade.primaryIndex)]
                let selected = try XCTUnwrap(face.selectedFont)
                XCTAssertEqual(selected.features.isEmpty, applyModifiers)
                let shaped = try XCTUnwrap(face.shape("ffi", direction: nil, language: nil, features: []))
                XCTAssertEqual(shaped.glyphs.map(\.index), applyModifiers ? [473] : [74, 74, 77])
            }
        }
        XCTAssertFalse(font.typefaceFeatures.isEmpty)
    }

    // Selected-font construction can wrap a resource without replacing it.
    private func resourceFace(_ face: Typeface?) -> Typeface? {
        (face as? ShapingFeatureTypeface)?.base ?? face
    }

    // ASSERTIONS fontCascadeRequestFlags27Observed fontFallbackInputs27Observed
    @MainActor
    func testConfiguredFallbackFlagsKeepCandidateSourceAndPrimaryExtras() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }
        for locale in ["en", "ko"] {
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: locale)
            environment.defaultFontRenderingMode = .vector()
            for original in [[], [TypefaceShapingFeature(tag: "liga", value: 1)!]] {
                let font = VUI.Font(typefaceProvider: SystemFontProvider(size: 23,
                    weight: .regular, design: .default, renderingMode: .vector()), features: original)
                let cascade = font.typefaceCascade(in: environment, forContext: SceneResources(),
                    contentScaleFactor: 1)
                let primary = try XCTUnwrap(cascade.primaryIndex)
                XCTAssertEqual(primary, locale == "en" ? 0 : 1)
                let faces = cascade.runFaces
                XCTAssertEqual(faces[primary].selectedFont?.flags, 192)
                if locale == "ko" { XCTAssertEqual(faces[0].selectedFont?.flags, 192) }
                let fallback = try XCTUnwrap(cascade.ordinaryFaces.firstIndex {
                    $0.identifier.hasPrefix("deferred:NotoSansKR:")
                })
                let expected: UInt32 = original.isEmpty ? 200 : 192
                XCTAssertEqual(faces[fallback].selectedFont?.flags, expected, locale)
                XCTAssertEqual(faces.last?.selectedFont?.flags, expected, locale)
            }
        }
    }

    // ASSERTIONS fontVariationExtras27Observed fontCascadeRequestFlags27Observed
    @MainActor
    func testConfiguredFallbackUsesRawVariationPresenceIncludingEmptyComparison() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }
        let url = try XCTUnwrap(defaultFontURL)
        let metadata = try XCTUnwrap(VVD.Font.metadata(path: url.path))
        let w: UInt32 = 0x7767_6874, h: UInt32 = 0x7764_7468, unknown: UInt32 = 0x4142_4344
        for (baseWeight, request, extra): (CGFloat, [UInt32: CGFloat], Bool) in [
            (400, [:], false), (400, [w: 400.0001], false), (400, [w: 400.001], true),
            (400, [h: 200], false), (400, [unknown: 400], true),
            (100, [:], false), (100, [w: 400], true), (100, [unknown: 400], false)
        ] {
            let instance = try XCTUnwrap(metadata.variationInstances.first { $0.coordinates == [baseWeight, 100] })
            let provider = BundledFontProvider(resource: .init(url: url), size: 23, weight: .regular,
                renderingMode: .vector(), variations: request.map { .init(tag: $0.key, value: $0.value) },
                appliesSyntheticWeight: false, instanceIndex: instance.index)
            var environment = EnvironmentValues()
            environment.defaultFontRenderingMode = .vector()
            let cascade = VUI.Font(typefaceProvider: provider).typefaceCascade(in: environment,
                forContext: SceneResources(), contentScaleFactor: 1)
            let faces = cascade.runFaces
            XCTAssertEqual(faces[0].selectedFont?.hasExtras, extra)
            let index = try XCTUnwrap(cascade.ordinaryFaces.firstIndex {
                $0.identifier.hasPrefix("deferred:NotoSansKR:")
            })
            let selected = try XCTUnwrap(faces[index].selectedFont)
            XCTAssertEqual(selected.flags, extra ? 192 : 200, "\(baseWeight), \(request)")
            if !extra { XCTAssertNil(selected.variationExtras) }
        }
    }

    // ASSERTIONS fontFallbackInputs27Observed fontDescriptorSelection27Observed
    @MainActor
    func testFontCascadeKeepsFileFeaturesAndPropagatesCommonSystemRequests() throws {
        let previousAppContext = appContext
        let testContext = MissingGlyphTestAppContext()
        appContext = testContext
        defer { appContext = previousAppContext }
        let requests = ["ss01", "fwid"].map { TypefaceShapingFeature(tag: $0, value: 1)! }
        for locale in ["en", "ko"] {
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: locale)
            environment.defaultFontRenderingMode = .vector()
            let font = VUI.Font(typefaceProvider: SystemFontProvider(size: 23,
                weight: .regular, design: .default, renderingMode: .vector()), features: requests)
            let cascade = font.typefaceCascade(in: environment, forContext: SceneResources(),
                contentScaleFactor: 1)
            let primary = try XCTUnwrap(cascade.primaryIndex)
            XCTAssertEqual(primary, locale == "en" ? 0 : 1)
            let faces = cascade.runFaces
            let original = try XCTUnwrap(faces[primary].selectedFont)
            XCTAssertEqual(original.features.map(\.type), [35])
            XCTAssertTrue(original.descriptor.isSystemFont)
            XCTAssertEqual(original.originalFeatures, [requests[1]])
            let fallbackIndex = try XCTUnwrap(cascade.ordinaryFaces.firstIndex {
                $0.identifier.hasPrefix("deferred:NotoSansKR:")
            })
            let fallback = faces[fallbackIndex]
            let selected = try XCTUnwrap(fallback.selectedFont)
            XCTAssertTrue(selected.descriptor.isSystemFont)
            XCTAssertTrue(selected.originalFeatures.isEmpty)
            XCTAssertEqual(selected.features.map(\.type), [22])
            XCTAssertEqual(selected.features.map(\.selector), [1])
            XCTAssertEqual(fallback.shape("123", direction: nil, language: nil, features: [])?
                .glyphs.map(\.index), [21668, 21669, 21670])
        }

        let backend = try XCTUnwrap(VVD.Font(data: Data(contentsOf: XCTUnwrap(defaultFontURL))))
        backend.setPointSize(23, dpi: (72, 72))
        let face = VectorTypeface(font: backend)
        let font = VUI.Font(typefaceProvider: FixedFontProvider(face), features: requests)
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "ko")
        environment.defaultFontRenderingMode = .vector()
        let cascade = font.typefaceCascade(in: environment, forContext: SceneResources(),
            contentScaleFactor: 1)
        XCTAssertEqual(cascade.primaryIndex, 0)
        XCTAssertTrue(cascade.fallbackFeatures.isEmpty)
        let fallbackIndex = try XCTUnwrap(cascade.ordinaryFaces.firstIndex {
            $0.identifier.hasPrefix("deferred:NotoSansKR:")
        })
        let fallback = cascade.runFaces[fallbackIndex]
        XCTAssertTrue(try XCTUnwrap(fallback.selectedFont).features.isEmpty)
        XCTAssertEqual(fallback.shape("123", direction: nil, language: nil, features: [])?
            .glyphs.map(\.index), [22523, 22524, 22525])
    }

    // ASSERTIONS fontFeatureNormalization27Observed
    @MainActor
    func testFontCascadePreservesFinalRepeatedFeatureRequest() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }
        let backend = try XCTUnwrap(VVD.Font(data: Data(contentsOf: XCTUnwrap(defaultFontURL))))
        backend.setPointSize(23, dpi: (72, 72))
        let face = VectorTypeface(font: backend)
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        for values: [UInt32] in [[0, 1, 0], [1, 0, 1], [0, 1, 0, 1], [1, 0, 1, 0]] {
            let requests = values.map { TypefaceShapingFeature(tag: 0x6c69_6761, value: $0) }
            let font = VUI.Font(typefaceProvider: FixedFontProvider(face), features: requests)
            let cascade = font.typefaceCascade(in: environment, forContext: SceneResources(),
                contentScaleFactor: 1)
            let selected = try XCTUnwrap(cascade.runFaces.first)
            let shaped = try XCTUnwrap(selected.shape("ffi", direction: .leftToRight,
                language: nil, features: []))
            let expected = try XCTUnwrap(backend.shape("ffi", features: [requests.last!]))
            XCTAssertEqual(shaped.glyphs.map(\.index), expected.glyphs.map(\.index))
            XCTAssertEqual(shaped.glyphs.map(\.sourceRange), expected.glyphs.map(\.sourceRange))
            XCTAssertEqual(shaped.glyphs.count, values.last == 0 ? 3 : 1)
        }
    }

    func testBackendFontTypesAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}

        requireSendable(VVD.Font.self)
        requireSendable(VVD.TextureFont.self)
    }

    func testBackendFontShapesLigaturesAndPreservesScalarClusters() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )

        let ligature = try XCTUnwrap(font.shape("ffi"))
        let disabledFeature = try XCTUnwrap(VVD.Font.ShapingFeature(
            tag: "liga",
            value: 0
        ))
        let separate = try XCTUnwrap(font.shape(
            "ffi",
            features: [disabledFeature]
        ))

        XCTAssertLessThan(ligature.glyphs.count, separate.glyphs.count)
        XCTAssertEqual(ligature.glyphs.first?.sourceRange, 0..<3)
        XCTAssertEqual(separate.glyphs.map(\.sourceRange), [0..<1, 1..<2, 2..<3])
    }

    func testBackendFontShapesCombiningSequenceAsSourceCluster() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )

        let shaped = try XCTUnwrap(font.shape("e\u{301}"))

        XCTAssertFalse(shaped.glyphs.isEmpty)
        XCTAssertTrue(shaped.glyphs.allSatisfy { $0.sourceRange == 0..<2 })
        XCTAssertGreaterThan(
            shaped.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width },
            0
        )
    }

    func testBackendFontShapesSecureMaskGlyph() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )

        let mask = UnicodeScalar("•")
        XCTAssertTrue(font.hasGlyph(for: mask))
        XCTAssertNotNil(font.glyphMetrics(for: mask))
        let shaped = try XCTUnwrap(font.shape("•••••"))
        XCTAssertEqual(shaped.glyphs.count, 5)
        XCTAssertGreaterThan(
            shaped.glyphs.reduce(CGFloat.zero) { $0 + $1.advance.width },
            0
        )
    }

    func testBackendFontGuessesRightToLeftShapingDirection() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))

        let shaped = try XCTUnwrap(font.shape("مرحبا"))

        XCTAssertEqual(shaped.direction, .rightToLeft)
    }

    func testBackendFontLoadsShapedGlyphByIndex() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )

        let shaped = try XCTUnwrap(font.shape("ffi"))
        let glyph = try XCTUnwrap(shaped.glyphs.first)

        XCTAssertNotNil(font.glyphMetrics(at: glyph.index))
        XCTAssertTrue(font.withGlyphBitmap(
            at: glyph.index,
            embolden: 0,
            outline: 0
        ) { _, _, _, _ in })

        var commands: [VVD.Font.OutlineCommand] = []
        XCTAssertNotNil(font.decomposeGlyphOutline(
            at: glyph.index
        ) { commands.append($0) })
        XCTAssertFalse(commands.isEmpty)
    }

    // ASSERTIONS textShapingClusterRuntimeObserved
    func testResolvedTextConsumesShapedGlyphIndicesAndSourceClusters() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )
        let face = VectorTypeface(font: font)
        let resolved = ResolvedTextSource(
            runs: [.text([face], "office")],
            scaleFactor: 1
        )

        let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)
        XCTAssertEqual(
            glyphs.compactMap(\.sourceRange),
            [0..<1, 1..<4, 4..<5, 5..<6]
        )
        XCTAssertTrue(glyphs.allSatisfy { $0.glyphIndex != nil })
        for glyph in glyphs {
            XCTAssertNotNil(face.glyph(at: try XCTUnwrap(glyph.glyphIndex)))
        }

        let layout = resolved.makeLayout(
            in: CGSize(width: 200, height: 100),
            layoutDirection: .leftToRight
        )
        let run = try XCTUnwrap(layout.first?.first)
        XCTAssertEqual(run.count, 4)
        XCTAssertEqual(run.characterIndices.map(\.value), [0, 1, 4, 5])

        let combining = ResolvedTextSource(
            runs: [.text([face], "e\u{301}x")],
            scaleFactor: 1
        )
        let combiningRun = try XCTUnwrap(combining.makeLayout(
            in: CGSize(width: 200, height: 100),
            layoutDirection: .leftToRight
        ).first?.first)
        XCTAssertEqual(combiningRun.count, 2)
        XCTAssertEqual(combiningRun.characterIndices.map(\.value), [0, 2])
        XCTAssertEqual(
            combining.glyphAtoms(
                in: CGSize(width: 200, height: 100)
            ).map(\.sourceRange),
            [0..<2, 2..<3]
        )
    }

    // ASSERTIONS textShapingClusterRuntimeObserved
    func testResolvedTextKeepsCombiningClusterAtomicAcrossWrapping() throws {
        let url = try XCTUnwrap(defaultFontURL)
        let font = try XCTUnwrap(VVD.Font(data: Data(contentsOf: url)))
        font.setPointSize(
            17,
            dpi: (UInt32(defaultDPI), UInt32(defaultDPI))
        )
        let face = VectorTypeface(font: font)
        let resolved = ResolvedTextSource(
            runs: [.text([face], "Ae\u{301}\u{323}B")],
            scaleFactor: 1
        )
        let unwrapped = try XCTUnwrap(resolved.makeGlyphs().first)
        let combiningGlyphs = unwrapped.glyphs.filter {
            $0.sourceRange == 1..<4
        }
        XCTAssertGreaterThan(
            combiningGlyphs.count,
            1,
            "ranges: \(unwrapped.glyphs.compactMap(\.sourceRange))"
        )

        let firstClusterWidth = try XCTUnwrap(
            unwrapped.glyphs.first?.advance.width
        )
        let wrapped = resolved.makeGlyphs(
            maxWidth: max(Int(floor(firstClusterWidth)), 1),
            maxHeight: .max
        )
        var clusterLines: [Range<Int>: Set<Int>] = [:]
        for (lineIndex, line) in wrapped.enumerated() {
            for range in line.glyphs.compactMap(\.sourceRange) {
                clusterLines[range, default: []].insert(lineIndex)
            }
        }
        XCTAssertTrue(clusterLines.values.allSatisfy { $0.count == 1 })
    }

    // ASSERTIONS textShapingClusterRuntimeObserved
    @MainActor
    func testTextFieldSelectionMapsLigatureInteriorsToClusterTrailingEdge()
        throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let layout = TextFieldSelectionLayout.resolve(
            text: "office",
            environment: environment,
            sceneResources: SceneResources(),
            leadingInset: 0,
            viewportOffset: 0
        )

        XCTAssertEqual(layout.characterOffsets.count, 7)
        XCTAssertLessThan(layout.characterOffsets[1], layout.characterOffsets[2])
        XCTAssertEqual(
            layout.characterOffsets[2],
            layout.characterOffsets[3],
            accuracy: 0.001
        )
        XCTAssertEqual(
            layout.characterOffsets[3],
            layout.characterOffsets[4],
            accuracy: 0.001
        )
        XCTAssertLessThan(layout.characterOffsets[4], layout.characterOffsets[5])
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

        let shaped = try XCTUnwrap(font.shape("ffi"))
        let shapedGlyph = try XCTUnwrap(shaped.glyphs.first)
        XCTAssertNotNil(font.glyphData(at: shapedGlyph.index))

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

        let resolved = ResolvedTextSource(
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
        let resolved = ResolvedTextSource(
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
        let resolved = ResolvedTextSource(
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
        let resolved = ResolvedTextSource(
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
        let resolved = ResolvedTextSource(
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
        let primaryFont = VUI.Font(typefaceProvider: primaryProvider)
        let fallbackFont = VUI.Font(typefaceProvider: fallbackProvider)
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
        let sharedFallbacks = [
            "Roboto", "NotoSans", "NotoSansKR", "NotoSansCJK",
            "NotoSansArabic", "NotoSansDevanagari", "NotoSansThai",
            "NotoSansBengali", "NotoSansHebrew", "NotoSansTamil",
            "NotoSansTelugu", "NotoSansKannada", "NotoSansMalayalam",
            "NotoSansGujarati", "NotoSansGurmukhi", "NotoSansOriya",
            "NotoSansSinhala", "NotoSansKhmer", "NotoSansLao",
            "NotoSansMyanmar", "NotoSansArmenian", "NotoSansGeorgian",
            "NotoSansEthiopic", "NotoSerifTibetan", "NotoSansThaana",
            "NotoSansMongolian", "NotoSansSyriac", "NotoSansOlChiki",
            "NotoSansMeeteiMayek", "NotoSansNKo", "NotoSansAdlam",
            "NotoSansTifinagh", "NotoSansCherokee", "NotoSansCanadianAboriginal",
            "NotoSansYi", "NotoSansJavanese", "NotoSansBalinese",
            "NotoSansSundanese", "NotoSansChakma", "NotoSansSymbols", "NotoSansSymbols2"
        ]

        XCTAssertEqual(configuration.version, 2)
        XCTAssertEqual(configuration.defaultLocale, "en")
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "en_US"))
                .map(\.rawValue),
            sharedFallbacks
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "ko_KR"))
                .map(\.rawValue),
            ["NanumSquareNeo"] + sharedFallbacks
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "ja_JP"))
                .map(\.rawValue),
            sharedFallbacks
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "fr_FR"))
                .map(\.rawValue),
            sharedFallbacks
        )
        XCTAssertEqual(
            configuration.fonts(for: Locale(identifier: "zh_Hans_CN"))
                .map(\.rawValue),
            sharedFallbacks
        )
        XCTAssertEqual(
            configuration.fonts(
                for: Locale(identifier: "ko_KR"),
                design: .monospaced
            ).map(\.rawValue),
            ["RobotoMono", "NotoSansMono", "NotoSansMonoCJK"] + sharedFallbacks
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

    func testSharedFallbackPreservesExactLocaleAndDesignPriority() throws {
        let url = BundledFontCatalog.shared.resources.resourceDirectory
            .appendingPathComponent("font-config.json")
        var source = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        source["designs"] = [
            "fallbacks": ["NotoSans", "Roboto"],
            "default": ["systemFont": "Roboto", "fallbacks": ["NotoSansCJK", "Roboto"], "locales": [
                "ko": ["Roboto", "NanumSquareNeo"],
                "ko-KR": ["NotoSansCJK", "Roboto"]
            ]],
            "monospaced": ["systemFont": "RobotoMono", "fallbacks": ["RobotoMono"], "locales": [
                "en": ["RobotoMono", "NotoSansMonoCJK"]
            ]]
        ]
        let configuration = try FontFallbackConfiguration(
            data: JSONSerialization.data(withJSONObject: source)
        )
        XCTAssertEqual(configuration.fonts(for: Locale(identifier: "ko_KR")).map(\.rawValue),
                       ["NotoSansCJK", "Roboto", "NotoSans"])
        XCTAssertEqual(configuration.fonts(for: Locale(identifier: "ko_KP")).map(\.rawValue),
                       ["Roboto", "NanumSquareNeo", "NotoSansCJK", "NotoSans"])
        XCTAssertEqual(configuration.fonts(for: Locale(identifier: "ar_EG")).map(\.rawValue),
                       ["NotoSansCJK", "Roboto", "NotoSans"])
        XCTAssertEqual(configuration.fonts(for: Locale(identifier: "ar_EG"), design: .rounded)
            .map(\.rawValue), ["NotoSansCJK", "Roboto", "NotoSans"])
        XCTAssertEqual(configuration.fonts(for: Locale(identifier: "ar_EG"), design: .monospaced)
            .map(\.rawValue), ["RobotoMono", "NotoSansMonoCJK", "NotoSans", "Roboto"])
        XCTAssertEqual(configuration.fallbacks(for: Locale(identifier: "ko_KR")).map(\.isDefault),
                       [false, false, true])
        XCTAssertEqual(configuration.fallbacks(for: Locale(identifier: "ko_KP")).map(\.isDefault),
                       [false, false, true, true])
        XCTAssertEqual(configuration.fallbacks(for: Locale(identifier: "ar_EG")).map(\.isDefault),
                       [true, true, true])
        XCTAssertEqual(configuration.fallbacks(for: Locale(identifier: "ar_EG"), design: .monospaced)
            .map(\.isDefault), [false, false, true, true])
    }

    func testSharedFallbackRejectsUndefinedDuplicateAndTerminalFonts() throws {
        let url = BundledFontCatalog.shared.resources.resourceDirectory
            .appendingPathComponent("font-config.json")
        let base = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let cases: [([String], FontFallbackConfigurationError)] = [
            (["Undefined"], .undefinedFont(BundledFontID("Undefined"))),
            (["Roboto", "Roboto"], .duplicateFallbackFont("designs", BundledFontID("Roboto"))),
            (["LastResort"], .terminalFontInFallbacks("designs"))
        ]
        for (fallbacks, expectedError) in cases {
            var source = base
            var designs = try XCTUnwrap(source["designs"] as? [String: Any])
            designs["fallbacks"] = fallbacks
            source["designs"] = designs
            let data = try JSONSerialization.data(withJSONObject: source)
            XCTAssertThrowsError(try FontFallbackConfiguration(data: data)) {
                XCTAssertEqual($0 as? FontFallbackConfigurationError, expectedError)
            }
        }
        var source = base
        source["defaultLocale"] = ""
        let data = try JSONSerialization.data(withJSONObject: source)
        XCTAssertThrowsError(try FontFallbackConfiguration(data: data)) {
            XCTAssertEqual($0 as? FontFallbackConfigurationError, .invalidDefaultLocale(""))
        }
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
        XCTAssertEqual(configuration.fonts(for: Locale(identifier: "fr_FR")), [primaryID])
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
                weight: weight.weightClass,
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
            XCTAssertEqual(try file("NotoSans", weight), "NotoSans-VariableFont_wdth,wght.ttf")
            XCTAssertEqual(try file("NotoSans", weight, isItalic: true),
                           "NotoSans-Italic-VariableFont_wdth,wght.ttf")
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
            font.typefaceProvider as? ExternalFontProvider
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
            remote.typefaceProvider as? ExternalFontProvider
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
            font.typefaceProvider as? ExternalFontProvider
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        ))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let resolved = ResolvedTextSource(
            runs: [.text(cascade.runFaces, "A")],
            scaleFactor: 1,
            drawMissingGlyphs: true
        )

        XCTAssertGreaterThan(
            try XCTUnwrap(resolved.makeGlyphs().first?.width),
            0
        )
        let catalog = BundledFontCatalog.shared
        for family in catalog.configuration.fonts(for: environment.locale)
            where family != catalog.configuration.systemFont {
            let url = try XCTUnwrap(catalog.resource(for: family, locale: environment.locale)?.url)
            XCTAssertFalse(testContext.loadedURLs.contains(url), family.rawValue)
        }
        let terminalURL = try XCTUnwrap(catalog.resource(
            for: BundledFontID("LastResort"),
            locale: environment.locale
        )?.url)
        XCTAssertFalse(testContext.loadedURLs.contains(terminalURL))
    }

    @MainActor
    func testSharedFallbackResolvesMixedScriptGlyphsAcrossDesigns() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        let samples: [(String, String)] = [
            ("한", "NotoSansKR"), ("ا", "NotoSansArabic"),
            ("क", "NotoSans"), ("ก", "NotoSansThai"),
            ("ক", "NotoSansBengali"), ("א", "NotoSansHebrew"),
            ("அ", "NotoSansTamil"), ("అ", "NotoSansTelugu"),
            ("ಅ", "NotoSansKannada"), ("അ", "NotoSansMalayalam"),
            ("અ", "NotoSansGujarati"), ("ਅ", "NotoSansGurmukhi"),
            ("ଅ", "NotoSansOriya"), ("අ", "NotoSansSinhala"),
            ("ក", "NotoSansKhmer"), ("ກ", "NotoSansLao"),
            ("က", "NotoSansMyanmar"), ("Ա", "NotoSansArmenian"),
            ("ა", "NotoSansGeorgian"), ("ሀ", "NotoSansEthiopic"),
            ("ཀ", "NotoSerifTibetan"), ("ހ", "NotoSansThaana"),
            ("ᠠ", "NotoSansMongolian"), ("ܐ", "NotoSansSyriac"),
            ("ᱚ", "NotoSansOlChiki"), ("ꯀ", "NotoSansMeeteiMayek"),
            ("ߊ", "NotoSansNKo"), ("𞤀", "NotoSansAdlam"),
            ("ⴰ", "NotoSansTifinagh"), ("Ꭰ", "NotoSansCherokee"),
            ("ᐁ", "NotoSansCanadianAboriginal"), ("ꀀ", "NotoSansYi"),
            ("ꦲ", "NotoSansJavanese"), ("ᬅ", "NotoSansBalinese"),
            ("ᮃ", "NotoSansSundanese"), ("𑄃", "NotoSansChakma"),
            ("⣿", "NotoSansSymbols2")
        ]
        for (locale, design) in ["en_US", "ar_EG", "th_TH", "he_IL"].flatMap({ locale in
            [VUI.Font.Design.default, .monospaced].map { (locale, $0) }
        }) {
            var environment = EnvironmentValues()
            environment.locale = Locale(identifier: locale)
            environment.defaultFontRenderingMode = .vector()
            let font = VUI.Font(typefaceProvider: SystemFontProvider(
                size: 17, weight: .regular, design: design, renderingMode: .vector()
            ))
            let cascade = font.typefaceCascade(
                in: environment, forContext: SceneResources(), contentScaleFactor: 1
            )
            let text = "A" + samples.map(\.0).joined()
            let resolved = ResolvedTextSource(
                runs: [.text(cascade.runFaces, text)], scaleFactor: 1, drawMissingGlyphs: true
            )
            let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)
            XCTAssertEqual(glyphs.map(\.scalar), Array(text.unicodeScalars))
            XCTAssertEqual((resourceFace(glyphs.first?.face) as? VectorTypeface)?.font.familyName,
                           design == .monospaced ? "Roboto Mono" : "Roboto")
            for (glyph, sample) in zip(glyphs.dropFirst(), samples) {
                let family = design == .monospaced && sample.1 == "NotoSansKR"
                    ? "NotoSansMonoCJK" : sample.1
                XCTAssertEqual(resourceFace(glyph.face)?.identifier, "deferred:\(family):0", locale)
                XCTAssertGreaterThan(glyph.advance.width, 0, sample.0)
                if design == .monospaced && sample.1 == "NotoSansArabic" {
                    XCTAssertNotEqual(glyph.advance.width, glyphs[0].advance.width)
                }
            }
        }
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        ))
        let sceneResources = SceneResources()
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: sceneResources,
            contentScaleFactor: 1
        )
        let korean = UnicodeScalar("ㄱ")
        let han = UnicodeScalar("漢")

        XCTAssertEqual(cascade.ordinaryFaces.filter { !$0.isEmojiFallback }.count, 42)
        XCTAssertEqual(cascade.ordinaryFaces.filter(\.isEmojiFallback).count, 3)
        XCTAssertTrue(cascade.ordinaryFaces[0].hasGlyph(for: korean))
        XCTAssertFalse(cascade.ordinaryFaces[0].hasGlyph(for: han))
        let hanFallback = try XCTUnwrap(cascade.ordinaryFaces.first {
            $0.identifier == "deferred:NotoSansKR:0"
        })
        XCTAssertTrue(hanFallback.hasGlyph(for: han))
        XCTAssertNotNil(cascade.missingGlyphFace)

        let faces = cascade.runFaces
        let resolved = ResolvedTextSource(
            runs: [.text(faces, "Aㄱ漢")],
            scaleFactor: 1
        )
        let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)

        XCTAssertEqual(glyphs.map(\.scalar), [
            UnicodeScalar("A"),
            korean,
            han,
        ])
        XCTAssertTrue(resourceFace(glyphs[0].face)?.isEqual(to: cascade.ordinaryFaces[0]) == true)
        XCTAssertTrue(resourceFace(glyphs[1].face)?.isEqual(to: cascade.ordinaryFaces[0]) == true)
        XCTAssertTrue(resourceFace(glyphs[2].face)?.isEqual(to: hanFallback) == true)
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

        XCTAssertNotNil(monospaced.provider as? FontBox<VUI.Font.StaticModifierProvider<VUI.Font.MonospacedModifier>>)
        XCTAssertNotNil(inactive.provider as? FontBox<VUI.Font.StaticModifierProvider<VUI.Font.UndoModifier<VUI.Font.MonospacedModifier>>>)
        XCTAssertNotNil(digits.provider as? FontBox<VUI.Font.StaticModifierProvider<VUI.Font.MonospacedDigitModifier>>)

        let environment = EnvironmentValues()
        let resolvedMonospaced = try XCTUnwrap(
            monospaced.resolved(in: environment).typefaceProvider as?
                SystemFontProvider
        )
        let resolvedInactive = try XCTUnwrap(
            inactive.resolved(in: environment).typefaceProvider as?
                SystemFontProvider
        )
        let resolvedTrueThenFalse = try XCTUnwrap(
            base.monospaced().monospaced(false)
                .resolved(in: environment).typefaceProvider as?
                SystemFontProvider
        )
        let resolvedFalseThenTrue = try XCTUnwrap(
            base.monospaced(false).monospaced()
                .resolved(in: environment).typefaceProvider as?
                SystemFontProvider
        )
        let resolvedExplicitDesign = try XCTUnwrap(
            VUI.Font.system(size: 17, design: .monospaced)
                .monospaced(false)
                .resolved(in: environment).typefaceProvider as?
                SystemFontProvider
        )
        let resolvedWeighted = try XCTUnwrap(
            monospaced.weight(.bold)
                .resolved(in: environment).typefaceProvider as?
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
    @MainActor
    func testSystemMonospacedDigitUsesBundledTabularAdvances() throws {
        let previousAppContext = appContext
        appContext = MissingGlyphTestAppContext()
        defer { appContext = previousAppContext }

        let font = VUI.Font.system(size: 17).monospacedDigit()
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .vector()
        let provider = try XCTUnwrap(
            font.resolved(in: environment).typefaceProvider as?
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

        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        XCTAssertEqual(cascade.shapingFeatures.map(\.tag), [0x746e_756d])
        XCTAssertTrue(cascade.runFaces.first is ShapingFeatureTypeface)
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
            base.resolved(in: environment).typefaceProvider as?
                SystemFontProvider
        )

        environment.fontModifiers = [
            .monospaced(true),
            .monospaced(false),
        ]
        let contentNearestFalse = try XCTUnwrap(
            base.resolved(in: environment).typefaceProvider as?
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
            resourceFace(localFalseText
                .makeGlyphs()
                .first?.glyphs.first?.face) as? VectorTypeface
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
            resourceFace(localTrueText
                .makeGlyphs()
                .first?.glyphs.first?.face) as? VectorTypeface
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .bold,
            design: .monospaced,
            renderingMode: .vector()
        ))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let latin = UnicodeScalar("A")
        let korean = UnicodeScalar("한")

        XCTAssertEqual(cascade.ordinaryFaces.filter { !$0.isEmojiFallback }.count, 44)
        XCTAssertEqual(cascade.ordinaryFaces.filter(\.isEmojiFallback).count, 3)
        XCTAssertTrue(cascade.ordinaryFaces[0].hasGlyph(for: latin))
        XCTAssertFalse(cascade.ordinaryFaces[0].hasGlyph(for: korean))
        XCTAssertFalse(cascade.ordinaryFaces[1].hasGlyph(for: korean))
        XCTAssertTrue(cascade.ordinaryFaces[2].hasGlyph(for: korean))

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
            "deferred:NotoSansMono:0"
        )
        let monoWidths = try "imW01".unicodeScalars.map {
            try XCTUnwrap(cascade.ordinaryFaces[1].glyphMetrics(for: $0)?.advance.width)
        }
        XCTAssertEqual(Set(monoWidths).count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(monoWidths.first), 0)
        XCTAssertEqual(
            cascade.ordinaryFaces[2].identifier,
            "deferred:NotoSansMonoCJK:1"
        )

        let resolved = ResolvedTextSource(
            runs: [.text(cascade.runFaces, "A한A")],
            scaleFactor: 1
        )
        let glyphs = try XCTUnwrap(resolved.makeGlyphs().first?.glyphs)
        XCTAssertEqual(glyphs.map(\.scalar), [latin, korean, latin])
        XCTAssertTrue(resourceFace(glyphs[0].face)?.isEqual(to: cascade.ordinaryFaces[0]) == true)
        XCTAssertTrue(resourceFace(glyphs[1].face)?.isEqual(to: cascade.ordinaryFaces[2]) == true)
        XCTAssertEqual(glyphs[0].advance.width, glyphs[2].advance.width)
        XCTAssertNotEqual(glyphs[1].advance.width, glyphs[0].advance.width)

        let latinText = ResolvedTextSource(
            runs: [.text(cascade.runFaces, "A")],
            scaleFactor: 1
        )
        let fallbackText = ResolvedTextSource(
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        ))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let primary = try XCTUnwrap(cascade.ordinaryFaces.first)
        let scalar = UnicodeScalar("ㄱ")
        let fallback = try XCTUnwrap(cascade.ordinaryFaces.dropFirst().first {
            $0.hasGlyph(for: scalar)
        })

        XCTAssertFalse(primary.hasGlyph(for: scalar))
        XCTAssertTrue(fallback.hasGlyph(for: scalar))
        XCTAssertTrue(
            primary.ascender != fallback.ascender ||
                primary.descender != fallback.descender
        )

        let latin = try XCTUnwrap(ResolvedTextSource(
            runs: [.text(cascade.runFaces, "A")],
            scaleFactor: 1
        ).makeGlyphs().first)
        let fallbackLine = try XCTUnwrap(ResolvedTextSource(
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        ))
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

        let resolved = ResolvedTextSource(
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        ))
        let cascade = font.typefaceCascade(
            in: environment,
            forContext: SceneResources(),
            contentScaleFactor: 1
        )
        let scalar = UnicodeScalar("\u{0378}")
        let resolved = ResolvedTextSource(
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
        let font = VUI.Font(typefaceProvider: SystemFontProvider(
            size: 17,
            weight: .regular,
            design: .default,
            renderingMode: .vector()
        ))
        let sceneResources = SceneResources()
        let faces = font.typefaceCascade(
            in: environment,
            forContext: sceneResources,
            contentScaleFactor: 1
        ).runFaces

        for scalar in [UnicodeScalar("\u{200B}"), UnicodeScalar("\u{200D}")] {
            let resolved = ResolvedTextSource(
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
}
