//
//  File: OverlayModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _OverlayModifier<Overlay>: ViewModifier where Overlay: View {
    public typealias Body = Never

    let overlay: Overlay
    let alignment: Alignment
}

extension View {
    public func border<S>(_ content: S,
                          width: CGFloat = 1) -> some View where S: ShapeStyle {

        let strokeStyle = StrokeStyle()
        let strokeShape = Rectangle._Inset(amount: width * 0.5)

        let shape = _StrokedShape(shape: strokeShape, style: strokeStyle)
        let overlay = _ShapeView(shape: shape,
                                 style: content,
                                 fillStyle: FillStyle(eoFill: false, antialiased: true))

        let modifier = _OverlayModifier(overlay: overlay, alignment: .center)
        return self.modifier(modifier)
    }
}
