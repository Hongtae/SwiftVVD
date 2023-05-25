//
//  File: ViewGroupContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

typealias LayoutProtocol = Layout
class ViewGroupContext<Layout, Content>: ViewProxy where Layout: LayoutProtocol, Content: View {
    var view: Content
    var layout: Layout
    var modifiers: [any ViewModifier]
    var environmentValues: EnvironmentValues
    var sharedContext: SharedContext
    var subviews: [any ViewProxy]

    var layoutOffset: CGPoint = .zero
    var layoutSize: CGSize = .zero
    var contentScaleFactor: CGFloat = 1

    init(view: Content,
         layout: Layout,
         subviews: [any ViewProxy],
         modifiers: [any ViewModifier],
         environmentValues: EnvironmentValues,
         sharedContext: SharedContext) {
        self.view = view
        self.layout = layout
        self.subviews = subviews
        self.modifiers = modifiers
        self.environmentValues = environmentValues
        self.sharedContext = sharedContext
    }

    func drawBackground(frame: CGRect, context: GraphicsContext) {
    }

    func drawOverlay(frame: CGRect, context: GraphicsContext) {
    }

    func draw(frame: CGRect, context: GraphicsContext) {
        self.drawBackground(frame: frame, context: context)

        subviews.forEach { view in
            let drawFrame = CGRect(origin: view.layoutOffset, size: view.layoutSize)
                .offsetBy(dx: frame.minX, dy: frame.minY)

            var ctxt = context
            ctxt.environment = view.environmentValues
            ctxt.contentOffset += view.layoutOffset
            view.draw(frame: drawFrame, context: ctxt)
        }

        self.drawOverlay(frame: frame, context: context)
    }

    func layout(offset: CGPoint, size: CGSize, scaleFactor: CGFloat) {
        self.layoutOffset = offset
        self.layoutSize = size
        self.contentScaleFactor = scaleFactor

//        self.subview.layout(offset: self.layoutOffset,
//                            size: self.layoutSize,
//                            scaleFactor: self.contentScaleFactor)
    }

    func updateEnvironment(_ environmentValues: EnvironmentValues) {
    }
}
