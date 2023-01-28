//
//  File: Gradient.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Gradient {
    public struct Stop: Equatable {
        public var color: Color
        public var location: CGFloat

        public init(color: Color, location: CGFloat) {
            self.color = color
            self.location = location
        }
    }

    public var stops: [Stop]

    public init(stops: [Stop]) {
        self.stops = stops
    }

    public init(colors: [Color]) {
        self.stops = []
        if colors.isEmpty == false {
            let numColors = colors.count
            if numColors > 1 {
                for (i, c) in colors.enumerated() {
                    let location = CGFloat(i) / CGFloat(numColors-1)
                    self.stops.append(Stop(color: c, location: location))
                }
            } else {
                self.stops.append(Stop(color: colors[0], location: 0))
            }
        }
    }

    public struct ColorSpace: Hashable {
        let id: UInt32

        static let device = ColorSpace(id: 0)
        static let perceptual = ColorSpace(id: 2)
    }
}

extension Gradient: ShapeStyle {
}

class AnyGradientBox {
}

struct AnyGradient: Hashable, ShapeStyle {
    static func == (lhs: AnyGradient, rhs: AnyGradient) -> Bool {
        ObjectIdentifier(lhs.provider) == ObjectIdentifier(rhs.provider)
    }

    func hash(into: inout Hasher) {
        into.combine(ObjectIdentifier(provider))
    }

    var provider: AnyGradientBox

    init(provider: AnyGradientBox) {
        self.provider = provider
    }

    public init(_ gradient: Gradient) {
        self.provider = AnyGradientBox()
    }

    public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient {
        AnyGradient(provider: AnyGradientBox())
    }
}
