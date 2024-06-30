//
//  File: ViewGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

class ViewGroupContext<Content> : ViewContext where Content: View {
    var view: Content
    var subviews: [ViewContext]
    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?
    let layoutProperties: LayoutProperties

    struct Generator : ViewGenerator {
        var graph: _GraphValue<Content>
        let subviews: [any ViewGenerator]
        var baseInputs: _GraphInputs
        var preferences: PreferenceInputs
        var traits: ViewTraitKeys = ViewTraitKeys()

        func makeView(content view: Content) -> ViewContext? {
            func makeBody<T: ViewGenerator>(_ gen: T) -> ViewContext? {
                if let body = self.graph.value(atPath: gen.graph, from: view) {
                    return gen.makeView(content: body)
                }
                return nil
            }
            let subviews = self.subviews.compactMap { makeBody($0) }
            let layout = baseInputs.properties?
                .find(type: DefaultLayoutPropertyItem.self)?
                .layout ?? DefaultLayoutPropertyItem.default
            return ViewGroupContext(view: view,
                                    subviews: subviews,
                                    layout: layout,
                                    inputs: baseInputs,
                                    graph: self.graph)
        }
    }

    init<L: Layout>(view: Content, subviews: [ViewContext], layout: L, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.view = inputs.environment._resolve(view)
        self.subviews = subviews
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = L.layoutProperties

        super.init(inputs: inputs, graph: graph)
        self.debugDraw = false
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.subviews.forEach {
            $0.updateEnvironment(self.environmentValues)
        }
    }

    override func setLayoutProperties(_ properties: LayoutProperties) {
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
        let frame = self.frame.standardized
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

    override func update(transform t: AffineTransform) {
        super.update(transform: t)
        self.subviews.forEach {
            $0.update(transform: t)
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
            var context = context
            context.environment = view.environmentValues
            view.drawView(frame: view.frame.standardized, context: context)
        }
    }

    override func gestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        fatalError()
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.standardized.contains(location) {
            for subview in subviews {
                let frame = subview.frame.standardized
                if frame.contains(location) {
                    let loc = location - frame.origin
                    if subview.handleMouseWheel(at: loc, delta: delta) {
                        return true
                    }
                }
            }
        }
        return super.handleMouseWheel(at: location, delta: delta)
    }
}
