//
//  File: Box.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct Box {
    let center: Vector3
    let u: Vector3  // unit vectors of each extent direction.
    let v: Vector3
    let w: Vector3
    let hu: Scalar
    let hv: Scalar
    let hw: Scalar
}
