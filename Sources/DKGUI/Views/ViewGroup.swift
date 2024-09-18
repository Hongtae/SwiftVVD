//
//  File: ViewGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

class ViewGroupContext<Content> : ViewContext where Content: View {
    var view: Content { references.content }
    var references: any ViewReferences<Content>
    var subviews: [ViewContext]
    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?
    let layoutProperties: LayoutProperties

    struct Generator : ViewGenerator {
        var graph: _GraphValue<Content>
        var subviews: [any ViewGenerator]
        var baseInputs: _GraphInputs

        func makeView<T>(encloser: T, graph: _GraphValue<T>) -> ViewContext? {
            if let view = graph.value(atPath: self.graph, from: encloser) {
                let subviews = self.subviews.compactMap {
                    $0.makeView(encloser: view, graph: self.graph)
                }
                let layout = baseInputs.properties
                    .find(type: DefaultLayoutPropertyItem.self)?
                    .layout ?? DefaultLayoutPropertyItem.default
                return ViewGroupContext(view: view,
                                        subviews: subviews,
                                        layout: layout,
                                        inputs: baseInputs,
                                        graph: self.graph)
            }
            fatalError("Unable to recover view")
        }

        mutating func mergeInputs(_ inputs: _GraphInputs) {
            subviews.indices.forEach { subviews[$0].mergeInputs(inputs) }
            baseInputs.mergedInputs.append(inputs)
        }
    }

    init<L: Layout>(view: Content, subviews: [ViewContext], layout: L, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.subviews = subviews
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = L.layoutProperties
        self.references = buildViewReferences(root: view, graph: graph, subviews: subviews)

        super.init(inputs: inputs, graph: graph)
        self._debugDraw = false

        defer {
            self.subviews.forEach {
                $0.setLayoutProperties(self.layoutProperties)
            }
        }
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        self._validPath = false
        if let value = graph.value(atPath: self.graph, from: encloser) as? Content {
            self._validPath = true

            if self.references.validatePath(encloser: value, graph: self.graph) {
                return subviews.allSatisfy {
                    $0.validatePath(encloser: value, graph: self.graph)
                }
            }
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        references.updateContent(encloser: encloser, graph: graph)
    }

    override func resolveGraphInputs<T>(encloser: T, graph: _GraphValue<T>) {
        super.resolveGraphInputs(encloser: encloser, graph: graph)
        references.updateContent(environment: inputs.environment)
        self.subviews.forEach {
            $0.resolveGraphInputs(encloser: self.view, graph: self.graph)
        }
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        references.updateContent(environment: inputs.environment)
        self.subviews.forEach {
            $0.updateEnvironment(self.environmentValues)
        }
    }

    override func setLayoutProperties(_: LayoutProperties) {
        super.setLayoutProperties(self.layoutProperties)
        self.subviews.forEach {
            $0.setLayoutProperties(self.layoutProperties)
        }
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        if self.subviews.isEmpty == false {
            let subviews: [LayoutSubview] = self.subviews.map {
                LayoutSubview(view: $0)
            }
            let layoutSubviews = AnyLayout.Subviews(subviews: subviews, layoutDirection: .leftToRight)

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
        let frame = self.frame
        guard frame.width > 0 && frame.height > 0 else { return }

        if self.subviews.isEmpty == false {
            let subviews: [LayoutSubview] = self.subviews.map {
                LayoutSubview(view: $0)
            }
            let layoutSubviews = AnyLayout.Subviews(subviews: subviews, layoutDirection: .leftToRight)

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
            } else {
                Log.error("Invalid layout cache")
            }
        }
    }

    override func loadResources(_ context: GraphicsContext) {
        super.loadResources(context)
        self.subviews.forEach {
            $0.loadResources(context)
        }
    }

    override func update(transform t: AffineTransform, origin: CGPoint) {
        super.update(transform: t, origin: origin)
        self.subviews.forEach {
            $0.update(transform: self.transformByRoot, origin: self.frame.origin)
        }
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)
        self.subviews.forEach {
            $0.update(tick: tick, delta: delta, date: date)
        }
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        super.draw(frame: frame, context: context)

        self.subviews.forEach { view in
            let width = view.frame.width
            let height = view.frame.height
            guard width > 0 && height > 0 else {
                return
            }

            if frame.intersection(view.frame).isNull {
                return
            }
            view.drawView(frame: view.frame, context: context)
        }
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        for subview in subviews {
            if let view = subview.hitTest(location) {
                return view
            }
        }
        return super.hitTest(location)
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        var outputs = super.gestureHandlers(at: location)
        if self.frame.contains(location) {
            for subview in subviews {
                let frame = subview.frame
                if frame.contains(location) {
                    outputs = outputs.merge(subview.gestureHandlers(at: location))
                }
            }
        }
        return outputs
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.contains(location) {
            for subview in subviews {
                let frame = subview.frame
                if frame.contains(location) {
                    if subview.handleMouseWheel(at: location, delta: delta) {
                        return true
                    }
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }
}
