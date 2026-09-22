//
//  File: ContainerShapeTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ContainerShapeTransform: Rule, AsyncAttribute {
    var _transform: Attribute<ViewTransform>
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var id: CoordinateSpace.ID

    var value: ViewTransform {
        var value = _transform.value
        value.appendPosition(_position.value)
        value.appendSizedSpace(id: id, size: _size.value)
        return value
    }
}
