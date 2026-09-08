//
//  File: BezierTimingFunction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct BezierTimingFunction<T: BinaryFloatingPoint & Sendable>: Equatable, Sendable {
    var p1x: T
    var p1y: T
    var p2x: T
    var p2y: T
}

extension BezierTimingFunction: ProtobufEncodableMessage, ProtobufDecodableMessage where T == Float {
    func encode(to encoder: inout ProtobufEncoder) throws {
        if p1x != 0 { encoder.encodeFloatFieldAlways(1, p1x) }
        if p1y != 0 { encoder.encodeFloatFieldAlways(2, p1y) }
        if p2x != 1 { encoder.encodeFloatFieldAlways(3, p2x) }
        if p2y != 1 { encoder.encodeFloatFieldAlways(4, p2y) }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        self.init(p1x: 0, p1y: 0, p2x: 1, p2y: 1)
        while let field = try decoder.nextField() {
            switch field.tag {
            case 1: p1x = try decoder.floatField(field)
            case 2: p1y = try decoder.floatField(field)
            case 3: p2x = try decoder.floatField(field)
            case 4: p2y = try decoder.floatField(field)
            default: try decoder.skipField(field)
            }
        }
    }
}
