//
//  File: Headless.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//


public struct PlatformFactoryHeadless: PlatformFactory {

    public func sharedApplication() -> Application? {
        return HeadlessApplication.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return HeadlessApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> (any Window)? {
        return HeadlessWindow(name: name, style: style, delegate: delegate, data: data)
    }

    public func supportedWindowStyles(_ style: WindowStyle) -> WindowStyle {
        []
    }
}
