//
//  File: CustomEventTrace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct CustomEventTrace {
    enum ActionEventType: Hashable {
        case enqueue
        case start
        case finish
        case gestureMetadata

        enum Reason: Hashable {
            case onAppear
            case onChange
            case onDisappear
            case gesture
            case didReleaseButton
            case animationLogicallyCompleted
            case animationRemoved
            case hoverChanged
            case scrollChanged
            case scrollPrefetch
            case signalPrefetch
            case navSelectionUpdate
            case splitSidebarVisibilityChanged
            case preferenceChange
            case onFocusChanged
            case navStackPush
            case navStackPop
        }
    }

    enum InstantiationEventType: Int8, Hashable {
        case assign
        case instantiateBegin
        case instantiateEnd
        case uninstantiateBegin
        case uninstantiateEnd
        case recordNamedProperty

        enum Kind: Int8, Hashable {
            case graph
            case app
            case view
            case gesture
            case widget
        }
    }
}
