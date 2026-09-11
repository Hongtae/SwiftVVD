import Foundation
import XCTest
@testable import VUI

private enum SystemOnlyFontDefinition: FontDefinition {
    static func resolveSystemFont(size: CGFloat, design: Font.Design?, weight: Font.Weight?, in context: Font.Context) -> FontDescriptor {
        FontDescriptor(source: .system(.default, .regular, false), pointSize: 99)
    }
}

final class FontTextStyleDescriptorTests: XCTestCase {
    private func textStyle(of descriptor: FontDescriptor) -> Font.TextStyle? {
        guard case let .system(_, _, _, _, style) = descriptor.source else { return nil }
        return style
    }

    // ASSERTIONS fontTextStyleDescriptorIdentityObserved
    // ASSERTIONS fontTextStyleDescriptorCopiesObserved
    func testTextStyleIdentitySurvivesOrderedFontModifiers() {
        for category in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
            var environment = EnvironmentValues()
            environment.dynamicTypeSize = category
            let context = environment.fontResolutionContext
            for style in Font.TextStyle.allCases {
                let base = Font.system(style)
                let original = base.resolveDescriptor(in: context)
                let variants = [base, base.weight(.heavy), base.italic(), base.width(.condensed),
                                base.monospaced(), base.monospaced(false), base.monospacedDigit(), base.bold(false),
                                base.weight(.light).italic().width(.expanded).monospacedDigit(),
                                base.monospaced().weight(.heavy)]
                for font in variants {
                    let descriptor = font.resolveDescriptor(in: context)
                    XCTAssertEqual(textStyle(of: descriptor), style)
                    XCTAssertEqual(descriptor.pointSize, original.pointSize)
                }
                XCTAssertEqual(textStyle(of: original), style)
            }
        }
    }

    // ASSERTIONS fontTextStyleDescriptorCopiesObserved
    func testDescriptorCopiesPreserveStyleWithoutMutatingRealizedBase() {
        let context = EnvironmentValues().fontResolutionContext
        for design in [Font.Design.default, .serif, .rounded, .monospaced] {
            let base = Font.system(.body, design: design).resolveDescriptor(in: context)
            XCTAssertEqual(base.resolvedWeight, 0)
            let changed = base.weight(.heavy).symbolicTrait(1, active: true).width(-0.2)
                .monospaced(true).adding(features: Font.MonospacedDigitModifier.shapingFeatures)
            guard case let .system(originalDesign, originalWeight, originalItalic, originalWidth, originalStyle) = base.source,
                  case let .system(changedDesign, changedWeight, changedItalic, changedWidth, changedStyle) = changed.source else {
                return XCTFail("Expected retained system requests.")
            }
            XCTAssertEqual(originalDesign, design)
            XCTAssertEqual(originalWeight, .regular)
            XCTAssertFalse(originalItalic)
            XCTAssertNil(originalWidth)
            XCTAssertEqual(originalStyle, .body)
            XCTAssertTrue(base.shapingFeatures.isEmpty)
            XCTAssertEqual(base.resolvedWeight, 0)
            XCTAssertEqual(changedStyle, .body)
            XCTAssertEqual(changedDesign, .monospaced)
            XCTAssertEqual(changedWeight, .heavy)
            XCTAssertTrue(changedItalic)
            XCTAssertEqual(changedWidth, -0.2)
            XCTAssertEqual(changed.pointSize, 13)
            XCTAssertEqual(changed.resolvedWeight, CGFloat(Float(0.56)))
            XCTAssertEqual(changed.shapingFeatures, Font.MonospacedDigitModifier.shapingFeatures)
            XCTAssertFalse(base === changed)
        }
    }

    // ASSERTIONS fontCustomRelativeStyleIsolationObserved
    func testFixedAndRelativeRequestsDoNotBecomeTextStyleDescriptors() {
        let context = EnvironmentValues().fontResolutionContext
        for font in [Font.system(size: 13), .system(size: 13, design: .monospaced),
                     .custom("Roboto-Regular", fixedSize: 13),
                     .custom("Roboto-Regular", size: 13, relativeTo: .body),
                     .custom("Roboto-Regular", size: 13, relativeTo: .title)] {
            for variant in [font, font.weight(.heavy), font.italic(), font.width(.condensed),
                            font.monospaced(), font.monospacedDigit()] {
                let descriptor = variant.resolveDescriptor(in: context)
                XCTAssertNil(textStyle(of: descriptor))
                XCTAssertEqual(descriptor.pointSize, 13)
            }
        }
        let relative = Font.SystemProvider(size: 13, weight: nil, design: nil, textStyle: .body, maximumSize: nil)
        XCTAssertNil(textStyle(of: relative.resolveDescriptor(in: context)))
    }

    // ASSERTIONS fontTextStyleDescriptorIdentityObserved
    func testDefaultTextStyleResolutionDoesNotUseSystemOverride() {
        var context = EnvironmentValues().fontResolutionContext
        context.fontDefinition.base = SystemOnlyFontDefinition.self
        XCTAssertEqual(Font.system(size: 13).resolveDescriptor(in: context).pointSize, 99)
        let descriptor = Font.system(.body).resolveDescriptor(in: context)
        XCTAssertEqual(descriptor.pointSize, 13)
        XCTAssertEqual(textStyle(of: descriptor), .body)
    }

    func testStyleMetadataLeavesGlyphResourceSelectionUnchanged() throws {
        let environment = EnvironmentValues()
        let style = Font.system(.body, design: .serif, weight: .heavy).width(.condensed).monospacedDigit()
        let fixed = Font.system(size: 13, weight: .heavy, design: .serif).width(.condensed).monospacedDigit()
        let styledFont = style.resolved(in: environment)
        let fixedFont = fixed.resolved(in: environment)
        let styledResource = try XCTUnwrap(styledFont.typefaceProvider as? SystemFontProvider)
        let fixedResource = try XCTUnwrap(fixedFont.typefaceProvider as? SystemFontProvider)
        XCTAssertTrue(styledResource.isEqual(to: fixedResource))
        XCTAssertEqual(styledFont.typefaceFeatures, fixedFont.typefaceFeatures)
    }
}
