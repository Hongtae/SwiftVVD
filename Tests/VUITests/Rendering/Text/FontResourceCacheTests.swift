import Dispatch
import Foundation
import Synchronization
import XCTest
@testable import VUI

private final class ResolutionCounter: Sendable {
    let calls = Mutex(0)
}

private struct CountingFontProvider: FontProvider {
    let counter: ResolutionCounter
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

final class FontResourceCacheTests: XCTestCase {
    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testExistingResolutionConsumerUsesTheSharedRequestCache() throws {
        let counter = ResolutionCounter()
        let font = Font(provider: FontBox(CountingFontProvider(counter: counter)))
        let environment = EnvironmentValues()
        let first = font.resolved(in: environment)
        let second = font.resolved(in: environment)
        let lhs = try XCTUnwrap(first.provider as? FontBox<Font.PlatformFontProvider>)
        let rhs = try XCTUnwrap(second.provider as? FontBox<Font.PlatformFontProvider>)
        XCTAssertTrue(lhs.base.font === rhs.base.font)
        XCTAssertEqual(counter.calls.withLock { $0 }, 1)
    }

    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testContextModifiersMoveIntoTheOrderedRequestKey() throws {
        let font = Font.system(.body)
        var context = EnvironmentValues().fontResolutionContext
        context.fontModifiers = [.dynamic(Font.WeightModifier(weight: .light))]
        let heavy = AnyFontModifier.dynamic(Font.WeightModifier(weight: .heavy))
        let appended = font.platformFont(in: context, modifiers: [heavy])
        let replaced = font.platformFont(in: context, modifiers: [heavy], overrideContextModifiers: true)
        XCTAssertEqual((appended.provider as? SystemFontProvider)?.weight, .heavy)
        XCTAssertEqual(appended, replaced)
        XCTAssertFalse(appended === replaced)
        XCTAssertEqual(context.fontModifiers.count, 1)
        var cleared = context
        cleared.fontModifiers = []
        XCTAssertTrue(replaced === font.platformFont(in: cleared, modifiers: [heavy]))
    }

    // ASSERTIONS fontResolvedResourceEqualityObserved
    func testResourceEqualityIsIndependentOfUnusedContextInputs() {
        var first = EnvironmentValues().fontResolutionContext
        first.effectiveFont = .system(size: 123)
        var second = first
        second.effectiveFont = .system(size: 456)
        let font = Font.system(.body)
        let lhs = font.platformFont(in: first)
        let rhs = font.platformFont(in: second)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(lhs === rhs)
        XCTAssertEqual(lhs, rhs)
        XCTAssertEqual(lhs.hashValue, rhs.hashValue)
    }

    // ASSERTIONS fontResolvedResourceEqualityObserved
    // ASSERTIONS fontTextStyleDescriptorCopiesObserved
    func testResolvedCopiesRetainStyleIdentityAndOwnTheirDescriptors() throws {
        let environment = EnvironmentValues()
        let body = Font.system(.body).resolved(in: environment)
        let fixed = Font.system(size: 13).resolved(in: environment)
        XCTAssertNotEqual(body, fixed)
        for font in [body, body.resolved(in: environment), body.weight(.heavy).width(.expanded)] {
            let descriptor = font.resolveDescriptor(in: environment.fontResolutionContext)
            guard case let .system(_, _, _, _, style) = descriptor.source else {
                return XCTFail("A resolved style must retain its descriptor source.")
            }
            XCTAssertEqual(style, .body)
        }
        let resource = try XCTUnwrap(body.provider as? FontBox<Font.PlatformFontProvider>).base.font
        let first = resource.descriptor()
        let second = resource.descriptor()
        XCTAssertFalse(first === second)
        let heavy = first.weight(.heavy)
        XCTAssertEqual(second.resolvedWeight, 0)
        XCTAssertEqual(heavy.resolvedWeight, CGFloat(Float(0.56)))
        XCTAssertEqual(resource.textStyle, .body)
    }

    func testAutomaticRenderingModeIsPartOfTheResolutionContext() {
        let font = Font.system(.body)
        var bitmap = EnvironmentValues()
        bitmap.defaultFontRenderingMode = .bitmap()
        var vector = bitmap
        vector.defaultFontRenderingMode = .vector()
        XCTAssertNotEqual(bitmap.fontResolutionContext, vector.fontResolutionContext)
        let lhs = font.resolved(in: bitmap)
        let rhs = font.resolved(in: vector)
        XCTAssertEqual((lhs.typefaceProvider as? SystemFontProvider)?.renderingMode, .bitmap())
        XCTAssertEqual((rhs.typefaceProvider as? SystemFontProvider)?.renderingMode, .vector())
        XCTAssertNotEqual(lhs, rhs)
    }

    func testResolvedResourcesKeepTheirRenderingModeAcrossEnvironmentChanges() {
        var bitmap = EnvironmentValues()
        bitmap.defaultFontRenderingMode = .bitmap()
        var vector = bitmap
        vector.defaultFontRenderingMode = .vector()
        for font in [Font.system(.body), .custom("Roboto-Regular", fixedSize: 13)] {
            let resolved = font.resolved(in: bitmap)
            for copy in [resolved, resolved.weight(.heavy), resolved.monospacedDigit()] {
                let sameEnvironment = copy.resolved(in: bitmap)
                let otherEnvironment = copy.resolved(in: vector)
                XCTAssertEqual(sameEnvironment, otherEnvironment)
            }
            XCTAssertNotEqual(resolved, font.resolved(in: vector))
        }
    }

    // ASSERTIONS fontResolvedLazyCacheBoundaryObserved
    func testConcurrentConsumersCreateIndependentMutableDescriptors() {
        let context = EnvironmentValues().fontResolutionContext
        let fonts = [Font.system(.body), .system(.caption), .custom("Roboto-Regular", fixedSize: 13)]
        DispatchQueue.concurrentPerform(iterations: 96) { index in
            let resource = fonts[index % fonts.count].platformFont(in: context)
            let original = resource.descriptor()
            let copy = resource.descriptor()
            XCTAssertFalse(original === copy)
            let changed = original.weight(.heavy).width(0.2)
            XCTAssertEqual(copy.pointSize, resource.pointSize)
            XCTAssertEqual(changed.pointSize, resource.pointSize)
            XCTAssertEqual(copy.resolvedWeight, resource.descriptor().resolvedWeight)
            XCTAssertEqual(resource, fonts[index % fonts.count].platformFont(in: context))
        }
    }
}
