//
//  File: DebugLayout.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Layout debug overlay infrastructure.
// Enable via .environment(\._debugLayout, true) on any view subtree.

private struct DebugLayoutKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var _debugLayout: Bool {
        get { self[DebugLayoutKey.self] }
        set { self[DebugLayoutKey.self] = newValue }
    }
}

// The semantic role of a view node — determines border color in debug overlays.
enum DebugLayoutCategory {
    case primitiveView   // Text, Image, Color, Canvas, _ShapeView, ...
    case layoutContainer // VStack, HStack, ZStack, AnyLayout, ...
    case layoutModifier  // _PaddingLayout, _FrameLayout, _FixedSizeLayout, ...

    var debugColor: Color {
        switch self {
        case .primitiveView:   return Color(red: 1.0, green: 0.3, blue: 0.3)  // red
        case .layoutContainer: return Color(red: 0.2, green: 0.5, blue: 1.0)  // blue
        case .layoutModifier:  return Color(red: 0.2, green: 0.8, blue: 0.4)  // green
        }
    }
}

// Appends a debug border rect to `dl.debugItems`.
// Call this inside a DisplayList AG rule, after reading `debugOn` and `frame`
// from their respective Attribute nodes (which registers the AG dependencies).
//
// Usage:
//   graph.makeRule {
//       let frame = placedFrameAttr.value
//       let debugOn = debugEnvAttr.value
//       var dl = DisplayList()
//       // ... content items ...
//       if debugOn {
//           appendDebugOverlay(to: &dl, frame: frame, category: .primitiveView)
//       }
//       return dl
//   }
func appendDebugOverlay(
    to dl: inout DisplayList,
    frame: CGRect,
    category: DebugLayoutCategory
) {
    let color = category.debugColor
    dl.debugItems.append { ctx in
        ctx.stroke(Path(CGRect(origin: frame.origin, size: frame.size)),
                   with: .color(color),
                   lineWidth: 1)
    }
}
