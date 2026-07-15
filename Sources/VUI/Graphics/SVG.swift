//
//  File: SVG.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

#if canImport(FoundationXML)
import FoundationXML
#endif

public struct SVG: Equatable {
    public enum ParsingError: Swift.Error, Equatable {
        case invalidDocument
        case missingViewport
        case invalidViewport
        case invalidPathData
        case invalidAttribute(name: String, value: String)
        case unsupportedPaint(String)
    }

    public enum Paint: Equatable {
        case color(Color)
        case currentColor
        case foregroundStyle
        case backgroundStyle
    }

    public enum Style: Equatable {
        case fill(
            paint: Paint,
            style: FillStyle,
            opacity: Double
        )
        case stroke(
            paint: Paint,
            style: StrokeStyle,
            opacity: Double
        )
    }

    public struct Layer: Equatable {
        public let path: Path
        public let transform: CGAffineTransform
        public let opacity: Double
        public let styles: [Style]

        public init(
            path: Path,
            transform: CGAffineTransform = .identity,
            opacity: Double = 1,
            styles: [Style]
        ) {
            self.path = path
            self.transform = transform
            self.opacity = opacity
            self.styles = styles
        }
    }

    public let viewBox: CGRect
    public let intrinsicSize: CGSize?
    public let layers: [Layer]

    public init(
        viewBox: CGRect,
        intrinsicSize: CGSize? = nil,
        layers: [Layer]
    ) {
        self.viewBox = viewBox
        self.intrinsicSize = intrinsicSize
        self.layers = layers
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        let document = SVGDocumentParser()
        let parser = XMLParser(data: data)
        parser.delegate = document
        parser.shouldResolveExternalEntities = false

        guard parser.parse(), document.failure == nil else {
            throw document.failure ?? .invalidDocument
        }
        guard let viewBox = document.viewBox else {
            throw ParsingError.missingViewport
        }
        guard viewBox.width > 0, viewBox.height > 0 else {
            throw ParsingError.invalidViewport
        }
        self.init(
            viewBox: viewBox,
            intrinsicSize: document.intrinsicSize,
            layers: document.layers
        )
    }

    public init(source: String) throws {
        try self.init(data: Data(source.utf8))
    }
}

private final class SVGDocumentParser: NSObject, XMLParserDelegate {
    private struct State {
        var fill: SVG.Paint? = .color(.black)
        var stroke: SVG.Paint?
        var currentColor: SVG.Paint = .currentColor
        var fillOpacity = 1.0
        var strokeOpacity = 1.0
        var isEOFilled = false
        var strokeStyle = StrokeStyle()
        var transform = CGAffineTransform.identity
        var opacity = 1.0
        var isVisible = true
    }

    var viewBox: CGRect?
    var intrinsicSize: CGSize?
    var layers: [SVG.Layer] = []
    var failure: SVG.ParsingError?

    private var states: [State] = []
    private var foundRoot = false
    private var styleSheetText: String?
    private var classStyleRules: [(name: String, declarations: [String: String])] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard failure == nil else { return }

        let name = localName(qName ?? elementName)
        let attributes = normalizedAttributes(attributeDict)
        if !foundRoot {
            guard name == "svg" else {
                fail(.invalidDocument, parser: parser)
                return
            }
            foundRoot = true
            guard parseViewport(attributes, parser: parser) else { return }
        }

        var state = states.last ?? State()
        guard apply(attributes, to: &state, parser: parser) else { return }

        if ["defs", "clippath", "mask", "symbol"].contains(name) {
            state.isVisible = false
        }
        states.append(state)

        if name == "style" {
            styleSheetText = ""
            return
        }

        guard state.isVisible,
              let path = makePath(
                element: name,
                attributes: attributes,
                parser: parser
              ) else {
            return
        }
        guard !path.isEmpty else { return }

        var styles: [SVG.Style] = []
        if let fill = state.fill, state.fillOpacity > 0 {
            styles.append(.fill(
                paint: resolvedCurrentColor(fill, in: state),
                style: FillStyle(eoFill: state.isEOFilled),
                opacity: state.fillOpacity
            ))
        }
        if let stroke = state.stroke,
           state.strokeOpacity > 0,
           state.strokeStyle.lineWidth > 0 {
            styles.append(.stroke(
                paint: resolvedCurrentColor(stroke, in: state),
                style: state.strokeStyle,
                opacity: state.strokeOpacity
            ))
        }
        guard !styles.isEmpty else { return }
        layers.append(SVG.Layer(
            path: path,
            transform: state.transform,
            opacity: state.opacity,
            styles: styles
        ))
    }

    private func makePath(
        element name: String,
        attributes: [String: String],
        parser: XMLParser
    ) -> Path? {
        switch name {
        case "path":
            guard let data = attributes["d"] else { return nil }
            var pathParser = SVGPathDataParser(data)
            guard let path = pathParser.parse() else {
                fail(.invalidPathData, parser: parser)
                return nil
            }
            return path

        case "rect":
            guard let width = length("width", in: attributes, default: nil, parser: parser),
                  let height = length("height", in: attributes, default: nil, parser: parser),
                  width >= 0, height >= 0 else {
                return nil
            }
            guard width > 0, height > 0 else { return Path() }
            guard let x = length("x", in: attributes, default: 0, parser: parser),
                  let y = length("y", in: attributes, default: 0, parser: parser) else {
                return nil
            }
            let parsedRX = length("rx", in: attributes, default: nil, parser: parser)
            let parsedRY = length("ry", in: attributes, default: nil, parser: parser)
            if failure != nil { return nil }
            let rx = min(max(parsedRX ?? parsedRY ?? 0, 0), width * 0.5)
            let ry = min(max(parsedRY ?? parsedRX ?? 0, 0), height * 0.5)
            let rect = CGRect(x: x, y: y, width: width, height: height)
            return rx > 0 || ry > 0
                ? Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: ry))
                : Path(rect)

        case "circle":
            guard let radius = length("r", in: attributes, default: nil, parser: parser),
                  radius >= 0,
                  let x = length("cx", in: attributes, default: 0, parser: parser),
                  let y = length("cy", in: attributes, default: 0, parser: parser) else {
                return nil
            }
            guard radius > 0 else { return Path() }
            return Path(ellipseIn: CGRect(
                x: x - radius,
                y: y - radius,
                width: radius * 2,
                height: radius * 2
            ))

        case "ellipse":
            guard let rx = length("rx", in: attributes, default: nil, parser: parser),
                  let ry = length("ry", in: attributes, default: nil, parser: parser),
                  rx >= 0, ry >= 0,
                  let x = length("cx", in: attributes, default: 0, parser: parser),
                  let y = length("cy", in: attributes, default: 0, parser: parser) else {
                return nil
            }
            guard rx > 0, ry > 0 else { return Path() }
            return Path(ellipseIn: CGRect(
                x: x - rx,
                y: y - ry,
                width: rx * 2,
                height: ry * 2
            ))

        case "line":
            guard let x1 = length("x1", in: attributes, default: 0, parser: parser),
                  let y1 = length("y1", in: attributes, default: 0, parser: parser),
                  let x2 = length("x2", in: attributes, default: 0, parser: parser),
                  let y2 = length("y2", in: attributes, default: 0, parser: parser) else {
                return nil
            }
            return Path { path in
                path.move(to: CGPoint(x: x1, y: y1))
                path.addLine(to: CGPoint(x: x2, y: y2))
            }

        case "polyline", "polygon":
            guard let value = attributes["points"] else { return nil }
            let values = SVGNumberList(value).values
            guard values.count >= 4, values.count.isMultiple(of: 2) else {
                fail(.invalidAttribute(name: "points", value: value), parser: parser)
                return nil
            }
            return Path { path in
                path.move(to: CGPoint(x: values[0], y: values[1]))
                for index in stride(from: 2, to: values.count, by: 2) {
                    path.addLine(to: CGPoint(x: values[index], y: values[index + 1]))
                }
                if name == "polygon" {
                    path.closeSubpath()
                }
            }

        default:
            return nil
        }
    }

    private func length(
        _ name: String,
        in attributes: [String: String],
        default defaultValue: CGFloat?,
        parser: XMLParser
    ) -> CGFloat? {
        guard let value = attributes[name] else { return defaultValue }
        guard let result = parseLength(value) else {
            fail(.invalidAttribute(name: name, value: value), parser: parser)
            return nil
        }
        return result
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if localName(qName ?? elementName) == "style", let styleSheetText {
            appendClassStyleRules(from: styleSheetText)
            self.styleSheetText = nil
        }
        if !states.isEmpty {
            states.removeLast()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleSheetText != nil {
            styleSheetText!.append(string)
        }
    }

    private func parseViewport(
        _ attributes: [String: String],
        parser: XMLParser
    ) -> Bool {
        let width = attributes["width"].flatMap(parseLength)
        let height = attributes["height"].flatMap(parseLength)
        if let width, let height, width > 0, height > 0 {
            intrinsicSize = CGSize(width: width, height: height)
        }

        if let value = attributes["viewbox"] {
            let components = SVGNumberList(value).values
            guard components.count == 4 else {
                fail(.invalidViewport, parser: parser)
                return false
            }
            viewBox = CGRect(
                x: components[0],
                y: components[1],
                width: components[2],
                height: components[3]
            )
        } else if let intrinsicSize {
            viewBox = CGRect(origin: .zero, size: intrinsicSize)
        } else {
            fail(.missingViewport, parser: parser)
            return false
        }

        guard let viewBox, viewBox.width > 0, viewBox.height > 0 else {
            fail(.invalidViewport, parser: parser)
            return false
        }
        return true
    }

    private func apply(
        _ rawAttributes: [String: String],
        to state: inout State,
        parser: XMLParser
    ) -> Bool {
        var attributes = rawAttributes
        let classNames = Set(
            rawAttributes["class"]?
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init) ?? []
        )
        for rule in classStyleRules where classNames.contains(rule.name) {
            attributes.merge(rule.declarations) { _, new in new }
        }
        if let inlineStyle = rawAttributes["style"] {
            attributes.merge(parseDeclarations(inlineStyle)) { _, new in new }
        }

        if let value = attributes["transform"] {
            var transformParser = SVGTransformParser(value)
            guard let transform = transformParser.parse() else {
                fail(.invalidAttribute(name: "transform", value: value), parser: parser)
                return false
            }
            state.transform = transform.concatenating(state.transform)
        }

        if let value = attributes["opacity"] {
            guard let opacity = parseOpacity(value) else {
                fail(.invalidAttribute(name: "opacity", value: value), parser: parser)
                return false
            }
            state.opacity *= opacity
        }
        if let value = attributes["display"], value.lowercased() == "none" {
            state.isVisible = false
        }
        if let value = attributes["visibility"],
           ["hidden", "collapse"].contains(value.lowercased()) {
            state.isVisible = false
        }

        if let value = attributes["color"], value.lowercased() != "inherit" {
            guard let color = parsePaint(value) else {
                fail(.unsupportedPaint(value), parser: parser)
                return false
            }
            state.currentColor = color
        }
        if let value = attributes["fill"], value.lowercased() != "inherit" {
            guard let fill = parseOptionalPaint(value) else {
                fail(.unsupportedPaint(value), parser: parser)
                return false
            }
            state.fill = fill
        }
        if let value = attributes["stroke"], value.lowercased() != "inherit" {
            guard let stroke = parseOptionalPaint(value) else {
                fail(.unsupportedPaint(value), parser: parser)
                return false
            }
            state.stroke = stroke
        }
        if let value = attributes["fill-opacity"] {
            guard let opacity = parseOpacity(value) else {
                fail(.invalidAttribute(name: "fill-opacity", value: value), parser: parser)
                return false
            }
            state.fillOpacity = opacity
        }
        if let value = attributes["stroke-opacity"] {
            guard let opacity = parseOpacity(value) else {
                fail(.invalidAttribute(name: "stroke-opacity", value: value), parser: parser)
                return false
            }
            state.strokeOpacity = opacity
        }
        if let value = attributes["fill-rule"] {
            switch value.lowercased() {
            case "nonzero": state.isEOFilled = false
            case "evenodd": state.isEOFilled = true
            default:
                fail(.invalidAttribute(name: "fill-rule", value: value), parser: parser)
                return false
            }
        }

        if let value = attributes["stroke-width"] {
            guard let width = parseLength(value), width >= 0 else {
                fail(.invalidAttribute(name: "stroke-width", value: value), parser: parser)
                return false
            }
            state.strokeStyle.lineWidth = width
        }
        if let value = attributes["stroke-linecap"] {
            switch value.lowercased() {
            case "butt": state.strokeStyle.lineCap = .butt
            case "round": state.strokeStyle.lineCap = .round
            case "square": state.strokeStyle.lineCap = .square
            default:
                fail(.invalidAttribute(name: "stroke-linecap", value: value), parser: parser)
                return false
            }
        }
        if let value = attributes["stroke-linejoin"] {
            switch value.lowercased() {
            case "miter", "miter-clip", "arcs": state.strokeStyle.lineJoin = .miter
            case "round": state.strokeStyle.lineJoin = .round
            case "bevel": state.strokeStyle.lineJoin = .bevel
            default:
                fail(.invalidAttribute(name: "stroke-linejoin", value: value), parser: parser)
                return false
            }
        }
        if let value = attributes["stroke-miterlimit"] {
            guard let limit = Double(value), limit >= 1 else {
                fail(.invalidAttribute(name: "stroke-miterlimit", value: value), parser: parser)
                return false
            }
            state.strokeStyle.miterLimit = CGFloat(limit)
        }
        if let value = attributes["stroke-dasharray"] {
            if value.lowercased() == "none" {
                state.strokeStyle.dash = []
            } else {
                let values = SVGNumberList(value).values
                guard !values.isEmpty, values.allSatisfy({ $0 >= 0 }) else {
                    fail(.invalidAttribute(name: "stroke-dasharray", value: value), parser: parser)
                    return false
                }
                state.strokeStyle.dash = values
            }
        }
        if let value = attributes["stroke-dashoffset"] {
            guard let offset = parseLength(value) else {
                fail(.invalidAttribute(name: "stroke-dashoffset", value: value), parser: parser)
                return false
            }
            state.strokeStyle.dashPhase = offset
        }
        return true
    }

    private func appendClassStyleRules(from source: String) {
        let source = source.replacingOccurrences(
            of: #"/\*.*?\*/"#,
            with: "",
            options: .regularExpression
        )
        for rule in source.split(separator: "}") {
            let pair = rule.split(separator: "{", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let declarations = parseDeclarations(String(pair[1]))
            guard !declarations.isEmpty else { continue }
            for selector in pair[0].split(separator: ",") {
                let selector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
                guard selector.first == ".", selector.dropFirst().allSatisfy({
                    $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
                }) else {
                    continue
                }
                classStyleRules.append((String(selector.dropFirst()), declarations))
            }
        }
    }

    private func parseDeclarations(_ source: String) -> [String: String] {
        var declarations: [String: String] = [:]
        for declaration in source.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            declarations[name] = value
        }
        return declarations
    }

    private func resolvedCurrentColor(_ paint: SVG.Paint, in state: State) -> SVG.Paint {
        paint == .currentColor ? state.currentColor : paint
    }

    private func normalizedAttributes(_ attributes: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: attributes.map {
            (localName($0.key), $0.value.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private func fail(_ error: SVG.ParsingError, parser: XMLParser) {
        failure = error
        parser.abortParsing()
    }
}

private func parseOptionalPaint(_ source: String) -> SVG.Paint?? {
    if source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "none" {
        return .some(nil)
    }
    return parsePaint(source).map(Optional.some)
}

private func parsePaint(_ source: String) -> SVG.Paint? {
    let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
    switch value.lowercased() {
    case "currentcolor": return .currentColor
    case "foregroundstyle": return .foregroundStyle
    case "backgroundstyle": return .backgroundStyle
    case "transparent": return .color(.clear)
    default: break
    }

    if let color = parseHexColor(value) ?? parseFunctionalColor(value) ?? parseNamedColor(value) {
        return .color(color)
    }
    return nil
}

private func parseHexColor(_ source: String) -> Color? {
    guard source.first == "#" else { return nil }
    let digits = String(source.dropFirst())
    guard let value = UInt64(digits, radix: 16) else { return nil }

    let components: (UInt64, UInt64, UInt64, UInt64)
    switch digits.count {
    case 3:
        components = (
            ((value >> 8) & 0xf) * 17,
            ((value >> 4) & 0xf) * 17,
            (value & 0xf) * 17,
            255
        )
    case 4:
        components = (
            ((value >> 12) & 0xf) * 17,
            ((value >> 8) & 0xf) * 17,
            ((value >> 4) & 0xf) * 17,
            (value & 0xf) * 17
        )
    case 6:
        components = (
            (value >> 16) & 0xff,
            (value >> 8) & 0xff,
            value & 0xff,
            255
        )
    case 8:
        components = (
            (value >> 24) & 0xff,
            (value >> 16) & 0xff,
            (value >> 8) & 0xff,
            value & 0xff
        )
    default:
        return nil
    }
    return Color(
        .sRGB,
        red: Double(components.0) / 255,
        green: Double(components.1) / 255,
        blue: Double(components.2) / 255,
        opacity: Double(components.3) / 255
    )
}

private func parseFunctionalColor(_ source: String) -> Color? {
    let lowercased = source.lowercased()
    let isRGBA = lowercased.hasPrefix("rgba(")
    guard isRGBA || lowercased.hasPrefix("rgb("), source.last == ")" else {
        return nil
    }
    let start = source.index(source.startIndex, offsetBy: isRGBA ? 5 : 4)
    let values = source[start..<source.index(before: source.endIndex)]
        .split(whereSeparator: { $0 == "," || $0.isWhitespace })
    guard values.count == (isRGBA ? 4 : 3) else { return nil }

    func channel(_ value: Substring) -> Double? {
        if value.last == "%" {
            return Double(value.dropLast()).map { min(max($0 / 100, 0), 1) }
        }
        return Double(value).map { min(max($0 / 255, 0), 1) }
    }
    func alpha(_ value: Substring) -> Double? {
        if value.last == "%" {
            return Double(value.dropLast()).map { min(max($0 / 100, 0), 1) }
        }
        return Double(value).map { min(max($0, 0), 1) }
    }

    guard let red = channel(values[0]),
          let green = channel(values[1]),
          let blue = channel(values[2]),
          let opacity = isRGBA ? alpha(values[3]) : 1 else {
        return nil
    }
    return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
}

private func parseNamedColor(_ source: String) -> Color? {
    let rgb: UInt32
    switch source.lowercased() {
    case "black": rgb = 0x000000
    case "silver": rgb = 0xc0c0c0
    case "gray", "grey": rgb = 0x808080
    case "white": rgb = 0xffffff
    case "maroon": rgb = 0x800000
    case "red": rgb = 0xff0000
    case "purple": rgb = 0x800080
    case "fuchsia", "magenta": rgb = 0xff00ff
    case "green": rgb = 0x008000
    case "lime": rgb = 0x00ff00
    case "olive": rgb = 0x808000
    case "yellow": rgb = 0xffff00
    case "navy": rgb = 0x000080
    case "blue": rgb = 0x0000ff
    case "teal": rgb = 0x008080
    case "aqua", "cyan": rgb = 0x00ffff
    default: return nil
    }
    return Color(
        .sRGB,
        red: Double((rgb >> 16) & 0xff) / 255,
        green: Double((rgb >> 8) & 0xff) / 255,
        blue: Double(rgb & 0xff) / 255
    )
}

private func parseOpacity(_ source: String) -> Double? {
    let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.last == "%" {
        return Double(value.dropLast()).map { min(max($0 / 100, 0), 1) }
    }
    return Double(value).map { min(max($0, 0), 1) }
}

private func parseLength(_ source: String) -> CGFloat? {
    var value = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.hasSuffix("px") {
        value.removeLast(2)
    }
    guard !value.hasSuffix("%"), let length = Double(value) else { return nil }
    return CGFloat(length)
}

private struct SVGTransformParser {
    private var scanner: SVGTransformScanner

    init(_ source: String) {
        self.scanner = SVGTransformScanner(source)
    }

    mutating func parse() -> CGAffineTransform? {
        var result = CGAffineTransform.identity
        while !scanner.isAtEnd {
            guard let name = scanner.consumeIdentifier(),
                  scanner.consume(40) else {
                return nil
            }
            var values: [CGFloat] = []
            while !scanner.nextIs(41) {
                guard let value = scanner.consumeNumber() else { return nil }
                values.append(value)
            }
            guard scanner.consume(41),
                  let transform = transform(named: name, values: values) else {
                return nil
            }
            result = transform.concatenating(result)
        }
        return result
    }

    private func transform(
        named name: String,
        values: [CGFloat]
    ) -> CGAffineTransform? {
        switch name.lowercased() {
        case "matrix" where values.count == 6:
            return CGAffineTransform(
                a: values[0], b: values[1],
                c: values[2], d: values[3],
                tx: values[4], ty: values[5]
            )
        case "translate" where values.count == 1 || values.count == 2:
            return CGAffineTransform(
                translationX: values[0],
                y: values.count == 2 ? values[1] : 0
            )
        case "scale" where values.count == 1 || values.count == 2:
            return CGAffineTransform(
                scaleX: values[0],
                y: values.count == 2 ? values[1] : values[0]
            )
        case "rotate" where values.count == 1:
            return CGAffineTransform(rotationAngle: values[0] * .pi / 180)
        case "rotate" where values.count == 3:
            return CGAffineTransform(translationX: -values[1], y: -values[2])
                .concatenating(CGAffineTransform(rotationAngle: values[0] * .pi / 180))
                .concatenating(CGAffineTransform(translationX: values[1], y: values[2]))
        case "skewx" where values.count == 1:
            return CGAffineTransform(
                a: 1, b: 0,
                c: tan(values[0] * .pi / 180), d: 1,
                tx: 0, ty: 0
            )
        case "skewy" where values.count == 1:
            return CGAffineTransform(
                a: 1, b: tan(values[0] * .pi / 180),
                c: 0, d: 1,
                tx: 0, ty: 0
            )
        default:
            return nil
        }
    }
}

private struct SVGTransformScanner {
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

    mutating func consumeIdentifier() -> String? {
        skipSeparators()
        let start = index
        while index < bytes.count,
              (65...90).contains(bytes[index]) || (97...122).contains(bytes[index]) {
            index += 1
        }
        guard start < index else { return nil }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func consumeNumber() -> CGFloat? {
        skipSeparators()
        let start = index
        if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
            index += 1
        }
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
            let exponent = index
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
                index += 1
            }
            let digitStart = index
            while index < bytes.count, (48...57).contains(bytes[index]) {
                index += 1
            }
            if digitStart == index { index = exponent }
        }
        return Double(String(decoding: bytes[start..<index], as: UTF8.self)).map { CGFloat($0) }
    }

    mutating func nextIs(_ byte: UInt8) -> Bool {
        skipSeparators()
        return index < bytes.count && bytes[index] == byte
    }

    mutating func consume(_ byte: UInt8) -> Bool {
        skipSeparators()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
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

struct SVGNumberList {
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
