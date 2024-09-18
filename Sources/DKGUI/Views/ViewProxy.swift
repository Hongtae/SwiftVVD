//
//  File: ViewProxy.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation

protocol ViewProxy {
    associatedtype Content
    var content: Self.Content { get }
    var contentGraph: _GraphValue<Self.Content> { get }
    func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool
    func updateContent<T>(encloser: T, graph: _GraphValue<T>)
}

class ProxyViewContext<Proxy : ViewProxy> : ViewContext {
    var proxy: Proxy
    var view: ViewContext

    init<T>(proxy: Proxy, view: ViewContext, inputs: _GraphInputs, graph: _GraphValue<T>) {
        self.proxy = proxy
        self.view = view
        super.init(inputs: inputs, graph: graph)
        self._debugDraw = false
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        self._validPath = false
        if self.proxy.validatePath(encloser: encloser, graph: graph) {
            self._validPath = true
            return self.view.validatePath(encloser: proxy.content, graph: proxy.contentGraph)
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        self.proxy.updateContent(encloser: encloser, graph: graph)
        self.view.updateContent(encloser: proxy.content, graph: proxy.contentGraph)
    }

    override func resolveGraphInputs<T>(encloser: T, graph: _GraphValue<T>) {
        super.resolveGraphInputs(encloser: encloser, graph: graph)
        self.view.resolveGraphInputs(encloser: proxy.content, graph: proxy.contentGraph)
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.view.updateEnvironment(environmentValues)
    }

    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        self.view.loadResources(context)
    }

    override func update(transform t: AffineTransform, origin: CGPoint) {
        super.update(transform: t, origin: origin)
        self.view.update(transform: self.transformByRoot, origin: self.frame.origin)
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        self.view.update(tick: tick, delta: delta, date: date)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        let width = self.view.frame.width
        let height = self.view.frame.height
        guard width > 0 && height > 0 else {
            return
        }
        if frame.intersection(self.view.frame).isNull {
            return
        }
        let frame = self.view.frame
        self.view.drawView(frame: frame, context: context)
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if let view = self.view.hitTest(location) {
            return view
        }
        return super.hitTest(location)
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
        super.setLayoutProperties(properties)
        self.view.setLayoutProperties(properties)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let center = CGPoint(x: self.frame.midX, y: self.frame.midY)
        let proposal = ProposedViewSize(width: self.frame.width, height: self.frame.height)
        self.view.place(at: center, anchor: .center, proposal: proposal)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        self.view.sizeThatFits(proposal)
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)
        return outputs.merge(self.view.gestureHandlers(at: location))
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        self.view.handleMouseWheel(at: location, delta: delta)
    }
}
