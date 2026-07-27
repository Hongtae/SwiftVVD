//
//  File: SymbolImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ResolvedVectorSymbol: Equatable {
    struct DrawPathInterval: Equatable {
        var from: Double
        var to: Double

        init(from: Double, to: Double) {
            self.from = min(max(from, 0), 1)
            self.to = min(max(to, self.from), 1)
        }
    }

    struct DrawMotionGroupTiming: Equatable {
        var pathDuration: Double?
        var opacityDuration: Double?

        var duration: Double {
            max(pathDuration ?? 0, opacityDuration ?? 0)
        }
    }

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

            func clipPath(from: Double, to: Double) -> Path {
                let lowerBound = min(max(from, 0), 1)
                let upperBound = min(max(to, lowerBound), 1)
                let totalLength = strokeLength
                guard upperBound > lowerBound, totalLength > 0 else {
                    return Path()
                }

                let intervalStart = CGFloat(lowerBound) * totalLength
                let intervalEnd = CGFloat(upperBound) * totalLength
                var guideStart: CGFloat = 0
                var result = Path()
                for guide in guides {
                    let length = guide.path.approximateLength
                    guard length > 0 else { continue }
                    let guideEnd = guideStart + length
                    let overlapStart = max(intervalStart, guideStart)
                    let overlapEnd = min(intervalEnd, guideEnd)
                    if overlapEnd > overlapStart {
                        let localStart = (overlapStart - guideStart) / length
                        let localEnd = (overlapEnd - guideStart) / length
                        let path = guide.path.trimmedPath(
                            from: localStart,
                            to: localEnd
                        )
                        result.addPath(path.strokedPath(guide.strokeStyle))
                    }
                    guideStart = guideEnd
                    if guideStart >= intervalEnd {
                        break
                    }
                }
                return result
            }

            func clipBoundaryOpacities(
                progress: Double,
                reversed: Bool
            ) -> (reveal: Double, completion: Double) {
                let progress = min(max(progress, 0), 1)
                let totalLength = strokeLength
                guard totalLength > 0, !guides.isEmpty else {
                    return (progress > 0 ? 1 : 0, progress >= 1 ? 1 : 0)
                }

                let startGuide = reversed ? guides.last! : guides.first!
                let endGuide = reversed ? guides.first! : guides.last!
                let minimumFadeLength = CGFloat.ulpOfOne.squareRoot()
                let startFadeLength = max(
                    startGuide.strokeStyle.lineWidth * 0.5,
                    minimumFadeLength
                )
                let endFadeLength = max(
                    endGuide.strokeStyle.lineWidth * 0.5,
                    minimumFadeLength
                )
                let revealedLength = CGFloat(progress) * totalLength
                let remainingLength = CGFloat(1 - progress) * totalLength
                return (
                    reveal: min(max(Double(revealedLength / startFadeLength), 0), 1),
                    completion: min(
                        max(Double(1 - remainingLength / endFadeLength), 0),
                        1
                    )
                )
            }
        }

        var path: Path
        var opacity: Double
        var isEOFilled: Bool
        var semanticLevel: Int
        var effectLevel: Int
        // Replacement grouping is independent of pulse-effect grouping.
        var replacementLevel: Int
        // A nil level keeps the path outside the variable-color animator.
        var variableColorLevel: Int?
        // Draw geometry is asset metadata, independent of visible fill order.
        var draw: DrawData?
    }

    var identity: Identity
    var viewport: CGRect
    var layers: [Layer]
    var artworkBounds: CGRect
    var intrinsicScale: CGFloat = 1

    func applyingEffectiveFontMetrics(
        in environment: EnvironmentValues
    ) -> Self {
        var result = self
        let font = environment.font ?? .system(.body)
        guard let pointSize = font.pointSizeForSymbolMetrics,
              pointSize.isFinite,
              pointSize >= 0 else {
            return result
        }

        guard !artworkBounds.isNull,
              artworkBounds.height.isFinite,
              artworkBounds.height > 0 else {
            return result
        }

        // Portable assets keep their source viewport, while the effective
        // font controls the visible vertical ink. The catalog paths used here
        // occupy a smaller region than their 24-unit design viewport.
        let targetInkHeight = pointSize * 0.9
        result.intrinsicScale = targetInkHeight / artworkBounds.height
        return result
    }

    var variableColorLevelCount: Int {
        layers.compactMap(\.variableColorLevel).max().map { $0 + 1 } ?? 0
    }

    var replacementLevelCount: Int {
        layers.map(\.replacementLevel).max().map { $0 + 1 } ?? 0
    }

    var drawMotionGroupCount: Int {
        layers.compactMap { $0.draw?.motionGroup }.max().map { $0 + 1 } ?? 0
    }

    var drawMotionGroupDurations: [Double] {
        drawMotionGroupTimings(appearing: false).map(\.duration)
    }

    func drawMotionGroupTimings(
        appearing: Bool
    ) -> [DrawMotionGroupTiming] {
        var timings = [DrawMotionGroupTiming](
            repeating: DrawMotionGroupTiming(
                pathDuration: nil,
                opacityDuration: nil
            ),
            count: drawMotionGroupCount
        )
        let glyphSize = max(viewport.width, viewport.height)
        guard glyphSize > 0 else { return timings }
        for layer in layers {
            guard let draw = layer.draw else { continue }
            if draw.guides.isEmpty {
                let duration = appearing ? 1.0 / 4.0 : 1.0 / 6.0
                timings[draw.motionGroup].opacityDuration = max(
                    timings[draw.motionGroup].opacityDuration ?? 0,
                    duration
                )
                continue
            }
            let normalizedLength = min(
                max(Double(draw.strokeLength / glyphSize) * 0.171821311, 0),
                1
            )
            let duration = 2.0 / 15.0 +
                13.0 / 15.0 * normalizedLength * (2 - normalizedLength)
            timings[draw.motionGroup].pathDuration = max(
                timings[draw.motionGroup].pathDuration ?? 0,
                duration
            )
        }
        return timings
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
    var replacementLevels: [Int]?
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
                replacementLevel: 0,
                variableColorLevel: nil,
                draw: nil
            ))
        }
        guard !layers.isEmpty else { return nil }
        if let metadata {
            guard metadata.semanticLevels.count == layers.count,
                  metadata.effectLevels.count == layers.count,
                  metadata.replacementLevels?.count == layers.count ||
                    metadata.replacementLevels == nil,
                  metadata.variableColorLevels?.count == layers.count ||
                    metadata.variableColorLevels == nil,
                  metadata.drawLayers?.count == layers.count ||
                    metadata.drawLayers == nil,
                  metadata.semanticLevels.allSatisfy({ $0 >= 0 }),
                  metadata.effectLevels.allSatisfy({ $0 >= 0 }),
                  metadata.replacementLevels?.allSatisfy({ $0 >= 0 }) != false,
                  metadata.variableColorLevels?.allSatisfy({
                    $0.map { $0 >= 0 } ?? true
                  }) != false,
                  metadata.drawLayers?.allSatisfy({
                    $0.map { $0.motionGroup >= 0 } ?? true
                  }) != false else {
                return nil
            }
            for index in layers.indices {
                layers[index].semanticLevel = metadata.semanticLevels[index]
                layers[index].effectLevel = metadata.effectLevels[index]
                layers[index].replacementLevel =
                    metadata.replacementLevels?[index] ?? 0
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
        let artworkBounds = layers.reduce(CGRect.null) {
            $0.union($1.path.boundingRect)
        }
        return ResolvedVectorSymbol(
            identity: identity,
            viewport: viewport,
            layers: layers,
            artworkBounds: artworkBounds
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
