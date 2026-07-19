//
//  File: SceneList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//


// Namespace for scene list grouping. .app covers all WindowGroup/Window scenes.
// Other namespaces are reserved for future scene categories.
enum SceneListNamespace: Hashable {
    case app
    case menuBarExtras
    case dialog
}

// SceneID contains the content type token and creation index within that type.
// Structure: (type: Any.Type, index: UInt8)
struct SceneID: Hashable {
    var typeID: ObjectIdentifier   // ObjectIdentifier wraps Any.Type for Hashable conformance
    var index: UInt8

    init(_ type: Any.Type, index: UInt8 = 0) {
        self.typeID = ObjectIdentifier(type)
        self.index = index
    }
}

// WindowKey is the unique identifier for a platform window.
// Structure: (namespace: SceneListNamespace, sceneID: SceneID)
struct WindowKey: Hashable {
    var namespace: SceneListNamespace
    var sceneID: SceneID
}

// SceneList is the namespace for scene-list preference channel types.
//
// Channel direction:
//   Scene to AppGraph: SceneList.Key preference output from _makeScene.
//   AppGraph to Scene: PrimarySceneSummariesInputKey input to _makeScene, defined in AppGraph.swift.
enum SceneList {

    // Key: PreferenceKey output from WindowGroupScene/_makeScene.
    // AppGraph registers this key in _SceneInputs.preferences before calling _makeScene,
    // then subscribes to the returned AG node to create/destroy windows.
    struct Key: PreferenceKey {
        typealias Value = [Item]
        static var defaultValue: [Item] { [] }
        static func reduce(value: inout [Item], nextValue: () -> [Item]) {
            value.append(contentsOf: nextValue())
        }
    }

    // Item is one window entry reported by a Scene through SceneList.Key.
    struct Item {
        // Classifies which controller registry the window belongs to.
        // Keep controller and presentation buckets separate during scene updates.
        enum Kind {
            case main       // WindowGroup has one or more instances per key.
            case single     // Window has exactly one instance per key.
            case settings   // Settings scene
            case auxiliary  // Auxiliary/popover window
        }

        // Identifies the window slot this scene is claiming.
        var windowKey: WindowKey

        // Window kind determines which registry in AppWindowsController receives this item.
        var kind: Kind

        // Creation-time window hints from scene modifiers.
        var sceneConfiguration = WindowSceneConfiguration()

        // Factory called once by AppWindowsController when it decides to open this window.
        // Captured at _makeScene time. Holds AG graph cursors for the content view.
        var makeController: () -> WindowController

        init(windowKey: WindowKey, kind: Kind = .main, makeController: @escaping () -> WindowController) {
            self.windowKey = windowKey
            self.kind = kind
            self.makeController = makeController
        }

        // Summary is a snapshot of an open window sent back from AppGraph to Scene
        // via PrimarySceneSummariesInputKey (reverse channel).
        struct Summary {
            var windowKey: WindowKey
            var activationState: SceneActivationState
        }
    }
}
