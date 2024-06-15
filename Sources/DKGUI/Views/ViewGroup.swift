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

    init<L: Layout>(view: Content, inputs: _ViewInputs, layout: L) {

        fatalError()
    }
}
