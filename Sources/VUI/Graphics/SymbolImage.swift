//
//  File: SymbolImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ResolvedVectorSymbol: Equatable {
    struct Identity: Equatable {
        var name: String
        var variableValue: Double?
        var resource: String
    }

    struct Layer: Equatable {
        struct DrawGuide: Equatable {
            var path: Path
            var strokeStyle: StrokeStyle
        }

        struct DrawData: Equatable {
            var motionGroup: Int
            var guides: [DrawGuide]

            var strokeLength: CGFloat {
                guides.reduce(0) { $0 + $1.path.approximateLength }
            }

            func clipPath(progress: Double, reversed: Bool) -> Path {
                let progress = min(max(progress, 0), 1)
                let totalLength = strokeLength
                guard progress > 0, totalLength > 0 else { return Path() }

                var remaining = CGFloat(progress) * totalLength
                var result = Path()
                let orderedGuides = reversed ? Array(guides.reversed()) : guides
                for guide in orderedGuides where remaining > 0 {
                    let length = guide.path.approximateLength
                    guard length > 0 else { continue }
                    let fraction = min(remaining / length, 1)
                    let path = reversed
                        ? guide.path.trimmedPath(from: 1 - fraction, to: 1)
                        : guide.path.trimmedPath(from: 0, to: fraction)
                    result.addPath(path.strokedPath(guide.strokeStyle))
                    remaining -= length
                }
                return result
            }
        }

        var path: Path
        var opacity: Double
        var isEOFilled: Bool
        var semanticLevel: Int
        var effectLevel: Int
        // A nil level keeps the path outside the variable-color animator.
        var variableColorLevel: Int?
        // Draw geometry is asset metadata, independent of visible fill order.
        var draw: DrawData?
    }

    var identity: Identity
    var viewport: CGRect
    var layers: [Layer]

    var variableColorLevelCount: Int {
        layers.compactMap(\.variableColorLevel).max().map { $0 + 1 } ?? 0
    }

    var drawMotionGroupCount: Int {
        layers.compactMap { $0.draw?.motionGroup }.max().map { $0 + 1 } ?? 0
    }

    var drawMotionGroupDurations: [Double] {
        var durations = [Double](repeating: 0, count: drawMotionGroupCount)
        let glyphSize = max(viewport.width, viewport.height)
        guard glyphSize > 0 else { return durations }
        for layer in layers {
            guard let draw = layer.draw else { continue }
            let normalizedLength = min(
                max(Double(draw.strokeLength / glyphSize) * 0.171821311, 0),
                1
            )
            let duration = 2.0 / 15.0 +
                13.0 / 15.0 * normalizedLength * (2 - normalizedLength)
            durations[draw.motionGroup] = max(
                durations[draw.motionGroup],
                duration
            )
        }
        return durations.map { max($0, 2.0 / 15.0) }
    }
}

enum SymbolAssetCatalog {
    static func resolve(
        name: String,
        variableValue: Double?,
        bundle: Bundle?
    ) -> ResolvedVectorSymbol? {
        let resourceBundle = bundle ?? .module
        guard let url = resourceBundle.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: bundle == nil ? "Symbols" : nil
        ),
        let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        let subdirectory = bundle == nil ? "Symbols" : nil
        let metadata = resourceBundle.url(
            forResource: "\(name).layers",
            withExtension: "json",
            subdirectory: subdirectory
        ).flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(SymbolAssetMetadata.self, from: $0) }
        return SVGSymbolDocument.parse(
            source,
            identity: ResolvedVectorSymbol.Identity(
                name: name,
                variableValue: variableValue,
                resource: url.absoluteString
            ),
            metadata: metadata
        )
    }
}

struct SymbolAssetMetadata: Decodable {
    struct DrawGuide: Decodable {
        var path: String
        var lineWidth: CGFloat
        var lineCap: String?
        var lineJoin: String?
        var miterLimit: CGFloat?
    }

    struct DrawLayer: Decodable {
        var motionGroup: Int
        var guides: [DrawGuide]
    }

    var semanticLevels: [Int]
    var effectLevels: [Int]
    var variableColorLevels: [Int?]?
    var drawLayers: [DrawLayer?]?
}

enum SVGSymbolDocument {
    static func parse(
        _ source: String,
        identity: ResolvedVectorSymbol.Identity,
        metadata: SymbolAssetMetadata? = nil
    ) -> ResolvedVectorSymbol? {
        guard let svgTag = firstTag(named: "svg", in: source),
              let viewBoxValue = attributes(in: svgTag)["viewBox"] else {
            return nil
        }
        let viewBoxComponents = SVGNumberList(viewBoxValue).values
        guard viewBoxComponents.count == 4 else { return nil }
        let viewport = CGRect(
            x: viewBoxComponents[0],
            y: viewBoxComponents[1],
            width: viewBoxComponents[2],
            height: viewBoxComponents[3]
        )
        guard viewport.width > 0, viewport.height > 0 else { return nil }

        var layers: [ResolvedVectorSymbol.Layer] = []
        for tag in tags(named: "path", in: source) {
            let attributes = attributes(in: tag)
            guard attributes["fill"]?.lowercased() != "none",
                  let pathData = attributes["d"] else {
                continue
            }
            var parser = SVGPathDataParser(pathData)
            guard let path = parser.parse(), !path.isEmpty else {
                continue
            }
            let opacity = (Double(attributes["opacity"] ?? "1") ?? 1)
                * (Double(attributes["fill-opacity"] ?? "1") ?? 1)
            layers.append(ResolvedVectorSymbol.Layer(
                path: path,
                opacity: opacity,
                isEOFilled: attributes["fill-rule"]?.lowercased() == "evenodd",
                semanticLevel: 0,
                effectLevel: 0,
                variableColorLevel: nil,
                draw: nil
            ))
        }
        guard !layers.isEmpty else { return nil }
        if let metadata {
            guard metadata.semanticLevels.count == layers.count,
                  metadata.effectLevels.count == layers.count,
                  metadata.variableColorLevels?.count == layers.count ||
                    metadata.variableColorLevels == nil,
                  metadata.drawLayers?.count == layers.count ||
                    metadata.drawLayers == nil,
                  metadata.semanticLevels.allSatisfy({ $0 >= 0 }),
                  metadata.effectLevels.allSatisfy({ $0 >= 0 }),
                  metadata.variableColorLevels?.allSatisfy({
                    $0.map { $0 >= 0 } ?? true
                  }) != false,
                  metadata.drawLayers?.allSatisfy({
                    $0.map { $0.motionGroup >= 0 && !$0.guides.isEmpty } ?? true
                  }) != false else {
                return nil
            }
            for index in layers.indices {
                layers[index].semanticLevel = metadata.semanticLevels[index]
                layers[index].effectLevel = metadata.effectLevels[index]
                layers[index].variableColorLevel =
                    metadata.variableColorLevels?[index]
                if let drawLayer = metadata.drawLayers?[index] {
                    var guides: [ResolvedVectorSymbol.Layer.DrawGuide] = []
                    guides.reserveCapacity(drawLayer.guides.count)
                    for guide in drawLayer.guides {
                        guard guide.lineWidth > 0,
                              let lineCap = symbolLineCap(guide.lineCap),
                              let lineJoin = symbolLineJoin(guide.lineJoin) else {
                            return nil
                        }
                        var parser = SVGPathDataParser(guide.path)
                        guard let path = parser.parse(), !path.isEmpty else {
                            return nil
                        }
                        guides.append(ResolvedVectorSymbol.Layer.DrawGuide(
                            path: path,
                            strokeStyle: StrokeStyle(
                                lineWidth: guide.lineWidth,
                                lineCap: lineCap,
                                lineJoin: lineJoin,
                                miterLimit: guide.miterLimit ?? 10
                            )
                        ))
                    }
                    layers[index].draw = ResolvedVectorSymbol.Layer.DrawData(
                        motionGroup: drawLayer.motionGroup,
                        guides: guides
                    )
                }
            }
        }
        return ResolvedVectorSymbol(
            identity: identity,
            viewport: viewport,
            layers: layers
        )
    }

    private static func symbolLineCap(_ value: String?) -> CGLineCap? {
        switch value?.lowercased() ?? "butt" {
        case "butt": .butt
        case "round": .round
        case "square": .square
        default: nil
        }
    }

    private static func symbolLineJoin(_ value: String?) -> CGLineJoin? {
        switch value?.lowercased() ?? "miter" {
        case "miter": .miter
        case "round": .round
        case "bevel": .bevel
        default: nil
        }
    }

    private static func firstTag(named name: String, in source: String) -> Substring? {
        tags(named: name, in: source).first
    }

    private static func tags(named name: String, in source: String) -> [Substring] {
        let prefix = "<\(name)"
        var result: [Substring] = []
        var searchStart = source.startIndex
        while let start = source.range(
            of: prefix,
            options: [.caseInsensitive],
            range: searchStart..<source.endIndex
        )?.lowerBound,
        let end = source[start...].firstIndex(of: ">") {
            result.append(source[start...end])
            searchStart = source.index(after: end)
        }
        return result
    }

    private static func attributes(in tag: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var index = tag.startIndex

        func isNameCharacter(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "-" ||
                character == "_" || character == ":"
        }

        while index < tag.endIndex {
            while index < tag.endIndex, !isNameCharacter(tag[index]) {
                index = tag.index(after: index)
            }
            let nameStart = index
            while index < tag.endIndex, isNameCharacter(tag[index]) {
                index = tag.index(after: index)
            }
            guard nameStart < index else { break }
            let name = String(tag[nameStart..<index])

            while index < tag.endIndex, tag[index].isWhitespace {
                index = tag.index(after: index)
            }
            guard index < tag.endIndex, tag[index] == "=" else { continue }
            index = tag.index(after: index)
            while index < tag.endIndex, tag[index].isWhitespace {
                index = tag.index(after: index)
            }
            guard index < tag.endIndex,
                  tag[index] == "\"" || tag[index] == "'" else {
                continue
            }
            let quote = tag[index]
            index = tag.index(after: index)
            let valueStart = index
            while index < tag.endIndex, tag[index] != quote {
                index = tag.index(after: index)
            }
            guard index < tag.endIndex else { break }
            result[name] = String(tag[valueStart..<index])
            index = tag.index(after: index)
        }
        return result
    }
}

private struct SVGNumberList {
    var values: [CGFloat] = []

    init(_ source: String) {
        var scanner = SVGPathScanner(source)
        while let value = scanner.consumeNumber() {
            values.append(value)
        }
    }
}

struct SVGPathDataParser {
    private var scanner: SVGPathScanner
    private var path = Path()
    private var command: UInt8?
    private var previousCommand: UInt8?
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    private var previousCubicControl: CGPoint?
    private var previousQuadraticControl: CGPoint?

    init(_ source: String) {
        self.scanner = SVGPathScanner(source)
    }

    mutating func parse() -> Path? {
        while !scanner.isAtEnd {
            if let nextCommand = scanner.consumeCommand() {
                command = nextCommand
                if nextCommand == Character("Z").asciiValue ||
                    nextCommand == Character("z").asciiValue {
                    path.closeSubpath()
                    current = subpathStart
                    resetControls()
                    previousCommand = nextCommand
                    command = nil
                }
                continue
            }
            guard let command, scanner.hasNumber else { return nil }
            guard consumeSegment(command) else { return nil }
            previousCommand = command
        }
        return path
    }

    private mutating func consumeSegment(_ command: UInt8) -> Bool {
        let relative = command >= Character("a").asciiValue! &&
            command <= Character("z").asciiValue!
        switch Character(UnicodeScalar(command)) {
        case "M", "m":
            guard let point = consumePoint(relative: relative) else { return false }
            path.move(to: point)
            current = point
            subpathStart = point
            resetControls()
            self.command = relative ? Character("l").asciiValue : Character("L").asciiValue
        case "L", "l":
            guard let point = consumePoint(relative: relative) else { return false }
            path.addLine(to: point)
            current = point
            resetControls()
        case "H", "h":
            guard let value = scanner.consumeNumber() else { return false }
            current.x = relative ? current.x + value : value
            path.addLine(to: current)
            resetControls()
        case "V", "v":
            guard let value = scanner.consumeNumber() else { return false }
            current.y = relative ? current.y + value : value
            path.addLine(to: current)
            resetControls()
        case "C", "c":
            guard let control1 = consumePoint(relative: relative),
                  let control2 = consumePoint(relative: relative),
                  let point = consumePoint(relative: relative) else { return false }
            path.addCurve(to: point, control1: control1, control2: control2)
            current = point
            previousCubicControl = control2
            previousQuadraticControl = nil
        case "S", "s":
            guard let control2 = consumePoint(relative: relative),
                  let point = consumePoint(relative: relative) else { return false }
            let control1: CGPoint
            if previousCommand == Character("C").asciiValue ||
                previousCommand == Character("c").asciiValue ||
                previousCommand == Character("S").asciiValue ||
                previousCommand == Character("s").asciiValue,
               let previousCubicControl {
                control1 = CGPoint(
                    x: current.x * 2 - previousCubicControl.x,
                    y: current.y * 2 - previousCubicControl.y
                )
            } else {
                control1 = current
            }
            path.addCurve(to: point, control1: control1, control2: control2)
            current = point
            previousCubicControl = control2
            previousQuadraticControl = nil
        case "Q", "q":
            guard let control = consumePoint(relative: relative),
                  let point = consumePoint(relative: relative) else { return false }
            path.addQuadCurve(to: point, control: control)
            current = point
            previousCubicControl = nil
            previousQuadraticControl = control
        case "T", "t":
            guard let point = consumePoint(relative: relative) else { return false }
            let control: CGPoint
            if previousCommand == Character("Q").asciiValue ||
                previousCommand == Character("q").asciiValue ||
                previousCommand == Character("T").asciiValue ||
                previousCommand == Character("t").asciiValue,
               let previousQuadraticControl {
                control = CGPoint(
                    x: current.x * 2 - previousQuadraticControl.x,
                    y: current.y * 2 - previousQuadraticControl.y
                )
            } else {
                control = current
            }
            path.addQuadCurve(to: point, control: control)
            current = point
            previousCubicControl = nil
            previousQuadraticControl = control
        case "A", "a":
            guard let rx = scanner.consumeNumber(),
                  let ry = scanner.consumeNumber(),
                  let rotation = scanner.consumeNumber(),
                  let largeArc = scanner.consumeNumber(),
                  let sweep = scanner.consumeNumber(),
                  let point = consumePoint(relative: relative) else { return false }
            addArc(
                from: current,
                to: point,
                radius: CGSize(width: rx, height: ry),
                rotation: rotation,
                largeArc: largeArc != 0,
                sweep: sweep != 0
            )
            current = point
            resetControls()
        default:
            return false
        }
        return true
    }

    private mutating func consumePoint(relative: Bool) -> CGPoint? {
        guard let x = scanner.consumeNumber(),
              let y = scanner.consumeNumber() else { return nil }
        let point = CGPoint(x: x, y: y)
        return relative
            ? CGPoint(x: current.x + point.x, y: current.y + point.y)
            : point
    }

    private mutating func resetControls() {
        previousCubicControl = nil
        previousQuadraticControl = nil
    }

    private mutating func addArc(
        from start: CGPoint,
        to end: CGPoint,
        radius: CGSize,
        rotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        var rx = abs(radius.width)
        var ry = abs(radius.height)
        guard start != end else { return }
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) * 0.5
        let dy = (start.y - end.y) * 0.5
        let transformedX = cosPhi * dx + sinPhi * dy
        let transformedY = -sinPhi * dx + cosPhi * dy

        let radiusScale = (transformedX * transformedX) / (rx * rx) +
            (transformedY * transformedY) / (ry * ry)
        if radiusScale > 1 {
            let scale = sqrt(radiusScale)
            rx *= scale
            ry *= scale
        }

        let numerator = max(
            0,
            rx * rx * ry * ry -
                rx * rx * transformedY * transformedY -
                ry * ry * transformedX * transformedX
        )
        let denominator = rx * rx * transformedY * transformedY +
            ry * ry * transformedX * transformedX
        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let coefficient = denominator > 0 ? sign * sqrt(numerator / denominator) : 0
        let centerX = coefficient * rx * transformedY / ry
        let centerY = coefficient * -ry * transformedX / rx
        let center = CGPoint(
            x: cosPhi * centerX - sinPhi * centerY + (start.x + end.x) * 0.5,
            y: sinPhi * centerX + cosPhi * centerY + (start.y + end.y) * 0.5
        )

        let startVector = CGPoint(
            x: (transformedX - centerX) / rx,
            y: (transformedY - centerY) / ry
        )
        let endVector = CGPoint(
            x: (-transformedX - centerX) / rx,
            y: (-transformedY - centerY) / ry
        )
        var startAngle = atan2(startVector.y, startVector.x)
        var delta = atan2(
            startVector.x * endVector.y - startVector.y * endVector.x,
            startVector.x * endVector.x + startVector.y * endVector.y
        )
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }
        let segmentCount = max(1, Int(ceil(abs(delta) / (.pi * 0.5))))
        delta /= CGFloat(segmentCount)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + rx * cosPhi * x - ry * sinPhi * y,
                y: center.y + rx * sinPhi * x + ry * cosPhi * y
            )
        }

        for _ in 0..<segmentCount {
            let endAngle = startAngle + delta
            let alpha = 4.0 / 3.0 * tan(delta * 0.25)
            let startCos = cos(startAngle)
            let startSin = sin(startAngle)
            let endCos = cos(endAngle)
            let endSin = sin(endAngle)
            path.addCurve(
                to: point(endCos, endSin),
                control1: point(startCos - alpha * startSin, startSin + alpha * startCos),
                control2: point(endCos + alpha * endSin, endSin - alpha * endCos)
            )
            startAngle = endAngle
        }
    }
}

private struct SVGPathScanner {
    private var bytes: [UInt8]
    private var index = 0

    init(_ source: String) {
        self.bytes = Array(source.utf8)
    }

    var isAtEnd: Bool {
        var copy = self
        copy.skipSeparators()
        return copy.index >= copy.bytes.count
    }

    var hasNumber: Bool {
        var copy = self
        copy.skipSeparators()
        guard copy.index < copy.bytes.count else { return false }
        let byte = copy.bytes[copy.index]
        return byte == 43 || byte == 45 || byte == 46 || (48...57).contains(byte)
    }

    mutating func consumeCommand() -> UInt8? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        let byte = bytes[index]
        guard (65...90).contains(byte) || (97...122).contains(byte) else { return nil }
        index += 1
        return byte
    }

    mutating func consumeNumber() -> CGFloat? {
        skipSeparators()
        guard index < bytes.count else { return nil }
        let start = index
        if bytes[index] == 43 || bytes[index] == 45 { index += 1 }

        var hasDigit = false
        while index < bytes.count, (48...57).contains(bytes[index]) {
            hasDigit = true
            index += 1
        }
        if index < bytes.count, bytes[index] == 46 {
            index += 1
            while index < bytes.count, (48...57).contains(bytes[index]) {
                hasDigit = true
                index += 1
            }
        }
        guard hasDigit else {
            index = start
            return nil
        }
        if index < bytes.count, bytes[index] == 69 || bytes[index] == 101 {
            let exponentStart = index
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
                index += 1
            }
            let digitsStart = index
            while index < bytes.count, (48...57).contains(bytes[index]) {
                index += 1
            }
            if digitsStart == index { index = exponentStart }
        }
        return Double(String(decoding: bytes[start..<index], as: UTF8.self)).map { CGFloat($0) }
    }

    private mutating func skipSeparators() {
        while index < bytes.count {
            switch bytes[index] {
            case 9, 10, 13, 32, 44:
                index += 1
            default:
                return
            }
        }
    }
}
