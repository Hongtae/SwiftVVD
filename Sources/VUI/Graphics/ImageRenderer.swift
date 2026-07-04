//
//  File: ImageRenderer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Combine
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Observation

public final class ImageRenderer<Content>: ObservableObject where Content: View {
    public final let objectWillChange = PassthroughSubject<Void, Never>()

    public final var content: Content {
        didSet {
            host.setContent(content)
            markChanged()
        }
    }

    public final var proposedSize: ProposedViewSize {
        didSet {
            markChanged()
        }
    }

    public final var scale: CGFloat {
        didSet {
            markChanged()
        }
    }

    public final var isOpaque: Bool {
        didSet {
            markChanged()
        }
    }

    public final var colorMode: ColorRenderingMode {
        didSet {
            markChanged()
        }
    }

    public final var allowedDynamicRange: Image.DynamicRange? {
        didSet {
            markChanged()
        }
    }

    @usableFromInline final var observationEnabled: Bool

    public init(content view: Content) {
        self.content = view
        self.proposedSize = .unspecified
        self.scale = 1
        self.isOpaque = false
        self.colorMode = .nonLinear
        self.allowedDynamicRange = nil
        self.observationEnabled = false

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
            resetChangeNotification()
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
            resetChangeNotification()
            return nil
        }

        render(rasterizationScale: currentScale, in: context)
        return context.makeImage()
        #else
        resetChangeNotification()
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
        resetChangeNotification()
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
        resetChangeNotification()
    }

    public final var isObservationEnabled: Bool {
        get { observationEnabled }
        set { observationEnabled = newValue }
    }

    public typealias ObjectWillChangePublisher = PassthroughSubject<Void, Never>

    var viewGraph: ViewGraph {
        host.viewGraph
    }

    private let host: ImageRendererHost<Content>
    private var pendingObjectWillChange = false

    private func markChanged() {
        guard !pendingObjectWillChange else {
            return
        }
        pendingObjectWillChange = true
        objectWillChange.send()
    }

    private func resetChangeNotification() {
        pendingObjectWillChange = false
    }

    private func resolvedRenderSize() -> CGSize {
        host.updateOutputsForRender()
        return host.viewGraph.data.withCurrent {
            host.viewGraph.rootLayoutComputer?.value.sizeThatFits(proposedSize)
                ?? proposedSize.replacingUnspecifiedDimensions()
        }
    }

}

extension ImageRenderer: Observable {}

@available(*, unavailable)
extension ImageRenderer: Sendable {}

private final class ImageRendererHost<Content: View>: ViewRendererHost, ViewGraphRootValueUpdater {
    var content: Content
    var storage: ViewGraph!
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
