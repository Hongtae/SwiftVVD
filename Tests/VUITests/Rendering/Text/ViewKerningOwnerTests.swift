import Foundation
import XCTest
@testable import VUI

// ASSERTIONS viewKerningPublic27Observed

final class ViewKerningOwnerTests: XCTestCase {
    func testViewProducerWritesTheDistinctDefaultKerningEnvironmentKey() throws {
        typealias Modifier = _EnvironmentKeyWritingModifier<CGFloat>
        typealias Once = ModifiedContent<EmptyView, Modifier>
        typealias Twice = ModifiedContent<Once, Modifier>

        let once = try XCTUnwrap(EmptyView().kerning(3) as? Once)
        XCTAssertEqual(once.modifier.keyPath, \EnvironmentValues.defaultKerning)
        XCTAssertNotEqual(
            once.modifier.keyPath,
            \EnvironmentValues.defaultBaselineOffset
        )
        XCTAssertEqual(once.modifier.value, 3)

        var environment = EnvironmentValues()
        XCTAssertEqual(environment.defaultKerning, 0)
        environment[keyPath: once.modifier.keyPath] = once.modifier.value
        XCTAssertEqual(environment.defaultKerning, 3)

        let nested = try XCTUnwrap(
            EmptyView().kerning(3).kerning(5) as? Twice
        )
        environment[keyPath: nested.modifier.keyPath] = nested.modifier.value
        environment[keyPath: nested.content.modifier.keyPath] =
            nested.content.modifier.value
        XCTAssertEqual(environment.defaultKerning, 3)
    }

    func testTextKerningUsesLocalValueBeforeInheritedFallback() {
        var environment = EnvironmentValues()
        XCTAssertNil(resolved(Text.Style(), in: environment).kern)

        environment.defaultKerning = 3

        XCTAssertNil(Text.Style().kerning)
        XCTAssertEqual(resolved(Text.Style(), in: environment).kern, 3)

        var local = Text.Style()
        Text.Modifier.kerning(7).modify(
            style: &local,
            environment: environment
        )
        XCTAssertEqual(resolved(local, in: environment).kern, 7)

        var cleared = Text.Style()
        Text.Modifier.kerning(0).modify(
            style: &cleared,
            environment: environment
        )
        let clearedAttributes = resolved(cleared, in: environment)
        XCTAssertEqual(clearedAttributes.kern, 0)
        XCTAssertNil(clearedAttributes.nsAttributes[.coreKern])

        environment.defaultKerning = 0
        XCTAssertNil(resolved(Text.Style(), in: environment).kern)
    }

    func testAttributedRunsReplaceCopiedParentKerningIndependently() {
        var environment = EnvironmentValues()
        environment.defaultKerning = 3

        var explicit = Text.Style()
        var explicitRun: [NSAttributedString.Key: Any] = [
            .coreKern: CGFloat(4)
        ]
        explicitRun.transferAttributedStringStyles(to: &explicit)
        XCTAssertEqual(resolved(explicit, in: environment).kern, 4)
        XCTAssertNil(explicitRun[.coreKern])

        var cleared = Text.Style()
        var zeroRun: [NSAttributedString.Key: Any] = [
            .coreKern: CGFloat(0)
        ]
        zeroRun.transferAttributedStringStyles(to: &cleared)
        let clearedAttributes = resolved(cleared, in: environment)
        XCTAssertEqual(clearedAttributes.kern, 0)
        XCTAssertNil(clearedAttributes.nsAttributes[.coreKern])

        var parent = Text.Style()
        Text.Modifier.kerning(7).modify(
            style: &parent,
            environment: environment
        )
        var first = parent
        var firstRun: [NSAttributedString.Key: Any] = [
            .coreKern: CGFloat(4)
        ]
        firstRun.transferAttributedStringStyles(to: &first)
        let second = parent
        XCTAssertEqual(resolved(first, in: environment).kern, 4)
        XCTAssertEqual(resolved(second, in: environment).kern, 7)
    }

    func testTrackingRemainsASeparateStyleAndAttributeOwner() {
        var environment = EnvironmentValues()
        environment.defaultKerning = 3

        var localTracking = Text.Style()
        Text.Modifier.tracking(5).modify(
            style: &localTracking,
            environment: environment
        )
        let localAttributes = resolved(localTracking, in: environment)
        XCTAssertEqual(localAttributes.kern, 3)
        XCTAssertEqual(localAttributes.tracking, 5)

        var attributedTracking = Text.Style()
        var run: [NSAttributedString.Key: Any] = [
            .coreTracking: CGFloat(4)
        ]
        run.transferAttributedStringStyles(to: &attributedTracking)
        let attributedAttributes = resolved(
            attributedTracking,
            in: environment
        )
        XCTAssertEqual(attributedAttributes.kern, 3)
        XCTAssertEqual(attributedAttributes.tracking, 4)
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
