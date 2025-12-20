//
//  File: AppKit.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT

public struct PlatformFactoryAppKit: PlatformFactory {

    public func sharedApplication() -> Application? {
        return AppKitApplication.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return AppKitApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> (any Window)? {
        return AppKitWindow(name: name, style: style, delegate: delegate, data: data)
    }

    public func supportedWindowStyles(_ style: WindowStyle) -> WindowStyle {
        style
    }
}

#endif //if ENABLE_APPKIT
