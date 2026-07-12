//
//  File: Wayland.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation

public struct PlatformFactoryWayland: PlatformFactory {

    public func sharedApplication() -> Application? {
        return WaylandApplication.shared
    }

    @MainActor
    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return WaylandApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) -> (any Window)? {
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

/// Extends Wayland's ordered 32-bit millisecond stream without assuming that
/// its undefined epoch matches the process monotonic clock.
struct MillisecondTimestampExtender {
    private var lastRawValue: UInt32?
    private var extendedMilliseconds: UInt64 = 0

    mutating func timestamp(for rawValue: UInt32) -> TimeInterval {
        if let lastRawValue {
            extendedMilliseconds += UInt64(rawValue &- lastRawValue)
        } else {
            extendedMilliseconds = UInt64(rawValue)
        }
        self.lastRawValue = rawValue
        return TimeInterval(extendedMilliseconds) / 1_000
    }
}

#endif //if ENABLE_WAYLAND
