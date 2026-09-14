import Foundation
import XCTest
@testable import VUI

final class TextLayoutPropertiesTests: XCTestCase {
    func testObservedCarrierLayoutAndDefaults() throws {
        XCTAssertEqual(MemoryLayout<TextLayoutProperties>.size, 145)
        XCTAssertEqual(MemoryLayout<TextLayoutProperties>.stride, 152)
        XCTAssertEqual(MemoryLayout<Text.Sizing>.size, 16)
        XCTAssertEqual(MemoryLayout<Text.WritingMode>.size, 1)
        XCTAssertEqual(MemoryLayout<TextShape>.size, 24)
        XCTAssertEqual(MemoryLayout<HorizontalEdge>.size, 1)

        let value = TextLayoutProperties()
        XCTAssertNil(value.lineLimit)
        XCTAssertNil(value.lowerLineLimit)
        XCTAssertEqual(value.truncationMode, .tail)
        XCTAssertEqual(value.multilineTextAlignment, .leading)
        XCTAssertEqual(value.layoutDirection, .leftToRight)
        XCTAssertEqual(value.transitionStyle, .default)
        XCTAssertEqual(value.minScaleFactor, 1)
        XCTAssertEqual(value.lineSpacing, 0)
        XCTAssertEqual(value.lineHeightMultiple, 0)
        XCTAssertEqual(value.maximumLineHeight, 0)
        XCTAssertEqual(value.minimumLineHeight, 0)
        XCTAssertEqual(value.hyphenationFactor, 0)
        XCTAssertFalse(value.hyphenationDisabled)
        XCTAssertEqual(value.writingMode, .horizontalTopToBottom)
        XCTAssertEqual(value.bodyHeadOutdent, 0)
        XCTAssertEqual(value.pixelLength, 1)
        XCTAssertEqual(value.textSizing, .standard)
        XCTAssertEqual(value.textShape, .bounds)
        XCTAssertFalse(value.widthIsFlexible)
        XCTAssertFalse(value.sizeFitting)
        XCTAssertEqual(try ProtobufEncoder.encoding(value), Data())
    }

    func testEnvironmentConstructionUsesObservedInputsAndClampsLineBounds() {
        var environment = EnvironmentValues()
        environment.lineLimit = 0
        environment.lowerLineLimit = -3
        environment.truncationMode = .middle
        environment.multilineTextAlignment = .trailing
        environment.layoutDirection = .rightToLeft
        environment.contentTransitionState.style = .animatedWidget
        environment.minimumScaleFactor = 0.6
        environment.lineSpacing = 2
        environment.lineHeightMultiple = 1.25
        environment.maximumLineHeight = 30
        environment.minimumLineHeight = 12
        environment.hyphenationFactor = 0.75
        environment.hyphenationDisabled = true
        environment.writingMode = .verticalRightToLeft
        environment.bodyHeadOutdent = 4
        environment.defaultPixelLength = 0.5
        environment.textSizing = .adjustsForOversizedCharacters
        environment.textShape = .excludeTop(.trailing, size: CGSize(width: 8, height: 9))
        environment.textJustification = .full(allLines: false, flexible: true)

        let value = TextLayoutProperties(from: environment)
        XCTAssertEqual(value.lineLimit, 1)
        XCTAssertEqual(value.lowerLineLimit, 0)
        XCTAssertEqual(value.truncationMode, .middle)
        XCTAssertEqual(value.multilineTextAlignment, .trailing)
        XCTAssertEqual(value.layoutDirection, .rightToLeft)
        XCTAssertEqual(value.transitionStyle, .animatedWidget)
        XCTAssertEqual(value.minScaleFactor, 0.6)
        XCTAssertEqual(value.lineSpacing, 2)
        XCTAssertEqual(value.lineHeightMultiple, 1.25)
        XCTAssertEqual(value.maximumLineHeight, 30)
        XCTAssertEqual(value.minimumLineHeight, 12)
        XCTAssertEqual(value.hyphenationFactor, 0.75)
        XCTAssertTrue(value.hyphenationDisabled)
        XCTAssertEqual(value.writingMode, .verticalRightToLeft)
        XCTAssertEqual(value.bodyHeadOutdent, 4)
        XCTAssertEqual(value.pixelLength, 0.5)
        XCTAssertEqual(value.textSizing, .adjustsForOversizedCharacters)
        XCTAssertEqual(value.textShape, environment.textShape)
        XCTAssertTrue(value.widthIsFlexible)
        XCTAssertFalse(value.sizeFitting)
    }

    // ASSERTIONS textMinimumScaleFactorEnvironmentObserved
    func testMinimumScaleFactorNormalizesOutOfRangeEnvironmentValues() {
        let controls: [(CGFloat, CGFloat)] = [
            (-.infinity, 1), (-0.5, 1), (-0.0, 1), (0, 1),
            (.leastNonzeroMagnitude, .leastNonzeroMagnitude), (0.25, 0.25),
            (1, 1), (CGFloat(1).nextUp, 1), (.infinity, 1), (.nan, .nan)
        ]
        var environment = EnvironmentValues()
        for (input, expected) in controls {
            environment.minimumScaleFactor = input
            let stored = environment.minimumScaleFactor
            let resolved = TextLayoutProperties(from: environment).minScaleFactor
            if expected.isNaN {
                XCTAssertTrue(stored.isNaN)
                XCTAssertTrue(resolved.isNaN)
            } else {
                XCTAssertEqual(stored, expected, "Input: \(input)")
                XCTAssertEqual(resolved, expected, "Input: \(input)")
            }
        }
    }

    // ASSERTIONS canvasTextLayoutDerivedEnvironmentObserved
    func testDerivedLayoutReadTracksNormalizedResultInsteadOfRawLineLimits() throws {
        var original = EnvironmentValues()
        original.lineLimit = 0
        original.lowerLineLimit = -3
        let environment = original.trackingCopy()
        let tracker = try XCTUnwrap(environment.tracker)
        let properties = environment[TextLayoutProperties.Key.self]
        XCTAssertEqual(properties.lineLimit, 1)
        XCTAssertEqual(properties.lowerLineLimit, 0)
        XCTAssertEqual(properties, TextLayoutProperties(from: original))

        var equivalent = original
        equivalent.lineLimit = -4
        equivalent.lowerLineLimit = -8
        equivalent.colorScheme = .dark
        XCTAssertFalse(tracker.hasDifferentUsedValues(equivalent._plist))

        var different = equivalent
        different.lineLimit = 2
        XCTAssertTrue(tracker.hasDifferentUsedValues(different._plist))
        different = equivalent
        different.lineSpacing = 3
        XCTAssertTrue(tracker.hasDifferentUsedValues(different._plist))
    }

    func testDerivedLayoutValueCopiesRemainIndependentAcrossTrackedOverrides() {
        var original = EnvironmentValues()
        original.lineLimit = 3
        var environment = original.trackingCopy()
        let saved = environment[TextLayoutProperties.Key.self]
        var edited = saved
        edited.lineLimit = 7
        edited.sizeFitting = true
        XCTAssertEqual(environment[TextLayoutProperties.Key.self], saved)

        environment.lineLimit = 5
        let overridden = environment[TextLayoutProperties.Key.self]
        XCTAssertEqual(overridden.lineLimit, 5)
        XCTAssertFalse(overridden.sizeFitting)
        XCTAssertEqual(saved.lineLimit, 3)
        XCTAssertEqual(edited.lineLimit, 7)
        XCTAssertTrue(edited.sizeFitting)
        XCTAssertEqual(original[TextLayoutProperties.Key.self].lineLimit, 3)
    }

    // ASSERTIONS canvasTextLayoutDerivedEnvironmentObserved
    func testStyledTextProducerTracksDerivedLayoutInsteadOfRawLineLimit() throws {
        var original = EnvironmentValues()
        original.font = Font.system(size: 14).resolved(in: original)
        original.lineLimit = 0
        let environment = original.trackingCopy()
        let tracker = try XCTUnwrap(environment.tracker)
        let context = GraphTextResolutionContext(
            environment: environment, sceneResources: SceneResources()
        )
        let text = Text(verbatim: "Layout").foregroundColor(.black)
        let resolved = try XCTUnwrap(text._resolveStyledText(
            context: context, referenceDate: Date(timeIntervalSinceReferenceDate: 0),
            archiveOptions: .init(), features: [], sizeFitting: false
        ))
        XCTAssertEqual(resolved.layoutProperties.lineLimit, 1)
        XCTAssertFalse(tracker.hasDifferentUsedValues(original._plist))
        var equivalent = original
        equivalent.lineLimit = -4
        XCTAssertFalse(tracker.hasDifferentUsedValues(equivalent._plist))
        var different = original
        different.lineLimit = 2
        XCTAssertTrue(tracker.hasDifferentUsedValues(different._plist))
    }

    func testProtobufFieldMappingMatchesObservedTags() throws {
        var value = TextLayoutProperties()
        value.truncationMode = .head
        value.lineLimit = 2
        value.lowerLineLimit = -1
        value.multilineTextAlignment = .center
        value.layoutDirection = .rightToLeft
        value.transitionStyle = .sessionWidget
        value.writingMode = .verticalRightToLeft
        value.widthIsFlexible = true
        value.textSizing = .uniformLineHeight
        value.sizeFitting = true
        value.hyphenationDisabled = true

        let data = try ProtobufEncoder.encoding(value)
        XCTAssertEqual(
            data,
            Data([
                0x08, 0x01,
                0x10, 0x04,
                0x18, 0x01,
                0x60, 0x02,
                0x68, 0x01,
                0x72, 0x02, 0x0a, 0x00,
                0x80, 0x01, 0x01,
                0x88, 0x01, 0x01,
                0x90, 0x01, 0x01,
                0x98, 0x01, 0x01,
                0xa0, 0x01, 0x01,
            ])
        )

        var decoder = ProtobufDecoder(data)
        XCTAssertEqual(try TextLayoutProperties(from: &decoder), value)
    }

    func testContentTransitionStyleUsesEmptyVariantMessages() throws {
        XCTAssertEqual(
            try ProtobufEncoder.encoding(ContentTransition.Style.default),
            Data()
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(ContentTransition.Style.sessionWidget),
            Data([0x0a, 0x00])
        )
        XCTAssertEqual(
            try ProtobufEncoder.encoding(ContentTransition.Style.animatedWidget),
            Data([0x12, 0x00])
        )

        var sessionDecoder = ProtobufDecoder(Data([0x0a, 0x00]))
        XCTAssertEqual(
            try ContentTransition.Style(from: &sessionDecoder),
            .sessionWidget
        )
    }
}
