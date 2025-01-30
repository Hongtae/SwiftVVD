//
//  File: ViewGroupContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// Class hierarchy
//
// ViewGroupContext : ViewContext
// - StaticViewGroupContext (layout with static subviews)
// - DynamicViewGroupContext (layout with dynamic subviews)

class ViewGroupContext : ViewContext {
    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?
    var layoutProperties: LayoutProperties
    var subviews: [ViewContext]
    var activeSubviews: [ViewContext] = []

    init(inputs: _GraphInputs, subviews: [ViewContext], layout: any Layout) {
        func layoutProperties<L : Layout>(_ layout: L) -> LayoutProperties {
            L.layoutProperties
        }
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = layoutProperties(layout)
        self.subviews = subviews
        super.init(inputs: inputs)

        self.subviews.forEach {
            $0.superview = self
            $0.setLayoutProperties(self.layoutProperties)
        }
    }

    deinit {
        self.subviews.forEach {
            $0.superview = nil
        }
    }

    override var isValid: Bool {
        activeSubviews.isEmpty == false
    }

    override func validate() -> Bool {
        subviews.forEach {
            assert($0.superview === self)
            $0.validate()
        }
        return activeSubviews.isEmpty == false
    }

    override func invalidate() {
        self.subviews.forEach {
            $0.invalidate()
        }
        self.activeSubviews = []
    }

    override func merge(graphInputs inputs: _GraphInputs) {
        super.merge(graphInputs: inputs)
        self.subviews.forEach {
            $0.merge(graphInputs: inputs)
        }
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.subviews.forEach {
            $0.updateEnvironment(self.environmentValues)
        }
    }

    override func setLayoutProperties(_: LayoutProperties) {
        self.subviews.forEach {
            $0.setLayoutProperties(self.layoutProperties)
        }
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let viewList = self.activeSubviews.flatMap {
            $0.multiViewForLayout()
        }
        let subviews: [LayoutSubview] = viewList.map {
            LayoutSubview(view: $0)
        }
        if subviews.isEmpty == false {
            let layoutSubviews = AnyLayout.Subviews(subviews: subviews,
                                                    layoutDirection: .leftToRight)

            if var cache = self.layoutCache {
                self.layout.updateCache(&cache, subviews: layoutSubviews)
                self.layoutCache = cache
            } else {
                self.layoutCache = self.layout.makeCache(subviews: layoutSubviews)
            }
            if var cache = self.layoutCache {
                let ret = self.layout.sizeThatFits(proposal: proposal,
                                                   subviews: layoutSubviews,
                                                   cache: &cache)
                self.layoutCache = cache
                return ret
            }
        }
        return proposal.replacingUnspecifiedDimensions()
    }

    override func layoutSubviews() {
        let frame = self.bounds
        guard frame.width > 0 && frame.height > 0 else { return }

        let viewList = self.activeSubviews.flatMap {
            $0.multiViewForLayout()
        }
        let subviews: [LayoutSubview] = viewList.map {
            LayoutSubview(view: $0)
        }
        if subviews.isEmpty == false {
            let layoutSubviews = AnyLayout.Subviews(subviews: subviews,
                                                    layoutDirection: .leftToRight)

            if var cache = self.layoutCache {
                self.layout.updateCache(&cache, subviews: layoutSubviews)
                self.layoutCache = cache
            } else {
                self.layoutCache = self.layout.makeCache(subviews: layoutSubviews)
            }
            if var cache = self.layoutCache {
                let proposal = ProposedViewSize(frame.size)
                let size = self.layout.sizeThatFits(proposal: proposal,
                                                    subviews: layoutSubviews,
                                                    cache: &cache)
                let halign = self.layout.explicitAlignment(of: HorizontalAlignment.center,
                                                           in: frame,
                                                           proposal: proposal,
                                                           subviews: layoutSubviews,
                                                           cache: &cache)
                let valign = self.layout.explicitAlignment(of: VerticalAlignment.center,
                                                           in: frame,
                                                           proposal: proposal,
                                                           subviews: layoutSubviews,
                                                           cache: &cache)

                // TODO: calcuate alignment guide.
                self.layout.placeSubviews(in: frame,
                                          proposal: proposal,
                                          subviews: layoutSubviews,
                                          cache: &cache)
                self.layoutCache = cache
                self.updateFrame()
            } else {
                Log.error("Invalid layout cache")
            }
        }
    }

    override func updateFrame() {
        self.activeSubviews.forEach {
            $0.updateFrame()
        }
    }

    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        self.activeSubviews.forEach {
            $0.loadResources(context)
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

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        var outputs = super.gestureHandlers(at: location)
        if self.bounds.contains(location) {
            for subview in activeSubviews {
                let local = location.applying(subview.transformToContainer.inverted())
                outputs = outputs.merge(subview.gestureHandlers(at: local))
            }
        }
        return outputs
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

class StaticViewGroupContext<Content> : ViewGroupContext {
    var root: Content?
    let graph: _GraphValue<Content>

    init(graph: _GraphValue<Content>, inputs: _GraphInputs, subviews: [ViewContext], layout: (any Layout)? = nil) {
        let layout = layout ?? inputs.properties
            .find(type: DefaultLayoutPropertyItem.self)?
            .layout ?? DefaultLayoutPropertyItem.defaultValue
        self.graph = graph
        super.init(inputs: inputs, subviews: subviews, layout: layout)
    }

    final override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let root {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: root)
            }
        }
        if let superview {
            return superview.value(atPath: graph)
        }
        if let root = self.sharedContext.viewContentRoot {
            return root.graph.value(atPath: graph, from: root.value)
        }
        return nil
    }

    override func updateContent() {
        self.root = nil
        self.root = value(atPath: self.graph)
        if var root = self.root {
            self.updateRoot(&root)
            self.root = root
            self.subviews.forEach {
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
            $0.invalidate()
        }
        self.activeSubviews = []
        self.root = nil
    }
}

class DynamicViewGroupContext<Content> : ViewGroupContext {
    var root: Content?
    let graph: _GraphValue<Content>
    let body: any ViewListGenerator

    init(graph: _GraphValue<Content>, inputs: _GraphInputs, body: any ViewListGenerator, layout: (any Layout)? = nil) {
        let layout = layout ?? inputs.properties
            .find(type: DefaultLayoutPropertyItem.self)?
            .layout ?? DefaultLayoutPropertyItem.defaultValue
        self.graph = graph
        self.body = body
        super.init(inputs: inputs, subviews: [], layout: layout)
    }

    final override func value<T>(atPath graph: _GraphValue<T>) -> T? {
        if let root {
            if graph.isDescendant(of: self.graph) {
                return self.graph.value(atPath: graph, from: root)
            }
        }
        if let superview {
            return superview.value(atPath: graph)
        }
        if let root = self.sharedContext.viewContentRoot {
            return root.graph.value(atPath: graph, from: root.value)
        }
        return nil
    }

    override func updateContent() {
        self.invalidate()
        self.root = value(atPath: self.graph)
        if var root = self.root {
            updateRoot(&root)
            self.root = root
            // generate subviews
            self.subviews = self.body.makeViewList(containerView: self).map {
                $0.makeView()
            }
            self.subviews.forEach {
                $0.superview = self
                $0.updateContent()
            }
            self.activeSubviews = self.subviews.filter { $0.isValid }
        } else {
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

