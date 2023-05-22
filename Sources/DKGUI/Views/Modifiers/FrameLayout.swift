//
//  File: FrameLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _FrameLayout: ViewModifier {
    public typealias Body = Never

    var width: CGFloat?
    var height: CGFloat?
    var alignment: Alignment
}

extension View {
    public func frame(width: CGFloat? = nil,
                      height: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View {
        let modifier = _FrameLayout(width: width, height: height, alignment: alignment)
        return self.modifier(modifier)
    }
}
