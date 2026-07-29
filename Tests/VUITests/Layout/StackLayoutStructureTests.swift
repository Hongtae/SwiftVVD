import Foundation
import XCTest
@testable import VUI

private final class OpaqueValueCacheState: @unchecked Sendable {
    var makeCount = 0
    var updateCount = 0
    var snapshots: [[String]] = []
}

private struct OpaqueValueCache {
    static let magic: UInt64 = 0x5a17_cace_d00d_beef

    var sentinel = Self.magic
    var history: [String]
}

private struct OpaqueValueCacheLayout: Layout {
    var revision: Int
    var state: OpaqueValueCacheState

    func makeCache(subviews: Subviews) -> OpaqueValueCache {
        state.makeCount += 1
        return OpaqueValueCache(history: ["make:\(revision):\(subviews.count)"])
    }

    func updateCache(
        _ cache: inout OpaqueValueCache,
        subviews: Subviews
    ) {
        precondition(cache.sentinel == OpaqueValueCache.magic)
        state.updateCount += 1
        state.snapshots.append(cache.history)
        cache.history.append("update:\(revision):\(subviews.count)")
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout OpaqueValueCache
    ) -> CGSize {
        precondition(cache.sentinel == OpaqueValueCache.magic)
        cache.history.append("size:\(revision):\(subviews.count)")
        state.snapshots.append(cache.history)
        return CGSize(
            width: CGFloat(revision + 10),
            height: CGFloat(revision + 20)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout OpaqueValueCache
    ) {
        precondition(cache.sentinel == OpaqueValueCache.magic)
        cache.history.append("place:\(revision):\(subviews.count)")
        state.snapshots.append(cache.history)
    }
}

final class StackLayoutStructureTests: XCTestCase {
    func testLayoutSubviewsUsesObservedDirectAndIndirectStorageShapes() {
        withGraph { graph in
            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let attributes = [
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.fixed(CGSize(width: 10, height: 20))
                    )
                ),
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.fixed(CGSize(width: 30, height: 40))
                    )
                ),
            ]
            let direct = LayoutSubviews(
                context: context,
                attributes: attributes,
                layoutDirection: .leftToRight
            )

            XCTAssertEqual(
                Mirror(reflecting: direct).children.compactMap(\.label),
                ["context", "storage", "layoutDirection"]
            )
            XCTAssertEqual(storageCaseName(of: direct), "direct")
            XCTAssertEqual(direct[0].index, 0)
            XCTAssertEqual(direct[1].index, 1)
            XCTAssertEqual(direct[1].containerLayoutDirection, .leftToRight)

            let indirect = direct[[1, 0]]
            XCTAssertEqual(storageCaseName(of: indirect), "indirect")
            XCTAssertEqual(indirect[0].index, 1)
            XCTAssertEqual(indirect[1].index, 0)
            XCTAssertEqual(
                indirect[0].sizeThatFits(.unspecified),
                CGSize(width: 30, height: 40)
            )

            let fullRange = direct[direct.startIndex..<direct.endIndex]
            XCTAssertEqual(storageCaseName(of: fullRange), "indirect")
            XCTAssertEqual(fullRange.context, context)
            XCTAssertEqual(fullRange.map(\.index), [0, 1])

            let emptyRange = direct[direct.startIndex..<direct.startIndex]
            XCTAssertEqual(storageCaseName(of: emptyRange), "indirect")
            XCTAssertEqual(emptyRange.context, context)
            XCTAssertTrue(emptyRange.isEmpty)

            let identityIndices = direct[Array(direct.indices)]
            XCTAssertEqual(storageCaseName(of: identityIndices), "indirect")
            XCTAssertEqual(identityIndices.context, context)
            XCTAssertEqual(identityIndices.map(\.index), [0, 1])

            XCTAssertEqual(direct[0], fullRange[0])
            XCTAssertEqual(direct[0], identityIndices[0])
            XCTAssertNotEqual(direct[0], indirect[0])
            XCTAssertNotEqual(
                direct[0],
                LayoutSubview(
                    proxy: direct[0].proxy,
                    index: direct[0].index + 1,
                    containerLayoutDirection: direct[0].containerLayoutDirection
                )
            )
            XCTAssertNotEqual(
                direct[0],
                LayoutSubview(
                    proxy: direct[0].proxy,
                    index: direct[0].index,
                    containerLayoutDirection: .rightToLeft
                )
            )

#if !DEBUG
            XCTAssertEqual(MemoryLayout<LayoutProxyAttributes>.size, 8)
            XCTAssertEqual(MemoryLayout<LayoutProxy>.size, 12)
            XCTAssertEqual(MemoryLayout<LayoutSubview>.size, 17)
            XCTAssertEqual(MemoryLayout<LayoutSubview>.stride, 20)
            XCTAssertEqual(MemoryLayout<LayoutSubview>.alignment, 4)
            XCTAssertEqual(MemoryLayout<LayoutSubviews>.size, 18)
            XCTAssertEqual(MemoryLayout<LayoutSubviews>.stride, 24)
            XCTAssertEqual(MemoryLayout<LayoutSubviews>.alignment, 8)
#endif
        }
    }

    func testStackCacheUsesObservedHeaderAndChildFieldStructure() {
        withGraph { graph in
            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let attributes = [
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.fixed(CGSize(width: 10, height: 20))
                    )
                ),
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.fixed(CGSize(width: 30, height: 40))
                    )
                ),
            ]
            let subviews = LayoutSubviews(
                context: context,
                attributes: attributes,
                layoutDirection: .leftToRight
            )
            let layout = HStackLayout(alignment: .center, spacing: 5)
            var cache = layout.makeCache(subviews: subviews)

            let fresh = reflectedStack(cache)
            XCTAssertEqual(
                Mirror(reflecting: fresh.header).children.compactMap(\.label),
                [
                    "minorAxisAlignment",
                    "uniformSpacing",
                    "majorAxis",
                    "internalSpacing",
                    "lastProposedSize",
                    "stackSize",
                    "proxies",
                    "resizeChildrenWithTrailingOverflow",
                ]
            )
            XCTAssertEqual(
                Mirror(reflecting: fresh.children[0]).children.compactMap(\.label),
                [
                    "layoutPriority",
                    "majorAxisRangeCache",
                    "distanceToPrevious",
                    "fittingOrder",
                    "geometry",
                ]
            )
            XCTAssertEqual(
                reflectedField(fresh.header, named: "uniformSpacing") as! CGFloat?,
                5
            )
            XCTAssertEqual(
                reflectedField(fresh.header, named: "majorAxis") as? Axis,
                .horizontal
            )
            XCTAssertEqual(
                reflectedField(fresh.header, named: "internalSpacing") as? CGFloat,
                5
            )
            let initialProposal = reflectedField(
                fresh.header,
                named: "lastProposedSize"
            ) as! ProposedViewSize
            XCTAssertEqual(initialProposal.width, -.infinity)
            XCTAssertEqual(initialProposal.height, -.infinity)
            XCTAssertEqual(
                reflectedField(fresh.header, named: "stackSize") as? CGSize,
                .zero
            )
            XCTAssertEqual(
                reflectedField(
                    fresh.header,
                    named: "resizeChildrenWithTrailingOverflow"
                ) as? Bool,
                false
            )
            XCTAssertEqual(
                reflectedField(fresh.children[0], named: "distanceToPrevious") as? CGFloat,
                0
            )
            XCTAssertEqual(
                reflectedField(fresh.children[1], named: "distanceToPrevious") as? CGFloat,
                5
            )
            XCTAssertEqual(
                reflectedField(fresh.children[0], named: "fittingOrder") as? Int,
                0
            )
            XCTAssertTrue(
                (reflectedField(fresh.children[0], named: "geometry") as! ViewGeometry)
                    .isInvalid
            )

            let proposal = ProposedViewSize(width: 100, height: 50)
            XCTAssertEqual(
                layout.sizeThatFits(
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                ),
                CGSize(width: 45, height: 40)
            )
            let resolved = reflectedStack(cache)
            XCTAssertEqual(
                reflectedField(resolved.header, named: "lastProposedSize")
                    as? ProposedViewSize,
                proposal
            )
            XCTAssertFalse(
                (reflectedField(resolved.children[0], named: "geometry") as! ViewGeometry)
                    .isInvalid
            )

#if !DEBUG
            XCTAssertEqual(MemoryLayout<_StackLayoutCache>.size, 112)
            XCTAssertEqual(MemoryLayout<_StackLayoutCache>.stride, 112)
            XCTAssertEqual(MemoryLayout<_StackLayoutCache>.alignment, 8)
#endif
        }
    }

    func testCustomLayoutValueCacheRemainsOpaqueAndPersistent() {
        withGraph { graph in
            let owner = graph.makeInput(value: ())
            let environment = graph.makeInput(value: EnvironmentValues())
            let context = SizeAndSpacingContext(
                context: AnyRuleContext(attribute: owner.identifier),
                owner: owner.identifier,
                environment: environment
            )
            let children = LayoutProxyCollection(
                context: AnyRuleContext(attribute: owner.identifier),
                attributes: []
            )
            let state = OpaqueValueCacheState()
            var engine = ViewLayoutEngine(
                layout: OpaqueValueCacheLayout(revision: 0, state: state),
                context: context,
                children: children
            )

            XCTAssertEqual(engine.sizeThatFits(.unspecified), CGSize(width: 10, height: 20))
            _ = engine.childGeometries(at: ViewSize(width: 10, height: 20), origin: .zero)

            engine.update(
                layout: OpaqueValueCacheLayout(revision: 1, state: state),
                context: context,
                children: children
            )
            XCTAssertEqual(
                engine.sizeThatFits(_ProposedSize(width: 50, height: 50)),
                CGSize(width: 11, height: 21)
            )

            XCTAssertEqual(state.makeCount, 1)
            XCTAssertEqual(state.updateCount, 1)
            XCTAssertEqual(
                state.snapshots,
                [
                    ["make:0:0", "size:0:0"],
                    ["make:0:0", "size:0:0", "place:0:0"],
                    ["make:0:0", "size:0:0", "place:0:0"],
                    ["make:0:0", "size:0:0", "place:0:0", "update:1:0", "size:1:0"],
                ]
            )
        }
    }

    private func storageCaseName(of subviews: LayoutSubviews) -> String? {
        let storage = reflectedField(subviews, named: "storage")
        return storage.flatMap {
            Mirror(reflecting: $0).children.first?.label
        }
    }

    private func reflectedStack(
        _ cache: _StackLayoutCache
    ) -> (header: Any, children: [Any]) {
        let stack = reflectedField(cache, named: "stack")!
        let header = reflectedField(stack, named: "header")!
        let children = Mirror(
            reflecting: reflectedField(stack, named: "children")!
        ).children.map(\.value)
        return (header, children)
    }

    private func reflectedField(_ value: Any, named name: String) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }

    private func withGraph(_ body: (_AGGraph) -> Void) {
        let graph = _AGGraph()
        _AGGraphContext(graph: graph).withCurrent {
            body(graph)
        }
    }
}
