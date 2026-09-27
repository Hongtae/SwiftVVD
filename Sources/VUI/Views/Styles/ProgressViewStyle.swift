//
//  File: ProgressViewStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol ProgressViewStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Self.Configuration) -> Self.Body

    typealias Configuration = ProgressViewStyleConfiguration
}

public struct ProgressViewStyleConfiguration {
    public struct Label: ViewAlias, PrimitiveView {
        public typealias Body = Never
    }

    public struct CurrentValueLabel: ViewAlias, PrimitiveView {
        public typealias Body = Never
    }

    struct Actions: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var value: ProgressViewValue
    public let fractionCompleted: Double?
    var alwaysIndeterminate: Bool
    public var label: Label?
    public var currentValueLabel: CurrentValueLabel?
    var actions: Actions?

    init(
        value: ProgressViewValue,
        hasLabel: Bool,
        hasCurrentValueLabel: Bool,
        hasActions: Bool
    ) {
        self.value = value
        fractionCompleted = value.fractionCompleted
        alwaysIndeterminate = value.alwaysIndeterminate
        label = hasLabel ? Label() : nil
        currentValueLabel = hasCurrentValueLabel
            ? CurrentValueLabel()
            : nil
        actions = hasActions ? Actions() : nil
    }
}

public struct DefaultProgressViewStyle: ProgressViewStyle {
    public init() {}

    @ViewBuilder
    public func makeBody(configuration: Configuration) -> some View {
        if configuration.fractionCompleted == nil {
            CircularProgressViewStyle().makeBody(
                configuration: configuration
            )
        } else {
            LinearProgressViewStyle().makeBody(
                configuration: configuration
            )
        }
    }
}

public struct LinearProgressViewStyle: ProgressViewStyle {
    var tint: Color?

    public init() {
        tint = nil
    }

    public init(tint: Color) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        LinearProgressViewBody(
            configuration: configuration,
            tint: tint
        )
    }
}

public struct CircularProgressViewStyle: ProgressViewStyle {
    var tint: Color?

    public init() {
        tint = nil
    }

    public init(tint: Color) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        CircularProgressViewBody(
            configuration: configuration,
            tint: tint
        )
    }
}

extension ProgressViewStyle where Self == DefaultProgressViewStyle {
    public static var automatic: DefaultProgressViewStyle { .init() }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
    public static var linear: LinearProgressViewStyle { .init() }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
    public static var circular: CircularProgressViewStyle { .init() }
}

extension View {
    public func progressViewStyle<S>(_ style: S) -> some View
    where S: ProgressViewStyle {
        modifier(ProgressViewStyleModifier(style: style))
    }
}

private struct LinearProgressViewBody: View {
    var configuration: ProgressViewStyleConfiguration
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                configuration.label
                configuration.currentValueLabel
            }
            ProgressTrackLayout(
                fraction: configuration.fractionCompleted ?? 0.3
            ) {
                Capsule().fill(Color.primaryFill)
                Capsule().fill(tint ?? Color.blue)
            }
            .frame(
                minWidth: 80,
                idealWidth: 160,
                maxWidth: .infinity,
                minHeight: 4,
                idealHeight: 4,
                maxHeight: 4
            )
        }
    }
}

private struct CircularProgressViewBody: View {
    var configuration: ProgressViewStyleConfiguration
    var tint: Color?

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(Color.primaryFill, lineWidth: 2)
                Circle()
                    .strokeBorder(tint ?? Color.blue, lineWidth: 3)
                    .scaleEffect(
                        max(configuration.fractionCompleted ?? 0.72, 0.2)
                    )
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                configuration.label
                configuration.currentValueLabel
            }
        }
    }
}

private struct ProgressTrackLayout: Layout {
    var fraction: Double

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        CGSize(width: proposal.width ?? 160, height: proposal.height ?? 4)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard subviews.count >= 2 else { return }
        let fillWidth = bounds.width
            * CGFloat(min(max(fraction, 0), 1))
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(bounds.size)
        )
        subviews[1].place(
            at: bounds.origin,
            proposal: ProposedViewSize(
                width: fillWidth,
                height: bounds.height
            )
        )
    }
}
