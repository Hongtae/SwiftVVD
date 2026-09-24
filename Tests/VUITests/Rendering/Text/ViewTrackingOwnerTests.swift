import Foundation
import XCTest
@testable import VUI

// ASSERTIONS viewTrackingPublic27Observed

final class ViewTrackingOwnerTests: XCTestCase {
    func testViewProducerWritesTheDistinctDefaultTrackingEnvironmentKey() throws {
        typealias Modifier = _EnvironmentKeyWritingModifier<CGFloat>
        typealias Once = ModifiedContent<EmptyView, Modifier>
        typealias Twice = ModifiedContent<Once, Modifier>

        let once = try XCTUnwrap(EmptyView().tracking(3) as? Once)
        XCTAssertEqual(once.modifier.keyPath, \EnvironmentValues.defaultTracking)
        XCTAssertNotEqual(
            once.modifier.keyPath,
            \EnvironmentValues.defaultKerning
        )
        XCTAssertNotEqual(
            once.modifier.keyPath,
            \EnvironmentValues.defaultBaselineOffset
        )
        XCTAssertEqual(once.modifier.value, 3)

        var environment = EnvironmentValues()
        XCTAssertEqual(environment.defaultTracking, 0)
        environment[keyPath: once.modifier.keyPath] = once.modifier.value
        XCTAssertEqual(environment.defaultTracking, 3)

        let nested = try XCTUnwrap(
            EmptyView().tracking(3).tracking(5) as? Twice
        )
        environment[keyPath: nested.modifier.keyPath] = nested.modifier.value
        environment[keyPath: nested.content.modifier.keyPath] =
            nested.content.modifier.value
        XCTAssertEqual(environment.defaultTracking, 3)
    }

    func testTextTrackingUsesLocalValueBeforeInheritedFallback() {
        var environment = EnvironmentValues()
        XCTAssertNil(resolved(Text.Style(), in: environment).tracking)

        environment.defaultTracking = 3

        XCTAssertNil(Text.Style().tracking)
        XCTAssertEqual(resolved(Text.Style(), in: environment).tracking, 3)

        var local = Text.Style()
        Text.Modifier.tracking(7).modify(
            style: &local,
            environment: environment
        )
        XCTAssertEqual(resolved(local, in: environment).tracking, 7)

        var cleared = Text.Style()
        Text.Modifier.tracking(0).modify(
            style: &cleared,
            environment: environment
        )
        let clearedAttributes = resolved(cleared, in: environment)
        XCTAssertEqual(clearedAttributes.tracking, 0)
        XCTAssertNil(clearedAttributes.nsAttributes[.coreTracking])

        environment.defaultTracking = 0
        XCTAssertNil(resolved(Text.Style(), in: environment).tracking)
    }

    func testAttributedRunsReplaceCopiedParentTrackingIndependently() {
        var environment = EnvironmentValues()
        environment.defaultTracking = 3

        var explicit = Text.Style()
        var explicitRun: [NSAttributedString.Key: Any] = [
            .coreTracking: CGFloat(4)
        ]
        explicitRun.transferAttributedStringStyles(to: &explicit)
        XCTAssertEqual(resolved(explicit, in: environment).tracking, 4)
        XCTAssertNil(explicitRun[.coreTracking])

        var cleared = Text.Style()
        var zeroRun: [NSAttributedString.Key: Any] = [
            .coreTracking: CGFloat(0)
        ]
        zeroRun.transferAttributedStringStyles(to: &cleared)
        let clearedAttributes = resolved(cleared, in: environment)
        XCTAssertEqual(clearedAttributes.tracking, 0)
        XCTAssertNil(clearedAttributes.nsAttributes[.coreTracking])

        var parent = Text.Style()
        Text.Modifier.tracking(7).modify(
            style: &parent,
            environment: environment
        )
        var first = parent
        var firstRun: [NSAttributedString.Key: Any] = [
            .coreTracking: CGFloat(4)
        ]
        firstRun.transferAttributedStringStyles(to: &first)
        let second = parent
        XCTAssertEqual(resolved(first, in: environment).tracking, 4)
        XCTAssertEqual(resolved(second, in: environment).tracking, 7)
    }

    func testKerningRemainsASeparateStyleAndAttributeOwner() {
        var environment = EnvironmentValues()
        environment.defaultTracking = 3

        var localKerning = Text.Style()
        Text.Modifier.kerning(5).modify(
            style: &localKerning,
            environment: environment
        )
        let localAttributes = resolved(localKerning, in: environment)
        XCTAssertEqual(localAttributes.kern, 5)
        XCTAssertEqual(localAttributes.tracking, 3)

        var attributedKerning = Text.Style()
        var run: [NSAttributedString.Key: Any] = [
            .coreKern: CGFloat(4)
        ]
        run.transferAttributedStringStyles(to: &attributedKerning)
        let attributedAttributes = resolved(
            attributedKerning,
            in: environment
        )
        XCTAssertEqual(attributedAttributes.kern, 4)
        XCTAssertEqual(attributedAttributes.tracking, 3)
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
