import XCTest
@testable import VUI

final class FrameLayoutTests: XCTestCase {
    func testFixedPlacementUsesParentAndChildAlignmentGuides() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let recorder = FrameLayoutPlacementRecorder()
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let layoutComputer = graph.makeInput(
                value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        recorder.proposals.append(proposal)
                        return CGSize(width: 40, height: 20)
                    },
                    explicitAlignment: { key, _ in
                        recorder.guideReads[key, default: 0] += 1
                        if key == frameProbeHorizontal.key {
                            return 30
                        }
                        if key == frameProbeVertical.key {
                            return 5
                        }
                        return nil
                    }
                )
            )
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(
                    layoutComputer: layoutComputer
                )
            )
            let layout = _FrameLayout(
                width: 100,
                height: 80,
                alignment: frameProbeAlignment
            )

            let placement = layout.placement(
                of: proxy,
                in: PlacementContext(
                    context: AnyRuleContext(attribute: owner.identifier),
                    owner: owner.identifier,
                    environment: environment,
                    parentSize: ViewSize(
                        CGSize(width: 100, height: 80),
                        proposal: _ProposedSize(width: 60, height: nil)
                    )
                )
            )

            XCTAssertEqual(placement.anchor, .topLeading)
            XCTAssertEqual(placement.anchorPosition, CGPoint(x: -5, y: 55))
            XCTAssertEqual(placement.proposedSize_.width, 100)
            XCTAssertEqual(placement.proposedSize_.height, 80)
            XCTAssertEqual(
                recorder.proposals,
                [_ProposedSize(width: 100, height: 80)]
            )
            XCTAssertEqual(recorder.guideReads[frameProbeHorizontal.key], 1)
            XCTAssertEqual(recorder.guideReads[frameProbeVertical.key], 1)
        }
    }

    func testFlexiblePlacementKeepsOnlyStrictlyInteriorAxisUnspecified() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let recorder = FrameLayoutPlacementRecorder()
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let layoutComputer = graph.makeInput(
                value: testLayoutComputer { proposal in
                    recorder.proposals.append(proposal)
                    return CGSize(width: 40, height: 20)
                }
            )
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(
                    layoutComputer: layoutComputer
                )
            )
            let layout = _FlexFrameLayout(
                minWidth: 10,
                maxWidth: 100,
                minHeight: 20,
                maxHeight: 100,
                alignment: .topLeading
            )

            let placement = layout.placement(
                of: proxy,
                in: PlacementContext(
                    context: AnyRuleContext(attribute: owner.identifier),
                    owner: owner.identifier,
                    environment: environment,
                    parentSize: ViewSize(
                        CGSize(width: 40, height: 20),
                        proposal: .unspecified
                    )
                )
            )

            XCTAssertEqual(placement.anchor, .topLeading)
            XCTAssertEqual(placement.anchorPosition, .zero)
            XCTAssertNil(placement.proposedSize_.width)
            XCTAssertEqual(placement.proposedSize_.height, 20)
            XCTAssertEqual(
                recorder.proposals,
                [_ProposedSize(width: nil, height: 20)]
            )
        }
    }

    func testFlexiblePlacementPinsBoundsIdealAndParentProposal() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let layoutComputer = graph.makeInput(
                value: testLayoutComputer { proposal in
                    proposal.fixingUnspecifiedDimensions(
                        at: CGSize(width: 40, height: 20)
                    )
                }
            )
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(
                    layoutComputer: layoutComputer
                )
            )

            func proposedWidth(
                size: CGFloat,
                parentProposal: CGFloat? = nil,
                min: CGFloat? = 10,
                ideal: CGFloat? = nil,
                max: CGFloat? = 100
            ) -> CGFloat? {
                let layout = _FlexFrameLayout(
                    minWidth: min,
                    idealWidth: ideal,
                    maxWidth: max,
                    alignment: .topLeading
                )
                return layout.placement(
                    of: proxy,
                    in: PlacementContext(
                        context: AnyRuleContext(attribute: owner.identifier),
                        owner: owner.identifier,
                        environment: environment,
                        parentSize: ViewSize(
                            CGSize(width: size, height: 20),
                            proposal: _ProposedSize(
                                width: parentProposal,
                                height: nil
                            )
                        )
                    )
                ).proposedSize_.width
            }

            XCTAssertNil(proposedWidth(size: 40))
            XCTAssertEqual(proposedWidth(size: 10), 10)
            XCTAssertEqual(proposedWidth(size: 100), 100)
            XCTAssertEqual(proposedWidth(size: 40, ideal: 40), 40)
            XCTAssertEqual(proposedWidth(size: 40, parentProposal: 40), 40)
        }
    }

    func testFlexibleSizingKeepsMeasurementAndResolvedDimensionRules() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let recorder = FrameLayoutPlacementRecorder()
            let owner = graph.makeInput(value: 0)
            let environment = graph.makeInput(value: EnvironmentValues())
            let layoutComputer = graph.makeInput(
                value: testLayoutComputer { proposal in
                    recorder.proposals.append(proposal)
                    return CGSize(width: 50, height: 50)
                }
            )
            let proxy = LayoutProxy(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: LayoutProxyAttributes(
                    layoutComputer: layoutComputer
                )
            )
            let context = SizeAndSpacingContext(
                context: AnyRuleContext(attribute: owner.identifier),
                owner: owner.identifier,
                environment: environment
            )

            XCTAssertEqual(
                _FlexFrameLayout(
                    minWidth: 30,
                    alignment: .center
                ).sizeThatFits(
                    in: _ProposedSize(width: 100, height: nil),
                    context: context,
                    child: proxy
                ).width,
                50
            )
            XCTAssertEqual(
                _FlexFrameLayout(
                    idealWidth: 70,
                    alignment: .center
                ).sizeThatFits(
                    in: .unspecified,
                    context: context,
                    child: proxy
                ).width,
                70
            )
            XCTAssertEqual(
                _FlexFrameLayout(
                    maxWidth: 120,
                    alignment: .center
                ).sizeThatFits(
                    in: _ProposedSize(width: 100, height: nil),
                    context: context,
                    child: proxy
                ).width,
                100
            )
            XCTAssertEqual(
                _FlexFrameLayout(
                    minWidth: 80,
                    alignment: .center
                ).sizeThatFits(
                    in: _ProposedSize(width: 50, height: nil),
                    context: context,
                    child: proxy
                ).width,
                80
            )

            XCTAssertEqual(
                recorder.proposals.map(\.width),
                [100, 70, 100, 80]
            )
        }
    }
}

private final class FrameLayoutPlacementRecorder {
    var proposals: [_ProposedSize] = []
    var guideReads: [AlignmentKey: Int] = [:]
}

private enum FrameProbeHorizontalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.width * 0.25
    }
}

private enum FrameProbeVerticalAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context.height * 0.75
    }
}

private let frameProbeHorizontal = HorizontalAlignment(
    FrameProbeHorizontalAlignmentID.self
)
private let frameProbeVertical = VerticalAlignment(
    FrameProbeVerticalAlignmentID.self
)
private let frameProbeAlignment = Alignment(
    horizontal: frameProbeHorizontal,
    vertical: frameProbeVertical
)
