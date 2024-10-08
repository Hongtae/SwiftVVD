//
//  File: ViewGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

class ViewGroupContext<Content> : ViewContext where Content: View {
    var view: Content { references.content }
    var references: any ViewReferences<Content>
    var subviews: [ViewContext]
    var layout: AnyLayout
    var layoutCache: AnyLayout.Cache?
    let layoutProperties: LayoutProperties

    init<L: Layout>(view: Content, subviews: [ViewContext], layout: L, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.subviews = subviews
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = L.layoutProperties

        assert(subviews.allSatisfy({ $0.graph.isDescendant(of: graph) }))
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
        let frame = self.bounds
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
            $0.update(transform: self.transformToRoot)
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

        let offsetX = frame.minX
        let offsetY = frame.minY

        self.subviews.forEach { view in
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
        for subview in subviews {
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
            for subview in subviews {
                let local = location.applying(subview.transformToContainer.inverted())
                outputs = outputs.merge(subview.gestureHandlers(at: local))
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
