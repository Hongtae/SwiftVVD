import Foundation
import XCTest
@testable import VUI

// ASSERTIONS viewBaselineOffsetPublic27Observed

final class ViewBaselineOffsetOwnerTests: XCTestCase {
    func testViewProducerWritesTheDefaultBaselineEnvironmentKey() throws {
        typealias Modifier = _EnvironmentKeyWritingModifier<CGFloat>
        typealias Once = ModifiedContent<EmptyView, Modifier>
        typealias Twice = ModifiedContent<Once, Modifier>

        let once = try XCTUnwrap(
            EmptyView().baselineOffset(3) as? Once
        )
        XCTAssertEqual(once.modifier.keyPath, \EnvironmentValues.defaultBaselineOffset)
        XCTAssertEqual(once.modifier.value, 3)

        var environment = EnvironmentValues()
        XCTAssertEqual(environment.defaultBaselineOffset, 0)
        environment[keyPath: once.modifier.keyPath] = once.modifier.value
        XCTAssertEqual(environment.defaultBaselineOffset, 3)

        let nested = try XCTUnwrap(
            EmptyView().baselineOffset(3).baselineOffset(5) as? Twice
        )
        environment[keyPath: nested.modifier.keyPath] = nested.modifier.value
        environment[keyPath: nested.content.modifier.keyPath] =
            nested.content.modifier.value
        XCTAssertEqual(environment.defaultBaselineOffset, 3)
    }

    func testTextBaselineUsesLocalValueBeforeInheritedFallback() {
        var environment = EnvironmentValues()
        environment.defaultBaselineOffset = 3

        XCTAssertNil(Text.Style().baselineOffset)
        XCTAssertEqual(resolved(Text.Style(), in: environment).baselineOffset, 3)

        var local = Text.Style()
        Text.Modifier.baseline(7).modify(
            style: &local,
            environment: environment
        )
        XCTAssertEqual(resolved(local, in: environment).baselineOffset, 7)

        var cleared = Text.Style()
        Text.Modifier.baseline(0).modify(
            style: &cleared,
            environment: environment
        )
        let clearedAttributes = resolved(cleared, in: environment)
        XCTAssertEqual(clearedAttributes.baselineOffset, 0)
        XCTAssertNil(clearedAttributes.nsAttributes[.coreBaselineOffset])
    }

    func testAttributedRunsReplaceCopiedParentStyleIndependently() {
        var environment = EnvironmentValues()
        environment.defaultBaselineOffset = 3

        var inherited = Text.Style()
        var explicit: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.coreBaselineOffset: CGFloat(4)
        ]
        explicit.transferAttributedStringStyles(to: &inherited)
        XCTAssertEqual(resolved(inherited, in: environment).baselineOffset, 4)
        XCTAssertNil(explicit[.coreBaselineOffset])

        var cleared = Text.Style()
        var zero: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.coreBaselineOffset: CGFloat(0)
        ]
        zero.transferAttributedStringStyles(to: &cleared)
        let clearedAttributes = resolved(cleared, in: environment)
        XCTAssertEqual(clearedAttributes.baselineOffset, 0)
        XCTAssertNil(clearedAttributes.nsAttributes[.coreBaselineOffset])

        var parent = Text.Style()
        Text.Modifier.baseline(7).modify(
            style: &parent,
            environment: environment
        )
        var first = parent
        var firstRun: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.coreBaselineOffset: CGFloat(4)
        ]
        firstRun.transferAttributedStringStyles(to: &first)
        let second = parent
        XCTAssertEqual(resolved(first, in: environment).baselineOffset, 4)
        XCTAssertEqual(resolved(second, in: environment).baselineOffset, 7)
    }

    private func resolved(
        _ style: Text.Style,
        in environment: EnvironmentValues
    ) -> _ResolvedTextRunAttributes {
        var properties = Text.ResolvedProperties()
        return style.nsAttributes(
            in: environment,
            properties: &properties,
            includeDefaultAttributes: false
        )
    }
}
