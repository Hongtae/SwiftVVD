import XCTest
@testable import VUI

final class ViewSpacingTests: XCTestCase {
    func testUnionAdoptsOtherDirectionBeforeResolvingLogicalEdges() {
        let other = ViewSpacing(
            Spacing(minima: [
                .init(category: .default, edge: .left): .distance(3),
                .init(category: .default, edge: .right): .distance(9),
            ]),
            layoutDirection: .rightToLeft
        )

        let result = ViewSpacing().union(other, edges: .leading)

        XCTAssertEqual(result.layoutDirection, .rightToLeft)
        XCTAssertNil(scalar(result.spacing, category: .default, edge: .left))
        XCTAssertEqual(
            scalar(result.spacing, category: .default, edge: .right),
            9
        )
    }

    func testUnionKeepsExistingDirectionInsteadOfTakingOtherDirection() {
        let initial = ViewSpacing(
            Spacing(),
            layoutDirection: .leftToRight
        )
        let other = ViewSpacing(
            Spacing(minima: [
                .init(category: .default, edge: .left): .distance(3),
                .init(category: .default, edge: .right): .distance(9),
            ]),
            layoutDirection: .rightToLeft
        )

        var result = initial
        result.formUnion(other, edges: .leading)

        XCTAssertEqual(result.layoutDirection, .leftToRight)
        XCTAssertEqual(
            scalar(result.spacing, category: .default, edge: .left),
            3
        )
        XCTAssertNil(scalar(result.spacing, category: .default, edge: .right))
    }

    func testDistancePrefersExactNonDefaultCategoryOverDefaults() {
        let category = Spacing.Category.edgeBelowText
        let predecessor = Spacing(minima: [
            .init(category: category, edge: .right): .distance(3),
            .init(category: .default, edge: .right): .distance(90),
        ])
        let successor = Spacing(minima: [
            .init(category: category, edge: .left): .distance(4),
            .init(category: .default, edge: .left): .distance(80),
            .init(category: .textBaseline, edge: .top): .distance(100),
        ])

        XCTAssertEqual(
            predecessor.distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .leftToRight,
                preferring: successor
            ),
            7
        )
    }

    func testDistanceDoesNotRemapSpecialCategories() {
        let predecessor = Spacing(minima: [
            .init(category: .edgeAboveText, edge: .right): .distance(30),
            .init(category: .default, edge: .right): .distance(5),
        ])
        let successor = Spacing(minima: [
            .init(category: .edgeBelowText, edge: .left): .distance(40),
            .init(category: .default, edge: .left): .distance(7),
        ])

        XCTAssertEqual(
            predecessor.distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .leftToRight,
                preferring: successor
            ),
            7
        )
    }

    func testDistanceUsesMaximumDefaultScalarAndPhysicalDirection() {
        let predecessor = Spacing(minima: [
            .init(category: .default, edge: .left): .distance(11),
            .init(category: .default, edge: .right): .distance(5),
            .init(category: .default, edge: .bottom): .distance(3),
        ])
        let successor = Spacing(minima: [
            .init(category: .default, edge: .left): .distance(7),
            .init(category: .default, edge: .right): .distance(13),
            .init(category: .default, edge: .top): .distance(9),
        ])

        XCTAssertEqual(
            predecessor.distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .leftToRight,
                preferring: successor
            ),
            7
        )
        XCTAssertEqual(
            predecessor.distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .rightToLeft,
                preferring: successor
            ),
            13
        )
        XCTAssertEqual(
            predecessor.distanceToSuccessorView(
                along: .vertical,
                layoutDirection: .rightToLeft,
                preferring: successor
            ),
            9
        )

        let onlyPredecessor = Spacing(minima: [
            .init(category: .default, edge: .right): .distance(4),
        ])
        XCTAssertEqual(
            onlyPredecessor.distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .leftToRight,
                preferring: Spacing()
            ),
            4
        )
        XCTAssertEqual(
            onlyPredecessor.distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .leftToRight,
                preferring: Spacing(minima: [
                    .init(category: .default, edge: .top): .distance(1),
                    .init(category: .default, edge: .bottom): .distance(2),
                ])
            ),
            4
        )
        XCTAssertNil(
            Spacing().distanceToSuccessorView(
                along: .horizontal,
                layoutDirection: .leftToRight,
                preferring: Spacing()
            )
        )
    }

    func testResetRetainsBoundaryCategoryAndDeletesOtherSelectedKeys() {
        let retained = Spacing.Key(category: .edgeBelowText, edge: .top)
        let unselected = Spacing.Key(category: .default, edge: .left)
        var spacing = Spacing(minima: [
            retained: .distance(12),
            .init(category: .default, edge: .top): .distance(4),
            .init(category: .textToText, edge: .top): .distance(8),
            unselected: .distance(7),
        ])

        spacing.reset(.top)

        XCTAssertEqual(spacing.minima.count, 2)
        XCTAssertEqual(spacing.minima[retained]?.value, 0)
        XCTAssertEqual(spacing.minima[unselected]?.value, 7)
    }

    func testResetInsertsTheBoundaryCategoryForEveryPhysicalEdge() {
        var spacing = Spacing()

        spacing.reset(.all)

        XCTAssertEqual(spacing.minima.count, 4)
        XCTAssertEqual(
            scalar(spacing, category: .edgeBelowText, edge: .top),
            0
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeRightText, edge: .left),
            0
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeAboveText, edge: .bottom),
            0
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeLeftText, edge: .right),
            0
        )
        for edge in AbsoluteEdge.allCases {
            XCTAssertNil(scalar(spacing, category: .default, edge: edge))
        }
    }

    func testTextMetricsSpacingPreservesArithmeticAndPixelSemantics() {
        let equal = Spacing.TextMetrics(
            ascend: 21.7265625,
            descend: 5.0859375,
            leading: 0.78515625,
            pixelLength: 0.5
        )
        XCTAssertEqual(
            Spacing.TextMetrics.spacing(top: equal, bottom: equal),
            1
        )

        let mismatchedTop = Spacing.TextMetrics(
            ascend: 0,
            descend: 3,
            leading: 0,
            pixelLength: 0.5
        )
        let cancellationBottom = Spacing.TextMetrics(
            ascend: 10_000_000_000_000_000,
            descend: 1,
            leading: 1,
            pixelLength: 99
        )
        XCTAssertEqual(
            Spacing.TextMetrics.spacing(
                top: mismatchedTop,
                bottom: cancellationBottom
            ),
            0
        )

        let zeroPixel = Spacing.TextMetrics(
            ascend: 1,
            descend: 1,
            leading: 2.4,
            pixelLength: 0
        )
        XCTAssertTrue(
            Spacing.TextMetrics.spacing(
                top: zeroPixel,
                bottom: zeroPixel
            ).isNaN
        )

        let negativePixel = Spacing.TextMetrics(
            ascend: 1,
            descend: 1,
            leading: 2.4,
            pixelLength: -0.5
        )
        XCTAssertEqual(
            Spacing.TextMetrics.spacing(
                top: negativePixel,
                bottom: negativePixel
            ),
            2
        )
    }

    func testTextSpacingBuildsHorizontalSixEntryMap() {
        let spacing = makeTextSpacing()
        let expectedMetrics = Spacing.TextMetrics(
            ascend: 12.568359375,
            descend: 2.7421875,
            leading: 0,
            pixelLength: 0.5
        )

        XCTAssertEqual(spacing.minima.count, 6)
        XCTAssertEqual(
            spacing.minima[.init(
                category: .textToText,
                edge: .top
            )],
            .bottomTextMetrics(expectedMetrics)
        )
        XCTAssertEqual(
            spacing.minima[.init(
                category: .textToText,
                edge: .bottom
            )],
            .topTextMetrics(expectedMetrics)
        )
        XCTAssertEqual(
            scalar(spacing, category: .textBaseline, edge: .top),
            -13
        )
        XCTAssertEqual(
            scalar(spacing, category: .textBaseline, edge: .bottom),
            -3
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeAboveText, edge: .top),
            4.7421875
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeBelowText, edge: .bottom),
            8.15087890625
        )
    }

    func testTextSpacingRotatesCategoriesForVerticalWriting() {
        var properties = TextLayoutProperties()
        properties.pixelLength = 0.5
        properties.writingMode = .verticalRightToLeft

        let spacing = makeTextSpacing(properties: properties)

        XCTAssertEqual(spacing.minima.count, 6)
        XCTAssertNotNil(spacing.minima[.init(
            category: .textToText,
            edge: .right
        )])
        XCTAssertNotNil(spacing.minima[.init(
            category: .textToText,
            edge: .left
        )])
        XCTAssertEqual(
            scalar(spacing, category: .rightTextBaseline, edge: .right),
            -13
        )
        XCTAssertEqual(
            scalar(spacing, category: .leftTextBaseline, edge: .left),
            -3
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeRightText, edge: .right),
            4.7421875
        )
        XCTAssertEqual(
            scalar(spacing, category: .edgeLeftText, edge: .left),
            8.15087890625
        )
        XCTAssertNil(spacing.minima[.init(
            category: .textToText,
            edge: .top
        )])
    }

    func testUniformLineHeightDistributesLeadingIntoTextMetrics() {
        var standardProperties = TextLayoutProperties()
        standardProperties.pixelLength = 1
        var uniformProperties = standardProperties
        uniformProperties.textSizing = .uniformLineHeight
        let font = ResolvedFontMetrics(
            capHeight: 8,
            ascender: 10,
            descender: -3,
            leading: 4
        )
        let ideal = ResolvedTextSource.LayoutMetrics(
            size: CGSize(width: 10, height: 15),
            firstBaseline: 11,
            lastBaseline: 11
        )

        let standard = Spacing.textSpacing(
            maxFontMetrics: font,
            idealMetrics: ideal,
            layoutProperties: standardProperties
        )
        let uniform = Spacing.textSpacing(
            maxFontMetrics: font,
            idealMetrics: ideal,
            layoutProperties: uniformProperties
        )

        XCTAssertEqual(
            textMetrics(standard, edge: .top),
            Spacing.TextMetrics(
                ascend: 10,
                descend: 3,
                leading: 4,
                pixelLength: 1
            )
        )
        XCTAssertEqual(
            textMetrics(uniform, edge: .top),
            Spacing.TextMetrics(
                ascend: 12,
                descend: 5,
                leading: 0,
                pixelLength: 1
            )
        )
        XCTAssertEqual(
            scalar(standard, category: .edgeAboveText, edge: .top),
            5
        )
        XCTAssertEqual(
            scalar(uniform, category: .edgeAboveText, edge: .top),
            3
        )
    }

    func testEmptyResolvedTextPublishesEmptySpacing() {
        let text = ResolvedStyledText()
        XCTAssertTrue(text.spacing().minima.isEmpty)
        XCTAssertTrue(
            StyledTextLayoutEngine(text: text, renderer: nil)
                .spacing()
                .minima
                .isEmpty
        )
    }

    private func makeTextSpacing(
        properties: TextLayoutProperties? = nil
    ) -> Spacing {
        let resolvedProperties: TextLayoutProperties
        if let properties {
            resolvedProperties = properties
        } else {
            var defaults = TextLayoutProperties()
            defaults.pixelLength = 0.5
            resolvedProperties = defaults
        }
        return Spacing.textSpacing(
            maxFontMetrics: ResolvedFontMetrics(
                capHeight: 9.15966796875,
                ascender: 12.568359375,
                descender: -2.7421875,
                leading: 0
            ),
            idealMetrics: ResolvedTextSource.LayoutMetrics(
                size: CGSize(width: 9, height: 16),
                firstBaseline: 13,
                lastBaseline: 13
            ),
            layoutProperties: resolvedProperties
        )
    }

    private func scalar(
        _ spacing: Spacing,
        category: Spacing.Category,
        edge: AbsoluteEdge
    ) -> CGFloat? {
        spacing.minima[.init(category: category, edge: edge)]?.value
    }

    private func textMetrics(
        _ spacing: Spacing,
        edge: AbsoluteEdge
    ) -> Spacing.TextMetrics? {
        guard let value = spacing.minima[.init(
            category: .textToText,
            edge: edge
        )] else {
            return nil
        }
        switch value {
        case let .topTextMetrics(metrics),
             let .bottomTextMetrics(metrics):
            return metrics
        case .distance:
            return nil
        }
    }
}
