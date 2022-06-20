//
//  File: SwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol SwapChain {
    var pixelFormat: PixelFormat { get set }
    var maximumBufferCount: UInt { get }

    func currentRenderPassDescriptor() async -> RenderPassDescriptor
    func present(waitEvents: [Event]) -> Bool

    var commandQueue: CommandQueue { get }
}

extension SwapChain {
    @discardableResult
    public func present() -> Bool {
        return present(waitEvents:[])
    }
}
