import XCTest
@testable import VEditor

final class EditorWorkspaceTests: XCTestCase {
    func testSampleWorkspaceInitialSelectionResolvesToEditorAndInspectorFile() {
        let workspace = EditorWorkspace.sample
        let file = workspace.file(id: workspace.initialSelectedFileID)

        XCTAssertEqual(workspace.projectName, "SampleGame")
        XCTAssertEqual(file?.name, "Game.swift")
        XCTAssertEqual(file?.kind, .swiftSource)
        XCTAssertFalse(file?.previewLines.isEmpty ?? true)
    }

    func testUnknownOrEmptySelectionHasNoSelectedFile() {
        let workspace = EditorWorkspace.sample

        XCTAssertNil(workspace.file(id: nil))
        XCTAssertNil(workspace.file(id: "Sources/Missing.swift"))
    }
}
