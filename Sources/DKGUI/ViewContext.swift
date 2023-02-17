//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

class SharedContext {
    var appContext: AppContext

    var window: Window?
    var commandQueue: CommandQueue? // render queue for window swap-chain

    var data: [String: Any] = [:]

    init(appContext: AppContext) {
        self.appContext = appContext
    }
}

protocol ViewProxy {
    associatedtype Content: View
    var view: Content { get }
    var modifiers: [any ViewModifier] { get }
    var environmentValues: EnvironmentValues { get }
    var sharedContext: SharedContext { get }
    var layoutOffset: CGPoint { get }
    var layoutSize: CGSize { get }
    var contentScaleFactor: CGFloat { get }

    mutating func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat)
    func update(tick: UInt64, delta: Double, date: Date)
    func draw(frame: CGRect, context: GraphicsContext)
}

extension ViewProxy {
    func update(tick: UInt64, delta: Double, date: Date) {
    }
    func draw(frame: CGRect, context: GraphicsContext) {
        // Log.err("Existential types must implement the draw() method themselves.")
    }
}

struct ViewContext<Content>: ViewProxy where Content: View {
    var view: Content
    var subview: any ViewProxy
    var modifiers: [any ViewModifier]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var layoutOffset: CGPoint = .zero
    var layoutSize: CGSize = .zero
    var contentScaleFactor: CGFloat = 1

    init(view: Content,
         modifiers: [any ViewModifier],
         environmentValues: EnvironmentValues,
         sharedContext: SharedContext) {
        self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        self.view = self.environmentValues._resolve(view)
        self.modifiers = modifiers
        self.sharedContext = sharedContext
        self.subview = _makeViewProxy(self.view.body,
                                      modifiers: self.modifiers,
                                      environmentValues: self.environmentValues,
                                      sharedContext: sharedContext)
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext) {
    }

    func draw(frame: CGRect, context: GraphicsContext) {
        self.drawBackground(frame: frame, context: context)

        let drawSubview = true
        if drawSubview {
            let subviewFrame = CGRect(origin: subview.layoutOffset, size: subview.layoutSize)
                .offsetBy(dx: frame.minX, dy: frame.minY)
            var subviewContext = context
            subviewContext.environment = subview.environmentValues
            subviewContext.contentOffset += subview.layoutOffset
            subview.draw(frame: subviewFrame, context: subviewContext)
        }
        self.drawOverlay(frame: frame, context: context)
    }

    mutating func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat) {
        self.layoutOffset = offset
        self.layoutSize = size
        self.contentScaleFactor = scaleFactor
        self.subview.layout(offset: self.layoutOffset,
                            size: self.layoutSize,
                            scaleFactor: self.contentScaleFactor)
    }
}

func _makeViewProxy<Content>(_ view: Content,
                             modifiers: [any ViewModifier],
                             environmentValues: EnvironmentValues,
                             sharedContext: SharedContext) -> any ViewProxy where Content: View {
    if let prim = view as? (any _PrimitiveView) {
        return prim.makeViewProxy(modifiers: modifiers,
                                  environmentValues: environmentValues,
                                  sharedContext: sharedContext)
    }
    return ViewContext(view: view,
                       modifiers: modifiers,
                       environmentValues: environmentValues,
                       sharedContext: sharedContext)
}
