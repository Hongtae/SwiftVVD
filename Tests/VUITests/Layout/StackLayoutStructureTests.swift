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

private enum StackNaNAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        CGFloat.nan
    }
}

private enum StackPositiveInfinityAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        CGFloat.infinity
    }
}

private enum StackNegativeInfinityAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        -CGFloat.infinity
    }
}

private enum StackExplicitAlignmentID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
}

private struct StackEdgeLayoutEngine: LayoutEngine {
    var size: CGSize
    var explicitValue: CGFloat?

    mutating func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        size
    }

    mutating func explicitAlignment(
        _ key: AlignmentKey,
        at size: ViewSize
    ) -> CGFloat? {
        guard key == HorizontalAlignment(StackExplicitAlignmentID.self).key else {
            return nil
        }
        return explicitValue
    }
}

private func isUnaryViewRoot<T>(_ value: T) -> Bool {
    value is any _VariadicView_UnaryViewRoot
}

final class StackLayoutStructureTests: XCTestCase {
    func testPublicStackLayoutsAreDistinctDerivedShells() {
        let publicH = HStackLayout(alignment: .bottom, spacing: 7)
        let internalH = _HStackLayout(alignment: .bottom, spacing: 7)
        let publicV = VStackLayout(alignment: .trailing, spacing: 9)
        let internalV = _VStackLayout(alignment: .trailing, spacing: 9)

        XCTAssertNotEqual(
            ObjectIdentifier(HStackLayout.self),
            ObjectIdentifier(_HStackLayout.self)
        )
        XCTAssertNotEqual(
            ObjectIdentifier(VStackLayout.self),
            ObjectIdentifier(_VStackLayout.self)
        )
        XCTAssertEqual(MemoryLayout<HStackLayout>.size, MemoryLayout<_HStackLayout>.size)
        XCTAssertEqual(MemoryLayout<HStackLayout>.stride, MemoryLayout<_HStackLayout>.stride)
        XCTAssertEqual(MemoryLayout<VStackLayout>.size, MemoryLayout<_VStackLayout>.size)
        XCTAssertEqual(MemoryLayout<VStackLayout>.stride, MemoryLayout<_VStackLayout>.stride)
        XCTAssertTrue(HStackLayout.Cache.self == _HStackLayout.Cache.self)
        XCTAssertTrue(VStackLayout.Cache.self == _VStackLayout.Cache.self)

        XCTAssertEqual(publicH.base.alignment, internalH.alignment)
        XCTAssertEqual(publicH.base.spacing, internalH.spacing)
        XCTAssertEqual(publicV.base.alignment, internalV.alignment)
        XCTAssertEqual(publicV.base.spacing, internalV.spacing)

        XCTAssertFalse(isUnaryViewRoot(publicH))
        XCTAssertFalse(isUnaryViewRoot(publicV))
        XCTAssertTrue(isUnaryViewRoot(internalH))
        XCTAssertTrue(isUnaryViewRoot(internalV))

        XCTAssertEqual(HStackLayout.layoutProperties.stackOrientation, .horizontal)
        XCTAssertTrue(HStackLayout.layoutProperties.isIdentityUnaryLayout)
        XCTAssertEqual(VStackLayout.layoutProperties.stackOrientation, .vertical)
        XCTAssertTrue(VStackLayout.layoutProperties.isIdentityUnaryLayout)
    }

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
                    .origin.x.isNaN
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
                    .origin.x.isNaN
            )

#if !DEBUG
            XCTAssertEqual(MemoryLayout<_StackLayoutCache>.size, 112)
            XCTAssertEqual(MemoryLayout<_StackLayoutCache>.stride, 112)
            XCTAssertEqual(MemoryLayout<_StackLayoutCache>.alignment, 8)
#endif
        }
    }

    func testStackAlignmentEdgesMatchNaNAndInfinityGeometrySemantics() {
        withGraph { graph in
            let subviews = makeStackSubviews(
                graph: graph,
                computer: LayoutComputer(
                    StackEdgeLayoutEngine(
                        size: CGSize(width: 20, height: 10),
                        explicitValue: nil
                    )
                )
            )
            let proposal = ProposedViewSize(width: 40, height: 20)

            let hNaN = resolveStack(
                HStackLayout(
                    alignment: VerticalAlignment(StackNaNAlignmentID.self),
                    spacing: 0
                ),
                proposal: proposal,
                subviews: subviews
            )
            XCTAssertEqual(hNaN.geometry.origin, CGPoint(x: 0, y: -CGFloat.infinity))
            XCTAssertEqual(hNaN.size, CGSize(width: 20, height: CGFloat.infinity))

            let hPositive = resolveStack(
                HStackLayout(
                    alignment: VerticalAlignment(
                        StackPositiveInfinityAlignmentID.self
                    ),
                    spacing: 0
                ),
                proposal: proposal,
                subviews: subviews
            )
            XCTAssertEqual(
                hPositive.geometry.origin,
                CGPoint(x: 0, y: -CGFloat.infinity)
            )
            XCTAssertEqual(
                hPositive.size,
                CGSize(width: 20, height: CGFloat.infinity)
            )

            let hNegative = resolveStack(
                HStackLayout(
                    alignment: VerticalAlignment(
                        StackNegativeInfinityAlignmentID.self
                    ),
                    spacing: 0
                ),
                proposal: proposal,
                subviews: subviews
            )
            XCTAssertEqual(
                hNegative.geometry.origin,
                CGPoint(x: 0, y: CGFloat.infinity)
            )
            XCTAssertEqual(hNegative.size, CGSize(width: 20, height: 0))

            let vNaN = resolveStack(
                VStackLayout(
                    alignment: HorizontalAlignment(StackNaNAlignmentID.self),
                    spacing: 0
                ),
                proposal: proposal,
                subviews: subviews
            )
            XCTAssertEqual(vNaN.geometry.origin, CGPoint(x: -CGFloat.infinity, y: 0))
            XCTAssertEqual(vNaN.size, CGSize(width: CGFloat.infinity, height: 10))

            let vPositive = resolveStack(
                VStackLayout(
                    alignment: HorizontalAlignment(
                        StackPositiveInfinityAlignmentID.self
                    ),
                    spacing: 0
                ),
                proposal: proposal,
                subviews: subviews
            )
            XCTAssertEqual(
                vPositive.geometry.origin,
                CGPoint(x: -CGFloat.infinity, y: 0)
            )
            XCTAssertEqual(
                vPositive.size,
                CGSize(width: CGFloat.infinity, height: 10)
            )

            let vNegative = resolveStack(
                VStackLayout(
                    alignment: HorizontalAlignment(
                        StackNegativeInfinityAlignmentID.self
                    ),
                    spacing: 0
                ),
                proposal: proposal,
                subviews: subviews
            )
            XCTAssertEqual(
                vNegative.geometry.origin,
                CGPoint(x: CGFloat.infinity, y: 0)
            )
            XCTAssertEqual(vNegative.size, CGSize(width: 0, height: 10))
        }
    }

    func testStackCommitsAndPropagatesExplicitAlignmentForNullGeometry() {
        withGraph { graph in
            let subviews = makeStackSubviews(
                graph: graph,
                computer: LayoutComputer(
                    StackEdgeLayoutEngine(
                        size: CGSize(width: 20, height: 10),
                        explicitValue: 3
                    )
                )
            )
            let layout = HStackLayout(
                alignment: VerticalAlignment(
                    StackNegativeInfinityAlignmentID.self
                ),
                spacing: 0
            )
            let proposal = ProposedViewSize(width: 40, height: 20)
            var cache = layout.makeCache(subviews: subviews)
            _ = layout.sizeThatFits(
                proposal: proposal,
                subviews: subviews,
                cache: &cache
            )

            let explicit = layout.explicitAlignment(
                of: HorizontalAlignment(StackExplicitAlignmentID.self),
                in: CGRect(x: 0, y: 0, width: 40, height: 20),
                proposal: proposal,
                subviews: subviews,
                cache: &cache
            )
            XCTAssertEqual(explicit, 3)

            var placement = PlacementData(
                count: 1,
                bounds: CGRect(x: 0, y: 0, width: 40, height: 20),
                layoutDirection: .leftToRight
            )
            withUnsafeMutablePointer(to: &placement) { pointer in
                ThreadLayoutData.withPlacementData(pointer) {
                    layout.placeSubviews(
                        in: CGRect(x: 0, y: 0, width: 40, height: 20),
                        proposal: proposal,
                        subviews: subviews,
                        cache: &cache
                    )
                }
            }
            XCTAssertEqual(placement.placedCount, 1)
            XCTAssertEqual(
                placement.geometries[0].origin,
                CGPoint(x: 0, y: CGFloat.infinity)
            )
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

    private func makeStackSubviews(
        graph: _AGGraph,
        computer: LayoutComputer
    ) -> LayoutSubviews {
        let owner = graph.makeInput(value: ())
        return LayoutSubviews(
            context: AnyRuleContext(attribute: owner.identifier),
            attributes: [
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(value: computer)
                ),
            ],
            layoutDirection: .leftToRight
        )
    }

    private func resolveStack<L: Layout>(
        _ layout: L,
        proposal: ProposedViewSize,
        subviews: L.Subviews
    ) -> (size: CGSize, geometry: ViewGeometry)
    where L.Cache == _StackLayoutCache {
        var cache = layout.makeCache(subviews: subviews)
        let size = layout.sizeThatFits(
            proposal: proposal,
            subviews: subviews,
            cache: &cache
        )
        let stack = reflectedStack(cache)
        let geometry = reflectedField(
            stack.children[0],
            named: "geometry"
        ) as! ViewGeometry
        return (size, geometry)
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
