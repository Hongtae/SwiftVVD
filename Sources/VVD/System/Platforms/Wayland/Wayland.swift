//
//  File: Wayland.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND

public struct PlatformFactoryWayland: PlatformFactory {

    public func sharedApplication() -> Application? {
        return WaylandApplication.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return WaylandApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> Window? {
        return WaylandWindow(name: name, style: style, delegate: delegate, data: data)
    }

    public func supportedWindowStyles(_ style: WindowStyle) -> WindowStyle {    
        var supported: WindowStyle = [.autoResize]
        if let app = WaylandApplication.shared {
            if app.decorationManager != nil {
                supported.formUnion([
                    .title, .closeButton, .minimizeButton, .maximizeButton, .resizableBorder
                ])
            }
        }
        return style.intersection(supported)
    }
}

#endif //if ENABLE_WAYLAND
