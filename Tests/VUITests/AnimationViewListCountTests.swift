import XCTest
@testable import VUI

private struct CountedAnimationContent: View, Equatable, _PrimitiveView {
    typealias Body = Never

    static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        3
    }
}

final class AnimationViewListCountTests: XCTestCase {
    func testAnimationViewForwardsStaticViewListCountToContent() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            let inputs = _GraphInputs(
                customInputs: PropertyList(),
                time: graph.makeInput(value: Time(seconds: 0)),
                cachedEnvironment: MutableBox(
                    CachedEnvironment(
                        environment: graph.makeInput(value: EnvironmentValues())
                    )
                ),
                phase: graph.makeInput(value: Phase()),
                transaction: graph.makeInput(value: Transaction()),
                changedDebugProperties: 0,
                options: [],
                mergedInputs: []
            )

            XCTAssertEqual(
                _AnimationView<CountedAnimationContent>._viewListCount(
                    inputs: _ViewListCountInputs(base: inputs)
                ),
                3
            )
        }
    }
}
