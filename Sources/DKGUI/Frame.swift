//
//  File: Frame.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

class ViewFrame<Content> : Frame where Content : View {

    override func load(screen: Screen) {}
    override func unload() {}
    override func update(tick: UInt64, delta: Double, date: Date) {}
    override func draw(canvas: Canvas) { canvas.clear(color: .yellow) }
    override func drawOverlay(canvas: Canvas) {}

    var view: Content
    nonisolated init(_ content: Content) {
        self.view = content
    }
}
