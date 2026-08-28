//
//  File: DrawDebugInfo.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _DrawDebug: _SceneModifier {
    public typealias Body = Never
    
    public struct Info: OptionSet, Sendable {
        public let rawValue: UInt16
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        
        public static let frameInfo      = Info(rawValue: 1 << 0)
        public static let updateTiming   = Info(rawValue: 1 << 1)
        public static let resourceTiming = Info(rawValue: 1 << 2)
        public static let drawTiming     = Info(rawValue: 1 << 3)
        public static let presentTiming  = Info(rawValue: 1 << 4)
        public static let thread         = Info(rawValue: 1 << 5)
        public static let queue          = Info(rawValue: 1 << 6)
        public static let appState       = Info(rawValue: 1 << 7)
        public static let windowState    = Info(rawValue: 1 << 8)

        public static let all            = Info(rawValue: .max)
    }
    
    let selectedValues: Info
    let placement: DebugInfoPlacement
    
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeScene called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        let configAttr: Attribute<WindowConfiguration.Override> = graph.makeRule {
            let modifier = modifier._attribute.value
            return WindowConfiguration.Override(
                drawDebugInfo: modifier.selectedValues,
                drawDebugInfoPlacement: modifier.placement
            )
        }
        outputs.preferences.append(
            WindowConfiguration.Override.Key.self,
            node: configAttr.identifier
        )
        return outputs
    }
}

extension Scene {
    public func drawDebugInfo(
        _ values: _DrawDebug.Info...,
        alignment: Alignment = .topLeading,
        offset: CGSize = .zero
    ) -> some Scene {
        var info: _DrawDebug.Info = []
        values.forEach { info.formUnion($0) }
        let modifier = _DrawDebug(
            selectedValues: info,
            placement: DebugInfoPlacement(
                alignment: alignment,
                offset: offset
            )
        )
        return self.modifier(modifier)
    }
}

struct DebugInfoPlacement: Equatable, Sendable {
    var alignment: Alignment = .topLeading
    var offset: CGSize = .zero
}

struct DebugInfoLayout {
    static let edgeInset: CGFloat = 5

    static func lineFrames(
        for lineSizes: [CGSize],
        in bounds: CGRect,
        placement: DebugInfoPlacement
    ) -> [CGRect] {
        guard lineSizes.isEmpty == false else {
            return []
        }

        let blockWidth = lineSizes.reduce(CGFloat.zero) {
            max($0, $1.width)
        }
        let blockHeight = lineSizes.reduce(CGFloat.zero) {
            $0 + $1.height
        }
        let fraction = placement.alignment.fraction
        let blockOrigin = CGPoint(
            x: bounds.minX + edgeInset
                + (bounds.width - edgeInset * 2 - blockWidth) * fraction.x
                + placement.offset.width,
            y: bounds.minY + edgeInset
                + (bounds.height - edgeInset * 2 - blockHeight) * fraction.y
                + placement.offset.height
        )

        var lineY = blockOrigin.y
        return lineSizes.map { lineSize in
            let frame = CGRect(
                x: blockOrigin.x
                    + (blockWidth - lineSize.width) * fraction.x,
                y: lineY,
                width: lineSize.width,
                height: lineSize.height
            )
            lineY += lineSize.height
            return frame
        }
    }
}
