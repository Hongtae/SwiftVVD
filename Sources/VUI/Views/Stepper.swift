//
//  File: Stepper.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct StepperStyleConfiguration {
    struct Label: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    struct CurrentValueField: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var currentValueField: CurrentValueField?
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    var onEditingChanged: (Bool) -> Void

    var label: Label { Label() }
}

public struct Stepper<Label>: View where Label: View {
    var configuration: StepperStyleConfiguration
    var label: Label
    var accessibilityValue: AccessibilityBoundedNumber?

    private init(
        label: Label,
        currentValueField: AnyView?,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void
    ) {
        configuration = StepperStyleConfiguration(
            currentValueField: currentValueField == nil
                ? nil
                : StepperStyleConfiguration.CurrentValueField(),
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
        self.label = label
        accessibilityValue = AccessibilityBoundedNumber(
            lowerBound: -.infinity,
            upperBound: .infinity,
            currentValueLabel: nil,
            currentValueField: currentValueField
        )
    }

    public init(
        @ViewBuilder label: () -> Label,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            label: label(),
            currentValueField: nil,
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V>(
        value: Binding<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: Strideable {
        self.init(
            label: label(),
            currentValueField: nil,
            onIncrement: {
                value.wrappedValue = value.wrappedValue.advanced(by: step)
            },
            onDecrement: {
                value.wrappedValue = value.wrappedValue.advanced(by: -step)
            },
            onEditingChanged: onEditingChanged
        )
    }

    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: Strideable {
        self.init(
            label: label(),
            currentValueField: nil,
            onIncrement: {
                let current = min(
                    max(value.wrappedValue, bounds.lowerBound),
                    bounds.upperBound
                )
                value.wrappedValue = current.advanced(by: step)
            },
            onDecrement: {
                let current = min(
                    max(value.wrappedValue, bounds.lowerBound),
                    bounds.upperBound
                )
                value.wrappedValue = current.advanced(by: -step)
            },
            onEditingChanged: onEditingChanged
        )
    }

    public init<F>(
        value: Binding<F.FormatInput>,
        step: F.FormatInput.Stride = 1,
        format: F,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where F: ParseableFormatStyle,
            F.FormatInput: BinaryFloatingPoint,
            F.FormatOutput == String {
        self.init(
            label: label(),
            currentValueField: AnyView(
                Text(format.format(value.wrappedValue))
            ),
            onIncrement: {
                value.wrappedValue = value.wrappedValue.advanced(by: step)
            },
            onDecrement: {
                value.wrappedValue = value.wrappedValue.advanced(by: -step)
            },
            onEditingChanged: onEditingChanged
        )
    }

    public init<F>(
        value: Binding<F.FormatInput>,
        in bounds: ClosedRange<F.FormatInput>,
        step: F.FormatInput.Stride = 1,
        format: F,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where F: ParseableFormatStyle,
            F.FormatInput: BinaryFloatingPoint,
            F.FormatOutput == String {
        self.init(
            label: label(),
            currentValueField: AnyView(
                Text(format.format(value.wrappedValue))
            ),
            onIncrement: {
                let current = min(
                    max(value.wrappedValue, bounds.lowerBound),
                    bounds.upperBound
                )
                value.wrappedValue = current.advanced(by: step)
            },
            onDecrement: {
                let current = min(
                    max(value.wrappedValue, bounds.lowerBound),
                    bounds.upperBound
                )
                value.wrappedValue = current.advanced(by: -step)
            },
            onEditingChanged: onEditingChanged
        )
    }

    public var body: some View {
        StepperBody(configuration: configuration)
            .modifier(
                StaticSourceWriter<
                    StepperStyleConfiguration.Label,
                    Label
                >(source: label)
            )
            .modifier(
                OptionalSourceWriter<
                    StepperStyleConfiguration.CurrentValueField,
                    AnyView
                >(source: accessibilityValue?.currentValueField)
            )
    }
}

extension Stepper where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            label: { Text(titleKey) },
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.init(
            label: { Text(titleResource) },
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        onIncrement: (() -> Void)?,
        onDecrement: (() -> Void)?,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where S: StringProtocol {
        self.init(
            label: { Text(title) },
            onIncrement: onIncrement,
            onDecrement: onDecrement,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V>(
        _ titleKey: LocalizedStringKey,
        value: Binding<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: Strideable {
        self.init(
            value: value,
            step: step,
            label: { Text(titleKey) },
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<V>(
        _ titleResource: LocalizedStringResource,
        value: Binding<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: Strideable {
        self.init(
            value: value,
            step: step,
            label: { Text(titleResource) },
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<S, V>(
        _ title: S,
        value: Binding<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where S: StringProtocol, V: Strideable {
        self.init(
            value: value,
            step: step,
            label: { Text(title) },
            onEditingChanged: onEditingChanged
        )
    }

    public init<V>(
        _ titleKey: LocalizedStringKey,
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: Strideable {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: { Text(titleKey) },
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<V>(
        _ titleResource: LocalizedStringResource,
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: Strideable {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: { Text(titleResource) },
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<S, V>(
        _ title: S,
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where S: StringProtocol, V: Strideable {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: { Text(title) },
            onEditingChanged: onEditingChanged
        )
    }

    public init<F>(
        _ titleKey: LocalizedStringKey,
        value: Binding<F.FormatInput>,
        step: F.FormatInput.Stride = 1,
        format: F,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where F: ParseableFormatStyle,
            F.FormatInput: BinaryFloatingPoint,
            F.FormatOutput == String {
        self.init(
            value: value,
            step: step,
            format: format,
            label: { Text(titleKey) },
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<S, F>(
        _ title: S,
        value: Binding<F.FormatInput>,
        step: F.FormatInput.Stride = 1,
        format: F,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where S: StringProtocol, F: ParseableFormatStyle,
            F.FormatInput: BinaryFloatingPoint,
            F.FormatOutput == String {
        self.init(
            value: value,
            step: step,
            format: format,
            label: { Text(title) },
            onEditingChanged: onEditingChanged
        )
    }

    public init<F>(
        _ titleKey: LocalizedStringKey,
        value: Binding<F.FormatInput>,
        in bounds: ClosedRange<F.FormatInput>,
        step: F.FormatInput.Stride = 1,
        format: F,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where F: ParseableFormatStyle,
            F.FormatInput: BinaryFloatingPoint,
            F.FormatOutput == String {
        self.init(
            value: value,
            in: bounds,
            step: step,
            format: format,
            label: { Text(titleKey) },
            onEditingChanged: onEditingChanged
        )
    }

    @_disfavoredOverload
    public init<S, F>(
        _ title: S,
        value: Binding<F.FormatInput>,
        in bounds: ClosedRange<F.FormatInput>,
        step: F.FormatInput.Stride = 1,
        format: F,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where S: StringProtocol, F: ParseableFormatStyle,
            F.FormatInput: BinaryFloatingPoint,
            F.FormatOutput == String {
        self.init(
            value: value,
            in: bounds,
            step: step,
            format: format,
            label: { Text(title) },
            onEditingChanged: onEditingChanged
        )
    }
}

struct StepperBody: View {
    var configuration: StepperStyleConfiguration

    var body: some View {
        HStack(spacing: 8) {
            configuration.label
            configuration.currentValueField
            VStack(spacing: 0) {
                Button(action: configuration.onIncrement ?? {}) {
                    Text("+")
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(configuration.onIncrement == nil)

                Button(action: configuration.onDecrement ?? {}) {
                    Text("−")
                        .frame(width: 20, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(configuration.onDecrement == nil)
            }
        }
    }
}
