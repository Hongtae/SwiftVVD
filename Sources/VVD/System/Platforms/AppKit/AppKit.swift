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
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window? {
        return AppKitWindow(name: name, style: style, delegate: delegate)
    }
}

#endif //if ENABLE_APPKIT
