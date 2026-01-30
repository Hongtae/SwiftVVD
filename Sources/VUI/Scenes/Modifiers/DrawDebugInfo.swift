//
//  File: DrawDebugInfo.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _DrawDebug: _SceneModifier {
    public typealias Body = Never
    
    public struct Info: OptionSet, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
        
        public static let fps          = Info(rawValue: 1 << 0)
        public static let thread       = Info(rawValue: 1 << 1)
        public static let queue        = Info(rawValue: 1 << 2)
        public static let appState     = Info(rawValue: 1 << 4)
        public static let windowState  = Info(rawValue: 1 << 5)

        public static let all          = Info(rawValue: .max)
    }
    
    let selectedValues: Info
    
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        var inputs = inputs
        inputs.setModifierTypeGraph(modifier)
        return body(_Graph(), inputs)
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
