import XCTest
@testable import VUI

final class GraphInputsMergeTests: XCTestCase {
    func testUsingGraphicsRendererIsBoolViewInputWithSeparateViewChannel() {
        assertBoolViewInput(UsingGraphicsRenderer.self)

        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)

            XCTAssertFalse(inputs[UsingGraphicsRenderer.self])
            XCTAssertFalse(inputs.base[UsingGraphicsRenderer.self])

            inputs[UsingGraphicsRenderer.self] = true

            XCTAssertTrue(inputs[UsingGraphicsRenderer.self])
            XCTAssertFalse(inputs.base[UsingGraphicsRenderer.self])

            inputs.base[UsingGraphicsRenderer.self] = true

            XCTAssertTrue(inputs[UsingGraphicsRenderer.self])
            XCTAssertTrue(inputs.base[UsingGraphicsRenderer.self])
        }
    }

    func testArchivedViewInputMatchesObservedMarkerCarrierAndViewChannel() throws {
        XCTAssertEqual(MemoryLayout<ArchivedViewInput.Flags>.size, 1)
        XCTAssertEqual(MemoryLayout<ArchivedViewInput.DeploymentVersion>.size, 1)
        XCTAssertEqual(MemoryLayout<ArchivedViewInput.Value>.size, 2)

        XCTAssertEqual(ArchivedViewInput.Flags.isArchived.rawValue, 0x01)
        XCTAssertEqual(ArchivedViewInput.Flags.stableIDs.rawValue, 0x02)
        XCTAssertEqual(ArchivedViewInput.Flags.customFontURLs.rawValue, 0x04)
        XCTAssertEqual(ArchivedViewInput.Flags.assetCatalogRefences.rawValue, 0x08)
        XCTAssertEqual(ArchivedViewInput.Flags.preciseTextLayout.rawValue, 0x10)
        XCTAssertEqual(ArchivedViewInput.Flags.intelligenceContent.rawValue, 0x20)
        XCTAssertEqual(ArchivedViewInput.Flags.publicArchive.rawValue, 0x40)

        XCTAssertEqual(ArchivedViewInput.DeploymentVersion.v5.rawValue, 1)
        XCTAssertEqual(ArchivedViewInput.DeploymentVersion.v6.rawValue, 2)
        XCTAssertEqual(ArchivedViewInput.DeploymentVersion.v7.rawValue, 3)
        XCTAssertEqual(ArchivedViewInput.DeploymentVersion.v7_4.rawValue, 4)
        XCTAssertEqual(
            ArchivedViewInput.DeploymentVersion.current,
            ArchivedViewInput.DeploymentVersion.v7_4
        )
        XCTAssertEqual(
            ArchivedViewInput.DeploymentVersion.oldest,
            ArchivedViewInput.DeploymentVersion.v5
        )

        let defaultValue = ArchivedViewInput.defaultValue
        XCTAssertTrue(defaultValue.flags.isEmpty)
        XCTAssertEqual(defaultValue.deploymentVersion, .current)
        XCTAssertFalse(defaultValue.isArchived)

        let archived = ArchivedViewInput.Value(
            flags: [.isArchived, .stableIDs, .customFontURLs, .assetCatalogRefences, .preciseTextLayout]
        )
        XCTAssertTrue(archived.isArchived)
        XCTAssertTrue(archived.stableIDs)
        XCTAssertTrue(archived.customFontURLs)
        XCTAssertTrue(archived.assetCatalogRefences)
        XCTAssertTrue(archived.preciseTextLayout)
        XCTAssertEqual(ArchivedViewInput.Value.isArchived.flags, .isArchived)
        XCTAssertEqual(ArchivedViewInput.Value.isArchived.deploymentVersion, .current)

        let encoded = try JSONEncoder().encode(ArchivedViewInput.DeploymentVersion.v7)
        XCTAssertEqual(
            try JSONDecoder().decode(ArchivedViewInput.DeploymentVersion.self, from: encoded),
            .v7
        )

        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)

            XCTAssertEqual(inputs[ArchivedViewInput.self], defaultValue)
            XCTAssertEqual(inputs.base[ArchivedViewInput.self], defaultValue)

            inputs[ArchivedViewInput.self] = archived

            XCTAssertEqual(inputs[ArchivedViewInput.self], archived)
            XCTAssertEqual(inputs.base[ArchivedViewInput.self], defaultValue)
        }
    }

    func testMergePreservesReceiverOptionsAndImportsOnlyOtherAnimationsDisabled() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var receiver = makeGraphInputs(graph: graph)
            receiver.options = [
                .supportsVariableFrameDuration,
                .viewNeedsGeometry,
            ]

            var other = makeGraphInputs(graph: graph)
            other.options = [
                .animationsDisabled,
                .viewRequestsLayoutComputer,
                .viewNeedsGeometryAccessibility,
                .needsAccessibility,
                .needsDynamicLayout,
            ]

            receiver.merge(other, ignoringPhase: false)

            XCTAssertTrue(receiver.options.contains(.supportsVariableFrameDuration))
            XCTAssertTrue(receiver.options.contains(.viewNeedsGeometry))
            XCTAssertTrue(receiver.options.contains(.animationsDisabled))
            XCTAssertFalse(receiver.options.contains(.viewRequestsLayoutComputer))
            XCTAssertFalse(receiver.options.contains(.viewNeedsGeometryAccessibility))
            XCTAssertFalse(receiver.options.contains(.needsAccessibility))
            XCTAssertFalse(receiver.options.contains(.needsDynamicLayout))
        }
    }

    func testMergeDoesNotImportOtherSupportsVariableFrameDuration() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            var receiver = makeGraphInputs(graph: graph)
            var other = makeGraphInputs(graph: graph)
            other.options = [.supportsVariableFrameDuration]

            receiver.merge(other)

            XCTAssertFalse(receiver.options.contains(.supportsVariableFrameDuration))
        }
    }

    func testMergeUsesMaterializedChildAnimatedFrameInsteadOfCapturedModifierFrame() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            var modifierInputs = makeGraphInputs(graph: graph)
            _ = makeAnimatableFrameAttributes(
                in: &modifierInputs,
                position: graph.makeInput(value: CGPoint(x: 10, y: 20)),
                size: graph.makeInput(value: ViewSize(CGSize(width: 110, height: 78)))
            )
            let modifierFrame = try XCTUnwrap(
                modifierInputs.cachedEnvironment.value.animatedFrame
            )

            var childInputs = makeGraphInputs(graph: graph)
            _ = makeAnimatableFrameAttributes(
                in: &childInputs,
                position: graph.makeInput(value: CGPoint(x: 44, y: 51)),
                size: graph.makeInput(value: ViewSize(CGSize(width: 40.5, height: 16)))
            )
            let childFrame = try XCTUnwrap(
                childInputs.cachedEnvironment.value.animatedFrame
            )

            modifierInputs.merge(childInputs)

            let mergedFrame = try XCTUnwrap(
                modifierInputs.cachedEnvironment.value.animatedFrame
            )
            XCTAssertNotEqual(
                modifierFrame.animatedFrame.identifier,
                childFrame.animatedFrame.identifier
            )
            XCTAssertEqual(
                mergedFrame.animatedFrame.identifier,
                childFrame.animatedFrame.identifier
            )
            XCTAssertEqual(
                mergedFrame._animatedPosition?.identifier,
                childFrame._animatedPosition?.identifier
            )
            XCTAssertEqual(
                mergedFrame._animatedSize?.identifier,
                childFrame._animatedSize?.identifier
            )
        }
    }

    private func makeGraphInputs(graph: _AGGraph) -> _GraphInputs {
        _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time()),
            cachedEnvironment: MutableBox(
                CachedEnvironment(
                    environment: graph.makeInput(value: EnvironmentValues.tracking())
                )
            ),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10))),
            safeAreaInsets: OptionalAttribute<SafeAreaInsets>(),
            containerSize: OptionalAttribute<ViewSize>(),
            stackOrientation: nil
        )
    }

    private func assertBoolViewInput<T: ViewInput>(_ type: T.Type) where T.Value == Bool {
        XCTAssertFalse(T.defaultValue)
    }
}
