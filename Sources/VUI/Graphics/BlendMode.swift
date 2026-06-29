//
//  File: BlendMode.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum BlendMode: Hashable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
    case sourceAtop
    case destinationOver
    case destinationOut
    case plusDarker
    case plusLighter

    var graphicsContextBlendMode: GraphicsContext.BlendMode {
        switch self {
        case .normal:
            return .normal
        case .multiply:
            return .multiply
        case .screen:
            return .screen
        case .overlay:
            return .overlay
        case .darken:
            return .darken
        case .lighten:
            return .lighten
        case .colorDodge:
            return .colorDodge
        case .colorBurn:
            return .colorBurn
        case .softLight:
            return .softLight
        case .hardLight:
            return .hardLight
        case .difference:
            return .difference
        case .exclusion:
            return .exclusion
        case .hue:
            return .hue
        case .saturation:
            return .saturation
        case .color:
            return .color
        case .luminosity:
            return .luminosity
        case .sourceAtop:
            return .sourceAtop
        case .destinationOver:
            return .destinationOver
        case .destinationOut:
            return .destinationOut
        case .plusDarker:
            return .plusDarker
        case .plusLighter:
            return .plusLighter
        }
    }
}
