import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import VUI

private final class ResolvedRequestCounter: Sendable {
    let calls = Mutex(0)
}

private struct RetainedRequestProvider: FontProvider {
    let counter: ResolvedRequestCounter
    var tag: Font.ProviderTag { .typeface }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.counter === rhs.counter }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(counter)) }
    func resolveDescriptor(in context: Font.Context) -> FontDescriptor {
        counter.calls.withLock { $0 += 1 }
        XCTAssertTrue(context.fontModifiers.isEmpty)
        return FontDescriptor(source: .system(.default, .regular, false, textStyle: .body), pointSize: 13)
    }
    func serialize(to encoder: any Encoder) throws { throw CocoaError(.coderInvalidValue) }
    static func deserialize(from decoder: any Decoder) throws -> Self { throw CocoaError(.coderInvalidValue) }
}

final class FontResolvedTests: XCTestCase {
    // ASSERTIONS fontResolvedRetainedContextObserved
    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testConstructionAndCopiesRetainRequestsWithoutRealizingThem() {
        let counter = ResolvedRequestCounter()
        var environment = EnvironmentValues()
        environment.font = .system(size: 31)
        environment.fontModifiers = [.dynamic(Font.WeightModifier(weight: .heavy))]
        let original = environment.fontResolutionContext
        let font = Font(provider: FontBox(RetainedRequestProvider(counter: counter)))
        let value = font.resolve(in: original)
        let copy = value
        environment.font = .system(size: 41)
        environment.fontModifiers = [.dynamic(Font.WeightModifier(weight: .light))]

        XCTAssertEqual(value.font, font)
        XCTAssertEqual(copy.context, original)
        XCTAssertNotEqual(copy.context, environment.fontResolutionContext)
        XCTAssertEqual(counter.calls.withLock { $0 }, 0)

        XCTAssertEqual(copy.pointSize, 13)
        XCTAssertEqual((copy.resource.provider as? SystemFontProvider)?.weight, .heavy)
        XCTAssertTrue(value.resource === copy.resource)
        XCTAssertEqual(counter.calls.withLock { $0 }, 1)
        XCTAssertEqual(value.context, original)
    }

    // ASSERTIONS fontResolvedRetainedContextObserved
    func testUnrealizedCopiesReleaseTheOriginalProviderAfterTheirLastOwner() {
        weak var source: AnyObject?
        var value: Font.Resolved? = {
            let provider = FontBox(RetainedRequestProvider(counter: ResolvedRequestCounter()))
            source = provider
            return Font(provider: provider).resolve(in: EnvironmentValues().fontResolutionContext)
        }()
        XCTAssertNotNil(source)
        var copy = value
        value = nil
        withExtendedLifetime(copy) { XCTAssertNotNil(source) }
        copy = nil
        XCTAssertNil(source)
    }

    // ASSERTIONS fontResolvedResourceEqualityObserved
    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testEqualityAndHashRealizeResourcesInsteadOfComparingRequests() {
        let counter = ResolvedRequestCounter()
        let font = Font(provider: FontBox(RetainedRequestProvider(counter: counter)))
        var first = EnvironmentValues().fontResolutionContext
        first.effectiveFont = .system(size: 31)
        var second = first
        second.effectiveFont = .system(size: 41)
        let lhs = font.resolve(in: first)
        let rhs = font.resolve(in: second)
        XCTAssertEqual(counter.calls.withLock { $0 }, 0)
        XCTAssertNotEqual(first, second)

        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(counter.calls.withLock { $0 }, 2)
        XCTAssertFalse(lhs.resource === rhs.resource)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
        XCTAssertEqual(Set([lhs, rhs]).count, 1)
        XCTAssertEqual(counter.calls.withLock { $0 }, 2)

        let hashCounter = ResolvedRequestCounter()
        let hashOnly = Font(provider: FontBox(RetainedRequestProvider(counter: hashCounter))).resolve(in: first)
        _ = hashOnly.hashValue
        XCTAssertEqual(hashCounter.calls.withLock { $0 }, 1)
    }

    // ASSERTIONS fontResolvedResourceEqualityObserved
    func testEquivalentLogicalProvidersShareEqualityButPreserveStyleIdentity() {
        let context = EnvironmentValues().fontResolutionContext
        let body = Font.body.resolve(in: context)
        let explicitBody = Font.system(.body, design: .default, weight: .regular).resolve(in: context)
        let fixed = Font.system(size: 13).resolve(in: context)
        XCTAssertNotEqual(body.font, explicitBody.font)
        XCTAssertEqual(body, explicitBody)
        XCTAssertEqual(body.hashValue, explicitBody.hashValue)
        XCTAssertEqual(body.pointSize, fixed.pointSize)
        XCTAssertNotEqual(body, fixed)
        let retained = Font(provider: FontBox(Font.PlatformFontProvider(font: body.resource))).resolve(in: context)
        XCTAssertEqual(retained, body)
        XCTAssertEqual(retained.hashValue, body.hashValue)
    }

    // ASSERTIONS fontResolvedRetainedContextObserved
    func testCapturedRenderingModeDoesNotFollowLaterEnvironmentChanges() {
        var environment = EnvironmentValues()
        environment.defaultFontRenderingMode = .bitmap()
        let captured = Font.body.resolve(in: environment.fontResolutionContext)
        environment.defaultFontRenderingMode = .vector()
        let changed = Font.body.resolve(in: environment.fontResolutionContext)
        XCTAssertEqual((captured.resource.provider as? SystemFontProvider)?.renderingMode, .bitmap())
        XCTAssertEqual((changed.resource.provider as? SystemFontProvider)?.renderingMode, .vector())
        XCTAssertNotEqual(captured, changed)
    }

    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testExistingEagerConsumerUsesTheSameRealizedValue() throws {
        let counter = ResolvedRequestCounter()
        let font = Font(provider: FontBox(RetainedRequestProvider(counter: counter)))
        var environment = EnvironmentValues()
        environment.fontModifiers = [.dynamic(Font.WeightModifier(weight: .heavy))]
        let value = font.resolve(in: environment.fontResolutionContext)
        let eager = font.resolved(in: environment)
        let provider = try XCTUnwrap(eager.provider as? FontBox<Font.PlatformFontProvider>)
        XCTAssertTrue(value.resource === provider.base.font)
        XCTAssertEqual(counter.calls.withLock { $0 }, 1)
    }

    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testConcurrentValueCopiesReadTheSharedResource() {
        let value = Font.body.resolve(in: EnvironmentValues().fontResolutionContext)
        let resource = value.resource
        let hash = value.hashValue
        DispatchQueue.concurrentPerform(iterations: 96) { _ in
            let copy = value
            XCTAssertTrue(copy.resource === resource)
            XCTAssertEqual(copy.pointSize, 13)
            XCTAssertEqual(copy.hashValue, hash)
            XCTAssertEqual(copy, value)
        }
    }
}
