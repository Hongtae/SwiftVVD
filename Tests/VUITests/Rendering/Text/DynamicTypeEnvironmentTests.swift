import XCTest
import VUI

// ASSERTIONS dynamicTypeEnvironment27Observed

private func mirroredChild<T>(
    _ value: Any,
    label: String,
    as type: T.Type
) -> T? {
    Mirror(reflecting: value).children.first {
        $0.label == label
    }?.value as? T
}

final class DynamicTypeEnvironmentTests: XCTestCase {
    private let cases: [DynamicTypeSize] = [
        .xSmall,
        .small,
        .medium,
        .large,
        .xLarge,
        .xxLarge,
        .xxxLarge,
        .accessibility1,
        .accessibility2,
        .accessibility3,
        .accessibility4,
        .accessibility5,
    ]

    private func requireDynamicConformances<T>(_: T.Type)
    where T: Hashable & Comparable & CaseIterable & Sendable {}

    private func requireLegibilityConformances<T>(_: T.Type)
    where T: Hashable & Sendable {}

    private func transformed<R>(
        by range: R
    ) -> [DynamicTypeSize]? where R: RangeExpression,
        R.Bound == DynamicTypeSize
    {
        let view = EmptyView().dynamicTypeSize(range)
        guard let modifier = mirroredChild(
            view,
            label: "modifier",
            as: _EnvironmentKeyTransformModifier<DynamicTypeSize>.self
        ) else {
            return nil
        }
        return cases.map {
            var value = $0
            modifier.transform(&value)
            return value
        }
    }

    func testPublicValuesAndEnvironmentMatchNativeProbe() {
        requireDynamicConformances(DynamicTypeSize.self)
        requireLegibilityConformances(LegibilityWeight.self)

        XCTAssertEqual(DynamicTypeSize.allCases, cases)
        XCTAssertEqual(
            cases.map(\.isAccessibilitySize),
            [false, false, false, false, false, false, false,
             true, true, true, true, true]
        )
        for pair in zip(cases, cases.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
        XCTAssertNotEqual(LegibilityWeight.regular, .bold)

        var environment = EnvironmentValues()
        XCTAssertEqual(environment.dynamicTypeSize, .large)
        XCTAssertNil(environment.legibilityWeight)
        environment.dynamicTypeSize = .accessibility3
        environment.legibilityWeight = .bold
        XCTAssertEqual(environment.dynamicTypeSize, .accessibility3)
        XCTAssertEqual(environment.legibilityWeight, .bold)
    }

    func testExactModifierWritesDynamicTypeEnvironment() throws {
        let view = EmptyView().dynamicTypeSize(.xxLarge)
        let modifier = try XCTUnwrap(
            mirroredChild(
                view,
                label: "modifier",
                as: _EnvironmentKeyWritingModifier<DynamicTypeSize>.self
            )
        )
        XCTAssertEqual(modifier.keyPath, \.dynamicTypeSize)
        XCTAssertEqual(modifier.value, .xxLarge)
    }

    func testRangeModifierClampsEveryDynamicTypeCase() {
        XCTAssertEqual(
            transformed(by: DynamicTypeSize.medium ... .accessibility2),
            [.medium, .medium, .medium, .large, .xLarge, .xxLarge,
             .xxxLarge, .accessibility1, .accessibility2, .accessibility2,
             .accessibility2, .accessibility2]
        )
        XCTAssertEqual(
            transformed(by: DynamicTypeSize.medium ..< .accessibility2),
            [.medium, .medium, .medium, .large, .xLarge, .xxLarge,
             .xxxLarge, .accessibility1, .accessibility1, .accessibility1,
             .accessibility1, .accessibility1]
        )
        XCTAssertEqual(
            transformed(by: ...DynamicTypeSize.large),
            [.xSmall, .small, .medium, .large, .large, .large,
             .large, .large, .large, .large, .large, .large]
        )
        XCTAssertEqual(
            transformed(by: ..<DynamicTypeSize.large),
            [.xSmall, .small, .medium, .medium, .medium, .medium,
             .medium, .medium, .medium, .medium, .medium, .medium]
        )
        XCTAssertEqual(
            transformed(by: DynamicTypeSize.xxxLarge...),
            [.xxxLarge, .xxxLarge, .xxxLarge, .xxxLarge, .xxxLarge,
             .xxxLarge, .xxxLarge, .accessibility1, .accessibility2,
             .accessibility3, .accessibility4, .accessibility5]
        )
        XCTAssertEqual(
            transformed(
                by: DynamicTypeSize.accessibility1 ... .accessibility1
            ),
            Array(repeating: .accessibility1, count: cases.count)
        )
        XCTAssertEqual(
            transformed(
                by: DynamicTypeSize.accessibility1 ..< .accessibility1
            ),
            Array(repeating: .xxxLarge, count: cases.count)
        )
    }
}
