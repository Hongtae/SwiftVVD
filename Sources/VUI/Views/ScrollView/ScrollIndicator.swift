//
//  File: ScrollIndicator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Geometry settings shared by overlay and fixed-area scroll indicators.
public struct ScrollIndicatorMetrics: Equatable, Hashable, Sendable {
    public var thickness: CGFloat
    public var minimumThumbLength: CGFloat

    public init(
        thickness: CGFloat = 8,
        minimumThumbLength: CGFloat = 24
    ) {
        self.thickness = thickness
        self.minimumThumbLength = minimumThumbLength
    }

    static let defaultValue = ScrollIndicatorMetrics()

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
    var horizontal = ScrollIndicatorMetrics.defaultValue
    var vertical = ScrollIndicatorMetrics.defaultValue

    mutating func set(_ metrics: ScrollIndicatorMetrics, axes: Axis.Set) {
        if axes.contains(.horizontal) {
            horizontal = metrics
        }
        if axes.contains(.vertical) {
            vertical = metrics
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

    /// One axis's resolved track, thumb, opacity, and layout-reservation mode.
    struct Indicator: Equatable {
        var trackFrame: CGRect
        var thumbFrame: CGRect
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
        EdgeInsets(
            top: 0,
            leading: 0,
            bottom: configuration.axes.contains(.horizontal)
                && properties.horizontalIndicator.style.value == .legacy
                    ? metrics.horizontal.resolved.thickness
                    : 0,
            trailing: configuration.axes.contains(.vertical)
                && properties.verticalIndicator.style.value == .legacy
                    ? metrics.vertical.resolved.thickness
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
        overlayOpacity: Double
    ) -> ScrollIndicatorLayout {
        let outerSize = resolvedSize(outerSize)
        let resolvedMetrics = ScrollIndicatorMetricsStorage(
            horizontal: metrics.horizontal.resolved,
            vertical: metrics.vertical.resolved
        )
        let requestedInsets = reservedInsets(
            configuration: configuration,
            properties: properties,
            metrics: resolvedMetrics
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
            let metrics = resolvedMetrics.horizontal
            let trackFrame: CGRect
            if fixedHorizontal {
                trackFrame = CGRect(
                    x: viewportFrame.minX,
                    y: viewportFrame.maxY,
                    width: viewportFrame.width,
                    height: horizontalThickness
                )
            } else {
                let thickness = min(metrics.thickness, viewportFrame.height)
                trackFrame = CGRect(
                    x: viewportFrame.minX,
                    y: viewportFrame.maxY - thickness,
                    width: viewportFrame.width,
                    height: thickness
                )
            }
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
                overlayOpacity: opacity
            )
        }

        if configuration.axes.contains(.vertical) {
            let metrics = resolvedMetrics.vertical
            let trackFrame: CGRect
            if fixedVertical {
                trackFrame = CGRect(
                    x: layoutDirection == .rightToLeft ? 0 : viewportFrame.maxX,
                    y: viewportFrame.minY,
                    width: verticalThickness,
                    height: viewportFrame.height
                )
            } else {
                let thickness = min(metrics.thickness, viewportFrame.width)
                trackFrame = CGRect(
                    x: layoutDirection == .rightToLeft
                        ? viewportFrame.minX
                        : viewportFrame.maxX - thickness,
                    y: viewportFrame.minY,
                    width: thickness,
                    height: viewportFrame.height
                )
            }
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
                overlayOpacity: opacity
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
        overlayOpacity: Double
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
            opacity: isFixedArea ? 1 : overlayOpacity,
            isFixedArea: isFixedArea
        )
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
}
