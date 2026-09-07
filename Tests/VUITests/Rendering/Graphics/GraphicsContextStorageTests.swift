import XCTest
import VVD
@testable import VUI

final class GraphicsContextStorageTests: XCTestCase {
    private func makeContext() throws -> GraphicsContext {
        #if canImport(Metal)
        let device = try XCTUnwrap(makeGraphicsDeviceContext(api: .metal))
        let queue = try XCTUnwrap(device.renderQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        return try XCTUnwrap(GraphicsContext(
            sceneResources: SceneResources(), environment: environment,
            viewport: CGRect(x: 0, y: 0, width: 32, height: 24),
            contentOffset: .zero, contentScaleFactor: 1,
            resolution: CGSize(width: 32, height: 24), commandBuffer: commands
        ))
        #else
        throw XCTSkip("A Metal device is required for the current drawing backend")
        #endif
    }

    // ASSERTIONS canvasGraphicsStorageSharingObserved
    func testValueCopiesShareDestinationAndDetachOnlyChangedState() throws {
        let original = try makeContext()
        XCTAssertEqual(MemoryLayout<GraphicsContext>.size, MemoryLayout<AnyObject>.size)
        XCTAssertFalse(original.storage.ownsState)
        XCTAssertEqual(original.storage.state, original.storage.shared.list.drawingState)
        var copy = original
        XCTAssertTrue(copy.storage === original.storage)
        copy.opacity = 1 + Double.ulpOfOne
        copy.blendMode = .normal
        copy.transform = .identity
        XCTAssertTrue(copy.storage === original.storage)
        XCTAssertEqual(original.storage.shared.list.ownedStateCount, 0)

        copy.opacity = 0.3
        XCTAssertFalse(copy.storage === original.storage)
        XCTAssertTrue(copy.storage.shared === original.storage.shared)
        XCTAssertNotEqual(copy.storage.state, original.storage.state)
        XCTAssertTrue(copy.storage.ownsState)
        XCTAssertEqual(copy.opacity, Double(Float(0.3)))
        XCTAssertEqual(original.opacity, 1)

        let state = copy.storage.state
        let identity = ObjectIdentifier(copy.storage)
        copy.translateBy(x: 3, y: 4)
        copy.blendMode = .multiply
        XCTAssertEqual(ObjectIdentifier(copy.storage), identity)
        XCTAssertEqual(copy.storage.state, state)
        XCTAssertEqual(original.transform, .identity)
        XCTAssertEqual(original.blendMode, .normal)
        XCTAssertEqual(copy.clipBoundingRect, CGRect(x: -3, y: -4, width: 32, height: 24))
        XCTAssertTrue(copy.drawingBackend === original.drawingBackend)
        XCTAssertTrue(copy.uploadBufferArena === original.uploadBufferArena)
        XCTAssertTrue(copy.pathGeometryScratch === original.pathGeometryScratch)
    }

    // ASSERTIONS canvasGraphicsStorageMutationRulesObserved
    func testNonuniqueCopyResetsOverrideAndShapeDistanceButPreservesCompositing() throws {
        var original = try makeContext()
        original.opacity = 0.3
        original.blendMode = .multiply
        original.environment.colorScheme = .dark
        original.storage.shapeDistance = 7
        var copy = original
        copy.translateBy(x: 1, y: 2)
        XCTAssertTrue(copy.storage.shared === original.storage.shared)
        XCTAssertNil(copy.storage.environmentOverride)
        XCTAssertTrue(copy.storage.shapeDistance.isNaN)
        XCTAssertEqual(copy.environment.colorScheme, .light)
        XCTAssertEqual(copy.opacity, original.opacity)
        XCTAssertEqual(copy.blendMode, .multiply)
        XCTAssertEqual(original.environment.colorScheme, .dark)
        XCTAssertEqual(original.storage.shapeDistance, 7)
    }

    func testUniqueMutationKeepsOverrideAndEnvironmentSetterDoesNotDetach() throws {
        var context = try makeContext()
        context.environment.colorScheme = .dark
        context.storage.shapeDistance = 7
        let identity = ObjectIdentifier(context.storage)
        context.opacity = 0.5
        XCTAssertEqual(ObjectIdentifier(context.storage), identity)
        XCTAssertEqual(context.environment.colorScheme, .dark)
        XCTAssertEqual(context.storage.shapeDistance, 7)
        let alias = context
        context.environment.colorScheme = .light
        XCTAssertTrue(context.storage === alias.storage)
        XCTAssertEqual(alias.environment.colorScheme, .light)

        var scopedEnvironment = context.environment
        scopedEnvironment.colorScheme = .dark
        let content = DisplayList.Content(
            command: .closure(bounds: nil), environment: scopedEnvironment
        ) { rendered in
            XCTAssertEqual(rendered.environment.colorScheme, .dark)
            XCTAssertFalse(rendered.storage === context.storage)
        }
        content.draw(in: context)
        XCTAssertEqual(context.environment.colorScheme, .light)
    }

    // ASSERTIONS canvasGraphicsAlternateColorSpaceCOWObserved
    func testChangedColorSpaceCreatesSharedWithEffectiveEnvironmentAndEmptyProvider() throws {
        var original = try makeContext()
        let provider = GraphicsContextSymbols()
        original.symbols = provider
        original.environment.colorScheme = .dark
        original.storage.shared.list.defaultColorSpace = .linearSRGB
        var copy = original
        copy.blendMode = .multiply
        XCTAssertFalse(copy.storage.shared === original.storage.shared)
        XCTAssertTrue(copy.storage.shared.list === original.storage.shared.list)
        XCTAssertEqual(copy.storage.shared.colorSpace, .linearSRGB)
        XCTAssertEqual(original.storage.shared.colorSpace, .sRGB)
        XCTAssertEqual(copy.environment.colorScheme, .dark)
        XCTAssertNil(copy.storage.environmentOverride)
        XCTAssertNil(copy.symbols)
        XCTAssertTrue(original.symbols === provider)
    }

    func testOwnedStatesAreDestroyedAndBorrowedRootLivesWithItsList() throws {
        var context: GraphicsContext? = try makeContext()
        weak let rootStorage = context?.storage
        weak let list = context?.storage.shared.list
        var copy = context!
        copy.opacity = 0.5
        XCTAssertEqual(list?.ownedStateCount, 1)
        context = nil
        XCTAssertNil(rootStorage)
        XCTAssertNotNil(list)
        XCTAssertEqual(copy.storage.shared.list.drawingState.pointee.transform, .identity)

        func temporaryCopies() {
            var second = copy
            second.scaleBy(x: 2, y: 3)
            XCTAssertEqual(list?.ownedStateCount, 2)
            XCTAssertEqual(second.transform.a, 2)
        }
        temporaryCopies()
        XCTAssertEqual(list?.ownedStateCount, 1)
        // Replacing the final context releases its owned state before the list.
        copy = try makeContext()
        XCTAssertNil(list)
    }

    func testCopiedStateColorSpaceIsIndependentOfListDefault() throws {
        let original = try makeContext()
        var copy = original
        copy.opacity = 0.5
        RBDrawingStateSetDefaultColorSpace(copy.storage.state, .linearSRGB)
        XCTAssertEqual(RBDrawingStateGetDefaultColorSpace(original.storage.state), .sRGB)
        XCTAssertEqual(original.storage.shared.list.defaultColorSpace, .sRGB)
        var child = copy
        child.opacity = 0.25
        XCTAssertFalse(child.storage.shared === copy.storage.shared)
        XCTAssertTrue(child.storage.shared.list === original.storage.shared.list)
        XCTAssertEqual(RBDrawingStateGetDefaultColorSpace(child.storage.state), .linearSRGB)
        XCTAssertEqual(child.storage.shared.colorSpace, .sRGB)
    }

    func testFiltersAndClipMutationsDetachStateWhileBoundsKeepDestinationOwnership() throws {
        let original = try makeContext()
        var copy = original
        copy.addFilter(.blur(radius: 2))
        copy.clipBoundingRect = CGRect(x: 2, y: 3, width: 4, height: 5)
        XCTAssertTrue(original.filters.isEmpty)
        XCTAssertEqual(copy.filters.count, 1)
        XCTAssertEqual(original.clipBoundingRect, original.viewport)
        copy.recordContentBounds(CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(original.contentBoundingRect, copy.clipBoundingRect)
    }

    func testRecordingUsesANewDestinationAndValueCopiesAppendWithoutRetainingContext() throws {
        var original = try makeContext()
        original.symbols = GraphicsContextSymbols()
        var recording: GraphicsContext? = original.recordingContext(size: CGSize(width: 8, height: 6))
        weak let storage = recording?.storage
        weak let list = recording?.storage.shared.list
        XCTAssertFalse(recording!.storage.shared === original.storage.shared)
        XCTAssertFalse(recording!.storage.shared.list === original.storage.shared.list)
        XCTAssertTrue(recording!.symbols === original.symbols)
        XCTAssertTrue(recording!.contentBoundsState !== original.contentBoundsState)
        let commands = recording!.recording!
        func append() {
            var copy = recording!
            copy.opacity = 0.5
            XCTAssertTrue(copy.recording === commands)
            copy.record(bounds: CGRect(x: 1, y: 2, width: 3, height: 2)) { _ in }
        }
        append()
        recording = nil
        XCTAssertNil(storage)
        XCTAssertNil(list)
        XCTAssertEqual(commands.commands.count, 1)
        XCTAssertEqual(commands.bounds, CGRect(x: 1, y: 2, width: 3, height: 2))
        XCTAssertEqual(original.contentBoundingRect, .null)
    }
}
