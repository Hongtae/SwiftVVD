//
//  File: Wayland.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND

public struct PlatformFactoryWayland: PlatformFactory {

    public func sharedApplication() -> Application? {
        return WaylandApplication.shared
    }

    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return WaylandApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window? {
        return WaylandWindow(name: name, style: style, delegate: delegate)
    }
}

#endif //if ENABLE_WAYLAND
