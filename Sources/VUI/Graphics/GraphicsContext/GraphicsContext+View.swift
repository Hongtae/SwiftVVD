//
//  File: GraphicsContext+View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    public struct ResolvedSymbol {
        let list: DrawingCommands
        public internal(set) var size: CGSize
    }

    public func resolveSymbol<ID>(id: ID) -> ResolvedSymbol? where ID: Hashable {
        symbols?.symbol(for: id, in: self)
    }

    public func draw(_ symbol: ResolvedSymbol, in rect: CGRect) {
        guard symbol.size.width != 0, symbol.size.height != 0 else { return }
        var context = self
        context.translateBy(x: rect.origin.x, y: rect.origin.y)
        context.scaleBy(
            x: rect.width / symbol.size.width,
            y: rect.height / symbol.size.height
        )
        symbol.list.draw(in: context)
    }

    public func draw(_ symbol: ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(symbol, in: CGRect(
            x: point.x - symbol.size.width * anchor.x,
            y: point.y - symbol.size.height * anchor.y,
            width: symbol.size.width,
            height: symbol.size.height
        ))
    }
}

class GraphicsContextSymbols {
    func symbol<ID: Hashable>(for id: ID, in context: GraphicsContext) -> GraphicsContext.ResolvedSymbol? {
        fatalError("GraphicsContextSymbols requires a concrete symbol renderer.")
    }
}

@available(*, unavailable)
extension GraphicsContext.ResolvedSymbol: Sendable {}
