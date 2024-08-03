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
            self.baseInputs.mergedInputs.append(inputs)
        }
    }

    init<L: Layout>(view: Content, subviews: [ViewContext], layout: L, inputs: _GraphInputs, graph: _GraphValue<Content>) {
        self.view = view
        self.subviews = subviews
        self.layout = AnyLayout(layout)
        self.layoutCache = nil
        self.layoutProperties = L.layoutProperties

        super.init(inputs: inputs, graph: graph)
        self._debugDraw = false

        defer {
            self.subviews.forEach {
                $0.setLayoutProperties(self.layoutProperties)
            }
        }
    }

    override func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        if let value = graph.value(atPath: self.graph, from: encloser) as? Content {
            return subviews.allSatisfy {
                $0.validatePath(encloser: value, graph: self.graph)
            }
        }
        return false
    }

    override func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let view = graph.value(atPath: self.graph, from: encloser) as? Content {
            self.view = view
            self.subviews.forEach {
                $0.updateContent(encloser: self.view, graph: self.graph)
            }
        } else {
            fatalError("Unable to recover View")
        }
    }

    override func resolveGraphInputs<T>(encloser: T, graph: _GraphValue<T>) {
        super.resolveGraphInputs(encloser: encloser, graph: graph)
        self.view = inputs.environment._resolve(self.view)
        self.subviews.forEach {
            $0.resolveGraphInputs(encloser: self.view, graph: self.graph)
        }
    }

    override func updateEnvironment(_ environmentValues: EnvironmentValues) {
        super.updateEnvironment(environmentValues)
        self.view = inputs.environment._resolve(self.view)
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
            view.drawView(frame: view.frame, context: context)
        }
    }

    override func gestureHandlers(at location: CGPoint) -> [_GestureHandler] {
        fatalError()
    }

    override func handleMouseWheel(at location: CGPoint, delta: CGPoint) -> Bool {
        if self.frame.contains(location) {
            for subview in subviews {
                let frame = subview.frame
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
