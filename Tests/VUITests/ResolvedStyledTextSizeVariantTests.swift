import XCTest
@testable import VUI

final class ResolvedStyledTextSizeVariantTests: XCTestCase {
    func testSmallerVariantCreatesNonRetainingLargerReciprocal() {
        let source = ResolvedStyledText(version: 1)
        let target = ResolvedStyledText(version: 2)

        source.smallerSizeVariant = target

        XCTAssertTrue(source.smallerSizeVariant === target)
        XCTAssertTrue(target.largerSizeVariant === source)
    }

    func testLargerVariantCreatesNonRetainingSmallerReciprocal() {
        let source = ResolvedStyledText(version: 1)
        let target = ResolvedStyledText(version: 2)

        source.largerSizeVariant = target

        XCTAssertTrue(source.largerSizeVariant === target)
        XCTAssertTrue(target.smallerSizeVariant === source)
    }

    func testReplacingAndClearingVariantDetachPreviousReciprocal() {
        let source = ResolvedStyledText(version: 1)
        let first = ResolvedStyledText(version: 2)
        let second = ResolvedStyledText(version: 3)

        source.smallerSizeVariant = first
        source.smallerSizeVariant = second

        XCTAssertNil(first.largerSizeVariant)
        XCTAssertTrue(source.smallerSizeVariant === second)
        XCTAssertTrue(second.largerSizeVariant === source)

        source.smallerSizeVariant = nil

        XCTAssertNil(source.smallerSizeVariant)
        XCTAssertNil(second.largerSizeVariant)
    }

    func testPrimaryVariantRetainsAndReciprocalDoesNotRetain() {
        var source: ResolvedStyledText? = ResolvedStyledText(version: 1)
        var target: ResolvedStyledText? = ResolvedStyledText(version: 2)
        weak let weakSource = source
        weak let weakTarget = target

        source?.smallerSizeVariant = target
        target = nil

        XCTAssertNotNil(weakTarget)

        source = nil

        XCTAssertNil(weakSource)
        XCTAssertNil(weakTarget)
    }

    func testReciprocalDoesNotRetainPrimaryOwner() {
        let target = ResolvedStyledText(version: 2)
        weak var weakSource: ResolvedStyledText?

        do {
            let source = ResolvedStyledText(version: 1)
            weakSource = source
            source.smallerSizeVariant = target
            XCTAssertTrue(target.largerSizeVariant === source)
        }

        XCTAssertNil(weakSource)
        XCTAssertNil(target.largerSizeVariant)
    }
}
