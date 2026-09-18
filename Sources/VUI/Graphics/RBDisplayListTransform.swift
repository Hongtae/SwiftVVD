//
//  File: RBDisplayListTransform.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

final class RBDisplayListTransform: NSObject, NSCopying {
    private struct Replacement {
        let from: RecordedColor
        let to: RecordedColor
    }
    private var replacements: [Replacement] = []

    func addColorReplacement(from: SIMD4<Float>, to: SIMD4<Float>, colorSpace: RBColorSpace) {
        precondition((0..<4).allSatisfy { to[$0] != -32768 },
            "Replacement-side wildcard channels are not implemented.")
        replacements.append(Replacement(from: RecordedColor(from, colorSpace: colorSpace),
                                        to: RecordedColor(to, colorSpace: colorSpace)))
    }

    func removeAll() { replacements.removeAll() }

    func copy(with zone: NSZone? = nil) -> Any {
        let copy = RBDisplayListTransform()
        copy.replacements = replacements
        return copy
    }

    private func applying(to item: RBDisplayList.Item) -> RBDisplayList.Item {
        var item = item
        if case let .layer(contents, frame) = item.contents {
            item.contents = .layer(RBMovedDisplayListContents(items: contents.items.map { applying(to: $0) }), frame: frame)
        } else if var color = item.color {
            var changed = false
            for replacement in replacements where replacement.from.matches(color) {
                var next = replacement.to
                if replacement.from.components.w == -32768 {
                    next.components.w = Float(Float16(color.components.w * next.components.w))
                }
                color = next
                changed = true
            }
            if changed {
                item.color = color
                item.replaceShading(.color(Color(color.resolved)))
            }
        }
        return item
    }

    func copyApplyingToDisplayList(_ contents: any RBDisplayListContents) -> any RBDisplayListContents {
        let items = recordedItems(in: contents)
        for item in items { item.requireColorOperations() }
        if items.isEmpty { return RBEmptyDisplayListContents() }
        return RBMovedDisplayListContents(items: items.map { applying(to: $0) })
    }
}
