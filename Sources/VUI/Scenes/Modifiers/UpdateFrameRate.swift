//
//  File: UpdateFrameRate.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Controls whether frames are rendered continuously and whether presentation
/// is synchronized to the display.
public enum FrameRenderingMode: Equatable, Sendable {
    /// Draw every frame and synchronize presentation to the display.
    case continuousWithDisplaySync

    /// Draw every frame without synchronizing presentation to the display.
    case continuousWithoutDisplaySync

    /// Draw only when content changes, synchronizing each presentation.
    case onDemand

    var displaySyncEnabled: Bool {
        switch self {
        case .continuousWithDisplaySync, .onDemand:
            true
        case .continuousWithoutDisplaySync:
            false
        }
    }

    var drawsEveryFrame: Bool {
        switch self {
        case .continuousWithDisplaySync, .continuousWithoutDisplaySync:
            true
        case .onDemand:
            false
        }
    }
}

public struct _UpdateFrameRate: _SceneModifier {
    public typealias Body = Never

    var active: CGFloat
    var inactive: CGFloat
    var renderingMode: FrameRenderingMode

    init(
        active: CGFloat = 60.0,
        inactive: CGFloat? = nil,
        renderingMode: FrameRenderingMode = .continuousWithDisplaySync
    ) {
        self.active = active
        self.inactive = inactive ?? active
        self.renderingMode = renderingMode
    }
    
    public static func _makeScene(modifier: _GraphValue<Self>, inputs: _SceneInputs, body: @escaping (_Graph, _SceneInputs) -> _SceneOutputs) -> _SceneOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeScene called outside an active _AGGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        let configAttr: Attribute<WindowConfiguration.Override> = graph.makeRule {
            let m = modifier._attribute.value
            return WindowConfiguration.Override(
                activeFrameInterval: Double(1.0 / m.active),
                inactiveFrameInterval: Double(1.0 / m.inactive),
                displaySyncEnabled: m.renderingMode.displaySyncEnabled,
                drawEveryFrames: m.renderingMode.drawsEveryFrame
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
    public func updateFrameRate(
        forActiveState active: CGFloat,
        forInactiveState inactive: CGFloat? = nil,
        renderingMode: FrameRenderingMode = .continuousWithDisplaySync
    ) -> some Scene {
        let modifier = _UpdateFrameRate(
            active: active,
            inactive: inactive,
            renderingMode: renderingMode
        )
        return self.modifier(modifier)
    }
}
