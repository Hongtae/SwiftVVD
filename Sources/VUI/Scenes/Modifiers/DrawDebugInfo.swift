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
    
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeScene called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        let configAttr: Attribute<WindowConfiguration.Override> = graph.makeRule {
            WindowConfiguration.Override(
                drawDebugInfo: modifier._attribute.value.selectedValues
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
    public func drawDebugInfo(_ values: _DrawDebug.Info...) -> some Scene {
        var info: _DrawDebug.Info = []
        values.forEach { info.formUnion($0) }
        let modifier = _DrawDebug(selectedValues: info)
        return self.modifier(modifier)
    }
}
