//
//  File: StackLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _StackLayoutCache {

}

public struct _LayoutRoot<L>: _VariadicView_ViewRoot where L: Layout {
    let layout: L

    init(_ layout: L) {
        self.layout = layout
    }
}
