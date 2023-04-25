//
//  File: GraphicsContext+View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
    public struct ResolvedSymbol {
        public var size: CGSize { .zero }
    }

    public func resolveSymbol<ID>(id: ID) -> ResolvedSymbol? where ID: Hashable {
        fatalError()
    }

    public func draw(_ symbol: ResolvedSymbol, in rect: CGRect) {
        fatalError()
    }
    public func draw(_ symbol: ResolvedSymbol, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
}