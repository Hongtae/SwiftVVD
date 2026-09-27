//
//  File: EditorWorkspace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct EditorFile: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case scene = "Scene"
        case swiftSource = "Swift Source"
        case shader = "Shader"
        case asset = "Asset"
    }

    let id: String
    let name: String
    let path: String
    let kind: Kind
    let previewLines: [String]
}

struct EditorLogEntry: Identifiable, Hashable, Sendable {
    enum Level: String, Hashable, Sendable {
        case info = "Info"
        case warning = "Warning"
        case error = "Error"
    }

    let id: Int
    let level: Level
    let message: String
}

struct EditorWorkspace: Sendable {
    let projectName: String
    let files: [EditorFile]
    let logs: [EditorLogEntry]
    let initialSelectedFileID: EditorFile.ID?

    func file(id: EditorFile.ID?) -> EditorFile? {
        guard let id else { return nil }
        return files.first { $0.id == id }
    }
}

extension EditorWorkspace {
    static let sample = EditorWorkspace(
        projectName: "SampleGame",
        files: [
            EditorFile(
                id: "Scenes/Main.scene",
                name: "Main.scene",
                path: "Scenes/Main.scene",
                kind: .scene,
                previewLines: [
                    "Scene Main {",
                    "    Camera: MainCamera",
                    "    Root: World",
                    "}",
                ]
            ),
            EditorFile(
                id: "Sources/Game.swift",
                name: "Game.swift",
                path: "Sources/Game.swift",
                kind: .swiftSource,
                previewLines: [
                    "import VGame",
                    "",
                    "struct SampleGame {",
                    "    var scene = GameScene()",
                    "",
                    "    mutating func update(deltaTime: Double) {",
                    "        scene.update(deltaTime: deltaTime)",
                    "    }",
                    "}",
                ]
            ),
            EditorFile(
                id: "Sources/PlayerController.swift",
                name: "PlayerController.swift",
                path: "Sources/PlayerController.swift",
                kind: .swiftSource,
                previewLines: [
                    "import VGame",
                    "",
                    "struct PlayerController {",
                    "    var movementSpeed = 4.0",
                    "}",
                ]
            ),
            EditorFile(
                id: "Shaders/Lit.frag.hlsl",
                name: "Lit.frag.hlsl",
                path: "Shaders/Lit.frag.hlsl",
                kind: .shader,
                previewLines: [
                    "float4 main(FragmentInput input) : SV_Target0",
                    "{",
                    "    return float4(input.color.rgb, 1.0);",
                    "}",
                ]
            ),
            EditorFile(
                id: "Assets/Player.mesh",
                name: "Player.mesh",
                path: "Assets/Player.mesh",
                kind: .asset,
                previewLines: [
                    "Asset preview is not implemented.",
                    "The editor pane will host a type-specific editor here.",
                ]
            ),
        ],
        logs: [
            EditorLogEntry(
                id: 1,
                level: .info,
                message: "Project SampleGame opened."
            ),
            EditorLogEntry(
                id: 2,
                level: .info,
                message: "Indexed 5 project files."
            ),
            EditorLogEntry(
                id: 3,
                level: .warning,
                message: "Scene preview and build pipeline are placeholders."
            ),
        ],
        initialSelectedFileID: "Sources/Game.swift"
    )
}
