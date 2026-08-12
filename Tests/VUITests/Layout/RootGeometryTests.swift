import Foundation
import XCTest
@testable import VUI

private struct FixedRootLayoutView: View, PrimitiveView, LeafViewLayout {
    var measuredSize: CGSize

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        var outputs = _ViewOutputs()
        makeLeafLayout(&outputs, view: view, inputs: inputs)
        return outputs
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        measuredSize
    }

    typealias Body = Never
}

private final class RootGeometryPlacementCapture: @unchecked Sendable {
    var position: Attribute<CGPoint>?
    var size: Attribute<ViewSize>?
    var placements = 0
}

private struct RootGeometryPlacementLeaf: View, TestPrimitiveView, LeafViewLayout {
    var capture: RootGeometryPlacementCapture

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        let capture = view._attribute.value.capture
        capture.position = inputs.position
        capture.size = inputs.size

        var outputs = _ViewOutputs()
        makeLeafLayout(&outputs, view: view, inputs: inputs)
        return outputs
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        CGSize(width: 10, height: 6)
    }

    typealias Body = Never
}

private struct RootGeometryProbeLayout: Layout {
    var capture: RootGeometryPlacementCapture

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        CGSize(width: 40, height: 20)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        capture.placements += 1
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.midX, y: bounds.midY),
                anchor: .center,
                proposal: ProposedViewSize(width: 10, height: 6)
            )
        }
    }
}

private struct RootGeometryPlacementRoot: View {
    var capture: RootGeometryPlacementCapture

    var body: some View {
        RootGeometryProbeLayout(capture: capture) {
            RootGeometryPlacementLeaf(capture: capture)
        }
    }
}

final class RootGeometryTests: XCTestCase {
    func testGeometryStorageKeepsNativeProjectionOffsets() {
        XCTAssertEqual(MemoryLayout<LayoutComputer>.size, 16)
        XCTAssertEqual(MemoryLayout<ViewSize>.size, 32)
        XCTAssertEqual(MemoryLayout<ViewDimensions>.size, 48)
        XCTAssertEqual(MemoryLayout<ViewGeometry>.size, 64)
#if !DEBUG
        XCTAssertEqual(MemoryLayout<RootGeometry>.size, 16)
        XCTAssertEqual(MemoryLayout<RootGeometry>.stride, 16)
#endif
    }

    func testViewSizeProposalStoragePreservesOptionalAndInfiniteValues() {
        let unspecified = ViewSize(
            CGSize(width: 10, height: 20),
            proposal: .unspecified
        )
        XCTAssertNil(unspecified.proposal.width)
        XCTAssertNil(unspecified.proposal.height)
        XCTAssertEqual(unspecified, unspecified)

        let infinite = ViewSize(
            CGSize(width: 10, height: 20),
            proposal: .infinity
        )
        XCTAssertEqual(infinite.proposal.width, .infinity)
        XCTAssertEqual(infinite.proposal.height, .infinity)

        XCTAssertEqual(ViewSize.zero.proposal, .zero)
    }

    func testViewGraphCentersFixedRootAndPublishesGeometryProjections() throws {
        let (viewGraph, _) = makeViewGraph(
            rootSize: CGSize(width: 40, height: 20),
            proposedSize: CGSize(width: 100, height: 80)
        )

        try viewGraph.data.withCurrent {
            let rootGeometry = try XCTUnwrap(viewGraph.rootGeometry)
            let geometry = rootGeometry.value

            XCTAssertEqual(geometry.origin, CGPoint(x: 30, y: 30))
            XCTAssertEqual(geometry.dimensions.size.value, CGSize(width: 40, height: 20))
            XCTAssertEqual(geometry.dimensions.size.proposal.width, 100)
            XCTAssertEqual(geometry.dimensions.size.proposal.height, 80)
            XCTAssertEqual(rootGeometry.origin().value, geometry.origin)
            XCTAssertEqual(rootGeometry.size().value, geometry.dimensions.size)
        }
    }

    func testCentersRootViewChangeInvalidatesRootGeometry() throws {
        let (viewGraph, _) = makeViewGraph(
            rootSize: CGSize(width: 40, height: 20),
            proposedSize: CGSize(width: 100, height: 80)
        )

        try viewGraph.data.withCurrent {
            let rootGeometry = try XCTUnwrap(viewGraph.rootGeometry)
            XCTAssertEqual(rootGeometry.value.origin, CGPoint(x: 30, y: 30))

            viewGraph.centersRootView = false

            XCTAssertEqual(rootGeometry.value.origin, .zero)
            XCTAssertEqual(
                rootGeometry.value.dimensions.size.value,
                CGSize(width: 40, height: 20)
            )
        }
    }

    func testSafeAreaElementsReduceExactProposalAndNextInsetsAreIgnored() throws {
        let (viewGraph, _) = makeViewGraph(
            rootSize: CGSize(width: 40, height: 20),
            proposedSize: CGSize(width: 100, height: 80)
        )

        try viewGraph.data.withCurrent {
            let safeAreaInsets = try XCTUnwrap(viewGraph.safeAreaInsetsAttr)
            safeAreaInsets.setValue(
                _SafeAreaInsetsModifier(
                    elements: [
                        SafeAreaInsets.Element(
                            regions: .container,
                            insets: EdgeInsets(
                                top: 10,
                                leading: 20,
                                bottom: 6,
                                trailing: 4
                            ),
                            cornerInsets: nil
                        ),
                    ],
                    nextInsets: .insets(
                        SafeAreaInsets(
                            EdgeInsets(
                                top: 100,
                                leading: 100,
                                bottom: 100,
                                trailing: 100
                            )
                        )
                    )
                )
            )

            let geometry = try XCTUnwrap(viewGraph.rootGeometry).value

            XCTAssertEqual(geometry.origin, CGPoint(x: 38, y: 32))
            XCTAssertEqual(geometry.dimensions.size.value, CGSize(width: 40, height: 20))
            XCTAssertEqual(geometry.dimensions.size.proposal.width, 76)
            XCTAssertEqual(geometry.dimensions.size.proposal.height, 64)
        }
    }

    func testRightToLeftFinalizationMirrorsRootInCompleteParentSize() throws {
        var environment = EnvironmentValues.tracking()
        environment.layoutDirection = .rightToLeft
        let (viewGraph, _) = makeViewGraph(
            rootSize: CGSize(width: 40, height: 20),
            proposedSize: CGSize(width: 100, height: 80),
            environment: environment
        )
        viewGraph.centersRootView = false

        try viewGraph.data.withCurrent {
            let safeAreaInsets = try XCTUnwrap(viewGraph.safeAreaInsetsAttr)
            safeAreaInsets.setValue(
                _SafeAreaInsetsModifier(
                    elements: [
                        SafeAreaInsets.Element(
                            regions: .container,
                            insets: EdgeInsets(
                                top: 10,
                                leading: 20,
                                bottom: 6,
                                trailing: 4
                            ),
                            cornerInsets: nil
                        ),
                    ],
                    nextInsets: nil
                )
            )

            let geometry = try XCTUnwrap(viewGraph.rootGeometry).value

            XCTAssertEqual(geometry.origin, CGPoint(x: 56, y: 10))
            XCTAssertEqual(geometry.dimensions.size.proposal.width, 76)
            XCTAssertEqual(geometry.dimensions.size.proposal.height, 64)
        }
    }

    func testProposedSizeMutationInvalidatesRootGeometryAndProjections() throws {
        let (viewGraph, _) = makeViewGraph(
            rootSize: CGSize(width: 40, height: 20),
            proposedSize: CGSize(width: 100, height: 80)
        )

        try viewGraph.data.withCurrent {
            let rootGeometry = try XCTUnwrap(viewGraph.rootGeometry)
            let origin = rootGeometry.origin()
            let size = rootGeometry.size()

            XCTAssertEqual(origin.value, CGPoint(x: 30, y: 30))
            XCTAssertEqual(size.value.value, CGSize(width: 40, height: 20))

            try XCTUnwrap(viewGraph.sizeAttr).setValue(
                ViewSize(CGSize(width: 140, height: 100))
            )

            XCTAssertEqual(origin.value, CGPoint(x: 50, y: 40))
            XCTAssertEqual(size.value.value, CGSize(width: 40, height: 20))
            XCTAssertEqual(size.value.proposal.width, 140)
            XCTAssertEqual(size.value.proposal.height, 100)
        }
    }

    func testRootProjectionsDriveCustomLayoutChildGeometry() throws {
        let capture = RootGeometryPlacementCapture()
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: RootGeometryPlacementRoot.self,
            content: RootGeometryPlacementRoot(capture: capture),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        viewGraph.setSize(CGSize(width: 100, height: 80))
        viewGraph.instantiateIfNeeded()

        try viewGraph.data.withCurrent {
            XCTAssertEqual(
                try XCTUnwrap(capture.position).value,
                CGPoint(x: 45, y: 37)
            )
            XCTAssertEqual(
                try XCTUnwrap(capture.size).value.value,
                CGSize(width: 10, height: 6)
            )
            XCTAssertEqual(capture.placements, 1)

            _ = try XCTUnwrap(capture.position).value
            _ = try XCTUnwrap(capture.size).value
            XCTAssertEqual(capture.placements, 1)
        }
    }

    func testStaticLayoutChildGeometryUsesSharedOffsetProjections() throws {
        let capture = RootGeometryPlacementCapture()
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: RootGeometryPlacementRoot.self,
            content: RootGeometryPlacementRoot(capture: capture),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        viewGraph.setSize(CGSize(width: 100, height: 80))
        viewGraph.instantiateIfNeeded()

        try viewGraph.data.withCurrent {
            let position = try XCTUnwrap(capture.position)
            let size = try XCTUnwrap(capture.size)
            let graph = viewGraph.data.graph
            let positionDescription = graph.debugDescription(
                for: position.identifier
            )
            let sizeDescription = graph.debugDescription(
                for: size.identifier
            )

            XCTAssertTrue(positionDescription.hasSuffix(" + 0)"))
            XCTAssertTrue(sizeDescription.hasSuffix(" + 32)"))

            func offsetParent(in description: String) -> Substring? {
                guard let marker = description.range(of: "(offset: @") else {
                    return nil
                }
                return description[marker.upperBound...]
                    .split(separator: " ")
                    .first
            }
            let positionParent = try XCTUnwrap(
                offsetParent(in: positionDescription)
            )
            let sizeParent = try XCTUnwrap(
                offsetParent(in: sizeDescription)
            )
            XCTAssertEqual(positionParent, sizeParent)
        }
    }

    private func makeViewGraph(
        rootSize: CGSize,
        proposedSize: CGSize,
        environment: EnvironmentValues = .tracking()
    ) -> (ViewGraph, TestViewRendererHost) {
        let rendererHost = TestViewRendererHost()
        let root = FixedRootLayoutView(measuredSize: rootSize)
        let viewGraph = ViewGraph(
            rootViewType: FixedRootLayoutView.self,
            content: root,
            rendererHost: rendererHost,
            initialEnvironment: environment,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        viewGraph.setSize(proposedSize)
        viewGraph.instantiateIfNeeded()
        return (viewGraph, rendererHost)
    }
}
