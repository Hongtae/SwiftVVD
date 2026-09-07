//
//  File: Gradient.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Gradient {
    public struct Stop: Equatable, Hashable, Sendable {
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

    public struct ColorSpace: Hashable, Sendable {
        var base: ResolvedGradient.ColorSpace

        public static let device = ColorSpace(base: .device)
        public static let perceptual = ColorSpace(base: .perceptual)
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
                if current.location <= 0.0 {
                    let t = (0.0 - current.location) / (s.location - current.location)
                    stops2.append(Stop(color: .lerp(current.color, s.color, t),
                                      location: 0.0))
                }
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

    func reversed() -> Self {
        Self(stops: self.stops.reversed().map {
            Stop(color: $0.color, location: 1.0 - $0.location)
        })
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

extension Gradient: ShapeStyle, Hashable {
    public typealias Resolved = Never
    public func _apply(to shape: inout _ShapeStyle_Shape) {
        LinearGradient(gradient: self, startPoint: .top, endPoint: .bottom)._apply(to: &shape)
    }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {}
}

protocol GradientProvider: Hashable, Serializable {
    var tag: Gradient.ProviderTag { get }
    func resolve(in environment: EnvironmentValues) -> ResolvedGradient
    func fallbackColor(in environment: EnvironmentValues) -> Color?
}

extension GradientProvider {
    func fallbackColor(in environment: EnvironmentValues) -> Color? { nil }
}

class AnyGradientBox: AnyShapeStyleBox, AnyCodableBox, @unchecked Sendable {
    typealias Box = AnyGradientBox
    typealias Tag = Gradient.ProviderTag

    var tag: Tag { fatalError("Abstract gradient box.") }
    func resolve(in environment: EnvironmentValues) -> ResolvedGradient {
        fatalError("Abstract gradient box.")
    }
    func fallbackColor(in environment: EnvironmentValues) -> Color? {
        fatalError("Abstract gradient box.")
    }
    func hash(into hasher: inout Hasher) { fatalError("Abstract gradient box.") }

    override func apply(to shape: inout _ShapeStyle_Shape) {
        _AnyLinearGradient(gradient: AnyGradient(provider: self),
                           startPoint: .top, endPoint: .bottom)._apply(to: &shape)
    }
}

final class GradientBox<T: GradientProvider>: AnyGradientBox, CodableBox, @unchecked Sendable {
    let base: T

    init(_ base: T) { self.base = base }

    override var tag: Tag { base.tag }
    override func resolve(in environment: EnvironmentValues) -> ResolvedGradient {
        base.resolve(in: environment)
    }
    override func fallbackColor(in environment: EnvironmentValues) -> Color? {
        base.fallbackColor(in: environment)
    }
    override func hash(into hasher: inout Hasher) { base.hash(into: &hasher) }
    override func isEqual(to other: AnyShapeStyleBox) -> Bool {
        guard let other = other as? GradientBox<T> else { return false }
        return base == other.base
    }
    func serialize(to encoder: any Encoder) throws { try base.serialize(to: encoder) }
    static func deserialize(from decoder: any Decoder) throws -> GradientBox<T> {
        GradientBox(try T.deserialize(from: decoder))
    }
}

public struct AnyGradient: Hashable, ShapeStyle, Serializable {
    public static func == (lhs: AnyGradient, rhs: AnyGradient) -> Bool {
        lhs.provider === rhs.provider || lhs.provider.isEqual(to: rhs.provider)
    }

    public func hash(into hasher: inout Hasher) {
        provider.hash(into: &hasher)
    }

    var provider: AnyGradientBox

    init(provider: AnyGradientBox) {
        self.provider = provider
    }

    public init(_ gradient: Gradient) {
        self.provider = GradientBox(gradient)
    }

    public func colorSpace(_ space: Gradient.ColorSpace) -> AnyGradient {
        AnyGradient(provider: GradientBox(ColorSpaceGradientProvider(
            base: .anyGradient(self), colorSpace: space.base
        )))
    }

    public typealias Resolved = Never
    public func _apply(to shape: inout _ShapeStyle_Shape) { provider.apply(to: &shape) }
    public static func _apply(to type: inout _ShapeStyle_ShapeType) {}
    func resolve(in environment: EnvironmentValues) -> ResolvedGradient {
        provider.resolve(in: environment)
    }
    func serialize(to encoder: any Encoder) throws { try provider.encode(to: encoder) }
    static func deserialize(from decoder: any Decoder) throws -> AnyGradient {
        AnyGradient(provider: try AnyGradientBox.decode(from: decoder))
    }
}

enum EitherGradient: Hashable, CodableByProxy {
    case gradient(Gradient)
    case anyGradient(AnyGradient)

    func resolve(in environment: EnvironmentValues) -> ResolvedGradient {
        switch self {
        case let .gradient(gradient): gradient.resolve(in: environment)
        case let .anyGradient(gradient): gradient.resolve(in: environment)
        }
    }

    func fallbackColor(in environment: EnvironmentValues) -> Color? {
        switch self {
        case .gradient: nil
        case let .anyGradient(gradient): gradient.provider.fallbackColor(in: environment)
        }
    }

    var codingProxy: Gradient.EitherGradientDefinition {
        switch self {
        case let .gradient(gradient): .gradient(ProxyCodable(gradient))
        case let .anyGradient(gradient): .anyGradient(ProxyCodable(gradient))
        }
    }

    static func unwrap(codingProxy: Gradient.EitherGradientDefinition) -> Self {
        switch codingProxy {
        case let .gradient(gradient): .gradient(gradient.wrappedValue)
        case let .anyGradient(gradient): .anyGradient(gradient.wrappedValue)
        }
    }
}

struct ColorSpaceGradientProvider: GradientProvider, CodableByProxy {
    var base: EitherGradient
    var colorSpace: ResolvedGradient.ColorSpace

    var tag: Gradient.ProviderTag { .colorSpace }
    func resolve(in environment: EnvironmentValues) -> ResolvedGradient {
        var gradient = base.resolve(in: environment)
        gradient.colorSpace = colorSpace
        return gradient
    }
    var codingProxy: Gradient.ColorSpaceGradientDefinition {
        .init(base: base, colorSpace: colorSpace)
    }
    static func unwrap(codingProxy: Gradient.ColorSpaceGradientDefinition) -> Self {
        .init(base: codingProxy.base, colorSpace: codingProxy.colorSpace)
    }
}

extension Gradient: GradientProvider, CodableByProxy {
    var tag: ProviderTag { .basic }

    func resolve(in environment: EnvironmentValues) -> ResolvedGradient {
        var headroom: Float?
        var resolved: [ResolvedGradient.Stop] = []
        resolved.reserveCapacity(stops.count)
        for stop in stops {
            let color = stop.color.resolveHDR(in: environment)
            resolved.append(.init(color: color.base, location: stop.location, interpolation: nil))
            if let value = color.headroom {
                headroom = headroom.map { max($0, value) } ?? value
            }
        }
        return .init(stops: resolved, colorSpace: .perceptual, headroom: headroom)
    }

    public func colorSpace(_ space: ColorSpace) -> AnyGradient {
        AnyGradient(provider: GradientBox(ColorSpaceGradientProvider(
            base: .gradient(self), colorSpace: space.base
        )))
    }

    var codingProxy: GradientDefinition {
        .init(stops: stops.map { .init(color: $0.color, location: $0.location) })
    }
    static func unwrap(codingProxy: GradientDefinition) -> Gradient {
        Gradient(stops: codingProxy.stops.map { .init(color: $0.color, location: $0.location) })
    }

    struct GradientDefinition: Codable { var stops: [StopDefinition] }
    struct StopDefinition: Codable {
        @ProxyCodable var color: Color
        var location: CGFloat
    }
    enum EitherGradientDefinition: Codable {
        case gradient(ProxyCodable<Gradient>)
        case anyGradient(ProxyCodable<AnyGradient>)
    }
    struct ColorSpaceGradientDefinition: Codable {
        @ProxyCodable var base: EitherGradient
        @CodableRawRepresentable var colorSpace: ResolvedGradient.ColorSpace
    }
    enum ProviderTag: Codable, CodableBoxTag {
        case basic, colorSpace

        typealias Box = AnyGradientBox
        var box: any CodableBox<AnyGradientBox>.Type {
            switch self {
            case .basic: GradientBox<Gradient>.self
            case .colorSpace: GradientBox<ColorSpaceGradientProvider>.self
            }
        }
    }
}
