//
//  File: ImageRenderer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Observation

@Observable
public final class ImageRenderer<Content> where Content: View {
    public final var content: Content {
        get {
            access(keyPath: \.content)
            return _content
        }
        set {
            withMutation(keyPath: \.content) {
                _content = newValue
                host.setContent(newValue)
            }
        }
    }

    public final var proposedSize: ProposedViewSize {
        get {
            access(keyPath: \.proposedSize)
            return _proposedSize
        }
        set {
            withMutation(keyPath: \.proposedSize) {
                _proposedSize = newValue
            }
        }
    }

    public final var scale: CGFloat {
        get {
            access(keyPath: \.scale)
            return _scale
        }
        set {
            withMutation(keyPath: \.scale) {
                _scale = newValue
            }
        }
    }

    public final var isOpaque: Bool {
        get {
            access(keyPath: \.isOpaque)
            return _isOpaque
        }
        set {
            withMutation(keyPath: \.isOpaque) {
                _isOpaque = newValue
            }
        }
    }

    public final var colorMode: ColorRenderingMode {
        get {
            access(keyPath: \.colorMode)
            return _colorMode
        }
        set {
            withMutation(keyPath: \.colorMode) {
                _colorMode = newValue
            }
        }
    }

    public final var allowedDynamicRange: Image.DynamicRange? {
        get {
            access(keyPath: \.allowedDynamicRange)
            return _allowedDynamicRange
        }
        set {
            withMutation(keyPath: \.allowedDynamicRange) {
                _allowedDynamicRange = newValue
            }
        }
    }

    public init(content view: Content) {
        self._content = view
        self._proposedSize = .unspecified
        self._scale = 1
        self._isOpaque = false
        self._colorMode = .nonLinear
        self._allowedDynamicRange = nil
        self._observationEnabled = false

        let host = ImageRendererHost(content: view)
        let graph = ViewGraph(
            replaceableContent: view,
            rendererHost: host,
            requestedOutputs: [.displayList, .layout],
            features: [ImageRendererHostViewGraph()]
        )
        host.attach(graph)
        self.host = host
    }

    public final var cgImage: CGImage? {
        #if canImport(CoreGraphics)
        let size = resolvedRenderSize()
        let currentScale = scale
        guard size.width > 0, size.height > 0, currentScale > 0 else {
            return nil
        }

        let width = max(1, Int((size.width * currentScale).rounded(.up)))
        let height = max(1, Int((size.height * currentScale).rounded(.up)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        render(rasterizationScale: currentScale, in: context)
        return context.makeImage()
        #else
        return nil
        #endif
    }

    public final func render(
        rasterizationScale: CGFloat = 1,
        renderer: (CGSize, (CGContext) -> Void) -> Void
    ) {
        #if canImport(CoreGraphics)
        let size = resolvedRenderSize()
        renderer(size) { context in
            self.render(rasterizationScale: rasterizationScale, in: context)
        }
        #else
        _ = rasterizationScale
        _ = renderer
        #endif
    }

    public final func render(
        rasterizationScale: CGFloat = 1,
        in context: CGContext
    ) {
        #if canImport(CoreGraphics)
        _ = context
        _ = rasterizationScale
        // DisplayList -> CGContext rasterization belongs to the graphics backend.
        #else
        _ = rasterizationScale
        _ = context
        #endif
    }

    public final var isObservationEnabled: Bool {
        get {
            access(keyPath: \.isObservationEnabled)
            return _observationEnabled
        }
        set {
            withMutation(keyPath: \.isObservationEnabled) {
                _observationEnabled = newValue
            }
        }
    }

    var viewGraph: ViewGraph {
        host.viewGraph
    }

    @ObservationIgnored private var _content: Content
    @ObservationIgnored private var _proposedSize: ProposedViewSize
    @ObservationIgnored private var _scale: CGFloat
    @ObservationIgnored private var _isOpaque: Bool
    @ObservationIgnored private var _colorMode: ColorRenderingMode
    @ObservationIgnored private var _allowedDynamicRange: Image.DynamicRange?
    @ObservationIgnored private var _observationEnabled: Bool
    @ObservationIgnored
    private let host: ImageRendererHost<Content>

    private func resolvedRenderSize() -> CGSize {
        host.updateOutputsForRender()
        return host.viewGraph.data.withCurrent {
            host.viewGraph.rootLayoutComputer?.value.sizeThatFits(_ProposedSize(proposedSize))
                ?? proposedSize.replacingUnspecifiedDimensions()
        }
    }

}

@available(*, unavailable)
extension ImageRenderer: Sendable {}

private final class ImageRendererHost<Content: View>: ViewRendererHost, ViewGraphRootValueUpdater {
    var content: Content
    var storage: ViewGraph!
    let sceneResources = SceneResources()
    var currentTimestamp: Time = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0

    init(content: Content) {
        self.content = content
    }

    var viewGraph: ViewGraph {
        storage
    }

    var responderNode: ResponderNode? {
        nil
    }

    var gestureGraph: GestureGraph? {
        nil
    }

    func attach(_ graph: ViewGraph) {
        storage = graph
        graph.updateDelegate = self
    }

    func setContent(_ content: Content) {
        self.content = content
        guard storage != nil else {
            return
        }
        storage.data.withCurrent {
            updateRootView()
        }
    }

    func updateOutputsForRender() {
        storage.updateOutputs(at: currentTimestamp)
    }

    func requestUpdate(after: Double) {
        // Rendering is pull-driven by the ImageRenderer accessors.
    }

    func `as`<T>(_ type: T.Type) -> T? {
        let requestedType = ObjectIdentifier(type)
        guard requestedType == ObjectIdentifier((any ViewGraphOwner).self)
                || requestedType == ObjectIdentifier((any ViewGraphDelegate).self) else {
            return nil
        }
        return self as? T
    }

    func updateRootView() {
        storage.rootAnyViewContentInput?.setValue(AnyView(content))
    }

    func updateEnvironment() {}
    func updateSize() {}
    func updateSafeArea() {}
    func updateContainerSize() {}
    func updateTransform() {}
    func updateFocusStore() {}
    func updateFocusedItem() {}
    func updateFocusedValues() {}
    func updateAccessibilityEnvironment() {}
}
