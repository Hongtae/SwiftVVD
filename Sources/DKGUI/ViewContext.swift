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
    var commandQueue: CommandQueue?

    var backBuffer: Texture?
    var stencilBuffer: Texture?

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
    func draw()
    func drawOverlay()
}

extension ViewProxy {
    func update(tick: UInt64, delta: Double, date: Date) {
    }
    func draw() {
    }
    func drawOverlay() {
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

    init(view: Content, modifiers: [any ViewModifier], environmentValues: EnvironmentValues, sharedContext: SharedContext) {
        self.environmentValues = environmentValues._resolve(modifiers: modifiers)
        self.view = self.environmentValues._resolve(view)
        self.modifiers = modifiers
        self.sharedContext = sharedContext
        self.subview = _makeViewProxy(self.view.body,
                                      modifiers: self.modifiers,
                                      environmentValues: self.environmentValues,
                                      sharedContext: sharedContext)
    }

    func draw() {
        subview.draw()
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
