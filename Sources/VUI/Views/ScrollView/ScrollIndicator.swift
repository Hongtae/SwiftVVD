//
//  File: ScrollIndicator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Collects the layout values shared by indicator presentation geometry.
///
/// Layout, drawing admission, hover admission, and pointer interaction resolve
/// the same value so a later theme integration has one metric injection point.
struct ScrollIndicatorPresentationMetrics: Equatable, Hashable, Sendable {
    static let defaultValue: ScrollIndicatorPresentationMetrics = {
        let axisMetrics = ScrollIndicatorMetrics()
        return ScrollIndicatorPresentationMetrics(
            overlayThickness: axisMetrics.thickness,
            overlayMinimumThumbLength: axisMetrics.minimumThumbLength,
            fixedAreaThickness: 11,
            fixedAreaMinimumThumbLength: 20,
            trackSideInset: 3,
            trackEndInset: 3,
            overlayExpansion: 5,
            overlayProximityPadding: 2
        )
    }()

    var overlayThickness: CGFloat
    var overlayMinimumThumbLength: CGFloat
    var fixedAreaThickness: CGFloat
    var fixedAreaMinimumThumbLength: CGFloat
    var trackSideInset: CGFloat
    var trackEndInset: CGFloat
    var overlayExpansion: CGFloat
    var overlayProximityPadding: CGFloat

    var resolved: ScrollIndicatorPresentationMetrics {
        ScrollIndicatorPresentationMetrics(
            overlayThickness: Self.resolvedLength(overlayThickness),
            overlayMinimumThumbLength:
                Self.resolvedLength(overlayMinimumThumbLength),
            fixedAreaThickness: Self.resolvedLength(fixedAreaThickness),
            fixedAreaMinimumThumbLength:
                Self.resolvedLength(fixedAreaMinimumThumbLength),
            trackSideInset: Self.resolvedLength(trackSideInset),
            trackEndInset: Self.resolvedLength(trackEndInset),
            overlayExpansion: Self.resolvedLength(overlayExpansion),
            overlayProximityPadding: Self.resolvedLength(overlayProximityPadding)
        )
    }

    private static func resolvedLength(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }
}

/// Geometry settings shared by overlay and fixed-area scroll indicators.
public struct ScrollIndicatorMetrics: Equatable, Hashable, Sendable {
    public var thickness: CGFloat
    public var minimumThumbLength: CGFloat

    public init(
        thickness: CGFloat = 6,
        minimumThumbLength: CGFloat = 26
    ) {
        self.thickness = thickness
        self.minimumThumbLength = minimumThumbLength
    }

    var resolved: ScrollIndicatorMetrics {
        ScrollIndicatorMetrics(
            thickness: Self.resolvedLength(thickness),
            minimumThumbLength: Self.resolvedLength(minimumThumbLength)
        )
    }

    private static func resolvedLength(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }
}

/// Stores independent indicator metrics for each scroll axis in the environment.
struct ScrollIndicatorMetricsStorage: Equatable, Sendable {
    private(set) var presentation: ScrollIndicatorPresentationMetrics
    private(set) var horizontal: ScrollIndicatorMetrics
    private(set) var vertical: ScrollIndicatorMetrics
    private var hasCustomHorizontalMetrics: Bool
    private var hasCustomVerticalMetrics: Bool

    init(
        presentation: ScrollIndicatorPresentationMetrics =
            .defaultValue,
        horizontal: ScrollIndicatorMetrics? = nil,
        vertical: ScrollIndicatorMetrics? = nil
    ) {
        let presentation = presentation.resolved
        let defaultAxisMetrics = ScrollIndicatorMetrics(
            thickness: presentation.overlayThickness,
            minimumThumbLength: presentation.overlayMinimumThumbLength
        )
        self.presentation = presentation
        self.horizontal = horizontal ?? defaultAxisMetrics
        self.vertical = vertical ?? defaultAxisMetrics
        self.hasCustomHorizontalMetrics = horizontal != nil
        self.hasCustomVerticalMetrics = vertical != nil
    }

    mutating func set(_ metrics: ScrollIndicatorMetrics, axes: Axis.Set) {
        if axes.contains(.horizontal) {
            horizontal = metrics
            hasCustomHorizontalMetrics = true
        }
        if axes.contains(.vertical) {
            vertical = metrics
            hasCustomVerticalMetrics = true
        }
    }

    /// Resolves presentation-specific framework defaults without replacing
    /// explicitly configured axis metrics, which override either presentation.
    func resolved(
        for axis: Axis,
        style: ScrollIndicatorStyle
    ) -> ScrollIndicatorMetrics {
        var metrics: ScrollIndicatorMetrics
        let hasCustomMetrics: Bool
        switch axis {
        case .horizontal:
            metrics = horizontal.resolved
            hasCustomMetrics = hasCustomHorizontalMetrics
        case .vertical:
            metrics = vertical.resolved
            hasCustomMetrics = hasCustomVerticalMetrics
        }
        if !hasCustomMetrics, style.value == .legacy {
            metrics.thickness = presentation.fixedAreaThickness
            metrics.minimumThumbLength =
                presentation.fixedAreaMinimumThumbLength
        }
        return metrics
    }
}

/// Carries the current overlay expansion fraction independently for each axis.
struct ScrollIndicatorExpansion: Equatable, Sendable {
    var horizontal: CGFloat = 0
    var vertical: CGFloat = 0

    subscript(axis: Axis) -> CGFloat {
        get {
            switch axis {
            case .horizontal: horizontal
            case .vertical: vertical
            }
        }
        set {
            switch axis {
            case .horizontal: horizontal = newValue
            case .vertical: vertical = newValue
            }
        }
    }
}

/// Resolved outer-viewport geometry shared by indicator rendering and hit testing.
struct ScrollIndicatorLayout: Equatable {
    /// The indicator element that admitted a pointer stream. Page cases describe
    /// content-offset direction, which can differ from visual order in RTL layouts.
    enum InteractionPart: Equatable {
        case thumb(Axis)
        case decrementPage(Axis)
        case incrementPage(Axis)

        var axis: Axis {
            switch self {
            case .thumb(let axis),
                 .decrementPage(let axis),
                 .incrementPage(let axis):
                axis
            }
        }
    }

    /// One axis's resolved drawing, interaction, and hover-proximity geometry.
    struct Indicator: Equatable {
        var trackFrame: CGRect
        var thumbFrame: CGRect
        var proximityFrame: CGRect? = nil
        /// Track visibility is independent of the thumb's overall visibility.
        /// A collapsed overlay presents only its thumb, while fixed-area tracks
        /// remain visible for the lifetime of their reserved region.
        var trackOpacity: Double = 1
        var opacity: Double
        var isFixedArea: Bool
    }

    var viewportFrame = CGRect.zero
    var reservedInsets = EdgeInsets()
    var horizontal: Indicator?
    var vertical: Indicator?
    var cornerFrame: CGRect?

    static func reservedInsets(
        configuration: ScrollViewConfiguration,
        properties: ScrollEnvironmentProperties,
        metrics: ScrollIndicatorMetricsStorage
    ) -> EdgeInsets {
        let horizontalMetrics = metrics.resolved(
            for: .horizontal,
            style: properties.horizontalIndicator.style
        )
        let verticalMetrics = metrics.resolved(
            for: .vertical,
            style: properties.verticalIndicator.style
        )
        let presentation = metrics.presentation
        return EdgeInsets(
            top: 0,
            leading: 0,
            bottom: configuration.axes.contains(.horizontal)
                && properties.horizontalIndicator.style.value == .legacy
                    ? fixedAreaSpan(
                        drawThickness: horizontalMetrics.thickness,
                        sideInset: presentation.trackSideInset
                    )
                    : 0,
            trailing: configuration.axes.contains(.vertical)
                && properties.verticalIndicator.style.value == .legacy
                    ? fixedAreaSpan(
                        drawThickness: verticalMetrics.thickness,
                        sideInset: presentation.trackSideInset
                    )
                    : 0
        )
    }

    static func make(
        outerSize: CGSize,
        contentOffset: CGPoint,
        contentSize: CGSize,
        contentInsets: EdgeInsets,
        configuration: ScrollViewConfiguration,
        properties: ScrollEnvironmentProperties,
        metrics: ScrollIndicatorMetricsStorage,
        layoutDirection: LayoutDirection,
        overlayOpacity: Double,
        expansion: ScrollIndicatorExpansion = ScrollIndicatorExpansion()
    ) -> ScrollIndicatorLayout {
        let outerSize = resolvedSize(outerSize)
        let requestedInsets = reservedInsets(
            configuration: configuration,
            properties: properties,
            metrics: metrics
        )
        let horizontalThickness = min(requestedInsets.bottom, outerSize.height)
        let verticalThickness = min(requestedInsets.trailing, outerSize.width)
        let fixedHorizontal = horizontalThickness > 0
        let fixedVertical = verticalThickness > 0

        let viewportOriginX = fixedVertical && layoutDirection == .rightToLeft
            ? verticalThickness
            : 0
        let viewportFrame = CGRect(
            x: viewportOriginX,
            y: 0,
            width: max(outerSize.width - verticalThickness, 0),
            height: max(outerSize.height - horizontalThickness, 0)
        )
        let visibleContentSize = viewportFrame.size.inset(by: contentInsets)
        let opacity = resolvedOpacity(overlayOpacity)
        let presentation = metrics.presentation

        var layout = ScrollIndicatorLayout(
            viewportFrame: viewportFrame,
            reservedInsets: EdgeInsets(
                top: 0,
                leading: 0,
                bottom: horizontalThickness,
                trailing: verticalThickness
            )
        )

        if configuration.axes.contains(.horizontal) {
            let metrics = metrics.resolved(
                for: .horizontal,
                style: properties.horizontalIndicator.style
            )
            let crossAxisFrame: CGRect
            if fixedHorizontal {
                let thickness = min(metrics.thickness, horizontalThickness)
                let inset = max((horizontalThickness - thickness) / 2, 0)
                crossAxisFrame = CGRect(
                    x: viewportFrame.minX,
                    y: viewportFrame.maxY + inset,
                    width: viewportFrame.width,
                    height: thickness
                )
            } else {
                let inset = min(
                    presentation.trackSideInset,
                    viewportFrame.height / 2
                )
                let thickness = overlayThickness(
                    collapsed: metrics.thickness,
                    available: max(viewportFrame.height - inset * 2, 0),
                    expansion: expansion.horizontal,
                    expansionDelta: presentation.overlayExpansion
                )
                crossAxisFrame = CGRect(
                    x: viewportFrame.minX,
                    y: viewportFrame.maxY - inset - thickness,
                    width: viewportFrame.width,
                    height: thickness
                )
            }
            let trackFrame = insetTrackEnds(
                crossAxisFrame,
                axis: .horizontal,
                inset: presentation.trackEndInset
            )
            let proximityFrame = fixedHorizontal ? nil : overlayProximityFrame(
                axis: .horizontal,
                viewportFrame: viewportFrame,
                collapsedThickness: metrics.thickness,
                layoutDirection: layoutDirection,
                presentation: presentation
            )
            layout.horizontal = makeIndicator(
                axis: .horizontal,
                trackFrame: trackFrame,
                contentOffset: contentOffset.x,
                contentLength: contentSize.width,
                viewportLength: visibleContentSize.width,
                metrics: metrics,
                configuration: properties.horizontalIndicator,
                showsIndicators: configuration.showsIndicators,
                isFixedArea: fixedHorizontal,
                layoutDirection: layoutDirection,
                overlayOpacity: opacity,
                proximityFrame: proximityFrame,
                expansion: expansion.horizontal
            )
        }

        if configuration.axes.contains(.vertical) {
            let metrics = metrics.resolved(
                for: .vertical,
                style: properties.verticalIndicator.style
            )
            let crossAxisFrame: CGRect
            if fixedVertical {
                let thickness = min(metrics.thickness, verticalThickness)
                let inset = max((verticalThickness - thickness) / 2, 0)
                crossAxisFrame = CGRect(
                    x: layoutDirection == .rightToLeft
                        ? inset
                        : viewportFrame.maxX + inset,
                    y: viewportFrame.minY,
                    width: thickness,
                    height: viewportFrame.height
                )
            } else {
                let inset = min(
                    presentation.trackSideInset,
                    viewportFrame.width / 2
                )
                let thickness = overlayThickness(
                    collapsed: metrics.thickness,
                    available: max(viewportFrame.width - inset * 2, 0),
                    expansion: expansion.vertical,
                    expansionDelta: presentation.overlayExpansion
                )
                crossAxisFrame = CGRect(
                    x: layoutDirection == .rightToLeft
                        ? viewportFrame.minX + inset
                        : viewportFrame.maxX - inset - thickness,
                    y: viewportFrame.minY,
                    width: thickness,
                    height: viewportFrame.height
                )
            }
            let trackFrame = insetTrackEnds(
                crossAxisFrame,
                axis: .vertical,
                inset: presentation.trackEndInset
            )
            let proximityFrame = fixedVertical ? nil : overlayProximityFrame(
                axis: .vertical,
                viewportFrame: viewportFrame,
                collapsedThickness: metrics.thickness,
                layoutDirection: layoutDirection,
                presentation: presentation
            )
            layout.vertical = makeIndicator(
                axis: .vertical,
                trackFrame: trackFrame,
                contentOffset: contentOffset.y,
                contentLength: contentSize.height,
                viewportLength: visibleContentSize.height,
                metrics: metrics,
                configuration: properties.verticalIndicator,
                showsIndicators: configuration.showsIndicators,
                isFixedArea: fixedVertical,
                layoutDirection: layoutDirection,
                overlayOpacity: opacity,
                proximityFrame: proximityFrame,
                expansion: expansion.vertical
            )
        }

        if fixedHorizontal && fixedVertical {
            layout.cornerFrame = CGRect(
                x: layoutDirection == .rightToLeft ? 0 : viewportFrame.maxX,
                y: viewportFrame.maxY,
                width: verticalThickness,
                height: horizontalThickness
            )
        }
        return layout
    }

    func interactionPart(
        at point: CGPoint,
        layoutDirection: LayoutDirection
    ) -> InteractionPart? {
        let indicators: [(Axis, Indicator?)] = [
            (.vertical, vertical),
            (.horizontal, horizontal),
        ]
        for (axis, indicator) in indicators {
            if indicator?.thumbFrame.contains(point) == true {
                return .thumb(axis)
            }
        }
        for (axis, indicator) in indicators {
            guard let indicator, indicator.trackFrame.contains(point) else {
                continue
            }
            let coordinate = axis == .horizontal ? point.x : point.y
            let thumbStart = axis == .horizontal
                ? indicator.thumbFrame.minX
                : indicator.thumbFrame.minY
            let isBeforeThumb = coordinate < thumbStart
            let decrementsOffset = axis != .horizontal
                || layoutDirection == .leftToRight
                ? isBeforeThumb
                : !isBeforeThumb
            return decrementsOffset
                ? .decrementPage(axis)
                : .incrementPage(axis)
        }
        return nil
    }

    /// Returns overlay axes whose maximum rollover band contains `point`.
    func hoverAxes(at point: CGPoint) -> Axis.Set {
        var axes = Axis.Set()
        if horizontal?.proximityFrame?.contains(point) == true {
            axes.insert(.horizontal)
        }
        if vertical?.proximityFrame?.contains(point) == true {
            axes.insert(.vertical)
        }
        return axes
    }

    private static func makeIndicator(
        axis: Axis,
        trackFrame: CGRect,
        contentOffset: CGFloat,
        contentLength: CGFloat,
        viewportLength: CGFloat,
        metrics: ScrollIndicatorMetrics,
        configuration: ScrollIndicatorConfiguration,
        showsIndicators: Bool,
        isFixedArea: Bool,
        layoutDirection: LayoutDirection,
        overlayOpacity: Double,
        proximityFrame: CGRect?,
        expansion: CGFloat
    ) -> Indicator? {
        let trackLength = axis == .horizontal
            ? trackFrame.width
            : trackFrame.height
        let contentLength = resolvedLength(contentLength)
        let viewportLength = min(resolvedLength(viewportLength), contentLength)
        let maximumOffset = max(contentLength - viewportLength, 0)
        let hasOverflow = maximumOffset > 0

        if isFixedArea {
            guard configuration.visibility != .never else {
                return nil
            }
        } else {
            guard showsIndicators,
                  hasOverflow,
                  configuration.visibility != .hidden,
                  configuration.visibility != .never,
                  overlayOpacity > 0 else {
                return nil
            }
        }

        let resolvedOffset = contentOffset.isFinite ? contentOffset : 0
        let leadingOverscroll = max(-resolvedOffset, 0)
        let trailingOverscroll = max(resolvedOffset - maximumOffset, 0)
        // The visible document intersection shrinks during rubber-band motion.
        // Keep the thumb pinned to the reached endpoint while shortening it by
        // the same proportion, subject to the configured minimum length.
        let presentedViewportLength = max(
            viewportLength - leadingOverscroll - trailingOverscroll,
            0
        )

        let thumbLength: CGFloat
        if hasOverflow {
            let proportionalLength = contentLength > 0 && contentLength.isFinite
                ? trackLength * presentedViewportLength / contentLength
                : 0
            thumbLength = min(
                max(metrics.minimumThumbLength, proportionalLength),
                trackLength
            )
        } else {
            thumbLength = trackLength
        }

        let clampedOffset = min(max(resolvedOffset, 0), maximumOffset)
        var progress: CGFloat
        if maximumOffset.isFinite, maximumOffset > 0 {
            progress = clampedOffset / maximumOffset
        } else {
            progress = 0
        }
        if axis == .horizontal && layoutDirection == .rightToLeft {
            progress = 1 - progress
        }
        let thumbOffset = max(trackLength - thumbLength, 0) * progress
        let thumbFrame: CGRect
        switch axis {
        case .horizontal:
            thumbFrame = CGRect(
                x: trackFrame.minX + thumbOffset,
                y: trackFrame.minY,
                width: thumbLength,
                height: trackFrame.height
            )
        case .vertical:
            thumbFrame = CGRect(
                x: trackFrame.minX,
                y: trackFrame.minY + thumbOffset,
                width: trackFrame.width,
                height: thumbLength
            )
        }
        return Indicator(
            trackFrame: trackFrame,
            thumbFrame: thumbFrame,
            proximityFrame: proximityFrame,
            trackOpacity: isFixedArea
                ? 1
                : (resolvedExpansion(expansion) > 0 ? overlayOpacity : 0),
            opacity: isFixedArea ? 1 : overlayOpacity,
            isFixedArea: isFixedArea
        )
    }

    private static func overlayThickness(
        collapsed: CGFloat,
        available: CGFloat,
        expansion: CGFloat,
        expansionDelta: CGFloat
    ) -> CGFloat {
        guard collapsed > 0, available > 0 else { return 0 }
        let progress = resolvedExpansion(expansion)
        return min(collapsed + expansionDelta * progress, available)
    }

    private static func resolvedExpansion(_ expansion: CGFloat) -> CGFloat {
        min(max(expansion.isFinite ? expansion : 0, 0), 1)
    }

    /// Fixed-area reservation includes equal gutters around a nonempty draw band.
    private static func fixedAreaSpan(
        drawThickness: CGFloat,
        sideInset: CGFloat
    ) -> CGFloat {
        drawThickness > 0 ? drawThickness + sideInset * 2 : 0
    }

    /// Insets only the scrolling axis. The cross-axis band has already been
    /// positioned independently for overlay or fixed-area presentation.
    private static func insetTrackEnds(
        _ frame: CGRect,
        axis: Axis,
        inset requestedInset: CGFloat
    ) -> CGRect {
        switch axis {
        case .horizontal:
            let inset = min(requestedInset, frame.width / 2)
            return frame.insetBy(dx: inset, dy: 0)
        case .vertical:
            let inset = min(requestedInset, frame.height / 2)
            return frame.insetBy(dx: 0, dy: inset)
        }
    }

    private static func overlayProximityFrame(
        axis: Axis,
        viewportFrame: CGRect,
        collapsedThickness: CGFloat,
        layoutDirection: LayoutDirection,
        presentation: ScrollIndicatorPresentationMetrics
    ) -> CGRect? {
        guard collapsedThickness > 0 else { return nil }
        let requestedThickness = collapsedThickness
            + presentation.overlayExpansion
            + presentation.overlayProximityPadding * 2
        switch axis {
        case .horizontal:
            let edgeInset = min(
                max(
                    presentation.trackSideInset
                        - presentation.overlayProximityPadding,
                    0
                ),
                viewportFrame.height / 2
            )
            let thickness = min(
                requestedThickness,
                max(viewportFrame.height - edgeInset * 2, 0)
            )
            guard thickness > 0 else { return nil }
            return insetTrackEnds(CGRect(
                x: viewportFrame.minX,
                y: viewportFrame.maxY - edgeInset - thickness,
                width: viewportFrame.width,
                height: thickness
            ), axis: .horizontal, inset: presentation.trackEndInset)
        case .vertical:
            let edgeInset = min(
                max(
                    presentation.trackSideInset
                        - presentation.overlayProximityPadding,
                    0
                ),
                viewportFrame.width / 2
            )
            let thickness = min(
                requestedThickness,
                max(viewportFrame.width - edgeInset * 2, 0)
            )
            guard thickness > 0 else { return nil }
            return insetTrackEnds(CGRect(
                x: layoutDirection == .rightToLeft
                    ? viewportFrame.minX + edgeInset
                    : viewportFrame.maxX - edgeInset - thickness,
                y: viewportFrame.minY,
                width: thickness,
                height: viewportFrame.height
            ), axis: .vertical, inset: presentation.trackEndInset)
        }
    }

    private static func resolvedLength(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }

    private static func resolvedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: resolvedLength(size.width),
            height: resolvedLength(size.height)
        )
    }

    private static func resolvedOpacity(_ opacity: Double) -> Double {
        opacity.isFinite ? min(max(opacity, 0), 1) : 0
    }
}

/// Projects the outer-viewport space reserved by fixed-area indicators.
struct ScrollIndicatorReservedInsets: Rule {
    typealias Value = EdgeInsets

    var _configuration: Attribute<ScrollViewConfiguration>
    var _storage: Attribute<ScrollEnvironmentStorage>
    var _metrics: Attribute<ScrollIndicatorMetricsStorage>

    var value: EdgeInsets {
        ScrollIndicatorLayout.reservedInsets(
            configuration: _configuration.value,
            properties: _storage.value.properties,
            metrics: _metrics.value
        )
    }
}

/// Derives the content viewport size after fixed-area reservation.
struct ScrollIndicatorViewportSize: Rule {
    typealias Value = ViewSize

    var _size: Attribute<ViewSize>
    var _reservedInsets: Attribute<EdgeInsets>

    var value: ViewSize {
        var size = _size.value
        size.value = size.value.inset(by: _reservedInsets.value)
        return size
    }
}

/// Positions the content viewport within its reserved outer frame.
struct ScrollIndicatorViewportPosition: Rule {
    typealias Value = CGPoint

    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _reservedInsets: Attribute<EdgeInsets>
    var _layoutDirection: Attribute<LayoutDirection>

    var value: CGPoint {
        var position = _position.value
        let size = _size.value.value
        let insets = _reservedInsets.value
        if _layoutDirection.value == .rightToLeft {
            position.x += min(insets.trailing, max(size.width, 0))
        } else {
            position.x += min(insets.leading, max(size.width, 0))
        }
        position.y += min(insets.top, max(size.height, 0))
        return position
    }
}

/// Carries axis-specific indicator geometry settings through the environment.
private struct ScrollIndicatorMetricsKey: EnvironmentKey {
    static var defaultValue: ScrollIndicatorMetricsStorage {
        ScrollIndicatorMetricsStorage()
    }
}

extension EnvironmentValues {
    var scrollIndicatorMetrics: ScrollIndicatorMetricsStorage {
        get { self[ScrollIndicatorMetricsKey.self] }
        set { self[ScrollIndicatorMetricsKey.self] = newValue }
    }

    public var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { scrollEnvironmentStorage.properties.horizontalIndicator.visibility }
        set {
            var properties = scrollEnvironmentStorage.properties
            properties.horizontalIndicator.visibility = newValue
            scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
        }
    }

    public var verticalScrollIndicatorVisibility: ScrollIndicatorVisibility {
        get { scrollEnvironmentStorage.properties.verticalIndicator.visibility }
        set {
            var properties = scrollEnvironmentStorage.properties
            properties.verticalIndicator.visibility = newValue
            scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
        }
    }
}

/// Applies visibility and option changes only to the selected indicator axes.
private struct TransformScrollIndicators: ScrollEnvironmentTransform {
    var visibility: ScrollIndicatorVisibility
    var options: ScrollIndicatorOptions
    var axes: Axis.Set

    func update(properties: inout ScrollEnvironmentProperties) {
        if axes.contains(.horizontal) {
            properties.horizontalIndicator.visibility = visibility
            properties.horizontalIndicator.options.formUnion(options)
        }
        if axes.contains(.vertical) {
            properties.verticalIndicator.visibility = visibility
            properties.verticalIndicator.options.formUnion(options)
        }
    }
}

/// Applies a presentation style only to the selected indicator axes.
private struct TransformScrollIndicatorStyle: ScrollEnvironmentTransform {
    var style: ScrollIndicatorStyle
    var axes: Axis.Set

    func update(properties: inout ScrollEnvironmentProperties) {
        if axes.contains(.horizontal) {
            properties.horizontalIndicator.style = style
        }
        if axes.contains(.vertical) {
            properties.verticalIndicator.style = style
        }
    }
}

/// Publishes a new indicator-flash seed whenever its trigger changes.
struct ScrollIndicatorsFlashModifier<Value>: ViewModifier where Value: Equatable {
    var value: Value
    @State private var seed: UInt32

    init(value: Value, seed: UInt32) {
        self.value = value
        self._seed = State(wrappedValue: seed)
    }

    func body(content: Content) -> some View {
        content
            .modifier(TransformScrollStorageModifier(
                transform: UpdateFlashSeed(seed: seed)
            ))
            .onChange(of: value, initial: false) {
                seed &+= 1
            }
    }

    /// Replaces the inherited flash seed with the modifier's current seed.
    struct UpdateFlashSeed: ScrollEnvironmentTransform {
        var seed: UInt32

        func update(properties: inout ScrollEnvironmentProperties) {
            properties.indicatorFlashSeed = seed
        }
    }
}

/// Controls whether both scroll indicators reveal themselves on appearance.
struct ScrollIndicatorFlashOnAppearModifier: ViewModifier {
    var isEnabled: Bool

    func body(content: Content) -> some View {
        content.modifier(TransformScrollStorageModifier(
            transform: UpdateIndicators(isEnabled: isEnabled)
        ))
    }

    /// Sets or clears the initial-reveal option without changing other options.
    struct UpdateIndicators: ScrollEnvironmentTransform {
        var isEnabled: Bool

        func update(properties: inout ScrollEnvironmentProperties) {
            if isEnabled {
                properties.verticalIndicator.options.insert(.revealsInitially)
                properties.horizontalIndicator.options.insert(.revealsInitially)
            } else {
                properties.verticalIndicator.options.remove(.revealsInitially)
                properties.horizontalIndicator.options.remove(.revealsInitially)
            }
        }
    }
}

extension View {
    nonisolated public func scrollIndicators(
        _ visibility: ScrollIndicatorVisibility,
        axes: Axis.Set = [.vertical, .horizontal]
    ) -> some View {
        modifier(TransformScrollStorageModifier(
            transform: TransformScrollIndicators(
                visibility: visibility,
                options: [],
                axes: axes
            )
        ))
    }

    /// Selects whether scroll indicators overlay content or reserve layout area.
    nonisolated public func scrollIndicatorStyle(
        _ style: ScrollIndicatorStyle,
        axes: Axis.Set = [.vertical, .horizontal]
    ) -> some View {
        modifier(TransformScrollStorageModifier(
            transform: TransformScrollIndicatorStyle(style: style, axes: axes)
        ))
    }

    /// Sets scrollbar thickness and minimum thumb length for selected axes.
    nonisolated public func scrollIndicatorMetrics(
        _ metrics: ScrollIndicatorMetrics,
        axes: Axis.Set = [.vertical, .horizontal]
    ) -> some View {
        transformEnvironment(\.scrollIndicatorMetrics) {
            $0.set(metrics, axes: axes)
        }
    }

    /// Flashes scroll indicators whenever the equatable trigger changes.
    nonisolated public func scrollIndicatorsFlash(
        trigger value: some Equatable
    ) -> some View {
        modifier(ScrollIndicatorsFlashModifier(value: value, seed: 0))
    }

    /// Controls whether scroll indicators flash when the view appears.
    nonisolated public func scrollIndicatorsFlash(onAppear: Bool) -> some View {
        modifier(ScrollIndicatorFlashOnAppearModifier(isEnabled: onAppear))
    }
}
