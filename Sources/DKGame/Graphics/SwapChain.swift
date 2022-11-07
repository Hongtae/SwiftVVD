//
//  File: SwapChain.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol SwapChain {
    var pixelFormat: PixelFormat { get set }
    var maximumBufferCount: Int { get }

    func currentRenderPassDescriptor() -> RenderPassDescriptor
    func present(waitEvents: [Event]) async -> Bool

    var commandQueue: CommandQueue { get }
}

extension SwapChain {
    @discardableResult
    public func present() async -> Bool {
        return await present(waitEvents:[])
    }
}
