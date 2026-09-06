import Foundation
import XCTest
@testable import VVD
@testable import VUI

final class ResolvedStyledTextStorageTests: XCTestCase {
    private struct ResolvedArchiveFields {
        var fields: [UInt] = []
        var smaller: [ResolvedArchiveFields] = []
    }

    private func decodeResolvedArchiveFields(
        _ decoder: inout ProtobufDecoder
    ) throws -> ResolvedArchiveFields {
        var result = ResolvedArchiveFields()
        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            result.fields.append(fieldNumber)
            if fieldNumber == 8, wireType == 2 {
                result.smaller.append(try decoder.decodeLengthDelimited { nested in
                    try decodeResolvedArchiveFields(&nested)
                })
            } else {
                try decoder.skipField(wireType: wireType)
            }
        }
        return result
    }

    func testResolvedRunsProduceCrossPlatformAttributedStorage() throws {
        let face = ResolvedStorageTestTypeface()
        let image = GraphicsContext.ResolvedImage(
            baseline: 0,
            shading: nil,
            texture: nil,
            textureTransform: .identity,
            scaleFactor: 1
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [
                .text([face], "A "),
                .attachment([face], image),
                .text([face], " B")
            ],
            scaleFactor: 2
        )

        let storage = resolved.attributedStorage
        XCTAssertEqual(storage.string, "A \u{fffc} B")
        XCTAssertTrue(resolved.hasAttachments)
        XCTAssertEqual(resolved.resolvedFeatures, [.attachments])

        var attachmentRanges: [NSRange] = []
        storage.enumerateAttribute(
            .resolvedTextAttachment,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            if value as? Bool == true {
                attachmentRanges.append(range)
            }
        }
        XCTAssertEqual(attachmentRanges.count, 1)
        XCTAssertEqual(
            storage.attributedSubstring(from: try XCTUnwrap(attachmentRanges.first)).string,
            "\u{fffc}"
        )

        let archive = _ResolvedAttributedStringArchive(storage)
        let encoded = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(_ResolvedAttributedStringArchive.self, from: encoded)
        XCTAssertEqual(decoded, archive)
        XCTAssertEqual(decoded.attributedString, storage)
    }

    func testStyledRunsProjectObservedSwiftUIAttributeKeysWithoutFlattening() throws {
        let face = ResolvedStorageTestTypeface()
        let lineStyle = Text.LineStyle(pattern: .dash, color: .green)
        let style = _ResolvedTextRunAttributes(
            font: .system(size: 18, weight: .bold),
            foregroundColor: .red,
            backgroundColor: .blue,
            strikethroughStyle: .single,
            underlineStyle: lineStyle,
            kern: 2,
            tracking: 1,
            baselineOffset: 3
        )
        let resolved = GraphicsContext.ResolvedText(
            runs: [.styledText([face], "styled", _TextAttributeValues(), style)],
            scaleFactor: 1
        )

        let storage = resolved.attributedStorage
        XCTAssertEqual(storage.string, "styled")
        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual(
            attributes[NSAttributedString.Key("VUI.Font")] as? VUI.Font,
            style.font
        )
        XCTAssertEqual(
            attributes[NSAttributedString.Key("VUI.ForegroundColor")] as? VUI.Color,
            .red
        )
        XCTAssertEqual(
            attributes[NSAttributedString.Key("VUI.BackgroundColor")] as? VUI.Color,
            .blue
        )
        XCTAssertEqual(
            attributes[NSAttributedString.Key("VUI.StrikethroughStyle")] as? Text.LineStyle,
            .single
        )
        XCTAssertEqual(
            attributes[NSAttributedString.Key("VUI.UnderlineStyle")] as? Text.LineStyle,
            lineStyle
        )
        XCTAssertEqual(attributes[NSAttributedString.Key("VUI.Kern")] as? CGFloat, 2)
        XCTAssertEqual(attributes[NSAttributedString.Key("VUI.Tracking")] as? CGFloat, 1)
        XCTAssertEqual(
            attributes[NSAttributedString.Key("VUI.BaselineOffset")] as? CGFloat,
            3
        )
    }

    func testResolvedTextStorageRestoresCoreAttributedRuns() throws {
        let face = ResolvedStorageTestTypeface()
        let firstStyle = _ResolvedTextRunAttributes(
            font: .system(size: 18, weight: .bold),
            foregroundColor: .red,
            backgroundColor: .blue,
            strikethroughStyle: .single,
            underlineStyle: Text.LineStyle(pattern: .dash, color: .green),
            kern: 2,
            tracking: 1,
            baselineOffset: 3
        )
        let secondStyle = _ResolvedTextRunAttributes(
            foregroundColor: .purple,
            kern: 4
        )
        let storage = GraphicsContext.ResolvedText(
            runs: [
                .styledText([face], "A", _TextAttributeValues(), firstStyle),
                .styledText([face], "😀B", _TextAttributeValues(), secondStyle)
            ],
            scaleFactor: 1
        ).attributedStorage

        let value = _attributedStringFromResolvedTextStorage(storage)
        var text: [String] = []
        var styles: [_ResolvedTextRunAttributes] = []
        AnySequence(value.runs).forEach { run in
            text.append(String(value.characters[run.range]))
            styles.append(_ResolvedTextRunAttributes(
                font: run[AttributeScopes.CoreAttributes.FontAttribute.self],
                foregroundColor: run[
                    AttributeScopes.CoreAttributes.ForegroundColorAttribute.self
                ],
                backgroundColor: run[
                    AttributeScopes.CoreAttributes.BackgroundColorAttribute.self
                ],
                strikethroughStyle: run[
                    AttributeScopes.CoreAttributes.StrikethroughStyleAttribute.self
                ],
                underlineStyle: run[
                    AttributeScopes.CoreAttributes.UnderlineStyleAttribute.self
                ],
                kern: run[AttributeScopes.CoreAttributes.KerningAttribute.self],
                tracking: run[
                    AttributeScopes.CoreAttributes.TrackingAttribute.self
                ],
                baselineOffset: run[
                    AttributeScopes.CoreAttributes.BaselineOffsetAttribute.self
                ]
            ))
        }

        XCTAssertEqual(text, ["A", "😀B"])
        XCTAssertEqual(styles, [firstStyle, secondStyle])

        var item = PlatformItemList.Item()
        item.text = storage
        guard case let .anyTextStorage(textStorage) = platformItemText(item).storage,
              let attributedStorage = textStorage as? AttributedStringTextStorage else {
            return XCTFail("platform text should retain attributed storage")
        }
        XCTAssertEqual(attributedStorage.str, value)
    }

    func testResolvedStyledTextReusesExistingFontMetricsAndRunStorage() throws {
        XCTAssertEqual(MemoryLayout<ResolvedFontMetrics>.size, 64)
        XCTAssertEqual(MemoryLayout<ResolvedFontMetrics>.stride, 64)

        let face = ResolvedStorageTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "metrics")],
            scaleFactor: 2
        )
        var properties = TextLayoutProperties()
        properties.lineLimit = 3

        let styled = ResolvedStyledText(
            layoutProperties: properties,
            archiveOptions: .isArchived,
            resolvedText: resolved,
            version: 7
        )

        XCTAssertEqual(try XCTUnwrap(styled.storage).string, "metrics")
        XCTAssertEqual(styled.layoutProperties.lineLimit, 3)
        XCTAssertTrue(styled.archiveOptions.isArchived)
        XCTAssertFalse(styled.isCollapsible)
        XCTAssertTrue(styled.features.isEmpty)
        XCTAssertTrue(styled.styles.isEmpty)
        XCTAssertTrue(styled.transitions.isEmpty)
        XCTAssertEqual(styled.links, Text.ResolvedProperties.Links())
        let metrics = try XCTUnwrap(styled.maxFontMetrics)
        XCTAssertEqual(metrics.capHeight, 4)
        XCTAssertEqual(metrics.ascender, 4)
        XCTAssertEqual(metrics.descender, -1)
        XCTAssertEqual(metrics.leading, 0)
        XCTAssertEqual(metrics.outsets, EdgeInsets())
    }

    func testResolvedStyledTextReusesMetricsWithinMeasuredProposalRange() {
        let face = ResolvedMetricsCacheTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "metrics")],
            scaleFactor: 1
        )
        let styled = ResolvedStyledText(resolvedText: resolved)

        XCTAssertEqual(styled.metricsCacheEntryCount, 0)
        let base = styled.sizeThatFits(
            _ProposedSize(width: 100, height: 100)
        )
        XCTAssertEqual(base, CGSize(width: 56, height: 10))
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)

        XCTAssertEqual(
            styled.firstBaseline(in: CGSize(width: 100, height: 100)),
            8
        )
        XCTAssertEqual(
            styled.lastBaseline(in: CGSize(width: 100, height: 100)),
            8
        )
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)

        let inner = styled.sizeThatFits(
            _ProposedSize(width: 90, height: 90)
        )
        XCTAssertEqual(inner, base)
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)

        let outside = styled.sizeThatFits(
            _ProposedSize(width: 110, height: 110)
        )
        XCTAssertEqual(outside, base)
        XCTAssertEqual(styled.metricsCacheEntryCount, 2)
    }

    func testResolvedStyledTextNormalizesUnspecifiedProposalToInfinity() {
        let face = ResolvedMetricsCacheTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "metrics")],
            scaleFactor: 1
        )
        let styled = ResolvedStyledText(resolvedText: resolved)

        let ideal = styled.sizeThatFits(.unspecified)
        XCTAssertEqual(ideal, CGSize(width: 56, height: 10))
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)
        XCTAssertEqual(
            styled.sizeThatFits(_ProposedSize(width: 100, height: 100)),
            ideal
        )
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)
    }

    // ASSERTIONS textFractionalNaturalWidthDoesNotTruncateObserved
    func testFractionalNaturalWidthUsesPixelCeilingAndDoesNotSelfTruncate() {
        for scale in [CGFloat(1), CGFloat(2), CGFloat(3)] {
            let face = FractionalWidthTestTypeface(
                advance: 7.3 * scale
            )
            let resolved = GraphicsContext.ResolvedText(
                runs: [.text([face], "AAAA")],
                scaleFactor: scale
            )
            let styled = ResolvedStyledText(resolvedText: resolved)
            let naturalSize = styled.sizeThatFits(.unspecified)
            let expectedWidth = ceil(29.2 * scale) / scale

            XCTAssertEqual(
                naturalSize.width,
                expectedWidth,
                accuracy: 0.000_001,
                "scale \(scale)"
            )
            XCTAssertFalse(
                resolved.makeLayout(
                    in: naturalSize,
                    layoutDirection: .leftToRight
                ).isTruncated,
                "Natural-width text self-truncated at scale \(scale)"
            )
            XCTAssertTrue(
                resolved.makeLayout(
                    in: CGSize(
                        width: naturalSize.width - 1 / scale,
                        height: naturalSize.height
                    ),
                    layoutDirection: .leftToRight
                ).isTruncated,
                "One-pixel-narrower text did not truncate at scale \(scale)"
            )
        }
    }

    // ASSERTIONS textEnvironmentDisplayScaleControlsPixelAlignmentObserved textEnvironmentDisplayScaleLeavesHostGlyphRasterUnchangedObserved
    @MainActor
    func testTextResolutionSeparatesDisplayScaleFromContentScaleTypeface() throws {
        let previousAppContext = appContext
        appContext = TextResolutionTestAppContext()
        defer { appContext = previousAppContext }

        let provider = DPIRecordingTypefaceProvider()
        let font = VUI.Font(provider: AnyFontBox(provider))
        let sceneResources = SceneResources()
        sceneResources.contentScaleFactor = 2

        for scale in [CGFloat(1), CGFloat(2), CGFloat(3)] {
            var environment = EnvironmentValues()
            environment.displayScale = scale
            environment._contentScaleFactor = 2
            let context = GraphTextResolutionContext(
                environment: environment,
                sceneResources: sceneResources
            )
            let resolved = try XCTUnwrap(
                Text(verbatim: "AAAA")
                    .font(font)
                    ._resolve(context: context, referenceDate: Date())
            )
            let naturalSize = resolved.measure()

            XCTAssertEqual(resolved.scaleFactor, 2)
            XCTAssertEqual(resolved.displayScale, scale)
            XCTAssertEqual(
                naturalSize.width,
                ceil(29.2 * scale) / scale,
                accuracy: 0.000_001,
                "scale \(scale)"
            )
        }

        XCTAssertEqual(provider.requestedDPIs, [144])
        XCTAssertEqual(sceneResources.cachedTypefaces.count, 1)
    }

    // ASSERTIONS fontProviderOnlyStorageObserved
    @MainActor
    func testTypefaceCacheKeyCanonicalizesContentScaleToBackendDPI() throws {
        let previousAppContext = appContext
        appContext = TextResolutionTestAppContext()
        defer { appContext = previousAppContext }

        let provider = DPIRecordingTypefaceProvider()
        let font = VUI.Font(provider: AnyFontBox(provider))
        let sceneResources = SceneResources()
        let scales = [CGFloat(1.49999), CGFloat(1.5)]

        XCTAssertEqual(
            MemoryLayout<VUI.Font>.size,
            MemoryLayout<AnyFontBox>.size
        )
        for scale in scales {
            XCTAssertNotNil(
                font.typeface(
                    forContext: sceneResources,
                    contentScaleFactor: scale
                )
            )
        }
        XCTAssertNotNil(font.typeface(forContext: sceneResources, dpi: 108))

        XCTAssertEqual(provider.requestedDPIs, [108])
        XCTAssertEqual(sceneResources.cachedTypefaces.count, 1)
        XCTAssertEqual(
            Set(sceneResources.cachedTypefaces.keys.map(\.font)),
            [font]
        )
        XCTAssertEqual(
            Set(sceneResources.cachedTypefaces.keys.map(\.dpi)),
            [108]
        )

        sceneResources.purgeResources(reason: .lowMemory)
        XCTAssertTrue(sceneResources.cachedTypefaces.isEmpty)
        XCTAssertNotNil(font.typeface(forContext: sceneResources, dpi: 108))
        XCTAssertEqual(provider.requestedDPIs, [108, 108])
    }

    // ASSERTIONS textDisplayScaleLayoutMetricsStableObserved
    @MainActor
    func testSystemFontKeepsLogicalMetricsAcrossDisplayScales() throws {
        guard let deviceContext = makeGraphicsDeviceContext(api: .metal) else {
            throw XCTSkip("Metal graphics device unavailable")
        }
        let previousAppContext = appContext
        let testAppContext = ResolvedTextScaleTestAppContext(
            graphicsDeviceContext: deviceContext
        )
        appContext = testAppContext
        defer { appContext = previousAppContext }

        let renderingModes: [(String, VUI.Font.RenderingMode)] = [
            ("bitmap", .bitmap()),
            ("vector", .vector()),
        ]
        for (modeName, renderingMode) in renderingModes {
            let provider = SystemFontProvider(
                size: 24,
                weight: .semibold,
                design: .default,
                renderingMode: renderingMode
            )
            var referenceLineSize: CGSize?
            for scale in [CGFloat(1), CGFloat(2), CGFloat(3)] {
                let dpi = UInt32(CGFloat(defaultDPI) * scale)
                let typeface = try XCTUnwrap(
                    provider.makeTypeface(
                        testAppContext,
                        dpi: dpi
                    )
                )
                let expectedEmbolden =
                    SystemFontProvider.embolden(for: .semibold) * scale
                if let textureTypeface = typeface as? TextureTypeface {
                    XCTAssertEqual(
                        textureTypeface.textureFont.boldStrength,
                        expectedEmbolden,
                        accuracy: 0.000_001
                    )
                } else if let vectorTypeface = typeface as? VectorTypeface {
                    XCTAssertEqual(
                        vectorTypeface.embolden,
                        expectedEmbolden,
                        accuracy: 0.000_001
                    )
                } else {
                    XCTFail("Unexpected \(modeName) typeface")
                }
                let resolved = GraphicsContext.ResolvedText(
                    runs: [
                        .text([typeface], "TestApp1 Labs"),
                    ],
                    scaleFactor: scale
                )
                let styled = ResolvedStyledText(resolvedText: resolved)
                let line = try XCTUnwrap(resolved.makeGlyphs().first)
                let logicalLineSize = CGSize(
                    width: line.width / scale,
                    height: line.height / scale
                )
                if let referenceLineSize {
                    XCTAssertEqual(
                        logicalLineSize.width,
                        referenceLineSize.width,
                        accuracy: 0.000_001,
                        "\(modeName) scale \(scale)"
                    )
                    XCTAssertEqual(
                        logicalLineSize.height,
                        referenceLineSize.height,
                        accuracy: 0.000_001,
                        "\(modeName) scale \(scale)"
                    )
                } else {
                    referenceLineSize = logicalLineSize
                }

                let naturalSize = styled.sizeThatFits(.unspecified)
                XCTAssertEqual(
                    naturalSize.width,
                    ceil(logicalLineSize.width * scale) / scale,
                    accuracy: 0.000_001,
                    "\(modeName) scale \(scale)"
                )
                XCTAssertEqual(
                    naturalSize.height,
                    logicalLineSize.height,
                    accuracy: 0.000_001,
                    "\(modeName) scale \(scale)"
                )
            }
        }
    }

    func testResolvedStyledTextPreservesZeroWidthProposalSemantics() {
        let face = ResolvedMetricsCacheTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "metrics")],
            scaleFactor: 1
        )
        let styled = ResolvedStyledText(resolvedText: resolved)

        XCTAssertEqual(styled.sizeThatFits(.zero), .zero)
        XCTAssertEqual(styled.metricsCacheEntryCount, 0)

        let collapsed = styled.sizeThatFits(
            _ProposedSize(width: 0, height: 100)
        )
        XCTAssertEqual(collapsed.width, 0)
        XCTAssertGreaterThan(collapsed.height, 0)
        XCTAssertEqual(styled.metricsCacheEntryCount, 1)
    }

    func testHeightConstraintOnlyTruncatesWhenTextHasOverflowingContent() {
        let face = ResolvedMetricsCacheTestTypeface()

        let singleLine = ResolvedStyledText(
            resolvedText: GraphicsContext.ResolvedText(
                runs: [.text([face], "metrics")],
                scaleFactor: 1
            )
        )
        let singleLineIdeal = singleLine.sizeThatFits(
            _ProposedSize(width: 100, height: .infinity)
        )
        XCTAssertEqual(singleLineIdeal, CGSize(width: 56, height: 10))
        XCTAssertEqual(
            singleLine.sizeThatFits(
                _ProposedSize(width: 100, height: 0)
            ),
            singleLineIdeal
        )

        let explicitLines = ResolvedStyledText(
            resolvedText: GraphicsContext.ResolvedText(
                runs: [.text([face], "AA\nBB")],
                scaleFactor: 1
            )
        )
        XCTAssertEqual(
            explicitLines.sizeThatFits(
                _ProposedSize(width: 100, height: .infinity)
            ),
            CGSize(width: 16, height: 20)
        )
        XCTAssertEqual(
            explicitLines.sizeThatFits(
                _ProposedSize(width: 100, height: 0)
            ),
            CGSize(width: 24, height: 10)
        )

        let wrappedLine = ResolvedStyledText(
            resolvedText: GraphicsContext.ResolvedText(
                runs: [.text([face], "AAAA")],
                scaleFactor: 1
            )
        )
        XCTAssertEqual(
            wrappedLine.sizeThatFits(
                _ProposedSize(width: 24, height: .infinity)
            ),
            CGSize(width: 24, height: 20)
        )
        XCTAssertEqual(
            wrappedLine.sizeThatFits(
                _ProposedSize(width: 24, height: 0)
            ),
            CGSize(width: 24, height: 10)
        )
    }

    func testResolvedPropertiesFeatureBitsMatchObservedSurface() {
        XCTAssertEqual(Text.ResolvedProperties.Features.keyColor.rawValue, 0x001)
        XCTAssertEqual(Text.ResolvedProperties.Features.attachments.rawValue, 0x002)
        XCTAssertEqual(Text.ResolvedProperties.Features.sensitive.rawValue, 0x004)
        XCTAssertEqual(Text.ResolvedProperties.Features.customRenderer.rawValue, 0x008)
        XCTAssertEqual(Text.ResolvedProperties.Features.useTextLayoutManager.rawValue, 0x010)
        XCTAssertEqual(Text.ResolvedProperties.Features.useTextSuffix.rawValue, 0x020)
        XCTAssertEqual(Text.ResolvedProperties.Features.produceTextLayout.rawValue, 0x040)
        XCTAssertEqual(Text.ResolvedProperties.Features.checkInterpolationStrategy.rawValue, 0x080)
        XCTAssertEqual(Text.ResolvedProperties.Features.isUniqueSizeVariant.rawValue, 0x100)
        XCTAssertEqual(Text.ResolvedProperties.Features.isStandaloneSizeVariant.rawValue, 0x200)
    }

    func testDynamicArchivePredicateUsesDirectStorageAndFlaggedLargerVariant() {
        let dynamicStorage = NSAttributedString(
            string: "dynamic",
            attributes: [.updateSchedule: true]
        )
        let dynamic = ResolvedStyledText(storage: dynamicStorage)
        XCTAssertTrue(dynamic.needsDynamicRenderingInArchive)

        let lateSchedule = NSMutableAttributedString(string: "late")
        lateSchedule.addAttribute(
            .updateSchedule,
            value: true,
            range: NSRange(location: 1, length: 1)
        )
        XCTAssertFalse(
            ResolvedStyledText(storage: lateSchedule).needsDynamicRenderingInArchive
        )
        let firstSchedule = NSMutableAttributedString(string: "first")
        firstSchedule.addAttribute(
            .updateSchedule,
            value: false,
            range: NSRange(location: 0, length: 1)
        )
        XCTAssertTrue(
            ResolvedStyledText(storage: firstSchedule).needsDynamicRenderingInArchive
        )

        let larger = ResolvedStyledText(storage: dynamicStorage)
        let attachmentRoot = ResolvedStyledText(features: [.attachments])
        attachmentRoot.largerSizeVariant = larger
        XCTAssertTrue(attachmentRoot.needsDynamicRenderingInArchive)

        let unflaggedRoot = ResolvedStyledText()
        unflaggedRoot.largerSizeVariant = larger
        XCTAssertFalse(unflaggedRoot.needsDynamicRenderingInArchive)
        XCTAssertFalse(ResolvedStyledText().needsDynamicRenderingInArchive)
    }

    func testDynamicPlaceholderEncodesMultiSizeVariantChain() throws {
        func text(_ value: String, features: Text.ResolvedProperties.Features) -> ResolvedStyledText {
            ResolvedStyledText(
                storage: NSAttributedString(
                    string: value,
                    attributes: [.updateSchedule: true]
                ),
                features: features
            )
        }

        let regular = text("regular", features: [.isUniqueSizeVariant])
        let compact = text("compact", features: [.isUniqueSizeVariant])
        let terminal = text("terminal", features: [])
        regular.setSizeVariantCandidates([regular, compact, terminal])

        let placeholder = DynamicTextPlaceholder(
            text: regular,
            size: CGSize(width: 120, height: 24)
        )
        XCTAssertEqual(
            Mirror(reflecting: placeholder).children.compactMap(\.label),
            ["text", "size"]
        )
        XCTAssertEqual(placeholder.identifier, "VUI.DynamicText")
        XCTAssertEqual(
            placeholder.boundingRect,
            CGRect(x: 0, y: 0, width: 120, height: 24)
        )

        var decoder = ProtobufDecoder(try placeholder.encodedData())
        XCTAssertEqual(try decoder.decodeVarint(), (1 << 3) | 2)
        let fields = try decoder.decodeLengthDelimited { nested in
            try decodeResolvedArchiveFields(&nested)
        }
        XCTAssertTrue(fields.fields.contains(1))
        XCTAssertTrue(fields.fields.contains(5))
        XCTAssertTrue(fields.fields.contains(7))
        XCTAssertTrue(fields.fields.contains(8))
        XCTAssertTrue(fields.smaller.first?.fields.contains(8) == true)

        XCTAssertEqual(try decoder.decodeVarint(), (2 << 3) | 2)
        let size = try decoder.decodeMessage(CGSize.self)
        XCTAssertEqual(size, CGSize(width: 120, height: 24))
        XCTAssertTrue(decoder.isAtEnd)
    }

    func testResolvedPropertiesSupplementalCarrierDefaultsAndAttachmentRegistration() throws {
        var properties = Text.ResolvedProperties()

        XCTAssertTrue(properties.features.isEmpty)
        XCTAssertEqual(properties.insets, EdgeInsets())
        XCTAssertTrue(properties.styles.isEmpty)
        XCTAssertTrue(properties.transitions.isEmpty)
        XCTAssertEqual(properties.suffix, .none)
        XCTAssertTrue(properties.customAttachments.isEmpty)
        XCTAssertTrue(properties.paragraph.languageIdentifiers.isEmpty)
        XCTAssertEqual(properties.paragraph.startIndex, 0)
        XCTAssertNil(properties.multilineTextAlignment)
        XCTAssertEqual(MemoryLayout<Text.ResolvedProperties.Links>.size, 0)

        properties.registerCustomAttachment(at: 3)
        properties.registerCustomAttachment(at: 3)
        properties.registerCustomAttachment(at: 8)

        XCTAssertEqual(properties.customAttachments.characterIndices, [3, 3, 8])
        XCTAssertFalse(properties.customAttachments.isEmpty)

        let transition = Text.ResolvedProperties.Transition(transition: .opacity)
        properties.transitions.append(transition)
        XCTAssertEqual(properties.transitions, [transition])
        XCTAssertEqual(properties.links, Text.ResolvedProperties.Links())

        properties.paragraph.languageIdentifiers = ["en", "ar"]
        properties.paragraph.markParagraphBoundary(at: 11)
        XCTAssertTrue(properties.paragraph.languageIdentifiers.isEmpty)
        XCTAssertEqual(properties.paragraph.startIndex, 11)

        let paragraphData = try JSONEncoder().encode(properties.paragraph)
        let decodedParagraph = try JSONDecoder().decode(
            Text.ResolvedProperties.Paragraph.self,
            from: paragraphData
        )
        XCTAssertEqual(decodedParagraph, properties.paragraph)
    }

    func testResolvedSuffixAndShapeStyleDefaultsMatchObservedSurface() throws {
        let face = ResolvedStorageTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "suffix")],
            scaleFactor: 1
        )
        var glyph = GraphicsContext.ResolvedText.Glyph(
            scalar: UnicodeScalar("s"),
            face: face
        )
        glyph.advance = CGSize(width: 8, height: 10)
        glyph.ascender = 8
        glyph.descender = -2
        let line = try XCTUnwrap(
            resolved.makeLayout(
                lineGlyphs: [
                    GraphicsContext.ResolvedText.LineGlyphs(
                        glyphs: [glyph],
                        ascender: 8,
                        descender: -2,
                        width: 8
                    )
                ],
                layoutDirection: .leftToRight
            ).first
        )
        let color = VUI.Color.ResolvedHDR(
            VUI.Color.Resolved(red: 0.25, green: 0.5, blue: 0.75)
        )
        let style = _ShapeStyle_Pack.Style(.color(color))
        let foreground2 = _ShapeStyle_Pack.Key(.foreground, 2)
        let foreground3 = _ShapeStyle_Pack.Key(.foreground, 3)
        let foregroundMax = _ShapeStyle_Pack.Key(
            .foreground,
            Int(UInt8.max)
        )
        let background0 = _ShapeStyle_Pack.Key(.background, 0)

        XCTAssertEqual(style.fill, .color(color))
        XCTAssertEqual(style.opacity, 1)
        XCTAssertNil(style._blend)
        XCTAssertTrue(style.effects.isEmpty)

        let truncated = ResolvedTextSuffix.truncated(line, [style])
        XCTAssertEqual(truncated.line, line)
        XCTAssertEqual(truncated.styles, [style])

        let alwaysVisible = ResolvedTextSuffix.alwaysVisible(line, [style])
        XCTAssertEqual(alwaysVisible.line, line)
        XCTAssertEqual(alwaysVisible.styles, [style])

        XCTAssertNil(ResolvedTextSuffix.none.line)
        XCTAssertTrue(ResolvedTextSuffix.none.styles.isEmpty)
        XCTAssertLessThan(foreground2, foreground3)
        XCTAssertLessThan(foregroundMax, background0)
        XCTAssertFalse(background0 < foregroundMax)

        // ASSERTIONS shapeStylePackKeyComparableOrderingRuntimeObserved
    }

    func testShapeStyleFillAnimatableArithmeticMatchesHiddenRuntime() {
        let color = VUI.Color.ResolvedHDR(
            VUI.Color.Resolved(
                colorSpace: .sRGBLinear,
                red: 0.25,
                green: 0.5,
                blue: 0.75,
                opacity: 0.8
            ),
            headroom: 4
        )
        let colorData = _ShapeStyle_Pack.Fill.AnimatableData.color(
            color.animatableData
        )
        let mesh = MeshGradient(
            width: 2,
            height: 2,
            points: [
                SIMD2(0, 0), SIMD2(1, 0),
                SIMD2(0, 1), SIMD2(1, 1),
            ],
            colors: [.red, .green, .blue, .white]
        ).resolvePaint(in: EnvironmentValues())
        let meshData = _ShapeStyle_Pack.Fill.AnimatableData.meshGradient(
            mesh.animatableData
        )

        var zeroPlusColor = _ShapeStyle_Pack.Fill.AnimatableData.zero
        zeroPlusColor += colorData
        XCTAssertEqual(zeroPlusColor, colorData)

        var zeroMinusColor = _ShapeStyle_Pack.Fill.AnimatableData.zero
        zeroMinusColor -= colorData
        XCTAssertEqual(zeroMinusColor, colorData)

        var colorPlusZero = colorData
        colorPlusZero += .zero
        XCTAssertEqual(colorPlusZero, colorData)

        var colorMinusZero = colorData
        colorMinusZero -= .zero
        XCTAssertEqual(colorMinusZero, colorData)

        var colorPlusMesh = colorData
        colorPlusMesh += meshData
        XCTAssertEqual(colorPlusMesh, colorData)

        var colorMinusMesh = colorData
        colorMinusMesh -= meshData
        XCTAssertEqual(colorMinusMesh, colorData)

        var meshPlusColor = meshData
        meshPlusColor += colorData
        XCTAssertEqual(meshPlusColor, meshData)

        var meshMinusColor = meshData
        meshMinusColor -= colorData
        XCTAssertEqual(meshMinusColor, meshData)

        // ASSERTIONS shapeStyleFillAnimatableArithmeticObserved
    }
}

private final class ResolvedStorageTestTypeface: Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? { nil }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "resolved-storage-test" }
    func isEqual(to other: any Typeface) -> Bool { self === (other as AnyObject) }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

private final class ResolvedMetricsCacheTestTypeface: Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        .texture(TextureFont.GlyphData(
            texture: nil,
            offset: CGPoint(x: 0, y: 8),
            advance: CGSize(width: 8, height: 10),
            frame: CGRect(x: 0, y: 0, width: 8, height: 10),
            ascender: 8,
            descender: -2
        ))
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        .zero
    }

    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "resolved-metrics-cache-test" }
    func isEqual(to other: any Typeface) -> Bool {
        self === (other as AnyObject)
    }
    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

private final class FractionalWidthTestTypeface: Typeface {
    let advance: CGFloat

    init(advance: CGFloat) {
        self.advance = advance
    }

    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? {
        .texture(TextureFont.GlyphData(
            texture: nil,
            offset: CGPoint(x: 0, y: 8),
            advance: CGSize(width: advance, height: 10),
            frame: CGRect(x: 0, y: 0, width: advance, height: 10),
            ascender: 8,
            descender: -2
        ))
    }

    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        .zero
    }

    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "fractional-width-\(advance)" }
    func isEqual(to other: any Typeface) -> Bool {
        guard let other = other as? FractionalWidthTestTypeface else {
            return false
        }
        return advance == other.advance
    }
    func hashIdentity(into hasher: inout Hasher) {
        hasher.combine(advance)
    }
}

private final class DPIRecordingTypefaceProvider: TypefaceProvider {
    var requestedDPIs: [UInt32] = []

    func isEqual(to other: any TypefaceProvider) -> Bool {
        self === (other as AnyObject)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    func makeTypeface(
        _ context: AppContext,
        dpi: UInt32
    ) -> (any Typeface)? {
        requestedDPIs.append(dpi)
        let contentScaleFactor = CGFloat(dpi) / CGFloat(defaultDPI)
        return FractionalWidthTestTypeface(
            advance: 7.3 * contentScaleFactor
        )
    }
}

private final class TextResolutionTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }

    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
    }
}

private final class ResolvedTextScaleTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext?
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    private var resources: [URL: any DataProtocol] = [:]

    init(graphicsDeviceContext: GraphicsDeviceContext) {
        self.graphicsDeviceContext = graphicsDeviceContext
    }

    func resourceData(forURL url: URL) -> (any DataProtocol)? {
        resources[url]
    }

    func setResource(data: (any DataProtocol)?, forURL url: URL) {
        resources[url] = data
    }
}
