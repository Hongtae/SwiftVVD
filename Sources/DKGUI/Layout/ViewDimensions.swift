//
//  File: ViewDimensions.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ViewDimensions: Equatable {
    var height: CGFloat
    var width: CGFloat

    subscript(guide: HorizontalAlignment) -> CGFloat {
        0
    }

    subscript(guide: VerticalAlignment) -> CGFloat {
        0
    }

    subscript(explicit guide: HorizontalAlignment) -> CGFloat? {
        nil
    }
    subscript(explicit guide: VerticalAlignment) -> CGFloat? {
        nil
    }
}
