//
//  File: CommandMenuPresentationStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Selects how a scene presents its command menu.
public enum CommandMenuPresentationStyle: Equatable, Sendable {
    /// Presents the menu inside each scene window using the framework renderer.
    case window

    /// Presents the menu through the current platform's system menu API.
    case platform
}

extension Scene {
    /// Selects the command-menu presenter for windows created by this scene.
    public func commandMenuPresentationStyle(
        _ style: CommandMenuPresentationStyle
    ) -> some Scene {
        modifier(TransformSceneListModifier { items in
            for index in items.indices {
                items[index].sceneConfiguration.commandMenuPresentationStyle = style
            }
        })
    }

}
