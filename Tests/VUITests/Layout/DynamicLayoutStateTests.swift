import XCTest
@testable import VUI

final class DynamicLayoutStateTests: XCTestCase {
    func testDynamicContainerIDUsesUniqueIDThenSignedViewIndexOrdering() {
        // ASSERTIONS dynamicLayoutStateOwnershipObserved
        let ids = [
            DynamicContainerID(uniqueId: 2, viewIndex: 0),
            DynamicContainerID(uniqueId: 1, viewIndex: 1),
            DynamicContainerID(uniqueId: 1, viewIndex: -1),
            DynamicContainerID(uniqueId: 1, viewIndex: 0),
        ]

        XCTAssertEqual(
            ids.sorted(),
            [
                DynamicContainerID(uniqueId: 1, viewIndex: -1),
                DynamicContainerID(uniqueId: 1, viewIndex: 0),
                DynamicContainerID(uniqueId: 1, viewIndex: 1),
                DynamicContainerID(uniqueId: 2, viewIndex: 0),
            ]
        )
    }

    func testDynamicLayoutMapStoresFlatSortedEntriesAndRemovesOneItemRange() {
        // ASSERTIONS dynamicLayoutStateOwnershipObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let firstComputer = graph.makeInput(
                value: LayoutComputer.defaultValue
            )
            let secondComputer = graph.makeInput(
                value: LayoutComputer.defaultValue
            )
            let first = LayoutProxyAttributes(
                layoutComputer: firstComputer
            )
            let second = LayoutProxyAttributes(
                layoutComputer: secondComputer
            )
            let firstID = DynamicContainerID(uniqueId: 4, viewIndex: 0)
            let secondID = DynamicContainerID(uniqueId: 2, viewIndex: 1)

            var map = DynamicLayoutMap()
            map[firstID] = first
            map[secondID] = second

            XCTAssertEqual(map.map.map(\.id), [secondID, firstID])
            XCTAssertEqual(map[firstID], first)
            XCTAssertEqual(map[secondID], second)
            XCTAssertEqual(
                map[DynamicContainerID(uniqueId: 9, viewIndex: 0)],
                LayoutProxyAttributes()
            )

            map[firstID] = LayoutProxyAttributes()
            XCTAssertEqual(map.map.map(\.id), [secondID])

            map[DynamicContainerID(uniqueId: 2, viewIndex: 0)] = first
            map.remove(uniqueId: 2)
            XCTAssertTrue(map.map.isEmpty)
        }
    }

    func testDynamicLayoutMapReordersByContainerInfoAndViewIndex() {
        // ASSERTIONS dynamicLayoutStateOwnershipObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let attributes = (0..<3).map { _ in
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.defaultValue
                    )
                )
            }
            let first = makeItem(
                uniqueId: 8,
                source: "first",
                viewCount: 2
            )
            let second = makeItem(
                uniqueId: 3,
                source: "second",
                viewCount: 1
            )
            var info = DynamicContainer.Info()
            info.replaceItems(active: [first, second])
            info.displayMap = [1, 0]

            var map = DynamicLayoutMap()
            map[DynamicContainerID(uniqueId: 8, viewIndex: 0)] =
                attributes[0]
            map[DynamicContainerID(uniqueId: 8, viewIndex: 1)] =
                attributes[1]
            map[DynamicContainerID(uniqueId: 3, viewIndex: 0)] =
                attributes[2]

            XCTAssertEqual(
                map.attributes(info: info),
                attributes
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 8, viewIndex: 0)
                ),
                0
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 8, viewIndex: 1)
                ),
                1
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 3, viewIndex: 0)
                ),
                2
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 8, viewIndex: 2)
                ),
                2,
                "The producer, rather than Info.viewIndex, owns the child-offset range invariant."
            )
            XCTAssertNil(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 99, viewIndex: 0)
                )
            )
        }
    }

    private func makeItem(
        uniqueId: UInt32,
        source: String,
        viewCount: Int32
    ) -> DynamicContainer.ItemInfo {
        DynamicContainer.ItemInfo(
            subgraph: AGSubgraph(),
            uniqueId: uniqueId,
            viewCount: viewCount,
            outputs: _ViewOutputs(),
            sourceID: _ViewList_ID(
                explicitID: AnyHashable(source)
            ).canonicalID,
            layoutAttributes: [],
            preferenceOutputs: []
        )
    }
}
