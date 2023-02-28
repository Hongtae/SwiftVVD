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

    func normalized() -> Self {
        let stops1 = self.stops.sorted { $0.location < $1.location }
        guard var current = stops1.first else {
            return self // empty gradient
        }
        var stops2: [Stop] = []
        stops2.reserveCapacity(stops1.count + 1)

        if current.location > 0.0 {
            stops2.append(Stop(color: current.color, location: 0.0))
        }
        for s in stops1 {
            if s.location > 0.0 && s.location < 1.0 {
                if current.location <= 0.0 {
                    let t = (0.0 - current.location) / (s.location - current.location)
                    stops2.append(Stop(color: .lerp(current.color, s.color, t),
                                      location: 0.0))
                }
                stops2.append(s)
            } else if s.location >= 1.0 {
                let t = (1.0 - current.location) / (s.location - current.location)
                stops2.append(Stop(color: .lerp(current.color, s.color, t),
                                  location: 1.0))
                break
            }
            current = s
        }
        if let last = stops2.last, last.location < 1.0 {
            var stop = last
            stop.location = 1.0
            stops2.append(stop)
        }
        return Gradient(stops: stops2)
    }

    func _linearInterpolatedColor(at location: CGFloat) -> Color {
        // Gradients must have at least one color and must be sorted.
        assert(stops.isEmpty == false)
        var current = stops.first!
        if location > current.location {
            for i in 1..<stops.count {
                let next = stops[i]
                if next.location > location {
                    return .lerp(current.color,
                                 next.color,
                                 (location - current.location) / (next.location - current.location))
                }
                current = next
            }
        }
        return current.color
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
