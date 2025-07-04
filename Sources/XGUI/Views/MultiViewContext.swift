//
//  File: MultiViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

// Class hierarchy
//
// MultiViewContext: ViewGroupContext
// - StaticMultiViewContext (static subviews)
// - DynamicMultiViewContext (dynamic subviews)

class MultiViewContext: ViewGroupContext {
    init(subviews: [ViewContext], inputs: _GraphInputs) {
        let layout = inputs.properties.value(forKey: DefaultLayoutProperty.self)
        super.init(subviews: subviews, layout: layout, inputs: inputs)
    }

    override func invalidate() {
        super.invalidate()
        self.subviews.forEach {
            $0.invalidate()
        }
        self.activeSubviews = []
    }

    override func multiViewForLayout() -> [ViewContext] {
        activeSubviews.flatMap {
            $0.multiViewForLayout()
        }
    }

    override func updateFrame() {
        if let superview {
            self.frame = superview.bounds
        }
        self.activeSubviews.forEach {
            $0.updateFrame()
        }
    }

    override func setLayoutProperties(_ layoutProperties: LayoutProperties) {
        self.subviews.forEach {
            $0.setLayoutProperties(layoutProperties)
        }
    }

    override func update(transform t: AffineTransform) {
        super.update(transform: t)
        self.activeSubviews.forEach {
            $0.update(transform: self.transformToRoot)
        }
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        self.activeSubviews.forEach {
            $0.update(tick: tick, delta: delta, date: date)
        }
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        let offsetX = frame.minX
        let offsetY = frame.minY

        self.activeSubviews.forEach { view in
            let width = view.frame.width
            let height = view.frame.height
            guard width > .ulpOfOne && height > .ulpOfOne else {
                return
            }

            let drawingFrame = view.frame.offsetBy(dx: offsetX, dy: offsetY)
            if frame.intersection(drawingFrame).isNull {
                return
            }
            view.drawView(frame: drawingFrame, context: context)
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        for subview in activeSubviews {
            let loc = location.applying(subview.transformToContainer.inverted())
            if let view = subview.hitTest(loc) {
                return view
            }
        }
        return super.hitTest(location)
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.bounds.contains(location) {
            for subview in activeSubviews {
                let frame = subview.frame
                if frame.contains(location) {
                    let local = location.applying(subview.transformToContainer.inverted())
                    if subview.handleMouseWheel(at: local, delta: delta) {
                        return true
                    }
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }
}

class StaticMultiViewContext<Content>: MultiViewContext {
    var root: Content?
    let graph: _GraphValue<Content>

    init(graph: _GraphValue<Content>, subviews: [ViewContext], inputs: _GraphInputs) {
        self.graph = graph
        super.init(subviews: subviews, inputs: inputs)
    }

    override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let root {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: root)
            }
        }
        return super.value(atPath: graph)
    }

    override func updateContent() {
        self.root = nil
        if var root = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateRoot(&root)
            self.requiresContentUpdates = false
            self.root = root
            self.subviews.forEach {
                $0.updateContent()
            }
            self.activeSubviews = self.subviews.filter(\.isValid)
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }

    func updateRoot(_ root: inout Content) {
    }

    override var isValid: Bool {
        if self.root != nil {
            return super.isValid
        }
        return false
    }

    override func validate() -> Bool {
        if self.root != nil {
            return super.validate()
        }
        return false
    }

    override func invalidate() {
        super.invalidate()
        self.activeSubviews = []
        self.root = nil
    }
}

class DynamicMultiViewContext<Content>: MultiViewContext {
    var root: Content?
    let graph: _GraphValue<Content>
    let body: any ViewListGenerator

    init(graph: _GraphValue<Content>, body: any ViewListGenerator, inputs: _GraphInputs) {
        self.graph = graph
        self.body = body
        super.init(subviews: [], inputs: inputs)
    }

    override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let root {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: root)
            }
        }
        return super.value(atPath: graph)
    }

    override func updateContent() {
        self.root = nil
        if var root = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateRoot(&root)
            self.requiresContentUpdates = false
            self.root = root
            // generate subviews
            self.subviews = self.body.makeViewList(containerView: self).map {
                $0.makeView(sharedContext: self.sharedContext)
            }
            self.subviews.forEach {
                $0.superview = self
                $0.updateContent()
            }
            self.activeSubviews = self.subviews.filter { $0.isValid }
        } else {
            self.invalidate()
            fatalError("Failed to resolve view for \(self.graph)")
        }
    }

    func updateRoot(_ root: inout Content) {
    }

    override var isValid: Bool {
        if self.root != nil {
            return super.isValid
        }
        return false
    }

    override func validate() -> Bool {
        if self.root != nil {
            return super.validate()
        }
        return false
    }

    override func invalidate() {
        super.invalidate()
        self.subviews.forEach {
            $0.superview = nil
        }
        self.subviews = []
        self.activeSubviews = []
        self.root = nil
    }
}
