import XCTest
@testable import VUI

final class SystemScrollViewHostTests: XCTestCase {
    func testFixedAreaScrollIndicatorsReserveViewportAndCornerByAxis() throws {
        let configuration = ScrollViewConfiguration(
            axes: [.horizontal, .vertical],
            showsIndicators: false
        )
        var properties = ScrollEnvironmentProperties()
        properties.horizontalIndicator = ScrollIndicatorConfiguration(
            visibility: .hidden,
            style: .fixedArea
        )
        properties.verticalIndicator = ScrollIndicatorConfiguration(
            visibility: .hidden,
            style: .fixedArea
        )
        let metrics = ScrollIndicatorMetricsStorage(
            horizontal: ScrollIndicatorMetrics(
                thickness: 6,
                minimumThumbLength: 18
            ),
            vertical: ScrollIndicatorMetrics(
                thickness: 10,
                minimumThumbLength: 20
            )
        )

        let layout = ScrollIndicatorLayout.make(
            outerSize: CGSize(width: 100, height: 80),
            contentOffset: CGPoint(x: 105, y: 63),
            contentSize: CGSize(width: 300, height: 200),
            contentInsets: EdgeInsets(),
            configuration: configuration,
            properties: properties,
            metrics: metrics,
            layoutDirection: .leftToRight,
            overlayOpacity: 0
        )

        XCTAssertEqual(layout.viewportFrame, CGRect(x: 0, y: 0, width: 84, height: 68))
        XCTAssertEqual(
            layout.reservedInsets,
            EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 16)
        )
        XCTAssertEqual(layout.horizontal?.trackFrame, CGRect(x: 3, y: 71, width: 78, height: 6))
        let horizontal = try XCTUnwrap(layout.horizontal)
        XCTAssertEqual(horizontal.thumbFrame.minX, 30.3, accuracy: 0.001)
        XCTAssertEqual(horizontal.thumbFrame.minY, 71, accuracy: 0.001)
        XCTAssertEqual(horizontal.thumbFrame.width, 21.84, accuracy: 0.001)
        XCTAssertEqual(horizontal.thumbFrame.height, 6, accuracy: 0.001)
        let vertical = try XCTUnwrap(layout.vertical)
        XCTAssertEqual(vertical.trackFrame, CGRect(x: 87, y: 3, width: 10, height: 62))
        XCTAssertEqual(vertical.thumbFrame.minY, 22.53, accuracy: 0.001)
        XCTAssertEqual(vertical.thumbFrame.height, 21.08, accuracy: 0.001)
        XCTAssertNil(vertical.proximityFrame)
        XCTAssertEqual(vertical.trackOpacity, 1)
        XCTAssertEqual(layout.cornerFrame, CGRect(x: 84, y: 68, width: 16, height: 12))
    }

    func testFixedAreaNeverHidesIndicatorWithoutReleasingReservedViewport() {
        let configuration = ScrollViewConfiguration(axes: .vertical)
        var properties = ScrollEnvironmentProperties()
        properties.verticalIndicator = ScrollIndicatorConfiguration(
            visibility: .never,
            style: .fixedArea
        )
        let metrics = ScrollIndicatorMetricsStorage(
            vertical: ScrollIndicatorMetrics(thickness: 12, minimumThumbLength: 24)
        )

        let layout = ScrollIndicatorLayout.make(
            outerSize: CGSize(width: 80, height: 60),
            contentOffset: .zero,
            contentSize: CGSize(width: 68, height: 40),
            contentInsets: EdgeInsets(),
            configuration: configuration,
            properties: properties,
            metrics: metrics,
            layoutDirection: .leftToRight,
            overlayOpacity: 1
        )

        XCTAssertEqual(layout.viewportFrame, CGRect(x: 0, y: 0, width: 62, height: 60))
        XCTAssertEqual(layout.reservedInsets.trailing, 18)
        XCTAssertNil(layout.vertical)
    }

    func testOverlayScrollIndicatorUsesOpacityMinimumThumbAndRTLProgress() throws {
        let configuration = ScrollViewConfiguration(axes: .horizontal)
        var properties = ScrollEnvironmentProperties()
        properties.horizontalIndicator = ScrollIndicatorConfiguration(
            visibility: .visible,
            style: .automatic
        )
        let metrics = ScrollIndicatorMetricsStorage(
            horizontal: ScrollIndicatorMetrics(
                thickness: 6,
                minimumThumbLength: 30
            )
        )

        let layout = ScrollIndicatorLayout.make(
            outerSize: CGSize(width: 100, height: 50),
            contentOffset: CGPoint(x: 100, y: 0),
            contentSize: CGSize(width: 400, height: 50),
            contentInsets: EdgeInsets(),
            configuration: configuration,
            properties: properties,
            metrics: metrics,
            layoutDirection: .rightToLeft,
            overlayOpacity: 0.4
        )

        XCTAssertEqual(layout.viewportFrame, CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(layout.reservedInsets, EdgeInsets())
        let horizontal = try XCTUnwrap(layout.horizontal)
        XCTAssertEqual(horizontal.trackFrame, CGRect(x: 3, y: 41, width: 94, height: 6))
        XCTAssertEqual(horizontal.thumbFrame.minX, 45.666, accuracy: 0.001)
        XCTAssertEqual(horizontal.thumbFrame.width, 30)
        XCTAssertEqual(horizontal.trackOpacity, 0)
        XCTAssertEqual(horizontal.opacity, 0.4)
        XCTAssertFalse(horizontal.isFixedArea)
    }

    // ASSERTIONS scrollIndicatorPresentationGeometryObserved
    func testDefaultScrollIndicatorMetricsResolveByPresentationStyle() throws {
        let configuration = ScrollViewConfiguration(axes: .vertical)

        func layout(
            style: ScrollIndicatorStyle,
            metrics: ScrollIndicatorMetricsStorage = ScrollIndicatorMetricsStorage(),
            contentOffset: CGPoint = .zero,
            contentHeight: CGFloat = 240,
            expansion: CGFloat = 0
        ) -> ScrollIndicatorLayout {
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: style
            )
            return ScrollIndicatorLayout.make(
                outerSize: CGSize(width: 100, height: 80),
                contentOffset: contentOffset,
                contentSize: CGSize(width: 100, height: contentHeight),
                contentInsets: EdgeInsets(),
                configuration: configuration,
                properties: properties,
                metrics: metrics,
                layoutDirection: .leftToRight,
                overlayOpacity: 1,
                expansion: ScrollIndicatorExpansion(vertical: expansion)
            )
        }

        let automatic = layout(style: .automatic)
        let collapsedOverlay = layout(style: .overlay)
        let expandedOverlay = layout(style: .overlay, expansion: 1)
        let fixedArea = layout(style: .fixedArea)

        XCTAssertEqual(automatic.vertical?.trackFrame, collapsedOverlay.vertical?.trackFrame)
        XCTAssertEqual(
            collapsedOverlay.vertical?.trackFrame,
            CGRect(x: 91, y: 3, width: 6, height: 74)
        )
        XCTAssertEqual(
            expandedOverlay.vertical?.trackFrame,
            CGRect(x: 86, y: 3, width: 11, height: 74)
        )
        XCTAssertEqual(
            expandedOverlay.vertical?.proximityFrame,
            CGRect(x: 84, y: 3, width: 15, height: 74)
        )
        XCTAssertEqual(
            fixedArea.vertical?.trackFrame,
            CGRect(x: 86, y: 3, width: 11, height: 74)
        )
        XCTAssertEqual(fixedArea.reservedInsets.trailing, 17)
        XCTAssertEqual(fixedArea.viewportFrame.width, 83)

        let minimumAutomatic = layout(
            style: .automatic,
            contentHeight: 2_000
        )
        let minimumOverlay = layout(
            style: .overlay,
            contentHeight: 2_000
        )
        let minimumFixedArea = layout(
            style: .fixedArea,
            contentHeight: 2_000
        )
        XCTAssertEqual(minimumAutomatic.vertical?.thumbFrame.height, 26)
        XCTAssertEqual(minimumOverlay.vertical?.thumbFrame.height, 26)
        XCTAssertEqual(minimumFixedArea.vertical?.thumbFrame.height, 20)

        let trailingOverlay = layout(
            style: .overlay,
            contentOffset: CGPoint(x: 0, y: 160)
        )
        XCTAssertEqual(collapsedOverlay.vertical?.thumbFrame.minY, 3)
        XCTAssertEqual(trailingOverlay.vertical?.thumbFrame.maxY, 77)

        let customMetrics = ScrollIndicatorMetricsStorage(
            vertical: ScrollIndicatorMetrics(
                thickness: 7,
                minimumThumbLength: 24
            )
        )
        let customFixedArea = layout(
            style: .fixedArea,
            metrics: customMetrics,
            contentHeight: 2_000
        )
        let customOverlay = layout(
            style: .overlay,
            metrics: customMetrics,
            contentHeight: 2_000
        )
        XCTAssertEqual(customFixedArea.vertical?.trackFrame.width, 7)
        XCTAssertEqual(customFixedArea.reservedInsets.trailing, 13)
        XCTAssertEqual(customFixedArea.vertical?.thumbFrame.height, 24)
        XCTAssertEqual(customOverlay.vertical?.thumbFrame.height, 24)

        let zeroThicknessFixedArea = layout(
            style: .fixedArea,
            metrics: ScrollIndicatorMetricsStorage(
                vertical: ScrollIndicatorMetrics(
                    thickness: 0,
                    minimumThumbLength: 24
                )
            )
        )
        XCTAssertEqual(zeroThicknessFixedArea.reservedInsets.trailing, 0)
    }

    func testPresentationMetricsDriveSharedIndicatorGeometry() throws {
        let configuration = ScrollViewConfiguration(axes: .vertical)
        let presentation = ScrollIndicatorPresentationMetrics(
            overlayThickness: 10,
            overlayMinimumThumbLength: 30,
            fixedAreaThickness: 14,
            fixedAreaMinimumThumbLength: 28,
            trackSideInset: 4,
            trackEndInset: 5,
            overlayExpansion: 6,
            overlayProximityPadding: 3
        )
        let metrics = ScrollIndicatorMetricsStorage(presentation: presentation)

        func layout(
            style: ScrollIndicatorStyle,
            expansion: CGFloat = 0
        ) -> ScrollIndicatorLayout {
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: style
            )
            return ScrollIndicatorLayout.make(
                outerSize: CGSize(width: 120, height: 100),
                contentOffset: .zero,
                contentSize: CGSize(width: 120, height: 400),
                contentInsets: EdgeInsets(),
                configuration: configuration,
                properties: properties,
                metrics: metrics,
                layoutDirection: .leftToRight,
                overlayOpacity: 1,
                expansion: ScrollIndicatorExpansion(vertical: expansion)
            )
        }

        let overlay = layout(style: .overlay, expansion: 1)
        XCTAssertEqual(
            overlay.vertical?.trackFrame,
            CGRect(x: 100, y: 5, width: 16, height: 90)
        )
        XCTAssertEqual(
            overlay.vertical?.proximityFrame,
            CGRect(x: 97, y: 5, width: 22, height: 90)
        )
        XCTAssertEqual(overlay.vertical?.thumbFrame.height, 30)

        let fixedArea = layout(style: .fixedArea)
        XCTAssertEqual(fixedArea.reservedInsets.trailing, 22)
        XCTAssertEqual(fixedArea.viewportFrame.width, 98)
        XCTAssertEqual(
            fixedArea.vertical?.trackFrame,
            CGRect(x: 102, y: 5, width: 14, height: 90)
        )
        XCTAssertEqual(fixedArea.vertical?.thumbFrame.height, 28)
    }

    // ASSERTIONS scrollIndicatorPresentationGeometryObserved scrollIndicatorSkinRuntimeObserved
    func testOverlayScrollIndicatorSeparatesDrawInteractionAndProximityGeometry() throws {
        let configuration = ScrollViewConfiguration(
            axes: [.horizontal, .vertical]
        )
        var properties = ScrollEnvironmentProperties()
        properties.horizontalIndicator = ScrollIndicatorConfiguration(
            visibility: .visible,
            style: .overlay
        )
        properties.verticalIndicator = ScrollIndicatorConfiguration(
            visibility: .visible,
            style: .overlay
        )
        let metrics = ScrollIndicatorMetricsStorage(
            horizontal: ScrollIndicatorMetrics(
                thickness: 6,
                minimumThumbLength: 20
            ),
            vertical: ScrollIndicatorMetrics(
                thickness: 8,
                minimumThumbLength: 20
            )
        )

        let collapsed = ScrollIndicatorLayout.make(
            outerSize: CGSize(width: 100, height: 80),
            contentOffset: CGPoint(x: 40, y: 40),
            contentSize: CGSize(width: 300, height: 240),
            contentInsets: EdgeInsets(),
            configuration: configuration,
            properties: properties,
            metrics: metrics,
            layoutDirection: .leftToRight,
            overlayOpacity: 1
        )
        let expanded = ScrollIndicatorLayout.make(
            outerSize: CGSize(width: 100, height: 80),
            contentOffset: CGPoint(x: 40, y: 40),
            contentSize: CGSize(width: 300, height: 240),
            contentInsets: EdgeInsets(),
            configuration: configuration,
            properties: properties,
            metrics: metrics,
            layoutDirection: .leftToRight,
            overlayOpacity: 1,
            expansion: ScrollIndicatorExpansion(horizontal: 1, vertical: 1)
        )

        XCTAssertEqual(collapsed.horizontal?.trackFrame, CGRect(
            x: 3,
            y: 71,
            width: 94,
            height: 6
        ))
        XCTAssertEqual(expanded.horizontal?.trackFrame, CGRect(
            x: 3,
            y: 66,
            width: 94,
            height: 11
        ))
        XCTAssertEqual(expanded.horizontal?.proximityFrame, CGRect(
            x: 3,
            y: 64,
            width: 94,
            height: 15
        ))
        XCTAssertEqual(collapsed.horizontal?.trackOpacity, 0)
        XCTAssertEqual(expanded.horizontal?.trackOpacity, 1)
        XCTAssertEqual(collapsed.vertical?.trackFrame, CGRect(
            x: 89,
            y: 3,
            width: 8,
            height: 74
        ))
        XCTAssertEqual(expanded.vertical?.trackFrame, CGRect(
            x: 84,
            y: 3,
            width: 13,
            height: 74
        ))
        XCTAssertEqual(expanded.vertical?.proximityFrame, CGRect(
            x: 82,
            y: 3,
            width: 17,
            height: 74
        ))
        XCTAssertEqual(collapsed.vertical?.trackOpacity, 0)
        XCTAssertEqual(expanded.vertical?.trackOpacity, 1)

        let proximityOnlyPoint = CGPoint(x: 84, y: 30)
        XCTAssertEqual(collapsed.hoverAxes(at: proximityOnlyPoint), .vertical)
        XCTAssertNil(collapsed.interactionPart(
            at: proximityOnlyPoint,
            layoutDirection: .leftToRight
        ))

        let rtl = ScrollIndicatorLayout.make(
            outerSize: CGSize(width: 100, height: 80),
            contentOffset: CGPoint(x: 40, y: 40),
            contentSize: CGSize(width: 300, height: 240),
            contentInsets: EdgeInsets(),
            configuration: configuration,
            properties: properties,
            metrics: metrics,
            layoutDirection: .rightToLeft,
            overlayOpacity: 1,
            expansion: ScrollIndicatorExpansion(vertical: 1)
        )
        XCTAssertEqual(rtl.vertical?.trackFrame.minX, 3)
        XCTAssertEqual(rtl.vertical?.trackFrame.width, 13)
        XCTAssertEqual(rtl.vertical?.proximityFrame?.minX, 1)
        XCTAssertEqual(rtl.vertical?.proximityFrame?.width, 17)
    }

    func testScrollIndicatorCompressesOverscrolledThumbAtLogicalEndpoints() throws {
        let configuration = ScrollViewConfiguration(
            axes: [.horizontal, .vertical]
        )
        var properties = ScrollEnvironmentProperties()
        properties.horizontalIndicator = ScrollIndicatorConfiguration(
            visibility: .visible,
            style: .overlay
        )
        properties.verticalIndicator = ScrollIndicatorConfiguration(
            visibility: .visible,
            style: .overlay
        )
        let metrics = ScrollIndicatorMetricsStorage(
            horizontal: ScrollIndicatorMetrics(
                thickness: 8,
                minimumThumbLength: 20
            ),
            vertical: ScrollIndicatorMetrics(
                thickness: 8,
                minimumThumbLength: 20
            )
        )

        func layout(
            offset: CGPoint,
            direction: LayoutDirection
        ) -> ScrollIndicatorLayout {
            ScrollIndicatorLayout.make(
                outerSize: CGSize(width: 100, height: 100),
                contentOffset: offset,
                contentSize: CGSize(width: 250, height: 250),
                contentInsets: EdgeInsets(),
                configuration: configuration,
                properties: properties,
                metrics: metrics,
                layoutDirection: direction,
                overlayOpacity: 1
            )
        }

        let normalStart = layout(offset: .zero, direction: .leftToRight)
        let overscrolledStart = layout(
            offset: CGPoint(x: -25, y: -25),
            direction: .leftToRight
        )
        XCTAssertEqual(normalStart.horizontal?.thumbFrame.width, 37.6)
        XCTAssertEqual(normalStart.vertical?.thumbFrame.height, 37.6)
        XCTAssertEqual(overscrolledStart.horizontal?.thumbFrame, CGRect(
            x: 3,
            y: 89,
            width: 28.2,
            height: 8
        ))
        XCTAssertEqual(overscrolledStart.vertical?.thumbFrame, CGRect(
            x: 89,
            y: 3,
            width: 8,
            height: 28.2
        ))

        let overscrolledEnd = layout(
            offset: CGPoint(x: 175, y: 175),
            direction: .leftToRight
        )
        XCTAssertEqual(overscrolledEnd.horizontal?.thumbFrame, CGRect(
            x: 68.8,
            y: 89,
            width: 28.2,
            height: 8
        ))
        XCTAssertEqual(overscrolledEnd.vertical?.thumbFrame, CGRect(
            x: 89,
            y: 68.8,
            width: 8,
            height: 28.2
        ))

        let fullyOverscrolled = layout(
            offset: CGPoint(x: 500, y: -500),
            direction: .leftToRight
        )
        XCTAssertEqual(fullyOverscrolled.horizontal?.thumbFrame, CGRect(
            x: 77,
            y: 89,
            width: 20,
            height: 8
        ))
        XCTAssertEqual(fullyOverscrolled.vertical?.thumbFrame, CGRect(
            x: 89,
            y: 3,
            width: 8,
            height: 20
        ))

        let rtlStart = layout(
            offset: CGPoint(x: -25, y: 0),
            direction: .rightToLeft
        )
        let rtlEnd = layout(
            offset: CGPoint(x: 175, y: 0),
            direction: .rightToLeft
        )
        XCTAssertEqual(rtlStart.horizontal?.thumbFrame.minX, 68.8)
        XCTAssertEqual(rtlStart.horizontal?.thumbFrame.maxX, 97)
        XCTAssertEqual(rtlEnd.horizontal?.thumbFrame.minX, 3)
        XCTAssertEqual(rtlEnd.horizontal?.thumbFrame.maxX, 31.2)
    }

    func testOverlayScrollIndicatorRequiresOverflowAndPresentationPermission() {
        var configuration = ScrollViewConfiguration(axes: .vertical)
        var properties = ScrollEnvironmentProperties()
        let metrics = ScrollIndicatorMetricsStorage()

        func layout(contentHeight: CGFloat) -> ScrollIndicatorLayout {
            ScrollIndicatorLayout.make(
                outerSize: CGSize(width: 80, height: 60),
                contentOffset: .zero,
                contentSize: CGSize(width: 80, height: contentHeight),
                contentInsets: EdgeInsets(),
                configuration: configuration,
                properties: properties,
                metrics: metrics,
                layoutDirection: .leftToRight,
                overlayOpacity: 1
            )
        }

        XCTAssertNil(layout(contentHeight: 60).vertical)
        XCTAssertNotNil(layout(contentHeight: 120).vertical)

        configuration.showsIndicators = false
        XCTAssertNil(layout(contentHeight: 120).vertical)

        configuration.showsIndicators = true
        properties.verticalIndicator.visibility = .hidden
        XCTAssertNil(layout(contentHeight: 120).vertical)
    }

    func testScrollIndicatorInteractionPartsRespectThumbAndHorizontalRTL() {
        var layout = ScrollIndicatorLayout()
        layout.horizontal = ScrollIndicatorLayout.Indicator(
            trackFrame: CGRect(x: 0, y: 90, width: 100, height: 10),
            thumbFrame: CGRect(x: 30, y: 90, width: 20, height: 10),
            opacity: 1,
            isFixedArea: true
        )
        layout.vertical = ScrollIndicatorLayout.Indicator(
            trackFrame: CGRect(x: 90, y: 0, width: 10, height: 90),
            thumbFrame: CGRect(x: 90, y: 30, width: 10, height: 20),
            opacity: 1,
            isFixedArea: true
        )

        XCTAssertEqual(
            layout.interactionPart(
                at: CGPoint(x: 95, y: 40),
                layoutDirection: .leftToRight
            ),
            .thumb(.vertical)
        )
        XCTAssertEqual(
            layout.interactionPart(
                at: CGPoint(x: 95, y: 10),
                layoutDirection: .leftToRight
            ),
            .decrementPage(.vertical)
        )
        XCTAssertEqual(
            layout.interactionPart(
                at: CGPoint(x: 95, y: 70),
                layoutDirection: .leftToRight
            ),
            .incrementPage(.vertical)
        )
        XCTAssertEqual(
            layout.interactionPart(
                at: CGPoint(x: 10, y: 95),
                layoutDirection: .leftToRight
            ),
            .decrementPage(.horizontal)
        )
        XCTAssertEqual(
            layout.interactionPart(
                at: CGPoint(x: 10, y: 95),
                layoutDirection: .rightToLeft
            ),
            .incrementPage(.horizontal)
        )
        XCTAssertNil(layout.interactionPart(
            at: CGPoint(x: 50, y: 50),
            layoutDirection: .leftToRight
        ))
    }

    func testHostingScrollViewThumbDragCapturesOutsideTrackAndPublishesPhase() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let host = makeIndicatorHost(
                graph: graph,
                axes: .vertical,
                contentOffset: CGPoint(x: 0, y: 100),
                contentSize: CGSize(width: 90, height: 500),
                viewportSize: CGSize(width: 90, height: 100)
            )
            let thumb = try XCTUnwrap(host.host.indicatorLayout.vertical?.thumbFrame)
            let track = try XCTUnwrap(host.host.indicatorLayout.vertical?.trackFrame)
            let start = CGPoint(x: thumb.midX, y: thumb.midY)
            XCTAssertEqual(
                host.scrollIndicatorInteractionPart(at: start),
                .thumb(.vertical)
            )
            XCTAssertTrue(host.beginScrollIndicatorInteraction(
                .thumb(.vertical),
                at: start,
                time: Time(seconds: 1)
            ))
            XCTAssertEqual(host.currentPhaseState.phase, .interacting)
            XCTAssertEqual(host.currentPhaseState.velocity, .zero)

            let halfTravel = (track.height - thumb.height) / 2
            host.updateScrollIndicatorInteraction(at: CGPoint(
                x: -200,
                y: start.y + halfTravel
            ))
            XCTAssertEqual(
                host.makeLayoutState().contentOffset.y,
                300,
                accuracy: 0.000_001
            )

            host.endScrollIndicatorInteraction(cancelled: false)
            XCTAssertEqual(host.currentPhaseState.phase, .idle)
            XCTAssertEqual(host.currentPhaseState.velocity, .zero)
        }
    }

    func testHostingScrollViewHorizontalRTLThumbDragReversesOffsetMapping() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let host = makeIndicatorHost(
                graph: graph,
                axes: .horizontal,
                contentOffset: CGPoint(x: 100, y: 0),
                contentSize: CGSize(width: 500, height: 90),
                viewportSize: CGSize(width: 100, height: 90),
                layoutDirection: .rightToLeft
            )
            let thumb = try XCTUnwrap(host.host.indicatorLayout.horizontal?.thumbFrame)
            let track = try XCTUnwrap(host.host.indicatorLayout.horizontal?.trackFrame)
            let start = CGPoint(x: thumb.midX, y: thumb.midY)
            XCTAssertTrue(host.beginScrollIndicatorInteraction(
                .thumb(.horizontal),
                at: start,
                time: Time(seconds: 1)
            ))

            let halfTravel = (track.width - thumb.width) / 2
            host.updateScrollIndicatorInteraction(at: CGPoint(
                x: start.x - halfTravel,
                y: -100
            ))
            XCTAssertEqual(
                host.makeLayoutState().contentOffset.x,
                300,
                accuracy: 0.000_001
            )
            host.endScrollIndicatorInteraction(cancelled: false)
        }
    }

    func testHostingScrollViewTrackPagingUsesOverlapAnimationAndTerminalIdle() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let host = makeIndicatorHost(
                graph: graph,
                axes: .vertical,
                contentOffset: CGPoint(x: 0, y: 500),
                contentSize: CGSize(width: 90, height: 2_000),
                viewportSize: CGSize(width: 90, height: 200)
            )
            let indicator = try XCTUnwrap(host.host.indicatorLayout.vertical)
            let point = CGPoint(
                x: indicator.trackFrame.midX,
                y: indicator.thumbFrame.maxY + 20
            )
            XCTAssertEqual(
                host.scrollIndicatorInteractionPart(at: point),
                .incrementPage(.vertical)
            )
            XCTAssertTrue(host.beginScrollIndicatorInteraction(
                .incrementPage(.vertical),
                at: point,
                time: Time(seconds: 1)
            ))
            host.endScrollIndicatorInteraction(cancelled: false)
            XCTAssertEqual(host.currentPhaseState.phase, .interacting)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.1)))
            XCTAssertEqual(
                host.makeLayoutState().contentOffset.y,
                595,
                accuracy: 0.000_001
            )
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.21)))
            XCTAssertEqual(
                host.makeLayoutState().contentOffset.y,
                690,
                accuracy: 0.000_001
            )
            XCTAssertEqual(host.currentPhaseState.phase, .idle)
            XCTAssertEqual(host.currentPhaseState.velocity, .zero)
        }
    }

    func testHostingScrollViewTrackPagingRepeatsAfterHoldDelay() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let host = makeIndicatorHost(
                graph: graph,
                axes: .vertical,
                contentOffset: CGPoint(x: 0, y: 500),
                contentSize: CGSize(width: 90, height: 2_000),
                viewportSize: CGSize(width: 90, height: 200)
            )
            let indicator = try XCTUnwrap(host.host.indicatorLayout.vertical)
            let point = CGPoint(
                x: indicator.trackFrame.midX,
                y: indicator.thumbFrame.maxY + 20
            )
            XCTAssertTrue(host.beginScrollIndicatorInteraction(
                .incrementPage(.vertical),
                at: point,
                time: Time(seconds: 1)
            ))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.21)))
            XCTAssertEqual(host.makeLayoutState().contentOffset.y, 690, accuracy: 0.000_001)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.5)))
            XCTAssertEqual(host.makeLayoutState().contentOffset.y, 690, accuracy: 0.000_001)
            XCTAssertEqual(host.currentPhaseState.phase, .interacting)
            host.endScrollIndicatorInteraction(cancelled: false)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.6)))
            XCTAssertEqual(host.makeLayoutState().contentOffset.y, 785, accuracy: 0.000_001)
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.71)))
            XCTAssertEqual(host.makeLayoutState().contentOffset.y, 880, accuracy: 0.000_001)
            XCTAssertEqual(host.currentPhaseState.phase, .idle)
        }
    }

    func testScrollViewResponderExclusivelyCapturesIndicatorSerialOutsideTrack() throws {
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let host = makeIndicatorHost(
                graph: graph,
                axes: .vertical,
                contentOffset: CGPoint(x: 0, y: 100),
                contentSize: CGSize(width: 90, height: 500),
                viewportSize: CGSize(width: 90, height: 100)
            )
            let container = HostingScrollView.PlatformContainer(scrollView: host)
            host.parentContainer = container
            let hostAttribute = graph.makeInput(value: host)
            let position = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let size = graph.makeInput(value: ViewSize(
                CGSize(width: 100, height: 100)
            ))
            let transform = graph.makeInput(value: ViewTransform.identity)
            let child = ScrollHostTestResponder()
            let children = graph.makeInput(value: [child] as [ViewResponder])
            let layoutResponder = DefaultLayoutViewResponder(
                inputs: makeAttachmentViewInputs(
                    graph: graph,
                    position: position,
                    size: size,
                    transform: transform
                ),
                viewSubgraph: AGSubgraph()
            )
            let responders = graph.makeStatefulRule(ScrollViewResponder(
                _scrollView: hostAttribute,
                _position: position,
                _size: size,
                _transform: transform,
                _children: children,
                _responder: nil,
                layoutResponder: layoutResponder
            ))
            let responder = try XCTUnwrap(
                responders.value.first as? HostingScrollViewResponder
            )
            let thumb = try XCTUnwrap(host.host.indicatorLayout.vertical?.thumbFrame)
            let track = try XCTUnwrap(host.host.indicatorLayout.vertical?.trackFrame)
            let halfTravel = (track.height - thumb.height) / 2
            let start = CGPoint(
                x: position.value.x + thumb.midX,
                y: position.value.y + thumb.midY
            )
            let eventID = EventID(type: ScrollEvent.self, serial: 701)
            let began = ScrollEvent(
                timestamp: Time(seconds: 1),
                phase: .began,
                binding: nil,
                translation: .zero,
                modifiers: [],
                hitTestLocation: start
            )
            XCTAssertTrue(responder.exclusivelyConsumes(began))
            let indicatorHit = responder.containsGlobalPoints(
                [start],
                cacheKey: nil,
                options: .platformDefault
            )
            XCTAssertTrue(indicatorHit.mask[0])
            XCTAssertTrue(indicatorHit.children.isEmpty)
            XCTAssertTrue(responder.consumeEvents(
                [eventID: began],
                at: Time(seconds: 1)
            ).isActive)

            let outside = CGPoint(
                x: position.value.x - 200,
                y: position.value.y + thumb.midY + halfTravel
            )
            let active = ScrollEvent(
                timestamp: Time(seconds: 1.1),
                phase: .active,
                binding: nil,
                translation: CGSize(width: -200, height: halfTravel),
                modifiers: [],
                hitTestLocation: outside
            )
            XCTAssertTrue(responder.exclusivelyConsumes(active))
            XCTAssertTrue(responder.consumeEvents(
                [eventID: active],
                at: Time(seconds: 1.1)
            ).isActive)
            XCTAssertEqual(
                host.makeLayoutState().contentOffset.y,
                300,
                accuracy: 0.000_001
            )

            let ended = ScrollEvent(
                timestamp: Time(seconds: 1.2),
                phase: .ended,
                binding: nil,
                translation: CGSize(width: -200, height: halfTravel),
                modifiers: [],
                hitTestLocation: outside
            )
            XCTAssertTrue(responder.exclusivelyConsumes(ended))
            XCTAssertTrue(responder.consumeEvents(
                [eventID: ended],
                at: Time(seconds: 1.2)
            ).isActive)
            XCTAssertEqual(host.currentPhaseState.phase, .idle)
            XCTAssertFalse(responder.exclusivelyConsumes(ended))
        }
    }

    func testHostingScrollViewFadesOverlayIndicatorsOnGraphClock() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let host = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .overlay
            )
            host.updateProperties(properties)
            host.updateIndicatorPresentation(
                outerSize: CGSize(width: 80, height: 60),
                metrics: ScrollIndicatorMetricsStorage(
                    vertical: ScrollIndicatorMetrics(
                        thickness: 6,
                        minimumThumbLength: 20
                    )
                )
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 80, height: 180),
                containingSize: CGSize(width: 80, height: 60),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))

            XCTAssertNil(host.host.indicatorLayout.vertical)
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)

            Update.ensure {
                host.publishSystemContentOffset(CGPoint(x: 0, y: 20))
            }
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.opacity, 1)

            XCTAssertFalse(host.updateIndicatorVisibility(at: Time(seconds: 0.69)))
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)

            XCTAssertTrue(host.updateIndicatorVisibility(at: Time(seconds: 0.825)))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0.5, accuracy: 0.001)
            XCTAssertEqual(
                host.host.indicatorLayout.vertical?.opacity ?? 0,
                0.5,
                accuracy: 0.001
            )

            XCTAssertTrue(host.updateIndicatorVisibility(at: Time(seconds: 0.95)))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)
            XCTAssertNil(host.host.indicatorLayout.vertical)
        }
    }

    // ASSERTIONS scrollIndicatorPresentationGeometryObserved scrollIndicatorSkinRuntimeObserved
    func testHostingScrollViewAnimatesOverlayRolloverAndHoldsVisibility() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let host = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .overlay
            )
            host.updateProperties(properties)
            host.updateIndicatorPresentation(
                outerSize: CGSize(width: 80, height: 60),
                metrics: ScrollIndicatorMetricsStorage(
                    vertical: ScrollIndicatorMetrics(
                        thickness: 8,
                        minimumThumbLength: 20
                    )
                )
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 80, height: 180),
                containingSize: CGSize(width: 80, height: 60),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            Update.ensure {
                host.publishSystemContentOffset(CGPoint(x: 0, y: 20))
            }

            let eventID = EventID(type: HoverEvent.self, serial: 801)
            let proximityPoint = CGPoint(x: 64, y: 30)
            XCTAssertTrue(host.updateScrollIndicatorHover(
                eventID: eventID,
                at: proximityPoint,
                time: .zero
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackFrame.width, 8)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackOpacity, 0)

            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 0.0625)
            ))
            let intermediateWidth = try XCTUnwrap(
                host.host.indicatorLayout.vertical?.trackFrame.width
            )
            XCTAssertGreaterThan(intermediateWidth, 8)
            XCTAssertLessThan(intermediateWidth, 13)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackOpacity, 1)

            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 0.125)
            ))
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackFrame.width, 13)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackOpacity, 1)
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)

            XCTAssertTrue(host.updateScrollIndicatorHover(
                eventID: eventID,
                at: CGPoint(x: 20, y: 30),
                time: Time(seconds: 0.2)
            ))
            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 0.325)
            ))
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackFrame.width, 8)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackOpacity, 0)
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)

            XCTAssertFalse(host.updateIndicatorVisibility(
                at: Time(seconds: 0.899)
            ))
            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 1.025)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0.5, accuracy: 0.001)
            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 1.15)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)
            XCTAssertNil(host.host.indicatorLayout.vertical)

            XCTAssertFalse(host.updateScrollIndicatorHover(
                eventID: eventID,
                at: proximityPoint,
                time: Time(seconds: 1.2)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)
        }
    }

    // ASSERTIONS scrollIndicatorPresentationGeometryObserved scrollIndicatorSkinRuntimeObserved
    func testOverlayIndicatorPressHoldsVisibilityWithoutExpandingTrack() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let host = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .overlay
            )
            host.updateProperties(properties)
            host.updateIndicatorPresentation(
                outerSize: CGSize(width: 80, height: 60),
                metrics: ScrollIndicatorMetricsStorage(
                    vertical: ScrollIndicatorMetrics(
                        thickness: 8,
                        minimumThumbLength: 20
                    )
                )
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 80, height: 180),
                containingSize: CGSize(width: 80, height: 60),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            Update.ensure {
                host.publishSystemContentOffset(CGPoint(x: 0, y: 20))
            }

            let thumb = try XCTUnwrap(
                host.host.indicatorLayout.vertical?.thumbFrame
            )
            let point = CGPoint(x: thumb.midX, y: thumb.midY)
            XCTAssertTrue(host.beginScrollIndicatorInteraction(
                .thumb(.vertical),
                at: point,
                time: Time(seconds: 2)
            ))
            XCTAssertFalse(host.updateIndicatorVisibility(
                at: Time(seconds: 5)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackFrame.width, 8)
            XCTAssertEqual(host.host.indicatorLayout.vertical?.trackOpacity, 0)

            host.endScrollIndicatorInteraction(
                cancelled: false,
                at: Time(seconds: 5)
            )
            XCTAssertFalse(host.updateIndicatorVisibility(
                at: Time(seconds: 5.69)
            ))
            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 5.825)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0.5, accuracy: 0.001)
        }
    }

    // ASSERTIONS scrollIndicatorPresentationGeometryObserved
    func testReleasedOverlayPageAnimationResumesFadeAfterMotionCompletes() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let host = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .overlay
            )
            host.updateProperties(properties)
            host.updateIndicatorPresentation(
                outerSize: CGSize(width: 80, height: 60),
                metrics: ScrollIndicatorMetricsStorage(
                    vertical: ScrollIndicatorMetrics(
                        thickness: 8,
                        minimumThumbLength: 20
                    )
                )
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 80, height: 180),
                containingSize: CGSize(width: 80, height: 60),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            Update.ensure {
                host.publishSystemContentOffset(CGPoint(x: 0, y: 20))
            }

            let indicator = try XCTUnwrap(host.host.indicatorLayout.vertical)
            let point = CGPoint(
                x: indicator.trackFrame.midX,
                y: indicator.thumbFrame.maxY + 5
            )
            XCTAssertTrue(host.beginScrollIndicatorInteraction(
                .incrementPage(.vertical),
                at: point,
                time: Time(seconds: 2)
            ))
            host.endScrollIndicatorInteraction(
                cancelled: false,
                at: Time(seconds: 2.01)
            )

            XCTAssertFalse(host.updateIndicatorVisibility(
                at: Time(seconds: 2.1)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 2.21)))
            XCTAssertEqual(host.currentPhaseState.phase, .idle)

            XCTAssertFalse(host.updateIndicatorVisibility(
                at: Time(seconds: 2.9)
            ))
            XCTAssertTrue(host.updateIndicatorVisibility(
                at: Time(seconds: 3.035)
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0.5, accuracy: 0.001)
        }
    }

    func testHostingScrollViewConsumesEachIndicatorFlashSeedOnce() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let host = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .overlay
            )
            host.updateProperties(properties)
            host.updateIndicatorPresentation(
                outerSize: CGSize(width: 80, height: 60),
                metrics: ScrollIndicatorMetricsStorage()
            )
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 80, height: 180),
                containingSize: CGSize(width: 80, height: 60),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)

            properties.indicatorFlashSeed = 1
            host.updateProperties(properties)
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)
            XCTAssertNotNil(host.host.indicatorLayout.vertical)
            XCTAssertTrue(host.updateIndicatorVisibility(at: Time(seconds: 0.95)))
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)

            host.updateProperties(properties)
            XCTAssertEqual(host.overlayIndicatorOpacity, 0)

            properties.indicatorFlashSeed = 2
            host.updateProperties(properties)
            XCTAssertEqual(host.overlayIndicatorOpacity, 1)
            XCTAssertNotNil(host.host.indicatorLayout.vertical)
        }
    }

    func testScrollViewContentFrameUsesUnspecifiedScrollableAxes() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            _ = graph.makeInput(value: ())
            var observedProposal: _ProposedSize?
            let contentComputer = testLayoutComputer(sizeThatFits: { proposal in
                observedProposal = proposal
                return CGSize(width: 240, height: 30)
            })

            let frame = ScrollViewUtilities.contentFrame(
                in: CGSize(width: 100, height: 80),
                contentComputer: contentComputer,
                axes: .horizontal
            )

            XCTAssertEqual(
                observedProposal,
                _ProposedSize(width: nil, height: 80)
            )
            XCTAssertEqual(frame.origin, .zero)
            XCTAssertEqual(frame.size.value, CGSize(width: 240, height: 80))
            XCTAssertEqual(
                frame.size.proposal,
                _ProposedSize(width: nil, height: 80)
            )
        }
    }

    func testScrollViewLayoutSizeKeepsSpecifiedScrollableAxis() {
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            _ = graph.makeInput(value: ())
            var observedProposal: _ProposedSize?
            let contentComputer = testLayoutComputer(sizeThatFits: { proposal in
                observedProposal = proposal
                return CGSize(width: 75, height: 260)
            })

            let size = ScrollViewUtilities.sizeThatFits(
                in: ProposedViewSize(width: 100, height: 180),
                contentComputer: contentComputer,
                axes: .vertical
            )

            XCTAssertEqual(
                observedProposal,
                _ProposedSize(width: 100, height: nil)
            )
            XCTAssertEqual(size, CGSize(width: 75, height: 180))
            XCTAssertNil(ScrollViewUtilities.sizeThatFits(
                in: ProposedViewSize(width: 100, height: 180),
                contentComputer: contentComputer,
                axes: []
            ))
        }
    }

    func testHostingScrollViewAppliesBounceRoleAndSpringsBackFromOverscroll() {
        func makeHost(
            behavior: ScrollBounceBehavior
        ) -> (_AGGraph, Attribute<SystemScrollLayoutState>, Attribute<ScrollPhaseState>, HostingScrollView) {
            let graph = _AGGraph()
            let graphRef = _AGGraphContext(graph: graph)
            return _AGGraph.withCurrent(graph) {
                let state = graph.makeInput(value: SystemScrollLayoutState())
                let phase = graph.makeInput(value: ScrollPhaseState())
                let host = HostingScrollView(
                    graphRef: graphRef,
                    layoutState: state.asWeak(),
                    phaseState: phase.asWeak()
                )
                host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
                var properties = ScrollEnvironmentProperties()
                properties.verticalBounceBehavior = behavior.role
                host.updateProperties(properties)
                _ = host.updateContext(HostingScrollViewUpdateContext(
                    contentOffset: .zero,
                    contentFrame: CGRect(x: 0, y: 0, width: 100, height: 70),
                    containingSize: CGSize(width: 100, height: 100),
                    offsetMode: .system,
                    safeInsets: EdgeInsets()
                ))
                return (graph, state, phase, host)
            }
        }

        let (automaticGraph, _, _, automaticHost) = makeHost(
            behavior: .automatic
        )
        _AGGraph.withCurrent(automaticGraph) {
            let active = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: 40),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: .zero)
            )
            automaticHost.dispatchScrollGesturePhase(.active(.pan(active)))
            XCTAssertEqual(
                automaticHost.makeLayoutState().contentOffset.y,
                -3.846153846153843,
                accuracy: 0.0000000001
            )
            XCTAssertEqual(automaticHost.currentPhaseState.phase, .interacting)

            automaticHost.dispatchScrollGesturePhase(.ended(.pan(active)))
            XCTAssertTrue(automaticHost.isDecelerating)
            XCTAssertEqual(automaticHost.currentPhaseState.phase, .decelerating)
            XCTAssertTrue(automaticHost.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(automaticHost.updateMotion(at: Time(seconds: 1.5)))
            XCTAssertEqual(
                automaticHost.makeLayoutState().contentOffset.y,
                0,
                accuracy: 0.0000000001
            )
            XCTAssertEqual(automaticHost.currentPhaseState.phase, .idle)
        }

        let (sizedGraph, _, _, sizedHost) = makeHost(
            behavior: .basedOnSize
        )
        _AGGraph.withCurrent(sizedGraph) {
            sizedHost.dispatchScrollGesturePhase(.active(.pan(PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: 40),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: .zero)
            ))))
            XCTAssertEqual(sizedHost.makeLayoutState().contentOffset, .zero)
            XCTAssertEqual(sizedHost.currentPhaseState.phase, .tracking)
        }
    }

    func testHostingScrollViewConsumesPanIntoSystemOffsetAndPhase() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 20)
            ))
            let phase = graph.makeInput(value: ScrollPhaseState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak(),
                phaseState: phase.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 400),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))

            host.dispatchScrollGesturePhase(.active(.pan(PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -30),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            ))))

            XCTAssertEqual(
                host.makeLayoutState().contentOffset,
                CGPoint(x: 0, y: 50)
            )
            XCTAssertEqual(host.makeLayoutState().contentOffsetMode, .system)
            XCTAssertEqual(host.currentPhaseState.phase, .interacting)
            XCTAssertEqual(
                host.currentPhaseState.velocity,
                CGVector(dx: 0, dy: -300)
            )

            host.dispatchScrollGesturePhase(.ended(.pan(PanGesture.Value(
                timestamp: Time(seconds: 1.1),
                translation: CGSize(width: 0, height: -30),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            ))))

            XCTAssertEqual(
                host.makeLayoutState().contentOffset,
                CGPoint(x: 0, y: 50)
            )
            XCTAssertEqual(host.currentPhaseState.phase, .decelerating)
            XCTAssertEqual(
                host.currentPhaseState.velocity,
                CGVector(dx: 0, dy: 300)
            )
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1.2)))
            XCTAssertGreaterThan(host.makeLayoutState().contentOffset.y, 50)
        }
    }

    func testHostingScrollViewResolvesTerminalOffsetThroughScrollTargetBehavior() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let phase = graph.makeInput(value: ScrollPhaseState())
            let recorder = HostScrollTargetBehaviorRecorder()
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak(),
                phaseState: phase.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.decelerationRate = .viewAligned
            properties.scrollBehavior = ResolvedScrollBehavior(
                base: HostRecordingScrollTargetBehavior(
                    recorder: recorder,
                    targetOrigin: CGPoint(x: 10, y: 190)
                ),
                axes: .vertical
            )
            host.updateProperties(properties)
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets(top: 10, leading: 10, bottom: 0, trailing: 0)
            ))

            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -10),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))

            XCTAssertTrue(host.isDecelerating)
            XCTAssertEqual(recorder.originalTarget?.rect.origin, CGPoint(x: 10, y: 60))
            XCTAssertEqual(recorder.originalTarget?.rect.size, CGSize(width: 100, height: 100))
            XCTAssertEqual(recorder.proposedTarget?.rect.size, CGSize(width: 100, height: 100))
            XCTAssertGreaterThan(recorder.proposedTarget?.rect.minY ?? 0, 70)
            XCTAssertEqual(recorder.velocity, CGVector(dx: 0, dy: 300))
            XCTAssertEqual(recorder.geometry?.contentOffset, CGPoint(x: 0, y: 60))
            XCTAssertEqual(recorder.geometry?.contentInsets.top, 10)
            XCTAssertEqual(recorder.axes, .vertical)
            XCTAssertEqual(recorder.decelerationRate, .viewAligned)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 4)))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(
                host.makeLayoutState().contentOffset,
                CGPoint(x: 0, y: 180)
            )
            XCTAssertEqual(host.currentPhaseState.phase, .idle)
        }
    }

    func testHostingScrollViewStartsTargetedMotionAfterZeroVelocityDrag() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.scrollBehavior = ResolvedScrollBehavior(
                base: HostRecordingScrollTargetBehavior(
                    recorder: HostScrollTargetBehaviorRecorder(),
                    targetOrigin: CGPoint(x: 0, y: 180)
                ),
                axes: .vertical
            )
            host.updateProperties(properties)
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))

            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -10),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: .zero)
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))

            XCTAssertTrue(host.isDecelerating)
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 4)))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(
                host.makeLayoutState().contentOffset,
                CGPoint(x: 0, y: 180)
            )
        }
    }

    func testHostingScrollViewRetargetsActiveBehaviorAfterLayoutUpdate() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let recorder = HostScrollTargetBehaviorRecorder()
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            var properties = ScrollEnvironmentProperties()
            properties.scrollBehavior = ResolvedScrollBehavior(
                base: HostRecordingScrollTargetBehavior(
                    recorder: recorder,
                    targetOrigin: CGPoint(x: 0, y: 180)
                ),
                axes: .vertical
            )
            host.updateProperties(properties)
            let context = HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            )
            _ = host.updateContext(context)

            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -10),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -300))
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))
            XCTAssertEqual(recorder.invocationCount, 1)

            recorder.overrideTargetOrigin = CGPoint(x: 0, y: 260)
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: host.makeLayoutState().contentOffset,
                contentFrame: context.contentFrame,
                containingSize: context.containingSize,
                offsetMode: .system,
                safeInsets: context.safeInsets
            ))
            XCTAssertEqual(recorder.invocationCount, 2)

            XCTAssertTrue(host.updateMotion(at: Time(seconds: 1)))
            XCTAssertTrue(host.updateMotion(at: Time(seconds: 4)))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(
                host.makeLayoutState().contentOffset,
                CGPoint(x: 0, y: 260)
            )
        }
    }

    func testHostingScrollViewTargetUpdateHonorsVelocityPreservation() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        _AGGraph.withCurrent(graph) {
            let state = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 0, y: 50)
            ))
            let phase = graph.makeInput(value: ScrollPhaseState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak(),
                phaseState: phase.asWeak()
            )
            host.updateConfiguration(ScrollViewConfiguration(axes: .vertical))
            let context = HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: CGRect(x: 0, y: 0, width: 100, height: 500),
                containingSize: CGSize(width: 100, height: 100),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            )
            _ = host.updateContext(context)
            let pan = PanGesture.Value(
                timestamp: Time(seconds: 1),
                translation: CGSize(width: 0, height: -20),
                touchType: .indirect,
                velocity: _Velocity(valuePerSecond: CGSize(width: 0, height: -240))
            )
            host.dispatchScrollGesturePhase(.active(.pan(pan)))
            host.dispatchScrollGesturePhase(.ended(.pan(pan)))
            XCTAssertTrue(host.isDecelerating)
            let preservedVelocity = host.currentMotionVelocity

            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: context.contentFrame,
                containingSize: context.containingSize,
                offsetMode: .target(
                    { _, _ in ScrollTarget(rect: CGRect(x: 0, y: 220, width: 100, height: 40)) },
                    config: ScrollTargetConfiguration(preservesVelocity: true)
                ),
                safeInsets: context.safeInsets
            ))
            XCTAssertTrue(host.isDecelerating)
            XCTAssertEqual(host.currentMotionVelocity, preservedVelocity)

            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: state.value.contentOffset,
                contentFrame: context.contentFrame,
                containingSize: context.containingSize,
                offsetMode: .target(
                    { _, _ in ScrollTarget(rect: CGRect(x: 0, y: 40, width: 100, height: 40)) },
                    config: ScrollTargetConfiguration(preservesVelocity: false)
                ),
                safeInsets: context.safeInsets
            ))
            XCTAssertFalse(host.isDecelerating)
            XCTAssertEqual(host.currentMotionVelocity.valuePerSecond, .zero)
        }
    }

    func testContentOffsetAdjustmentReasonMatchesProbedCases() {
        func name(_ reason: ContentOffsetAdjustmentReason) -> String {
            switch reason {
            case .translation: "translation"
            case .positionTranslation: "positionTranslation"
            case .alignment: "alignment"
            case .reset: "reset"
            case .resetPosition: "resetPosition"
            }
        }

        XCTAssertEqual(
            [
                .translation,
                .positionTranslation,
                .alignment,
                .reset,
                .resetPosition,
            ].map(name),
            [
                "translation",
                "positionTranslation",
                "alignment",
                "reset",
                "resetPosition",
            ]
        )
    }

    func testSystemScrollLayoutStateMergesOffsetModeAndReasonSeeds() {
        var adjustment = SystemScrollLayoutState(contentOffsetSeed: VersionSeed(value: 7))
        adjustment.updateContentOffset(mode: .adjustment(reason: .reset), updateSeed: 4)
        XCTAssertEqual(adjustment.contentOffsetMode, .adjustment(reason: .reset))
        XCTAssertEqual(adjustment.contentOffsetSeed.value, 2_340_873_906)

        var target = SystemScrollLayoutState(contentOffsetSeed: VersionSeed(value: 7))
        target.updateContentOffset(mode: .target(nil, config: ScrollTargetConfiguration()), updateSeed: 4)
        XCTAssertEqual(target.contentOffsetSeed.value, 186_384_208)

        var system = SystemScrollLayoutState()
        system.updateContentOffset(mode: .system, updateSeed: 9)
        XCTAssertEqual(system.contentOffsetSeed.value, 9)

        var invalid = SystemScrollLayoutState(contentOffsetSeed: VersionSeed(value: .max))
        invalid.updateContentOffset(mode: .adjustment(reason: .alignment), updateSeed: 2)
        XCTAssertEqual(invalid.contentOffsetSeed.value, UInt32.max)
    }

    func testSystemScrollLayoutStateLayoutComparisonIncludesLiveViewportOffset() {
        // ASSERTIONS scrollAdjustedOutputChangedEdgeObserved
        func valuesAreLayoutEqual(
            _ lhs: SystemScrollLayoutState,
            _ rhs: SystemScrollLayoutState
        ) -> Bool {
            _AGGraph.compareValues(
                lhs,
                rhs,
                options: AGComparisonOptions(mode: .layout)
            )
        }

        let baseline = SystemScrollLayoutState(
            contentOffset: CGPoint(x: 10, y: 20),
            contentInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
            systemContentInsets: EdgeInsets(top: 5, leading: 6, bottom: 7, trailing: 8),
            systemTranslation: CGSize(width: 9, height: 10),
            contentRectToPrepare: CGRect(x: 11, y: 12, width: 13, height: 14),
            contentOffsetMode: .system,
            contentOffsetSeed: VersionSeed(value: 15)
        )
        var candidate = baseline
        XCTAssertTrue(valuesAreLayoutEqual(baseline, candidate))

        candidate.contentOffset = CGPoint(x: 100, y: 200)
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let rawState = graph.makeInput(value: baseline)
            XCTAssertTrue(
                graph.setValue(
                    for: rawState,
                    to: candidate,
                    evaluateSideEffects: false
                ),
                "the external state input must still observe a live offset write"
            )
        }

        candidate = baseline
        candidate.contentInsets.top += 1
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))

        candidate = baseline
        candidate.systemContentInsets.leading += 1
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))

        candidate = baseline
        candidate.systemTranslation.width += 1
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))

        candidate = baseline
        candidate.contentRectToPrepare = nil
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))

        candidate = baseline
        candidate.contentOffsetMode = .adjustment(reason: .alignment)
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))

        candidate = baseline
        candidate.contentOffsetSeed = VersionSeed(value: 16)
        XCTAssertFalse(valuesAreLayoutEqual(baseline, candidate))
    }

    func testScrollTargetConfigurationCopiesObservedTransactionValues() {
        var transaction = Transaction(animation: .linear(duration: 1))
        transaction.scrollToRequiresCompleteVisibility = true
        transaction.scrollPositionUpdatePreservesVelocity = true

        XCTAssertEqual(
            ScrollTargetConfiguration(transaction: transaction),
            ScrollTargetConfiguration(
                animation: .linear(duration: 1),
                requiresVisibility: true,
                preservesVelocity: true
            )
        )

        var disabled = transaction
        disabled.disablesAnimations = true
        XCTAssertNil(ScrollTargetConfiguration(transaction: disabled).animation)
        XCTAssertTrue(ScrollTargetConfiguration(transaction: disabled).requiresVisibility)
        XCTAssertTrue(ScrollTargetConfiguration(transaction: disabled).preservesVelocity)
    }

    func testScrollViewAnimationOffsetMatchesObservedVisibilityAndClampRows() {
        let viewport = CGRect(x: 100, y: 100, width: 200, height: 200)
        let content = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)

        func offset(
            _ target: CGRect,
            anchor: UnitPoint? = nil,
            requiresVisibility: Bool = false,
            contentFrame: CGRect? = nil
        ) -> CGPoint {
            ScrollViewUtilities.animationOffset(
                targetFrame: target,
                anchor: anchor,
                viewPortFrame: viewport,
                contentFrame: contentFrame ?? content,
                requiresVisibility: requiresVisibility
            )
        }

        let anchoredTarget = CGRect(x: 350, y: 450, width: 100, height: 80)
        XCTAssertEqual(offset(anchoredTarget, anchor: .topLeading), CGPoint(x: 350, y: 450))
        XCTAssertEqual(offset(anchoredTarget, anchor: .center), CGPoint(x: 300, y: 390))
        XCTAssertEqual(offset(anchoredTarget, anchor: .bottomTrailing), CGPoint(x: 250, y: 330))

        XCTAssertEqual(
            offset(CGRect(x: 150, y: 150, width: 50, height: 50)),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(CGRect(x: 150, y: 150, width: 50, height: 50), requiresVisibility: true),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(CGRect(x: 250, y: 150, width: 100, height: 50)),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 250, y: 150, width: 100, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 150, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 50, y: 150, width: 100, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 50, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 150, y: 250, width: 50, height: 100),
                requiresVisibility: true
            ),
            CGPoint(x: 100, y: 150)
        )
        XCTAssertEqual(
            offset(CGRect(x: 350, y: 150, width: 50, height: 50)),
            CGPoint(x: 200, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 350, y: 150, width: 50, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 200, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 20, y: 30, width: 40, height: 40),
                requiresVisibility: true
            ),
            CGPoint(x: 20, y: 30)
        )
        XCTAssertEqual(
            offset(CGRect(x: 300, y: 150, width: 50, height: 50)),
            CGPoint(x: 150, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 300, y: 150, width: 50, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 150, y: 100)
        )
        XCTAssertEqual(
            offset(CGRect(x: 50, y: 150, width: 400, height: 50)),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 50, y: 150, width: 400, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 100, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: 350, y: 150, width: 400, height: 50),
                requiresVisibility: true
            ),
            CGPoint(x: 350, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: -400, y: 150, width: 400, height: 50),
                requiresVisibility: true,
                contentFrame: CGRect(x: -500, y: 0, width: 1_500, height: 1_000)
            ),
            CGPoint(x: -200, y: 100)
        )
        XCTAssertEqual(
            offset(
                CGRect(x: -100, y: -80, width: 20, height: 20),
                anchor: .center,
                contentFrame: CGRect(x: 25, y: 35, width: 500, height: 600)
            ),
            CGPoint(x: 25, y: 35)
        )
    }

    // ASSERTIONS: lazyMultiAxisSectionGridRuntimeObserved
    func testScrollViewAnimationOffsetComposesTopLeadingTargetAcrossBothAxes() {
        let viewport = CGRect(x: 0, y: 0, width: 100, height: 100)
        let content = CGRect(x: 0, y: 0, width: 266, height: 1_100)

        func offset(_ target: CGRect) -> CGPoint {
            ScrollViewUtilities.animationOffset(
                targetFrame: target,
                anchor: .topLeading,
                viewPortFrame: viewport,
                contentFrame: content,
                requiresVisibility: false
            )
        }

        let first = offset(
            CGRect(
                x: 80,
                y: 793.3809523809524,
                width: 126,
                height: 45
            )
        )
        XCTAssertEqual(first.x, 80, accuracy: 0.000_001)
        XCTAssertEqual(first.y, 793.3809523809524, accuracy: 0.000_001)

        let next = offset(
            CGRect(
                x: 80,
                y: 863.3809523809524,
                width: 126,
                height: 35
            )
        )
        XCTAssertEqual(next.x, 80, accuracy: 0.000_001)
        XCTAssertEqual(next.y, 863.3809523809524, accuracy: 0.000_001)
    }

    func testScrollAnchorStorageUsesRoleDefaultAndRightToLeftAdjustment() {
        var anchors = ScrollAnchorStorage(defaultValue: .center)
        XCTAssertTrue(ScrollAnchorStorage().isEmpty)
        XCTAssertFalse(anchors.isEmpty)
        XCTAssertEqual(anchors.initialOffset, .center)
        XCTAssertEqual(anchors.sizeChanges, .center)
        XCTAssertEqual(anchors.alignment, .center)

        anchors.anchors[.initialOffset] = UnitPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(
            anchors.adjustedAnchor(role: .initialOffset, layoutDirection: .leftToRight),
            UnitPoint(x: 0.25, y: 0.75)
        )
        XCTAssertEqual(
            anchors.adjustedAnchor(role: .initialOffset, layoutDirection: .rightToLeft),
            UnitPoint(x: 0.75, y: 0.75)
        )
        XCTAssertEqual(anchors.sizeChanges, .center)
    }

    func testAdjustedStateInitialOffsetUsesAnchorPerActiveAxisAndClamps() {
        let frame = CGRect(x: 40, y: 50, width: 300, height: 500)
        let container = CGSize(width: 100, height: 200)

        XCTAssertEqual(
            ScrollViewAdjustedState.initialOffset(
                containerSize: container,
                contentFrame: frame,
                axes: [.horizontal, .vertical],
                anchors: ScrollAnchorStorage(defaultValue: .center),
                layoutDirection: .leftToRight
            ),
            CGPoint(x: 100, y: 150)
        )
        XCTAssertEqual(
            ScrollViewAdjustedState.initialOffset(
                containerSize: container,
                contentFrame: frame,
                axes: .horizontal,
                anchors: ScrollAnchorStorage(
                    anchors: [.initialOffset: .leading],
                    defaultValue: .bottom
                ),
                layoutDirection: .rightToLeft
            ),
            CGPoint(x: 200, y: 0)
        )
        XCTAssertEqual(
            ScrollViewAdjustedState.initialOffset(
                containerSize: CGSize(width: 400, height: 600),
                contentFrame: frame,
                axes: [.horizontal, .vertical],
                anchors: ScrollAnchorStorage(defaultValue: .bottomTrailing),
                layoutDirection: .leftToRight
            ),
            .zero
        )
    }

    func testScrollPositionInitialOffsetMatchesObservedStorageAxisAndRTLBranches() {
        let container = CGSize(width: 100, height: 120)
        let frame = CGRect(x: 0, y: 0, width: 300, height: 400)

        XCTAssertNil(ScrollPosition().initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: [.horizontal, .vertical],
            layoutDirection: .leftToRight
        ))
        XCTAssertNil(ScrollPosition(id: "target").initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: [.horizontal, .vertical],
            layoutDirection: .leftToRight
        ))
        XCTAssertEqual(ScrollPosition(edge: .bottom).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .vertical,
            layoutDirection: .leftToRight
        ), CGPoint(x: 0, y: 280))
        XCTAssertEqual(ScrollPosition(edge: .trailing).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .horizontal,
            layoutDirection: .rightToLeft
        ), .zero)
        XCTAssertEqual(ScrollPosition(point: CGPoint(x: 70, y: 230)).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: [.horizontal, .vertical],
            layoutDirection: .leftToRight
        ), CGPoint(x: 70, y: 0))
        XCTAssertEqual(ScrollPosition(point: CGPoint(x: 70, y: 230)).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .vertical,
            layoutDirection: .leftToRight
        ), CGPoint(x: 0, y: 230))
        XCTAssertEqual(ScrollPosition(x: 70).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .horizontal,
            layoutDirection: .rightToLeft
        ), CGPoint(x: 130, y: 0))
        XCTAssertNil(ScrollPosition(y: 230).initialContentOffset(
            containerSize: container,
            contentFrame: frame,
            axes: .horizontal,
            layoutDirection: .leftToRight
        ))
    }

    func testAdjustedStateUsesBoundInitialPositionAndResetPositionReason() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            var stored = ScrollPosition(y: 230)
            let binding = Binding<ScrollPosition>(
                get: { stored },
                set: { value, _ in stored = value }
            )
            let adjusted = graph.makeStatefulRule(ScrollViewAdjustedState(
                _size: graph.makeInput(value: ViewSize(width: 100, height: 120)),
                _configuration: graph.makeInput(value: ScrollViewConfiguration(axes: .vertical)),
                _defaultAnchors: graph.makeInput(value: ScrollAnchorStorage()),
                _state: graph.makeInput(value: SystemScrollLayoutState()),
                _phaseState: graph.makeInput(value: ScrollPhaseState()),
                _contentFrame: graph.makeInput(value: ViewFrame(
                    origin: .zero,
                    size: ViewSize(width: 300, height: 400)
                )),
                _pixelLength: graph.makeInput(value: CGFloat(1)),
                _phase: graph.makeInput(value: _GraphInputs.Phase()),
                _transaction: graph.makeInput(value: Transaction()),
                _layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                _positionBinding: binding
            ))

            let state = adjusted.value
            XCTAssertEqual(state.contentOffset, CGPoint(x: 0, y: 230))
            XCTAssertEqual(state.contentOffsetMode, .adjustment(reason: .resetPosition))
        }
    }

    func testAdjustedStateAlignsInitialSizeChangeAndUndersizedRoles() {
        var initial = CGPoint.zero
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &initial,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.initialOffset: .center]),
            layoutDirection: .leftToRight,
            oldFrame: .zero,
            oldSize: CGSize(width: -CGFloat.infinity, height: -CGFloat.infinity),
            oldOffset: .zero,
            hasScrolled: false,
            pixelLength: 1
        ))
        XCTAssertEqual(initial.x, 100)

        var sizeChange = CGPoint(x: 100, y: 0)
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &sizeChange,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 500, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.sizeChanges: .center]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: CGPoint(x: 100, y: 0),
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(sizeChange.x, 200)

        var alignment = CGPoint.zero
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &alignment,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.alignment: .trailing]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 80, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: .zero,
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(alignment.x, 100)

        var centeredUndersized = CGPoint(x: 10, y: 0)
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &centeredUndersized,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 180, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.sizeChanges: .center]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 80, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: CGPoint(x: 10, y: 0),
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(centeredUndersized.x, 0)
    }

    func testAdjustedStateAlignmentUsesPixelRoundingAndChangeTolerance() {
        var rounded = CGPoint.zero
        XCTAssertTrue(ScrollViewAdjustedState.alignIfNeeded(
            &rounded,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 305, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.initialOffset: .center]),
            layoutDirection: .leftToRight,
            oldFrame: .zero,
            oldSize: CGSize(width: -CGFloat.infinity, height: -CGFloat.infinity),
            oldOffset: .zero,
            hasScrolled: false,
            pixelLength: 2
        ))
        XCTAssertEqual(rounded.x, 102)

        var unchanged = CGPoint(x: 20, y: 7)
        XCTAssertFalse(ScrollViewAdjustedState.alignIfNeeded(
            &unchanged,
            axis: .horizontal,
            newSize: CGSize(width: 100, height: 100),
            newContentFrame: CGRect(x: 0, y: 0, width: 500, height: 100),
            anchors: ScrollAnchorStorage(anchors: [.sizeChanges: .center]),
            layoutDirection: .leftToRight,
            oldFrame: CGRect(x: 0, y: 0, width: 300, height: 100),
            oldSize: CGSize(width: 100, height: 100),
            oldOffset: CGPoint(x: 20, y: 7),
            hasScrolled: true,
            pixelLength: 1
        ))
        XCTAssertEqual(unchanged, CGPoint(x: 20, y: 7))
    }

    func testAdjustedStateAppliesAutomaticAlignmentAndSkipsDisabledBehavior() {
        func offsets(
            for behavior: ScrollContentOffsetAdjustmentBehavior
        ) -> [CGPoint] {
            let graph = _AGGraph()
            let graphRef = _AGGraphContext(graph: graph)
            return graphRef.withCurrent {
                let rawState = graph.makeInput(value: SystemScrollLayoutState())
                let configuration = graph.makeInput(value: ScrollViewConfiguration(axes: .horizontal))
                let anchors = graph.makeInput(value: ScrollAnchorStorage(
                    anchors: [.sizeChanges: .center]
                ))
                let frame = graph.makeInput(value: ViewFrame(
                    origin: .zero,
                    size: ViewSize(width: 300, height: 100)
                ))
                let size = graph.makeInput(value: ViewSize(width: 100, height: 100))
                var transactionValue = Transaction()
                transactionValue.scrollContentOffsetAdjustmentBehavior = behavior
                let transaction = graph.makeInput(value: transactionValue)
                let adjusted = graph.makeStatefulRule(ScrollViewAdjustedState(
                    _size: size,
                    _configuration: configuration,
                    _defaultAnchors: anchors,
                    _state: rawState,
                    _phaseState: graph.makeInput(value: ScrollPhaseState()),
                    _contentFrame: frame,
                    _pixelLength: graph.makeInput(value: CGFloat(1)),
                    _phase: graph.makeInput(value: _GraphInputs.Phase()),
                    _transaction: transaction,
                    _layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight)
                ))

                let initial = adjusted.value.contentOffset
                frame.setValue(ViewFrame(
                    origin: .zero,
                    size: ViewSize(width: 500, height: 100)
                ))
                return [initial, adjusted.value.contentOffset]
            }
        }

        XCTAssertEqual(offsets(for: .automatic), [
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
        ])
        XCTAssertEqual(offsets(for: .disabled), [.zero, .zero])
    }

    func testAdjustedStateMarksScrollOriginChangeBeforeLaterInitialAlignment() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let rawState = graph.makeInput(value: SystemScrollLayoutState())
            let configuration = graph.makeInput(value: ScrollViewConfiguration(axes: .horizontal))
            let anchors = graph.makeInput(value: ScrollAnchorStorage(
                anchors: [.initialOffset: .center]
            ))
            let frame = graph.makeInput(value: ViewFrame(
                origin: .zero,
                size: ViewSize(width: 300, height: 100)
            ))
            let transaction = graph.makeInput(value: Transaction())
            let adjusted = graph.makeStatefulRule(ScrollViewAdjustedState(
                _size: graph.makeInput(value: ViewSize(width: 100, height: 100)),
                _configuration: configuration,
                _defaultAnchors: anchors,
                _state: rawState,
                _phaseState: graph.makeInput(value: ScrollPhaseState()),
                _contentFrame: frame,
                _pixelLength: graph.makeInput(value: CGFloat(1)),
                _phase: graph.makeInput(value: _GraphInputs.Phase()),
                _transaction: transaction,
                _layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight)
            ))

            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 100, y: 0))

            var fromScrollView = Transaction()
            fromScrollView.fromScrollView = true
            transaction.setValue(fromScrollView)
            rawState.setValue(SystemScrollLayoutState(
                contentOffset: CGPoint(x: 100, y: 0),
                contentOffsetMode: .system
            ))
            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 100, y: 0))

            frame.setValue(ViewFrame(
                origin: .zero,
                size: ViewSize(width: 500, height: 100)
            ))
            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 100, y: 0))
        }
    }

    func testScrollHostInputRulesUseObservedDefaultAlignmentAndSafeArea() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let configuration = graph.makeInput(value: ScrollViewConfiguration(
                axes: [.horizontal, .vertical]
            ))
            let sourceAnchors = graph.makeInput(value: ScrollAnchorStorage())
            let defaultRule = ScrollViewDefaultAnchors(
                _configuration: configuration,
                _anchors: sourceAnchors
            )
            XCTAssertEqual(
                Mirror(reflecting: defaultRule).children.compactMap(\.label),
                ["_configuration", "_anchors", "oldAnchors", "oldAxes"]
            )
            let defaultAnchors = graph.makeStatefulRule(defaultRule)
            XCTAssertEqual(defaultAnchors.value.defaultValue, .topLeading)

            sourceAnchors.setValue(ScrollAnchorStorage(
                anchors: [.alignment: .center]
            ))
            let frame = graph.makeInput(value: ViewFrame(
                origin: .zero,
                size: ViewSize(CGSize(width: 100, height: 80))
            ))
            let size = graph.makeInput(value: ViewSize(CGSize(width: 200, height: 200)))
            let alignmentRule = ScrollViewAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: size
            )
            XCTAssertEqual(
                Mirror(reflecting: alignmentRule).children.compactMap(\.label),
                ["_configuration", "_scrollAnchors", "_contentFrame", "_size"]
            )
            let alignment = graph.makeRule(alignmentRule)
            XCTAssertEqual(alignment.value, CGSize(width: 50, height: 60))

            let direction = graph.makeInput(value: LayoutDirection.rightToLeft)
            sourceAnchors.setValue(ScrollAnchorStorage(
                anchors: [.alignment: .topLeading]
            ))
            let rtlRule = ScrollViewRTLAlignmentAdjustment(
                _configuration: configuration,
                _scrollAnchors: defaultAnchors,
                _contentFrame: frame,
                _size: size,
                _layoutDirection: direction
            )
            XCTAssertEqual(
                Mirror(reflecting: rtlRule).children.compactMap(\.label),
                [
                    "_configuration", "_scrollAnchors", "_contentFrame", "_size",
                    "_layoutDirection",
                ]
            )
            let rtl = graph.makeRule(rtlRule)
            XCTAssertEqual(rtl.value, CGSize(width: 100, height: 0))

            sourceAnchors.setValue(ScrollAnchorStorage(
                anchors: [.alignment: .center]
            ))
            let safeArea = graph.makeInput(value: EdgeInsets(
                top: 1,
                leading: 2,
                bottom: 3,
                trailing: 4
            ))
            let adjustedSafeAreaRule = ScrollViewAdjustedSafeArea(
                _safeArea: safeArea,
                _configuration: configuration,
                _alignmentAdjustment: alignment,
                _rtlAdjustment: rtl
            )
            XCTAssertEqual(
                Mirror(reflecting: adjustedSafeAreaRule).children.compactMap(\.label),
                ["_safeArea", "_configuration", "_alignmentAdjustment", "_rtlAdjustment"]
            )
            XCTAssertEqual(
                graph.makeRule(adjustedSafeAreaRule).value,
                EdgeInsets(top: 61, leading: 52, bottom: 3, trailing: 4)
            )
        }
    }

    func testScrollHostPropertyRulesStoreObservedFieldsAndApplyConfiguration() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let configuration = graph.makeInput(value: ScrollViewConfiguration(
                axes: .vertical,
                isScrollEnabled: false
            ))
            var values = EnvironmentValues()
            values.layoutDirection = .rightToLeft
            let environment = graph.makeInput(value: values)
            var baseProperties = ScrollEnvironmentProperties(environment: values)
            baseProperties.horizontalBounceBehavior = ScrollBounceBehavior.always.role
            baseProperties.decelerationRate = .paging
            let storage = graph.makeInput(value: ScrollEnvironmentStorage(
                baseProperties
            ))
            let behaviorRule = ScrollViewAdjustedBehaviorProperties(
                _configuration: configuration,
                _environment: environment,
                _storage: storage
            )
            XCTAssertEqual(
                Mirror(reflecting: behaviorRule).children.compactMap(\.label),
                [
                    "_configuration", "_environment", "_storage", "tracker",
                    "oldBehavior", "oldAxes",
                ]
            )
            let behavior = graph.makeStatefulRule(behaviorRule)
            let layoutDirection = graph.makeInput(value: LayoutDirection.rightToLeft)
            let isEnabled = graph.makeInput(value: true)
            let isContainedInPlatter = graph.makeInput(value: true)
            let propertiesRule = ScrollViewAdjustedProperties(
                _configuration: configuration,
                _scrollStorage: storage,
                _behaviorProperties: behavior,
                _layoutDirection: layoutDirection,
                _isEnabled: isEnabled,
                _isContainedInPlatter: OptionalAttribute(isContainedInPlatter)
            )
            XCTAssertEqual(
                Mirror(reflecting: propertiesRule).children.compactMap(\.label),
                [
                    "_configuration", "_scrollStorage", "_behaviorProperties",
                    "_layoutDirection", "_isEnabled", "_isContainedInPlatter",
                ]
            )
            let adjustedProperties = graph.makeRule(propertiesRule)
            let properties = adjustedProperties.value
            XCTAssertFalse(properties.isEnabled)
            XCTAssertEqual(properties.layoutDirection, .rightToLeft)
            XCTAssertTrue(properties.isContainedInPlatter)
            XCTAssertEqual(properties.verticalBounceBehavior.rawValue, 3)
            XCTAssertEqual(properties.horizontalBounceBehavior.rawValue, 3)
            XCTAssertEqual(properties.decelerationRate, .standard)

            configuration.setValue(ScrollViewConfiguration(
                axes: .vertical,
                isScrollEnabled: true
            ))
            let enabledProperties = adjustedProperties.value
            XCTAssertTrue(enabledProperties.isEnabled)
            XCTAssertEqual(enabledProperties.verticalBounceBehavior.rawValue, 0)
            XCTAssertEqual(enabledProperties.horizontalBounceBehavior.rawValue, 1)
            XCTAssertEqual(enabledProperties.decelerationRate, .standard)
        }
    }

    func testSystemScrollLayoutStateStoresProbedFieldsInOrder() {
        XCTAssertEqual(
            Mirror(reflecting: ScrollAnchorStorage()).children.compactMap(\.label),
            ["anchors", "defaultValue"]
        )
        XCTAssertEqual(
            Mirror(reflecting: SystemScrollLayoutState()).children.compactMap(\.label),
            [
                "contentOffset",
                "contentInsets",
                "systemContentInsets",
                "systemTranslation",
                "contentRectToPrepare",
                "contentOffsetMode",
                "contentOffsetSeed",
            ]
        )
        XCTAssertEqual(
            Mirror(reflecting: ScrollTargetConfiguration()).children.compactMap(\.label),
            ["animation", "requiresVisibility", "preservesVelocity"]
        )
        XCTAssertEqual(
            Mirror(reflecting: HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: .zero,
                containingSize: .zero,
                offsetMode: .system,
                safeInsets: EdgeInsets()
            )).children.compactMap(\.label),
            ["contentOffset", "contentFrame", "containingSize", "offsetMode", "safeInsets"]
        )
    }

    // ASSERTIONS systemScrollViewCommitMutationMergeObserved
    func testScrollViewCommitMutationUsesObservedMergePolicy() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let firstLayout = graph.makeInput(value: SystemScrollLayoutState())
            let secondLayout = graph.makeInput(value: SystemScrollLayoutState())
            let phase = graph.makeInput(value: ScrollPhaseState())
            let container = graph.makeInput(value: CGSize.zero)
            let otherContainer = graph.makeInput(value: CGSize.zero)

            var mutation = ScrollViewCommitMutation(
                layoutState: (
                    SystemScrollLayoutState(contentOffset: CGPoint(x: 1, y: 2)),
                    firstLayout.asWeak()
                ),
                phaseState: nil,
                containerSize: (CGSize(width: 10, height: 20), container.asWeak()),
                isPreferred: false
            )
            XCTAssertEqual(
                Mirror(reflecting: mutation).children.compactMap(\.label),
                ["layoutState", "phaseState", "containerSize", "isPreferred"]
            )

            XCTAssertTrue(mutation.merge(ScrollViewCommitMutation(
                layoutState: (
                    SystemScrollLayoutState(contentOffset: CGPoint(x: 3, y: 4)),
                    firstLayout.asWeak()
                ),
                phaseState: (ScrollPhaseState(phase: .interacting), phase.asWeak()),
                containerSize: (CGSize(width: 30, height: 40), container.asWeak()),
                isPreferred: false
            )))
            XCTAssertEqual(
                mutation.layoutState?.value.contentOffset,
                CGPoint(x: 3, y: 4)
            )
            XCTAssertEqual(mutation.phaseState?.value.phase, .interacting)
            XCTAssertEqual(mutation.containerSize?.value, CGSize(width: 30, height: 40))
            XCTAssertFalse(mutation.isPreferred)

            XCTAssertFalse(mutation.merge(ScrollViewCommitMutation(
                layoutState: nil,
                phaseState: nil,
                containerSize: (CGSize(width: 50, height: 60), otherContainer.asWeak()),
                isPreferred: false
            )))
            XCTAssertEqual(mutation.containerSize?.value, CGSize(width: 30, height: 40))

            var preferred = ScrollViewCommitMutation(
                layoutState: (
                    SystemScrollLayoutState(contentOffset: CGPoint(x: 7, y: 8)),
                    secondLayout.asWeak()
                ),
                phaseState: nil,
                containerSize: nil,
                isPreferred: true
            )
            XCTAssertTrue(preferred.merge(ScrollViewCommitMutation(
                layoutState: (
                    SystemScrollLayoutState(contentOffset: CGPoint(x: 9, y: 10)),
                    secondLayout.asWeak()
                ),
                phaseState: nil,
                containerSize: nil,
                isPreferred: false
            )))
            XCTAssertEqual(
                preferred.layoutState?.value.contentOffset,
                CGPoint(x: 7, y: 8)
            )
            XCTAssertTrue(preferred.isPreferred)
            XCTAssertFalse(preferred.merge(ScrollViewCommitMutation(
                layoutState: nil,
                phaseState: nil,
                containerSize: nil,
                isPreferred: true
            )))

            var promoted = ScrollViewCommitMutation(
                layoutState: nil,
                phaseState: nil,
                containerSize: nil,
                isPreferred: false
            )
            XCTAssertTrue(promoted.merge(ScrollViewCommitMutation(
                layoutState: (
                    SystemScrollLayoutState(contentOffset: CGPoint(x: 11, y: 12)),
                    firstLayout.asWeak()
                ),
                phaseState: nil,
                containerSize: nil,
                isPreferred: true
            )))
            XCTAssertEqual(
                promoted.layoutState?.value.contentOffset,
                CGPoint(x: 11, y: 12)
            )
            XCTAssertTrue(promoted.isPreferred)
        }
    }

    func testScrollViewCommitMutationAppliesAllStatesInOneHostTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        var layout: Attribute<SystemScrollLayoutState>!
        var phase: Attribute<ScrollPhaseState>!
        var container: Attribute<CGSize>!
        var containerTransaction: Transaction?

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            layout = graph.makeInput(value: SystemScrollLayoutState())
            phase = graph.makeInput(value: ScrollPhaseState())
            container = graph.makeInput(value: CGSize.zero)
            let nextLayout = SystemScrollLayoutState(
                contentOffset: CGPoint(x: 13, y: 14),
                contentOffsetMode: .adjustment(reason: .translation)
            )
            let nextPhase = ScrollPhaseState(phase: .interacting)
            let nextContainer = CGSize(width: 90, height: 140)

            Update.ensure {
                ScrollViewCommitMutation.commit(
                    layoutState: (nextLayout, layout.asWeak()),
                    phaseState: (nextPhase, phase.asWeak()),
                    containerSize: (nextContainer, container.asWeak()),
                    isPreferred: false,
                    transaction: Transaction()
                )
                XCTAssertTrue(viewGraph.hasPendingTransactions)
                XCTAssertEqual(layout.value.contentOffset, .zero)
                XCTAssertEqual(phase.value.phase, .idle)
                XCTAssertEqual(container.value, .zero)
            }

            XCTAssertEqual(layout.value, nextLayout)
            XCTAssertEqual(phase.value, nextPhase)
            XCTAssertEqual(container.value, nextContainer)
            containerTransaction = viewGraph.data.graph.transaction(
                for: container.identifier
            )
        }

        XCTAssertFalse(viewGraph.hasPendingTransactions)
        let transaction = try XCTUnwrap(containerTransaction)
        XCTAssertTrue(transaction.fromScrollView)
    }

    func testScrollViewCommitMutationResolvesOwnerOutsideGraphContext() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        var layout = WeakAttribute<SystemScrollLayoutState>()
        var phase = WeakAttribute<ScrollPhaseState>()
        var container = WeakAttribute<CGSize>()

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            layout = graph.makeInput(
                value: SystemScrollLayoutState()
            ).asWeak()
            phase = graph.makeInput(value: ScrollPhaseState()).asWeak()
            container = graph.makeInput(value: CGSize.zero).asWeak()
        }

        let nextLayout = SystemScrollLayoutState(
            contentOffset: CGPoint(x: 13, y: 14),
            contentOffsetMode: .adjustment(reason: .translation)
        )
        let nextPhase = ScrollPhaseState(phase: .interacting)
        let nextContainer = CGSize(width: 90, height: 140)
        XCTAssertNil(_AGGraph.current)

        Update.ensure {
            XCTAssertNil(_AGGraph.current)
            ScrollViewCommitMutation.commit(
                layoutState: (nextLayout, layout),
                phaseState: (nextPhase, phase),
                containerSize: (nextContainer, container),
                isPreferred: false,
                transaction: Transaction()
            )
            XCTAssertTrue(viewGraph.hasPendingTransactions)
        }

        XCTAssertNil(_AGGraph.current)
        XCTAssertFalse(viewGraph.hasPendingTransactions)
        XCTAssertEqual(layout.value, nextLayout)
        XCTAssertEqual(phase.value, nextPhase)
        XCTAssertEqual(container.value, nextContainer)
        XCTAssertNil(_AGGraph.current)
    }

    func testScrollViewCommitMutationRequestsImmediateUpdateForSystemMode() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        let delegate = ScrollCommitViewGraphDelegate(graph: viewGraph)
        viewGraph.viewDelegate = delegate
        var layout: Attribute<SystemScrollLayoutState>!

        viewGraph.data.withCurrent {
            layout = viewGraph.data.graph.makeInput(
                value: SystemScrollLayoutState()
            )
            Update.ensure {
                ScrollViewCommitMutation.commit(
                    layoutState: (
                        SystemScrollLayoutState(
                            contentOffset: CGPoint(x: 4, y: 5),
                            contentOffsetMode: .system
                        ),
                        layout.asWeak()
                    ),
                    isPreferred: false,
                    transaction: Transaction()
                )
                XCTAssertTrue(viewGraph.hasPendingTransactions)
                XCTAssertTrue(delegate.requestedDelays.isEmpty)
            }
        }

        XCTAssertEqual(delegate.requestedDelays, [0])
        XCTAssertTrue(viewGraph.hasPendingTransactions)
        viewGraph.flushTransactions()
        viewGraph.data.withCurrent {
            XCTAssertEqual(layout.value.contentOffset, CGPoint(x: 4, y: 5))
        }
        XCTAssertFalse(viewGraph.hasPendingTransactions)
    }

    func testHostingScrollViewRoundTripsGraphAndSystemState() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        var state = WeakAttribute<SystemScrollLayoutState>()
        var host: HostingScrollView!

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let stateAttribute = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 2, y: 3),
                contentOffsetSeed: VersionSeed(value: 7)
            ))
            state = stateAttribute.asWeak()
            host = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: state
            )
            let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)

            host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 10, y: 20),
                contentFrame: CGRect(x: 4, y: 5, width: 300, height: 400),
                containingSize: CGSize(width: 80, height: 120),
                offsetMode: .adjustment(reason: .translation),
                safeInsets: insets
            ))

            let platformState = host.makeLayoutState()
            XCTAssertEqual(platformState.contentOffset, CGPoint(x: 10, y: 20))
            XCTAssertEqual(platformState.contentInsets, insets)
            XCTAssertEqual(platformState.systemContentInsets, insets)
            XCTAssertEqual(platformState.contentOffsetMode, .system)
            XCTAssertEqual(platformState.contentOffsetSeed.value, 0)
        }

        Update.ensure {
            host.publishSystemContentOffset(CGPoint(x: 30, y: 40))
            XCTAssertEqual(
                host.makeLayoutState().contentOffset,
                CGPoint(x: 30, y: 40)
            )
            XCTAssertEqual(
                state.value?.contentOffset,
                CGPoint(x: 2, y: 3)
            )
            XCTAssertTrue(viewGraph.hasPendingTransactions)
        }

        viewGraph.flushTransactions()
        XCTAssertEqual(state.value?.contentOffset, CGPoint(x: 30, y: 40))
        XCTAssertEqual(state.value?.contentOffsetMode, .system)
        XCTAssertEqual(state.value?.contentOffsetSeed.value, 0)
        XCTAssertFalse(viewGraph.hasPendingTransactions)
    }

    // ASSERTIONS systemScrollViewContainerSizeCommitLifecycleObserved
    func testHostingScrollViewDefersAndCoalescesContainerSizeCommit() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph
        var containerSize: Attribute<CGSize>!
        var scrollHost: HostingScrollView!

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            containerSize = graph.makeInput(value: CGSize.zero)
            scrollHost = HostingScrollView(
                graphRef: _AGGraphContext(graph: graph),
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak(),
                containerSize: containerSize.asWeak()
            )

            _ = scrollHost.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 300, height: 400),
                containingSize: CGSize(width: 80, height: 120),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            _ = scrollHost.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 300, height: 400),
                containingSize: CGSize(width: 90, height: 140),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))

            XCTAssertEqual(containerSize.value, .zero)
        }

        XCTAssertTrue(viewGraph.hasPendingTransactions)
        viewGraph.flushTransactions()

        try viewGraph.data.withCurrent {
            XCTAssertEqual(containerSize.value, CGSize(width: 90, height: 140))
            let transaction = try XCTUnwrap(
                viewGraph.data.graph.transaction(for: containerSize.identifier)
            )
            XCTAssertTrue(transaction.fromScrollView)
        }
        XCTAssertFalse(viewGraph.hasPendingTransactions)

        viewGraph.data.withCurrent {
            _ = scrollHost.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 300, height: 400),
                containingSize: CGSize(width: 90, height: 140),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
        }
        XCTAssertFalse(viewGraph.hasPendingTransactions)
    }

    func testHostingScrollViewResolvesVisibilityAwareTargetIntoPendingContext() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(graphRef: graphRef, layoutState: state.asWeak())
            let target = ScrollTarget(
                rect: CGRect(x: 250, y: 150, width: 100, height: 50)
            )
            let config = ScrollTargetConfiguration(
                animation: .linear(duration: 0.25),
                requiresVisibility: true,
                preservesVelocity: true
            )

            XCTAssertFalse(host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 100, y: 100),
                contentFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
                containingSize: CGSize(width: 200, height: 200),
                offsetMode: .target({ _, _ in target }, config: config),
                safeInsets: EdgeInsets()
            )))

            XCTAssertEqual(host.pendingContext?.contentOffset, CGPoint(x: 150, y: 100))
            XCTAssertEqual(host.animationTarget, target)
            XCTAssertEqual(host.animationTargetConfig, config)

            host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 100, y: 100),
                contentFrame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
                containingSize: CGSize(width: 200, height: 200),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            XCTAssertNil(host.animationTarget)
            XCTAssertNil(host.animationTargetConfig)
        }
    }

    // ASSERTIONS systemScrollViewDeferredTargetInvocationContextObserved
    // ASSERTIONS attributeGraphStrongAttributeOwnerLookupObserved
    func testHostingScrollViewReappliesTargetThroughGraphActionOutbox() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        var host: HostingScrollView!
        var targetY: Attribute<CGFloat>!
        var providerGraphBindings: [Bool] = []

        graphRef.withCurrent {
            targetY = graph.makeInput(value: 100)
            host = HostingScrollView(
                graphRef: graphRef,
                layoutState: graph.makeInput(
                    value: SystemScrollLayoutState()
                ).asWeak()
            )
        }

        graphRef.withCurrent {
            _ = host.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 200, height: 1_000),
                containingSize: CGSize(width: 200, height: 200),
                offsetMode: .target(
                    { _, _ in
                        providerGraphBindings.append(_AGGraph.current != nil)
                        return ScrollTarget(
                            rect: CGRect(
                                x: 0,
                                y: targetY.value,
                                width: 200,
                                height: 40
                            ),
                            anchor: .top
                        )
                    },
                    config: ScrollTargetConfiguration()
                ),
                safeInsets: EdgeInsets()
            ))
        }

        XCTAssertEqual(providerGraphBindings, [true])
        XCTAssertEqual(host.pendingContext?.contentOffset.y, 100)
        XCTAssertEqual(graph.actionOutbox.count, 1)

        graphRef.withCurrent {
            targetY.value = 400
        }
        let actions = graph.actionOutbox
        graph.actionOutbox.removeAll()
        XCTAssertNil(_AGGraph.current)
        actions.forEach { $0() }

        XCTAssertEqual(providerGraphBindings, [true, true])
        XCTAssertNil(_AGGraph.current)
        XCTAssertEqual(host.pendingContext?.contentOffset.y, 400)
        XCTAssertFalse(Update.isActive)
    }

    func testMakeHostingScrollViewReusesHostObject() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeStatefulRule(MakeHostingScrollView(
                _layoutState: state,
                graphRef: graphRef
            ))

            let first = host.value
            state.setValue(SystemScrollLayoutState(contentOffset: CGPoint(x: 1, y: 2)))
            XCTAssertTrue(first === host.value)
        }
    }

    func testHostingScrollViewPropertiesControlPresentationClipping() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            )
            var properties = ScrollEnvironmentProperties()

            XCTAssertTrue(host.host.isClippingEnabled)

            properties.isClippingEnabled = false
            host.updateProperties(properties)
            XCTAssertFalse(host.host.isClippingEnabled)

            properties.isClippingEnabled = true
            host.updateProperties(properties)
            XCTAssertTrue(host.host.isClippingEnabled)

            // ASSERTIONS: scrollClipDisabledPlatformConsumerObserved
        }
    }

    func testAdjustedStateAndUpdatedHostPreserveHostOriginatedState() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let rawState = graph.makeInput(value: SystemScrollLayoutState(
                contentOffset: CGPoint(x: 12, y: 34),
                systemContentInsets: EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 0),
                systemTranslation: CGSize(width: 2, height: 3),
                contentOffsetSeed: VersionSeed(value: 5)
            ))
            let insets = EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
            let configuration = graph.makeInput(value: ScrollViewConfiguration(contentInsets: insets))
            let frame = graph.makeInput(value: ViewFrame(
                origin: CGPoint(x: 5, y: 6),
                size: ViewSize(CGSize(width: 300, height: 400))
            ))
            let size = graph.makeInput(value: ViewSize(CGSize(width: 80, height: 120)))
            let anchors = graph.makeInput(value: ScrollAnchorStorage())
            let phaseState = graph.makeInput(value: ScrollPhaseState())
            let pixelLength = graph.makeInput(value: CGFloat(1))
            let phase = graph.makeInput(value: _GraphInputs.Phase())
            let transaction = graph.makeInput(value: Transaction())
            let layoutDirection = graph.makeInput(value: LayoutDirection.leftToRight)
            let adjustedRule = ScrollViewAdjustedState(
                _size: size,
                _configuration: configuration,
                _defaultAnchors: anchors,
                _state: rawState,
                _phaseState: phaseState,
                _contentFrame: frame,
                _pixelLength: pixelLength,
                _phase: phase,
                _transaction: transaction,
                _layoutDirection: layoutDirection
            )
            XCTAssertEqual(
                Mirror(reflecting: adjustedRule).children.compactMap(\.label),
                [
                    "_size", "_configuration", "_defaultAnchors", "_state",
                    "_phaseState", "_contentFrame", "_pixelLength", "_phase",
                    "_transaction", "_layoutDirection", "_positionBinding",
                    "oldFrame", "oldSize", "oldOffset", "hasScrolled",
                    "resetSeed", "_lastUpdateSeed",
                ]
            )
            let adjusted = graph.makeStatefulRule(adjustedRule)

            XCTAssertEqual(adjusted.value.contentOffset, .zero)
            XCTAssertEqual(adjusted.value.contentInsets, insets)
            XCTAssertEqual(
                adjusted.value.systemContentInsets,
                EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 0)
            )
            XCTAssertEqual(adjusted.value.systemTranslation, CGSize(width: 2, height: 3))
            XCTAssertEqual(adjusted.value.contentOffsetMode, .adjustment(reason: .reset))
            XCTAssertEqual(adjusted.value.contentOffsetSeed.value, 3_470_406_040)

            rawState.setValue(SystemScrollLayoutState(
                contentOffset: CGPoint(x: 12, y: 34),
                systemContentInsets: EdgeInsets(top: 9, leading: 0, bottom: 0, trailing: 0),
                systemTranslation: CGSize(width: 2, height: 3),
                contentOffsetMode: .system,
                contentOffsetSeed: VersionSeed(value: 6)
            ))
            XCTAssertEqual(adjusted.value.contentOffset, CGPoint(x: 12, y: 34))
            XCTAssertEqual(adjusted.value.contentOffsetMode, .system)
            XCTAssertEqual(adjusted.value.contentOffsetSeed.value, 6)

            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: rawState.asWeak()
            ))
            var environmentValues = EnvironmentValues()
            environmentValues.automaticContentMargins = OptionalEdgeInsets(
                EdgeInsets(top: 7, leading: 8, bottom: 9, trailing: 10)
            )
            environmentValues.scrollContentBackground = ScrollContentBackground(
                visibility: .visible
            )
            let environment = graph.makeInput(value: environmentValues)
            var propertiesValue = ScrollEnvironmentProperties(environment: environmentValues)
            propertiesValue.isClippingEnabled = false
            let properties = graph.makeInput(value: propertiesValue)
            let containerSize = graph.makeInput(value: CGSize(width: 80, height: 120))
            let outerSize = graph.makeInput(value: CGSize(width: 88, height: 126))
            let indicatorMetrics = graph.makeInput(value: ScrollIndicatorMetricsStorage())
            let safeAreaInsets = graph.makeInput(value: insets)
            let rtlAdjustment = graph.makeInput(value: CGSize.zero)
            let updatedRule = UpdatedHostingScrollView(
                _scrollView: host,
                _configuration: configuration,
                _properties: properties,
                _contentFrame: frame,
                _size: containerSize,
                _outerSize: outerSize,
                _indicatorMetrics: indicatorMetrics,
                _safeAreaInsets: safeAreaInsets,
                _rtlAdjustment: rtlAdjustment,
                _adjustedState: adjusted,
                _environment: environment
            )
            XCTAssertEqual(
                Mirror(reflecting: updatedRule).children.compactMap(\.label),
                [
                    "_descendantScrollViewsAxes", "_container", "_scrollView",
                    "_configuration", "_properties", "_contentFrame", "_size",
                    "_outerSize", "_indicatorMetrics", "_safeAreaInsets",
                    "_rtlAdjustment", "_adjustedState", "_environment",
                    "lastUpdateSeed", "tracker", "oldProperties", "oldMargins",
                ]
            )
            let updated = graph.makeStatefulRule(updatedRule)

            XCTAssertTrue(updated.value === host.value)
            XCTAssertEqual(host.value.configuration.contentInsets, insets)
            XCTAssertEqual(host.value.properties, propertiesValue)
            XCTAssertEqual(
                host.value.contentMargins.automatic,
                OptionalEdgeInsets(EdgeInsets(top: 7, leading: 8, bottom: 9, trailing: 10))
            )
            XCTAssertEqual(host.value.scrollContentBackground.visibility, .visible)

            environmentValues.automaticContentMargins = OptionalEdgeInsets(
                EdgeInsets(top: 11, leading: 12, bottom: 13, trailing: 14)
            )
            environmentValues.scrollContentBackground = ScrollContentBackground(
                visibility: .hidden
            )
            environment.setValue(environmentValues)
            propertiesValue.isEnabled = false
            properties.setValue(propertiesValue)
            _ = updated.value
            XCTAssertEqual(host.value.properties, propertiesValue)
            XCTAssertEqual(
                host.value.contentMargins.automatic,
                OptionalEdgeInsets(EdgeInsets(top: 11, leading: 12, bottom: 13, trailing: 14))
            )
            XCTAssertEqual(host.value.scrollContentBackground.visibility, .hidden)
            XCTAssertEqual(host.value.pendingContext, HostingScrollViewUpdateContext(
                contentOffset: CGPoint(x: 12, y: 34),
                contentFrame: CGRect(x: 5, y: 6, width: 300, height: 400),
                containingSize: CGSize(width: 80, height: 120),
                offsetMode: .system,
                safeInsets: insets
            ))

            // ASSERTIONS: scrollContentBackgroundPlatformConsumerObserved
        }
    }

    func testUpdatedScrollViewContainerRetainsOneAttachmentIdentity() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            ))
            let container = graph.makeStatefulRule(
                UpdatedScrollViewContainer(_scrollView: host)
            )

            let first = container.value
            XCTAssertTrue(first === container.value)
            XCTAssertTrue(first.scrollView === host.value)
            XCTAssertTrue(host.value.parentContainer === first)
            XCTAssertTrue(host.value.host.scrollView === host.value)

            let secondHost = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            ))
            let secondContainer = graph.makeStatefulRule(
                UpdatedScrollViewContainer(_scrollView: secondHost)
            ).value
            XCTAssertFalse(first === secondContainer)
            XCTAssertFalse(host.value === secondHost.value)
            XCTAssertFalse(host.value.host === secondHost.value.host)
        }
    }

    func testScrollViewDisplayListFrameUsesPinnedInsetRTLAndPixelOrder() {
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let configuration = graph.makeInput(value: ScrollViewConfiguration(
                axes: .vertical,
                contentInsets: EdgeInsets(
                    top: 0.5,
                    leading: 1.5,
                    bottom: 2.5,
                    trailing: 3.5
                )
            ))
            let alignmentAdjustment = graph.makeInput(
                value: CGSize(width: 90, height: 80)
            )
            let rule = ScrollViewDisplayListFrame(
                _configuration: configuration,
                _position: graph.makeInput(value: CGPoint(x: 10.25, y: 20.25)),
                _containerPosition: graph.makeInput(value: CGPoint(x: 2, y: 4)),
                _size: graph.makeInput(value: ViewSize(
                    CGSize(width: 100.2, height: 50.2)
                )),
                _safeAreaInsets: graph.makeInput(value: EdgeInsets(
                    top: 1,
                    leading: 2,
                    bottom: 3,
                    trailing: 4
                )),
                _alignmentAdjustment: alignmentAdjustment,
                _rtlAdjustment: graph.makeInput(value: CGSize(width: 5, height: 6)),
                _layoutDirection: graph.makeInput(value: .rightToLeft),
                _pixelLength: graph.makeInput(value: 0.5)
            )
            XCTAssertEqual(
                Mirror(reflecting: rule).children.compactMap(\.label),
                [
                    "_configuration", "_position", "_containerPosition",
                    "_size", "_safeAreaInsets", "_alignmentAdjustment",
                    "_rtlAdjustment", "_layoutDirection", "_pixelLength",
                ]
            )
            let frame = graph.makeRule(rule)

            XCTAssertEqual(
                configuration.value.edgesToExpandDisplayListFrame,
                .all
            )
            XCTAssertEqual(
                frame.value,
                CGRect(x: -2, y: 9, width: 116, height: 63)
            )

            alignmentAdjustment.setValue(CGSize(width: -30, height: -40))
            XCTAssertEqual(
                frame.value,
                CGRect(x: -2, y: 9, width: 116, height: 63)
            )
        }
    }

    func testScrollViewDisplayListPassesThroughWithoutLiveContainer() {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            ))
            let frame = graph.makeInput(value: CGRect(x: 1, y: 2, width: 30, height: 40))
            let child = graph.makeInput(value: attachmentDisplayList(serial: 1))
            let passedThrough = graph.makeRule(ScrollViewDisplayList(
                identity: _DisplayList_Identity(decodedValue: 71),
                _scrollView: host,
                _frame: frame,
                _contentList: OptionalAttribute(child)
            ))
            let empty = graph.makeRule(ScrollViewDisplayList(
                identity: _DisplayList_Identity(decodedValue: 72),
                _scrollView: host,
                _frame: frame,
                _contentList: OptionalAttribute()
            ))

            XCTAssertEqual(passedThrough.value, child.value)
            XCTAssertTrue(empty.value.items.isEmpty)
        }
    }

    func testScrollViewDisplayListReusesGroupIdentityAcrossChildUpdates() throws {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        try graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            ))
            let container = graph.makeStatefulRule(
                UpdatedScrollViewContainer(_scrollView: host)
            )
            _ = container.value
            let frameValue = CGRect(x: 2, y: 3, width: 90, height: 70)
            let frame = graph.makeInput(value: frameValue)
            let child = graph.makeInput(value: attachmentDisplayList(serial: 1))
            let identity = _DisplayList_Identity(decodedValue: 73)
            let displayList = graph.makeRule(ScrollViewDisplayList(
                identity: identity,
                _scrollView: host,
                _frame: frame,
                _contentList: OptionalAttribute(child)
            ))

            let first = displayList.value
            let firstItem = try XCTUnwrap(first.items.first)
            let firstEffect = try XCTUnwrap(firstItem.effectItem)
            guard case let .platformGroup(factory) = firstEffect.effect else {
                return XCTFail("expected platform-group effect")
            }
            XCTAssertEqual(first.items.count, 1)
            XCTAssertEqual(firstItem.identity, identity)
            XCTAssertEqual(firstItem.frame, frameValue)
            XCTAssertEqual(firstEffect.contents, child.value)
            XCTAssertEqual(ObjectIdentifier(factory), ObjectIdentifier(container.value))
            XCTAssertTrue(factory.platformGroupContainer === host.value.host)

            child.setValue(attachmentDisplayList(serial: 2))
            let second = displayList.value
            let secondItem = try XCTUnwrap(second.items.first)
            let secondEffect = try XCTUnwrap(secondItem.effectItem)
            XCTAssertEqual(secondItem.identity, identity)
            XCTAssertEqual(secondItem.frame, frameValue)
            XCTAssertNotEqual(firstItem.version, secondItem.version)
            XCTAssertEqual(secondEffect.contents, child.value)
            XCTAssertTrue(host.value.parentContainer === container.value)
        }
    }

    func testScrollViewResponderReusesIdentityAndNestsUpdatedChildren() throws {
        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)

        try graphRef.withCurrent {
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            ))
            let container = graph.makeStatefulRule(
                UpdatedScrollViewContainer(_scrollView: host)
            )
            _ = container.value
            let firstChild = ScrollHostTestResponder()
            let secondChild = ScrollHostTestResponder()
            let children: Attribute<[ViewResponder]> = graph.makeInput(
                value: [firstChild]
            )
            let position = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let size = graph.makeInput(value: ViewSize(
                CGSize(width: 100, height: 80)
            ))
            let transform = graph.makeInput(value: ViewTransform.identity)
            let inputs = makeAttachmentViewInputs(
                graph: graph,
                position: position,
                size: size,
                transform: transform
            )
            let layoutResponder = DefaultLayoutViewResponder(
                inputs: inputs,
                viewSubgraph: AGSubgraph()
            )
            let rule = ScrollViewResponder(
                _scrollView: host,
                _position: position,
                _size: size,
                _transform: transform,
                _children: children,
                _responder: nil,
                layoutResponder: layoutResponder
            )
            XCTAssertEqual(
                Mirror(reflecting: rule).children.compactMap(\.label),
                [
                    "_scrollView", "_position", "_size", "_transform",
                    "_children", "_responder", "layoutResponder",
                ]
            )
            let responders = graph.makeStatefulRule(rule)

            let first = try XCTUnwrap(
                responders.value.first as? HostingScrollViewResponder
            )
            XCTAssertTrue(first === responders.value.first)
            XCTAssertTrue(host.value.responder === first)
            XCTAssertTrue(first.representedView === host.value.host)
            XCTAssertTrue(first.hostContainer === container.value)
            XCTAssertNil(first.parent)
            XCTAssertTrue(layoutResponder.parent === first)
            XCTAssertTrue(first.children.first === firstChild)
            XCTAssertTrue(firstChild.parent === first)

            children.setValue([secondChild])
            let updated = try XCTUnwrap(
                responders.value.first as? HostingScrollViewResponder
            )
            XCTAssertTrue(updated === first)
            XCTAssertTrue(updated.children.first === secondChild)
            XCTAssertNil(firstChild.parent)
            XCTAssertTrue(secondChild.parent === updated)
        }
    }

    // ASSERTIONS scrollIndicatorPresentationGeometryObserved hoverEventBindingAncestorDispatchObserved
    func testScrollViewResponderConvertsGlobalHoverIntoIndicatorRollover() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let graphRef = _AGGraphContext(graph: graph)
            let state = graph.makeInput(value: SystemScrollLayoutState())
            let host = graph.makeInput(value: HostingScrollView(
                graphRef: graphRef,
                layoutState: state.asWeak()
            ))
            let container = graph.makeStatefulRule(
                UpdatedScrollViewContainer(_scrollView: host)
            )
            _ = container.value

            host.value.updateConfiguration(
                ScrollViewConfiguration(axes: .vertical)
            )
            var properties = ScrollEnvironmentProperties()
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .overlay
            )
            host.value.updateProperties(properties)
            host.value.updateIndicatorPresentation(
                outerSize: CGSize(width: 80, height: 60),
                metrics: ScrollIndicatorMetricsStorage(
                    vertical: ScrollIndicatorMetrics(
                        thickness: 8,
                        minimumThumbLength: 20
                    )
                )
            )
            _ = host.value.updateContext(HostingScrollViewUpdateContext(
                contentOffset: .zero,
                contentFrame: CGRect(x: 0, y: 0, width: 80, height: 180),
                containingSize: CGSize(width: 80, height: 60),
                offsetMode: .system,
                safeInsets: EdgeInsets()
            ))
            Update.ensure {
                host.value.publishSystemContentOffset(CGPoint(x: 0, y: 20))
            }

            let position = graph.makeInput(value: CGPoint(x: 10, y: 20))
            let size = graph.makeInput(value: ViewSize(
                CGSize(width: 80, height: 60)
            ))
            let transform = graph.makeInput(value: ViewTransform.identity)
            let inputs = makeAttachmentViewInputs(
                graph: graph,
                position: position,
                size: size,
                transform: transform
            )
            let responderRule = graph.makeStatefulRule(ScrollViewResponder(
                _scrollView: host,
                _position: position,
                _size: size,
                _transform: transform,
                _children: graph.makeInput(value: []),
                _responder: nil,
                layoutResponder: DefaultLayoutViewResponder(
                    inputs: inputs,
                    viewSubgraph: AGSubgraph()
                )
            ))
            let responder = try XCTUnwrap(
                responderRule.value.first as? HostingScrollViewResponder
            )
            let eventID = EventID(type: HoverEvent.self, serial: 802)

            XCTAssertTrue(responder.updateHoverEvent(
                id: eventID,
                at: CGPoint(x: 74, y: 50),
                time: .zero
            ))
            XCTAssertTrue(host.value.updateIndicatorVisibility(
                at: Time(seconds: 0.125)
            ))
            XCTAssertEqual(
                host.value.host.indicatorLayout.vertical?.trackFrame.width,
                13
            )

            XCTAssertTrue(responder.endHoverEvent(
                id: eventID,
                time: Time(seconds: 0.2)
            ))
            XCTAssertTrue(host.value.updateIndicatorVisibility(
                at: Time(seconds: 0.325)
            ))
            XCTAssertEqual(
                host.value.host.indicatorLayout.vertical?.trackFrame.width,
                8
            )
        }
    }

    func testScrollViewAttachmentBacklinksDoNotRetainTheOwnerChain() {
        weak var weakHost: HostingScrollView?
        weak var weakContainer: HostingScrollView.PlatformContainer?
        weak var weakGroup: HostingScrollView.PlatformGroupContainer?

        let graph = _AGGraph()
        let graphRef = _AGGraphContext(graph: graph)
        graphRef.withCurrent {
            do {
                let state = graph.makeInput(value: SystemScrollLayoutState())
                let host = HostingScrollView(
                    graphRef: graphRef,
                    layoutState: state.asWeak()
                )
                let container = HostingScrollView.PlatformContainer(
                    scrollView: host
                )
                host.parentContainer = container
                weakHost = host
                weakContainer = container
                weakGroup = host.host
            }

            XCTAssertNil(weakHost)
            XCTAssertNil(weakContainer)
            XCTAssertNil(weakGroup)
        }
    }

    private func makeIndicatorHost(
        graph: _AGGraph,
        axes: Axis.Set,
        contentOffset: CGPoint,
        contentSize: CGSize,
        viewportSize: CGSize,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> HostingScrollView {
        let graphRef = _AGGraphContext(graph: graph)
        let state = graph.makeInput(value: SystemScrollLayoutState(
            contentOffset: contentOffset
        ))
        let phase = graph.makeInput(value: ScrollPhaseState())
        let host = HostingScrollView(
            graphRef: graphRef,
            layoutState: state.asWeak(),
            phaseState: phase.asWeak()
        )
        host.updateConfiguration(ScrollViewConfiguration(axes: axes))
        var properties = ScrollEnvironmentProperties()
        if axes.contains(.horizontal) {
            properties.horizontalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .fixedArea
            )
        }
        if axes.contains(.vertical) {
            properties.verticalIndicator = ScrollIndicatorConfiguration(
                visibility: .visible,
                style: .fixedArea
            )
        }
        host.updateProperties(properties)
        host.updateSafeArea(EdgeInsets(), layoutDirection: layoutDirection)
        let thickness: CGFloat = 10
        host.updateIndicatorPresentation(
            outerSize: CGSize(
                width: viewportSize.width
                    + (axes.contains(.vertical) ? thickness : 0),
                height: viewportSize.height
                    + (axes.contains(.horizontal) ? thickness : 0)
            ),
            metrics: ScrollIndicatorMetricsStorage(
                horizontal: ScrollIndicatorMetrics(
                    thickness: thickness,
                    minimumThumbLength: 20
                ),
                vertical: ScrollIndicatorMetrics(
                    thickness: thickness,
                    minimumThumbLength: 20
                )
            )
        )
        _ = host.updateContext(HostingScrollViewUpdateContext(
            contentOffset: contentOffset,
            contentFrame: CGRect(origin: .zero, size: contentSize),
            containingSize: viewportSize,
            offsetMode: .system,
            safeInsets: EdgeInsets()
        ))
        return host
    }

    private func attachmentDisplayList(serial: UInt32) -> DisplayList {
        var list = DisplayList()
        list.items.append(DisplayList.Item(
            effect: .identity,
            contents: DisplayList(),
            frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            identity: _DisplayList_Identity(decodedValue: serial),
            version: DisplayList.Version(value: Int(serial))
        ))
        return list
    }

    private func makeAttachmentViewInputs(
        graph: _AGGraph,
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        transform: Attribute<ViewTransform>
    ) -> _ViewInputs {
        let keys = PreferenceKeys()
        return _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time()),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: EnvironmentValues.tracking()),
                transaction: graph.makeInput(value: Transaction())
            ),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: keys,
                hostKeys: graph.makeInput(value: keys)
            ),
            transform: transform,
            position: position,
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: size,
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}

private final class ScrollHostTestResponder: ViewResponder {
}

private final class ScrollCommitViewGraphDelegate: ViewGraphDelegate {
    weak var graph: ViewGraph?
    var requestedDelays: [Double] = []

    init(graph: ViewGraph) {
        self.graph = graph
    }

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let graph else {
            fatalError("The view graph must outlive its delegate.")
        }
        return body(graph)
    }

    func graphDidChange() {}

    func requestUpdate(after: Double) {
        requestedDelays.append(after)
    }

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }
}

private final class HostScrollTargetBehaviorRecorder {
    var originalTarget: ScrollTarget?
    var proposedTarget: ScrollTarget?
    var velocity: CGVector?
    var geometry: ScrollGeometry?
    var axes: Axis.Set?
    var decelerationRate: ScrollDecelerationRate?
    var overrideTargetOrigin: CGPoint?
    var invocationCount = 0
}

private struct HostRecordingScrollTargetBehavior: ScrollTargetBehavior {
    var recorder: HostScrollTargetBehaviorRecorder
    var targetOrigin: CGPoint

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        recorder.invocationCount += 1
        recorder.originalTarget = context.originalTarget
        recorder.proposedTarget = target
        recorder.velocity = context.velocity
        recorder.geometry = context.geometry
        recorder.axes = context.axes
        recorder.decelerationRate = context.decelerationRate
        target.rect.origin = recorder.overrideTargetOrigin ?? targetOrigin
    }
}
