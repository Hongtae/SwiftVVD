//
//  File: HoverModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _HoverBackgroundModifier<Background>: ViewModifier where Background: View {
    public var background: Background

    @inlinable public init(background: Background) {
        self.background = background
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view {
            if let background = makeView(view: modifier[\.background], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    HoverBackgroundViewContext(hoverContent: background.makeView(),
                                              graph: graph,
                                              body: body.makeView(),
                                              inputs: inputs)
                }
                return _ViewOutputs(view: view)
            }
        }
        return outputs
    }

    public typealias Body = Never
}

extension _HoverBackgroundModifier: _UnaryViewModifier {
}

public struct _HoverOverlayModifier<Overlay>: ViewModifier where Overlay: View {
    public var overlay: Overlay

    @inlinable public init(overlay: Overlay) {
        self.overlay = overlay
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view {
            if let overlay = makeView(view: modifier[\.overlay], inputs: inputs).view {
                let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                    HoverOverlayViewContext(hoverContent: overlay.makeView(),
                                           graph: graph,
                                           body: body.makeView(),
                                           inputs: inputs)
                }
                return _ViewOutputs(view: view)
            }
        }
        return outputs
    }

    public typealias Body = Never
}

extension _HoverOverlayModifier: _UnaryViewModifier {
}

public struct _HoverRegionModifier: ViewModifier {
    public var action: (Bool) -> Void

    @inlinable public init(_ action: @escaping (Bool) -> Void) {
        self.action = action
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                HoverRegionViewContext(graph: graph, body: body.makeView(), inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }

    public typealias Body = Never
}

extension _HoverRegionModifier: _UnaryViewModifier {
}

extension View {
    @inlinable
    public func hoverBackground<V>(@ViewBuilder content: () -> V) -> some View where V: View {
        modifier(_HoverBackgroundModifier(background: content()))
    }

    @inlinable
    public func hoverOverlay<V>(@ViewBuilder content: () -> V) -> some View where V: View {
        modifier(_HoverOverlayModifier(overlay: content()))
    }

    @inlinable
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(_HoverRegionModifier(action))
    }
}

private class HoverViewContextBase<Modifier: ViewModifier>: ViewModifierContext<Modifier> {
    let hoverContent: ViewContext
    var isMouseHovered = false

    init(hoverContent: ViewContext, graph: _GraphValue<Modifier>, body: ViewContext, inputs: _GraphInputs) {
        self.hoverContent = hoverContent
        defer { self.hoverContent.superview = self }
        super.init(graph: graph, body: body, inputs: inputs)
    }

    deinit {
        self.hoverContent.superview = nil
    }

    override func updateContent() {
        super.updateContent()
        if self.view != nil {
            hoverContent.updateContent()
        }
    }

    override func validate() -> Bool {
        if super.validate() {
            hoverContent.validate()
            return true
        }
        return false
    }

    override func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        if deviceID == 0 {
            let hovered = self.isMouseHovered
            if isTopMost {
                self.isMouseHovered = self.hitTest(location) != nil
            } else {
                self.isMouseHovered = false
            }
            if hovered != self.isMouseHovered {
                self.body.updateContent()
            }
        }
        return super.handleMouseHover(at: location, deviceID: deviceID, isTopMost: isTopMost)
    }
}

private class HoverBackgroundViewContext<Background: View>: HoverViewContextBase<_HoverBackgroundModifier<Background>> {
    override init(hoverContent: ViewContext, graph: _GraphValue<_HoverBackgroundModifier<Background>>, body: ViewContext, inputs: _GraphInputs) {
        super.init(hoverContent: hoverContent, graph: graph, body: body, inputs: inputs)
    }

    override func drawBackground(frame: CGRect, context: GraphicsContext) {
        super.drawBackground(frame: frame, context: context)
        guard isMouseHovered else { return }
        hoverContent.drawView(frame: frame, context: context)
    }
}

private class HoverOverlayViewContext<Overlay: View>: HoverViewContextBase<_HoverOverlayModifier<Overlay>> {
    override init(hoverContent: ViewContext, graph: _GraphValue<_HoverOverlayModifier<Overlay>>, body: ViewContext, inputs: _GraphInputs) {
        super.init(hoverContent: hoverContent, graph: graph, body: body, inputs: inputs)
    }

    override func drawOverlay(frame: CGRect, context: GraphicsContext) {
        super.drawOverlay(frame: frame, context: context)
        guard isMouseHovered else { return }
        hoverContent.drawView(frame: frame, context: context)
    }

    override func hitTest(_ location: CGPoint) -> ViewContext? {
        if isMouseHovered {
            let local = location.applying(hoverContent.transformToContainer.inverted())
            if let result = hoverContent.hitTest(local) {
                return result
            }
        }
        return super.hitTest(location)
    }
}

private class HoverRegionViewContext: ViewModifierContext<_HoverRegionModifier> {
    var isMouseHovered = false

    override func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        if deviceID == 0 {
            let hovered = self.isMouseHovered
            if isTopMost {
                self.isMouseHovered = self.hitTest(location) != nil
            } else {
                self.isMouseHovered = false
            }
            if hovered != self.isMouseHovered {
                self.view?.action(self.isMouseHovered)
            }
        }
        return super.handleMouseHover(at: location, deviceID: deviceID, isTopMost: isTopMost)
    }
}
