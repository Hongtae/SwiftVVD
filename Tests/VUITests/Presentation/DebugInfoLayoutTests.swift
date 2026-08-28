import XCTest
@testable import VUI

final class DebugInfoLayoutTests: XCTestCase {
    func testStandardAlignmentsPlaceAndAlignEveryLine() {
        let bounds = CGRect(x: 10, y: 20, width: 200, height: 100)
        let lineSizes = [
            CGSize(width: 40, height: 10),
            CGSize(width: 80, height: 20),
        ]
        let cases: [(Alignment, [CGRect])] = [
            (
                .topLeading,
                [
                    CGRect(x: 15, y: 25, width: 40, height: 10),
                    CGRect(x: 15, y: 35, width: 80, height: 20),
                ]
            ),
            (
                .top,
                [
                    CGRect(x: 90, y: 25, width: 40, height: 10),
                    CGRect(x: 70, y: 35, width: 80, height: 20),
                ]
            ),
            (
                .topTrailing,
                [
                    CGRect(x: 165, y: 25, width: 40, height: 10),
                    CGRect(x: 125, y: 35, width: 80, height: 20),
                ]
            ),
            (
                .leading,
                [
                    CGRect(x: 15, y: 55, width: 40, height: 10),
                    CGRect(x: 15, y: 65, width: 80, height: 20),
                ]
            ),
            (
                .center,
                [
                    CGRect(x: 90, y: 55, width: 40, height: 10),
                    CGRect(x: 70, y: 65, width: 80, height: 20),
                ]
            ),
            (
                .trailing,
                [
                    CGRect(x: 165, y: 55, width: 40, height: 10),
                    CGRect(x: 125, y: 65, width: 80, height: 20),
                ]
            ),
            (
                .bottomLeading,
                [
                    CGRect(x: 15, y: 85, width: 40, height: 10),
                    CGRect(x: 15, y: 95, width: 80, height: 20),
                ]
            ),
            (
                .bottom,
                [
                    CGRect(x: 90, y: 85, width: 40, height: 10),
                    CGRect(x: 70, y: 95, width: 80, height: 20),
                ]
            ),
            (
                .bottomTrailing,
                [
                    CGRect(x: 165, y: 85, width: 40, height: 10),
                    CGRect(x: 125, y: 95, width: 80, height: 20),
                ]
            ),
        ]

        for (alignment, expectedFrames) in cases {
            XCTAssertEqual(
                DebugInfoLayout.lineFrames(
                    for: lineSizes,
                    in: bounds,
                    placement: DebugInfoPlacement(alignment: alignment)
                ),
                expectedFrames,
                "Unexpected frames for \(alignment)."
            )
        }
    }

    func testOffsetTranslatesTheAlignedBlockAfterInsetPlacement() {
        let frames = DebugInfoLayout.lineFrames(
            for: [
                CGSize(width: 40, height: 10),
                CGSize(width: 80, height: 20),
            ],
            in: CGRect(x: 10, y: 20, width: 200, height: 100),
            placement: DebugInfoPlacement(
                alignment: .topTrailing,
                offset: CGSize(width: 3, height: -4)
            )
        )

        XCTAssertEqual(
            frames,
            [
                CGRect(x: 168, y: 21, width: 40, height: 10),
                CGRect(x: 128, y: 31, width: 80, height: 20),
            ]
        )
        XCTAssertEqual(frames.map(\.maxX), [208, 208])
    }

    func testEmptyLinesProduceNoFrames() {
        XCTAssertTrue(
            DebugInfoLayout.lineFrames(
                for: [],
                in: CGRect(x: 10, y: 20, width: 200, height: 100),
                placement: DebugInfoPlacement()
            ).isEmpty
        )
    }
}
