//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

protocol ViewProxy {
    associatedtype Content: View
    var view: Content { get }
    var modifiers: [any ViewModifier] { get }
    var subviews: [any ViewProxy] { get }
    var environmentValues: EnvironmentValues { get }

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
    var modifiers: [any ViewModifier]
    var subviews: [any ViewProxy]
    var environmentValues: EnvironmentValues

    init(view: Content, modifiers: [any ViewModifier], parent: any ViewProxy) {
        self.view = view
        self.modifiers = modifiers
        var environmentValues = parent.environmentValues
        modifiers.forEach { modifier in
            if let env = modifier as? _EnvironmentModifier {
                environmentValues = env.resolveEnvironmentValues(environmentValues)
            }
        }
        self.environmentValues = environmentValues
        self.subviews = []
    }

    init(view: Content, parent: any ViewProxy) {
        self.view = view
        self.modifiers = []
        self.subviews = []
        self.environmentValues = parent.environmentValues
    }
}

func _makeViewProxy<Content>(_ view: Content,
                             modifiers: [any ViewModifier],
                             parent: any ViewProxy) -> any ViewProxy where Content: View {
    if let prim = view as? (any _PrimitiveView) {
        return prim.makeViewProxy(modifiers: modifiers, parent: parent)
    }
    return _makeViewProxy(view.body, modifiers: modifiers, parent: parent)
}
