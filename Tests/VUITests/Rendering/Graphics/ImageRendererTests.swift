import Observation
import XCTest
@testable import VUI

final class ImageRendererTests: XCTestCase {
    func testImageRendererDefaultsAndNotifiesObservationChanges() {
        let renderer = ImageRenderer(content: ImageRendererFixedRoot(size: .zero))

        XCTAssertNil(renderer.proposedSize.width)
        XCTAssertNil(renderer.proposedSize.height)
        XCTAssertEqual(renderer.scale, 1)
        XCTAssertFalse(renderer.isOpaque)
        XCTAssertEqual(renderer.colorMode, .nonLinear)
        XCTAssertNil(renderer.allowedDynamicRange)
        XCTAssertFalse(renderer.isObservationEnabled)
        requireObservable(renderer)

        let notificationCounter = ImageRendererObservationCounter()
        trackImageRenderer(renderer, counter: notificationCounter)

        renderer.proposedSize = ProposedViewSize(width: 80, height: 40)
        XCTAssertEqual(notificationCounter.count, 1)

        renderer.scale = 2
        renderer.isOpaque = true
        renderer.colorMode = .linear
        renderer.content = ImageRendererFixedRoot(size: CGSize(width: 21, height: 11))
        XCTAssertEqual(notificationCounter.count, 1)

        trackImageRenderer(renderer, counter: notificationCounter)

        var renderCallbackCount = 0
        renderer.render { _, draw in
            renderCallbackCount += 1
            draw(makeBitmapContext(width: 1, height: 1))
        }
        XCTAssertEqual(renderCallbackCount, 1)

        renderer.isOpaque = false
        XCTAssertEqual(notificationCounter.count, 2)
    }

    func testImageRendererCGImageSurface() {
        #if canImport(CoreGraphics)
        let renderer = ImageRenderer(content: ImageRendererFixedRoot(size: CGSize(width: 21, height: 11)))
        renderer.scale = 2

        let image = renderer.cgImage
        XCTAssertEqual(image?.width, 42)
        XCTAssertEqual(image?.height, 22)
        #endif
    }

    func testImageRendererRenderUsesRootLayoutSize() {
        let renderer = ImageRenderer(content: ImageRendererFixedRoot(size: CGSize(width: 21, height: 11)))
        renderer.proposedSize = ProposedViewSize(width: 80, height: 40)

        var callbackSize = CGSize.zero
        renderer.render(rasterizationScale: 1.5) { size, draw in
            callbackSize = size
            draw(makeBitmapContext(width: 21, height: 11))
        }

        XCTAssertEqual(callbackSize.width, 21)
        XCTAssertEqual(callbackSize.height, 11)
    }

    func testImageRendererDirectContextRenderDoesNotMutateObservedState() {
        let renderer = ImageRenderer(content: ImageRendererFixedRoot(size: CGSize(width: 21, height: 11)))

        let notificationCounter = ImageRendererObservationCounter()
        trackImageRenderer(renderer, counter: notificationCounter)

        renderer.proposedSize = ProposedViewSize(width: 80, height: 40)
        XCTAssertEqual(notificationCounter.count, 1)

        trackImageRenderer(renderer, counter: notificationCounter)

        renderer.render(rasterizationScale: 1.5, in: makeBitmapContext(width: 21, height: 11))
        XCTAssertEqual(notificationCounter.count, 1)

        renderer.scale = 2
        XCTAssertEqual(notificationCounter.count, 2)
    }

    func testImageRendererInstallsGraphicsRendererRootFeature() {
        let recorder = ImageRendererRootInputRecorder()
        let renderer = ImageRenderer(content: ImageRendererFeatureRoot(recorder: recorder))

        XCTAssertEqual(
            renderer.viewGraph.viewGraphFeatureCount,
            2,
            "the root hit-test feature precedes the image-renderer feature"
        )
        XCTAssertEqual(recorder.events, ["root"])
        XCTAssertTrue(recorder.rootUsingGraphicsRenderer)
        XCTAssertTrue(recorder.rootAnimationsDisabled)
        XCTAssertFalse(recorder.rootSupportsVFD)
    }
}

private final class ImageRendererRootInputRecorder {
    var events: [String] = []
    var rootUsingGraphicsRenderer = false
    var rootAnimationsDisabled = false
    var rootSupportsVFD = false
}

private struct ImageRendererFeatureRoot: View {
    let recorder: ImageRendererRootInputRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ImageRendererFeatureRoot._makeView called outside an active _AGGraph context.")
        }
        let recorder = view._attribute.value.recorder
        recorder.events.append("root")
        recorder.rootUsingGraphicsRenderer = inputs[UsingGraphicsRenderer.self]
        recorder.rootAnimationsDisabled = inputs.base.options.contains(.animationsDisabled)
        recorder.rootSupportsVFD = inputs.supportsVFD

        let layoutComputer = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 1, height: 1))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layoutComputer))
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
    }
}

extension ImageRendererFeatureRoot: TestPrimitiveView {}

private struct ImageRendererFixedRoot: View {
    var size: CGSize

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ImageRendererFixedRoot._makeView called outside an active _AGGraph context.")
        }
        let layoutComputer = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layoutComputer))
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
    }
}

extension ImageRendererFixedRoot: TestPrimitiveView {}

private func makeBitmapContext(width: Int, height: Int) -> CGContext {
    #if canImport(CoreGraphics)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    #else
    _ = width
    _ = height
    return CGContext()
    #endif
}

private func requireObservable<T: Observable>(_ value: T) {}

private final class ImageRendererObservationCounter: @unchecked Sendable {
    var count = 0

    func increment() {
        count += 1
    }
}

private func trackImageRenderer<Content: View>(
    _ renderer: ImageRenderer<Content>,
    counter: ImageRendererObservationCounter
) {
    withObservationTracking {
        _ = renderer.content
        _ = renderer.proposedSize
        _ = renderer.scale
        _ = renderer.isOpaque
        _ = renderer.colorMode
        _ = renderer.allowedDynamicRange
        _ = renderer.isObservationEnabled
    } onChange: {
        counter.increment()
    }
}
