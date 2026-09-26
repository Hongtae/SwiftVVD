//
//  File: ProgressView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum ProgressViewValue {
    case absolute(
        fractionCompleted: Double?,
        alwaysIndeterminate: Bool
    )
    case dateRelative(interval: ClosedRange<Date>, countdown: Bool)

    var fractionCompleted: Double? {
        switch self {
        case .absolute(let fractionCompleted, _):
            return fractionCompleted
        case .dateRelative(let interval, let countdown):
            let duration = interval.upperBound.timeIntervalSince(
                interval.lowerBound
            )
            guard duration > 0 else { return 1 }
            let elapsed = Date().timeIntervalSince(interval.lowerBound)
            let fraction = min(max(elapsed / duration, 0), 1)
            return countdown ? 1 - fraction : fraction
        }
    }

    var alwaysIndeterminate: Bool {
        switch self {
        case .absolute(_, let alwaysIndeterminate):
            alwaysIndeterminate
        case .dateRelative:
            false
        }
    }
}

public struct ProgressView<Label, CurrentValueLabel>: View
where Label: View, CurrentValueLabel: View {
    enum Base {
        case custom(CustomProgressView<Label, CurrentValueLabel>)
        case observing(FoundationProgressView)
    }

    var base: Base

    private init(
        value: ProgressViewValue,
        label: Label?,
        currentValueLabel: CurrentValueLabel?,
        actions: AnyView? = nil
    ) {
        base = .custom(
            CustomProgressView(
                value: value,
                label: label,
                currentValueLabel: currentValueLabel,
                actions: actions
            )
        )
    }

    @ViewBuilder
    public var body: some View {
        switch base {
        case .custom(let progress):
            progress
        case .observing(let progress):
            progress
        }
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    public init() where Label == EmptyView {
        self.init(
            value: .absolute(
                fractionCompleted: nil,
                alwaysIndeterminate: true
            ),
            label: nil,
            currentValueLabel: nil
        )
    }

    public init(@ViewBuilder label: () -> Label) {
        self.init(
            value: .absolute(
                fractionCompleted: nil,
                alwaysIndeterminate: true
            ),
            label: label(),
            currentValueLabel: nil
        )
    }

    public init(_ titleKey: LocalizedStringKey) where Label == Text {
        self.init(label: { Text(titleKey) })
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource
    ) where Label == Text {
        self.init(label: { Text(titleResource) })
    }

    @_disfavoredOverload
    public init<S>(_ title: S) where Label == Text, S: StringProtocol {
        self.init(label: { Text(title) })
    }
}

extension ProgressView {
    public init<V>(
        value: V?,
        total: V = 1
    ) where Label == EmptyView, CurrentValueLabel == EmptyView,
            V: BinaryFloatingPoint {
        self.init(
            value: Self.progressValue(value: value, total: total),
            label: nil,
            currentValueLabel: nil
        )
    }

    public init<V>(
        value: V?,
        total: V = 1,
        @ViewBuilder label: () -> Label
    ) where CurrentValueLabel == EmptyView, V: BinaryFloatingPoint {
        self.init(
            value: Self.progressValue(value: value, total: total),
            label: label(),
            currentValueLabel: nil
        )
    }

    public init<V>(
        value: V?,
        total: V = 1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where V: BinaryFloatingPoint {
        self.init(
            value: Self.progressValue(value: value, total: total),
            label: label(),
            currentValueLabel: currentValueLabel()
        )
    }

    public init<V>(
        _ titleKey: LocalizedStringKey,
        value: V?,
        total: V = 1
    ) where Label == Text, CurrentValueLabel == EmptyView,
            V: BinaryFloatingPoint {
        self.init(value: value, total: total) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<V>(
        _ titleResource: LocalizedStringResource,
        value: V?,
        total: V = 1
    ) where Label == Text, CurrentValueLabel == EmptyView,
            V: BinaryFloatingPoint {
        self.init(value: value, total: total) { Text(titleResource) }
    }

    @_disfavoredOverload
    public init<S, V>(
        _ title: S,
        value: V?,
        total: V = 1
    ) where Label == Text, CurrentValueLabel == EmptyView,
            S: StringProtocol, V: BinaryFloatingPoint {
        self.init(value: value, total: total) { Text(title) }
    }

    private static func progressValue<V>(
        value: V?,
        total: V
    ) -> ProgressViewValue where V: BinaryFloatingPoint {
        guard let rawValue = value else {
            return .absolute(
                fractionCompleted: nil,
                alwaysIndeterminate: true
            )
        }
        let numericValue = Double(rawValue)
        let numericTotal = Double(total)
        guard numericValue.isFinite, numericTotal.isFinite,
              numericValue >= 0 else {
            return .absolute(
                fractionCompleted: nil,
                alwaysIndeterminate: false
            )
        }
        let fraction = numericTotal > 0
            ? min(max(numericValue / numericTotal, 0), 1)
            : 1
        return .absolute(
            fractionCompleted: fraction,
            alwaysIndeterminate: false
        )
    }
}

extension ProgressView
where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init(_ progress: Foundation.Progress) {
        base = .observing(FoundationProgressView(progress: progress))
    }
}

extension ProgressView
where Label == ProgressViewStyleConfiguration.Label,
      CurrentValueLabel == ProgressViewStyleConfiguration.CurrentValueLabel {
    public init(_ configuration: ProgressViewStyleConfiguration) {
        self.init(
            value: configuration.value,
            label: configuration.label,
            currentValueLabel: configuration.currentValueLabel
        )
    }
}

public struct DefaultDateProgressLabel: View {
    public init() {}

    public var body: some View {
        EmptyView()
    }
}

extension ProgressView {
    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) {
        self.init(
            value: .dateRelative(
                interval: timerInterval,
                countdown: countsDown
            ),
            label: label(),
            currentValueLabel: currentValueLabel()
        )
    }
}

extension ProgressView where CurrentValueLabel == DefaultDateProgressLabel {
    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            timerInterval: timerInterval,
            countsDown: countsDown,
            label: label,
            currentValueLabel: { DefaultDateProgressLabel() }
        )
    }
}

extension ProgressView
where Label == EmptyView, CurrentValueLabel == DefaultDateProgressLabel {
    public init(
        timerInterval: ClosedRange<Date>,
        countsDown: Bool = true
    ) {
        self.init(
            timerInterval: timerInterval,
            countsDown: countsDown,
            label: { EmptyView() }
        )
    }
}

struct CustomProgressView<Label, CurrentValueLabel>: View
where Label: View, CurrentValueLabel: View {
    var value: ProgressViewValue
    var label: Label?
    var currentValueLabel: CurrentValueLabel?
    var actions: AnyView?

    var body: some View {
        ResolvedProgressView(
            value: value,
            _label: OptionalViewAlias(label != nil),
            _currentValueLabel: OptionalViewAlias(
                currentValueLabel != nil
            ),
            _actions: OptionalViewAlias(actions != nil)
        )
        .modifier(
            OptionalSourceWriter<
                ProgressViewStyleConfiguration.Label,
                Label
            >(source: label)
        )
        .modifier(
            OptionalSourceWriter<
                ProgressViewStyleConfiguration.CurrentValueLabel,
                CurrentValueLabel
            >(source: currentValueLabel)
        )
        .modifier(
            OptionalSourceWriter<
                ProgressViewStyleConfiguration.Actions,
                AnyView
            >(source: actions)
        )
    }
}

struct FoundationProgressView: View {
    var progress: Foundation.Progress
    var __state: Foundation.Progress?

    init(progress: Foundation.Progress) {
        self.progress = progress
        __state = progress
    }

    var body: some View {
        CustomProgressView<EmptyView, EmptyView>(
            value: .absolute(
                fractionCompleted: progress.isIndeterminate
                    ? nil
                    : min(max(progress.fractionCompleted, 0), 1),
                alwaysIndeterminate: progress.isIndeterminate
            ),
            label: nil,
            currentValueLabel: nil,
            actions: nil
        )
    }
}

struct ResolvedProgressView: View {
    var value: ProgressViewValue
    var _label: OptionalViewAlias<ProgressViewStyleConfiguration.Label>
    var _currentValueLabel: OptionalViewAlias<
        ProgressViewStyleConfiguration.CurrentValueLabel
    >
    var _actions: OptionalViewAlias<ProgressViewStyleConfiguration.Actions>

    var body: some View {
        ResolvedProgressViewStyle(
            configuration: ProgressViewStyleConfiguration(
                value: value,
                hasLabel: _label.isPresent,
                hasCurrentValueLabel: _currentValueLabel.isPresent,
                hasActions: _actions.isPresent
            )
        )
    }
}

struct ResolvedProgressViewStyle: StyleableView {
    var configuration: ProgressViewStyleConfiguration

    static var defaultStyleModifier:
        ProgressViewStyleModifier<DefaultProgressViewStyle> {
        ProgressViewStyleModifier(style: .init())
    }
}
