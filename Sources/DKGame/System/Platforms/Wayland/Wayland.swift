//
//  File: Wayland.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND

public struct PlatformFactoryWayland: PlatformFactory {

    public func sharedApplication() -> Application? {
        return nil
    }

    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        fatalError("Not implemented yet.")
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window? {
        return nil
    }
}

#endif //if ENABLE_UIKIT
