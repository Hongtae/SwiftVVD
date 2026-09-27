//
//  File: Slider.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol SliderTickContent<Value> {
    associatedtype Value: BinaryFloatingPoint
    associatedtype Body: RandomAccessCollection
        where Body.Element == SliderTick<Value>

    var body: Body { get }
}

public struct SliderTick<V>: SliderTickContent, Identifiable, Comparable
where V: BinaryFloatingPoint {
    public struct ID: Hashable {
        fileprivate var value: V
    }

    public typealias Value = V
    public typealias Body = [SliderTick<V>]

    var value: V
    var label: AnyView?

    public init(_ value: V) {
        self.value = value
        label = nil
    }

    public init(_ value: V, @ViewBuilder label: () -> some View) {
        self.value = value
        self.label = AnyView(label())
    }

    init(value: V, label: AnyView?) {
        self.value = value
        self.label = label
    }

    public var id: ID { ID(value: value) }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    public var body: Body { [self] }
}

extension SliderTick {
    public init(_ titleKey: LocalizedStringKey, _ value: V) {
        self.init(value) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init(_ titleResource: LocalizedStringResource, _ value: V) {
        self.init(value) { Text(titleResource) }
    }

    @_disfavoredOverload
    public init<S>(_ title: S, _ value: V) where S: StringProtocol {
        self.init(value) { Text(title) }
    }
}

public struct TupleSliderTickContent<V, T>: SliderTickContent
where V: BinaryFloatingPoint {
    public typealias Value = V
    public typealias Body = [SliderTick<V>]

    public var value: T
    private var ticks: [SliderTick<V>]

    init(_ value: T, ticks: [SliderTick<V>]) {
        self.value = value
        self.ticks = ticks
    }

    public var body: Body { ticks }
}

private struct SliderTickList<V>: SliderTickContent
where V: BinaryFloatingPoint {
    typealias Value = V
    typealias Body = [SliderTick<V>]

    var body: Body
}

@resultBuilder
public struct SliderTickBuilder<V> where V: BinaryFloatingPoint {
    public static func buildBlock() -> some SliderTickContent<V> {
        SliderTickList<V>(body: [])
    }

    public static func buildBlock<C>(_ content: C) -> some SliderTickContent<V>
    where C: SliderTickContent, C.Value == V {
        SliderTickList<V>(body: Array(content.body))
    }

    public static func buildBlock<C0, C1>(
        _ first: C0,
        _ second: C1
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C0.Value == V, C1.Value == V {
        SliderTickList<V>(
            body: Array(first.body) + Array(second.body)
        )
    }

    public static func buildBlock<C0, C1, C2>(
        _ first: C0,
        _ second: C1,
        _ third: C2
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V {
        SliderTickList<V>(
            body: Array(first.body) + Array(second.body) + Array(third.body)
        )
    }

    public static func buildBlock<C0, C1, C2, C3>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V, C3.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body)
                + Array(c2.body) + Array(c3.body)
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C4: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V,
          C3.Value == V, C4.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body) + Array(c2.body)
                + Array(c3.body) + Array(c4.body)
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C4: SliderTickContent, C5: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V,
          C3.Value == V, C4.Value == V, C5.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body) + Array(c2.body)
                + Array(c3.body) + Array(c4.body) + Array(c5.body)
        )
    }

    public static func buildBlock<C0, C1, C2, C3, C4, C5, C6>(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C4: SliderTickContent, C5: SliderTickContent,
          C6: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V,
          C3.Value == V, C4.Value == V, C5.Value == V,
          C6.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body) + Array(c2.body)
                + Array(c3.body) + Array(c4.body) + Array(c5.body)
                + Array(c6.body)
        )
    }

    public static func buildBlock<
        C0, C1, C2, C3, C4, C5, C6, C7
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C4: SliderTickContent, C5: SliderTickContent,
          C6: SliderTickContent, C7: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V,
          C3.Value == V, C4.Value == V, C5.Value == V,
          C6.Value == V, C7.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body) + Array(c2.body)
                + Array(c3.body) + Array(c4.body) + Array(c5.body)
                + Array(c6.body) + Array(c7.body)
        )
    }

    public static func buildBlock<
        C0, C1, C2, C3, C4, C5, C6, C7, C8
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C4: SliderTickContent, C5: SliderTickContent,
          C6: SliderTickContent, C7: SliderTickContent,
          C8: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V,
          C3.Value == V, C4.Value == V, C5.Value == V,
          C6.Value == V, C7.Value == V, C8.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body) + Array(c2.body)
                + Array(c3.body) + Array(c4.body) + Array(c5.body)
                + Array(c6.body) + Array(c7.body) + Array(c8.body)
        )
    }

    public static func buildBlock<
        C0, C1, C2, C3, C4, C5, C6, C7, C8, C9
    >(
        _ c0: C0,
        _ c1: C1,
        _ c2: C2,
        _ c3: C3,
        _ c4: C4,
        _ c5: C5,
        _ c6: C6,
        _ c7: C7,
        _ c8: C8,
        _ c9: C9
    ) -> some SliderTickContent<V>
    where C0: SliderTickContent, C1: SliderTickContent,
          C2: SliderTickContent, C3: SliderTickContent,
          C4: SliderTickContent, C5: SliderTickContent,
          C6: SliderTickContent, C7: SliderTickContent,
          C8: SliderTickContent, C9: SliderTickContent,
          C0.Value == V, C1.Value == V, C2.Value == V,
          C3.Value == V, C4.Value == V, C5.Value == V,
          C6.Value == V, C7.Value == V, C8.Value == V,
          C9.Value == V {
        SliderTickList<V>(
            body: Array(c0.body) + Array(c1.body) + Array(c2.body)
                + Array(c3.body) + Array(c4.body) + Array(c5.body)
                + Array(c6.body) + Array(c7.body) + Array(c8.body)
                + Array(c9.body)
        )
    }

    public static func buildExpression<C>(
        _ content: C
    ) -> some SliderTickContent<V>
    where C: SliderTickContent, C.Value == V {
        SliderTickList<V>(body: Array(content.body))
    }

    public static func buildOptional<C>(
        _ content: C?
    ) -> some SliderTickContent<V>
    where C: SliderTickContent, C.Value == V {
        SliderTickList<V>(body: content.map { Array($0.body) } ?? [])
    }

    public static func buildArray<C>(
        _ contents: [C]
    ) -> some SliderTickContent<V>
    where C: SliderTickContent, C.Value == V {
        SliderTickList<V>(body: contents.flatMap { Array($0.body) })
    }

    public static func buildEither<First>(
        first content: First
    ) -> some SliderTickContent<V>
    where First: SliderTickContent, First.Value == V {
        SliderTickList<V>(body: Array(content.body))
    }

    public static func buildEither<Second>(
        second content: Second
    ) -> some SliderTickContent<V>
    where Second: SliderTickContent, Second.Value == V {
        SliderTickList<V>(body: Array(content.body))
    }
}

public struct SliderTickContentForEach<Data, ID, Content>:
    SliderTickContent
where Data: RandomAccessCollection, ID: Hashable,
      Content: SliderTickContent {
    public typealias Value = Content.Value
    public typealias Body = [SliderTick<Value>]

    private var ticks: Body

    public init<V>(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        @SliderTickBuilder<V> content: (Data.Element) -> Content
    ) where V == Data.Element, Data.Element == Content.Value {
        _ = id
        ticks = data.flatMap { Array(content($0).body) }
    }

    public init<V>(
        _ data: Data,
        @SliderTickBuilder<V> content: (Data.Element) -> Content
    ) where ID == V.ID, V: Identifiable, V == Data.Element,
            Data.Element == Content.Value {
        ticks = data.flatMap { Array(content($0).body) }
    }

    public init<V>(
        _ data: Range<Int>,
        @SliderTickBuilder<V> content: (Int) -> Content
    ) where Data == Range<Int>, V == Content.Value {
        ticks = data.flatMap { Array(content($0).body) }
    }

    public var body: Body { ticks }
}

struct SliderMark<V> where V: BinaryFloatingPoint {
    var value: V
    var label: AnyView?
}

struct AccessibilityBoundedNumber {
    var lowerBound: Double
    var upperBound: Double
    var currentValueLabel: AnyView?
    var currentValueField: AnyView?
}

public struct Slider<Label, ValueLabel>: View
where Label: View, ValueLabel: View {
    var _value: Binding<Double>
    var neutralValue: Double
    var enabledBounds: ClosedRange<Double>?
    var onEditingChanged: (Bool) -> Void
    var skipDistance: Double
    var discreteValueCount: Int
    var marks: [SliderMark<Double>]?
    var ticks: [SliderTick<Double>]?
    var _minimumValueLabel: ValueLabel
    var _maximumValueLabel: ValueLabel
    var hasCustomMinMaxValueLabels: Bool
    var label: Label
    var accessibilityValue: AccessibilityBoundedNumber?

    private init<V>(
        value: Binding<V>,
        bounds: ClosedRange<V>,
        step: V.Stride?,
        neutralValue: V?,
        enabledBounds: ClosedRange<V>?,
        label: Label,
        currentValueLabel: AnyView?,
        minimumValueLabel: ValueLabel,
        maximumValueLabel: ValueLabel,
        hasCustomMinMaxValueLabels: Bool,
        explicitTicks: [SliderTick<V>]?,
        tick: ((V) -> SliderTick<V>?)?,
        onEditingChanged: @escaping (Bool) -> Void
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        let lower = Double(bounds.lowerBound)
        let upper = Double(bounds.upperBound)
        let span = upper - lower
        let stepValue: Double?
        if let step {
            stepValue = Double(step)
        } else {
            stepValue = nil
        }

        _value = Slider.makeProjectedBinding(
            value: value,
            lower: lower,
            upper: upper,
            step: stepValue
        )
        self.neutralValue = neutralValue.map {
            Slider.normalized(Double($0), lower: lower, upper: upper)
        } ?? 0
        self.enabledBounds = enabledBounds.map {
            Double($0.lowerBound)...Double($0.upperBound)
        }
        self.onEditingChanged = onEditingChanged
        skipDistance = stepValue.map {
            span > 0 ? min(max($0 / span, 0), 1) : 0
        } ?? 0.1

        let generatedValues: [V]
        if let stepValue, stepValue > 0, span >= 0 {
            let intervalCount = Int((span / stepValue).rounded(.down))
            discreteValueCount = intervalCount + 1
            generatedValues = (0...intervalCount).map {
                V(lower + Double($0) * stepValue)
            }
        } else {
            discreteValueCount = 0
            generatedValues = []
        }

        if let explicitTicks {
            ticks = explicitTicks.map {
                SliderTick<Double>(
                    value: Slider.normalized(
                        Double($0.value), lower: lower, upper: upper
                    ),
                    label: $0.label
                )
            }.sorted()
        } else if generatedValues.isEmpty {
            ticks = nil
        } else {
            ticks = generatedValues.map {
                SliderTick<Double>(
                    Slider.normalized(Double($0), lower: lower, upper: upper)
                )
            }
        }

        if let tick {
            let generatedMarks = generatedValues.compactMap { value in
                tick(value).map {
                    SliderMark(
                        value: Slider.normalized(
                            Double($0.value), lower: lower, upper: upper
                        ),
                        label: $0.label
                    )
                }
            }
            marks = generatedMarks.isEmpty ? nil : generatedMarks
        } else if let explicitTicks {
            let generatedMarks = explicitTicks.compactMap { item in
                item.label.map {
                    SliderMark(
                        value: Slider.normalized(
                            Double(item.value), lower: lower, upper: upper
                        ),
                        label: $0
                    )
                }
            }
            marks = generatedMarks.isEmpty ? nil : generatedMarks
        } else {
            marks = nil
        }

        _minimumValueLabel = minimumValueLabel
        _maximumValueLabel = maximumValueLabel
        self.hasCustomMinMaxValueLabels = hasCustomMinMaxValueLabels
        self.label = label
        accessibilityValue = AccessibilityBoundedNumber(
            lowerBound: lower,
            upperBound: upper,
            currentValueLabel: currentValueLabel,
            currentValueField: nil
        )
    }

    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.init(
            value: value,
            bounds: bounds,
            step: nil,
            neutralValue: nil,
            enabledBounds: nil,
            label: label(),
            currentValueLabel: nil,
            minimumValueLabel: minimumValueLabel(),
            maximumValueLabel: maximumValueLabel(),
            hasCustomMinMaxValueLabels: true,
            explicitTicks: nil,
            tick: nil,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.init(
            value: value,
            bounds: bounds,
            step: step,
            neutralValue: nil,
            enabledBounds: nil,
            label: label(),
            currentValueLabel: nil,
            minimumValueLabel: minimumValueLabel(),
            maximumValueLabel: maximumValueLabel(),
            hasCustomMinMaxValueLabels: true,
            explicitTicks: nil,
            tick: nil,
            onEditingChanged: onEditingChanged
        )
    }

    public var body: some View {
        ResolvedSliderStyle(
            configuration: SliderStyleConfiguration(
                label: .init(),
                minimumValueLabel: .init(),
                maximumValueLabel: .init(),
                _value: _value,
                neutralValue: neutralValue,
                enabledBounds: enabledBounds,
                onEditingChanged: onEditingChanged,
                skipDistance: skipDistance,
                discreteValueCount: discreteValueCount,
                ticks: ticks,
                marks: marks,
                hasCustomMinMaxValueLabels: hasCustomMinMaxValueLabels,
                accessibilityValue: accessibilityValue
            )
        )
        .modifier(
            StaticSourceWriter<SliderStyleConfiguration.Label, Label>(
                source: label
            )
        )
        .modifier(
            StaticSourceWriter<
                SliderStyleConfiguration.MinimumValueLabel,
                ValueLabel
            >(source: _minimumValueLabel)
        )
        .modifier(
            StaticSourceWriter<
                SliderStyleConfiguration.MaximumValueLabel,
                ValueLabel
            >(source: _maximumValueLabel)
        )
    }

    fileprivate static func normalized(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        guard value.isFinite, lower.isFinite, upper.isFinite,
              upper > lower else {
            return 0
        }
        return min(max((value - lower) / (upper - lower), 0), 1)
    }

    private static func makeProjectedBinding<V>(
        value: Binding<V>,
        lower: Double,
        upper: Double,
        step: Double?
    ) -> Binding<Double>
    where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        Binding<Double>(
            get: {
                normalized(
                    Double(value.wrappedValue),
                    lower: lower,
                    upper: upper
                )
            },
            set: { projected, transaction in
                let fraction = min(max(projected, 0), 1)
                var raw = lower + fraction * (upper - lower)
                if let step, step > 0, step.isFinite {
                    raw = lower + ((raw - lower) / step).rounded() * step
                }
                raw = min(max(raw, lower), upper)
                value.transaction(transaction).wrappedValue = V(raw)
            }
        )
    }
}

extension Slider where ValueLabel == EmptyView {
    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.init(
            value: value,
            in: bounds,
            label: label,
            minimumValueLabel: { EmptyView() },
            maximumValueLabel: { EmptyView() },
            onEditingChanged: onEditingChanged
        )
        hasCustomMinMaxValueLabels = false
    }

    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        @ViewBuilder label: () -> Label,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: label,
            minimumValueLabel: { EmptyView() },
            maximumValueLabel: { EmptyView() },
            onEditingChanged: onEditingChanged
        )
        hasCustomMinMaxValueLabels = false
    }
}

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.init(
            value: value,
            in: bounds,
            label: { EmptyView() },
            onEditingChanged: onEditingChanged
        )
    }

    public init<V>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint {
        self.init(
            value: value,
            in: bounds,
            step: step,
            label: { EmptyView() },
            onEditingChanged: onEditingChanged
        )
    }
}

extension Slider {
    public init<V, CurrentValueLabel>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel = {
            EmptyView()
        },
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint,
            CurrentValueLabel: View {
        self.init(
            value: value,
            bounds: bounds,
            step: nil,
            neutralValue: neutralValue,
            enabledBounds: enabledBounds,
            label: label(),
            currentValueLabel: AnyView(currentValueLabel()),
            minimumValueLabel: minimumValueLabel(),
            maximumValueLabel: maximumValueLabel(),
            hasCustomMinMaxValueLabels:
                ValueLabel.self != EmptyView.self,
            explicitTicks: nil,
            tick: nil,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V, CurrentValueLabel, Ticks>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel = {
            EmptyView()
        },
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        @SliderTickBuilder<V> ticks: () -> Ticks,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint,
            CurrentValueLabel: View, Ticks: SliderTickContent,
            Ticks.Value == V {
        self.init(
            value: value,
            bounds: bounds,
            step: nil,
            neutralValue: neutralValue,
            enabledBounds: enabledBounds,
            label: label(),
            currentValueLabel: AnyView(currentValueLabel()),
            minimumValueLabel: minimumValueLabel(),
            maximumValueLabel: maximumValueLabel(),
            hasCustomMinMaxValueLabels:
                ValueLabel.self != EmptyView.self,
            explicitTicks: Array(ticks().body),
            tick: nil,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V, CurrentValueLabel>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel = {
            EmptyView()
        },
        @ViewBuilder minimumValueLabel: () -> ValueLabel,
        @ViewBuilder maximumValueLabel: () -> ValueLabel,
        tick: @escaping (V) -> SliderTick<V>? = { _ in nil },
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint,
            CurrentValueLabel: View {
        self.init(
            value: value,
            bounds: bounds,
            step: step,
            neutralValue: neutralValue,
            enabledBounds: enabledBounds,
            label: label(),
            currentValueLabel: AnyView(currentValueLabel()),
            minimumValueLabel: minimumValueLabel(),
            maximumValueLabel: maximumValueLabel(),
            hasCustomMinMaxValueLabels:
                ValueLabel.self != EmptyView.self,
            explicitTicks: nil,
            tick: tick,
            onEditingChanged: onEditingChanged
        )
    }
}

extension Slider where ValueLabel == EmptyView {
    public init<V, CurrentValueLabel>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel = {
            EmptyView()
        },
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint,
            CurrentValueLabel: View {
        self.init(
            value: value,
            bounds: bounds,
            step: nil,
            neutralValue: neutralValue,
            enabledBounds: enabledBounds,
            label: label(),
            currentValueLabel: AnyView(currentValueLabel()),
            minimumValueLabel: EmptyView(),
            maximumValueLabel: EmptyView(),
            hasCustomMinMaxValueLabels: false,
            explicitTicks: nil,
            tick: nil,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V, CurrentValueLabel, Ticks>(
        value: Binding<V>,
        in bounds: ClosedRange<V> = 0...1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel = {
            EmptyView()
        },
        @SliderTickBuilder<V> ticks: () -> Ticks,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint,
            CurrentValueLabel: View, Ticks: SliderTickContent,
            Ticks.Value == V {
        self.init(
            value: value,
            bounds: bounds,
            step: nil,
            neutralValue: neutralValue,
            enabledBounds: enabledBounds,
            label: label(),
            currentValueLabel: AnyView(currentValueLabel()),
            minimumValueLabel: EmptyView(),
            maximumValueLabel: EmptyView(),
            hasCustomMinMaxValueLabels: false,
            explicitTicks: Array(ticks().body),
            tick: nil,
            onEditingChanged: onEditingChanged
        )
    }

    public init<V, CurrentValueLabel>(
        value: Binding<V>,
        in bounds: ClosedRange<V>,
        step: V.Stride = 1,
        neutralValue: V? = nil,
        enabledBounds: ClosedRange<V>? = nil,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel = {
            EmptyView()
        },
        tick: @escaping (V) -> SliderTick<V>? = { _ in nil },
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) where V: BinaryFloatingPoint, V.Stride: BinaryFloatingPoint,
            CurrentValueLabel: View {
        self.init(
            value: value,
            bounds: bounds,
            step: step,
            neutralValue: neutralValue,
            enabledBounds: enabledBounds,
            label: label(),
            currentValueLabel: AnyView(currentValueLabel()),
            minimumValueLabel: EmptyView(),
            maximumValueLabel: EmptyView(),
            hasCustomMinMaxValueLabels: false,
            explicitTicks: nil,
            tick: tick,
            onEditingChanged: onEditingChanged
        )
    }
}

struct SliderStyleConfiguration {
    struct Label: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    struct MinimumValueLabel: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    struct MaximumValueLabel: ViewAlias, PrimitiveView {
        typealias Body = Never
    }

    var label: Label
    var minimumValueLabel: MinimumValueLabel
    var maximumValueLabel: MaximumValueLabel
    var _value: Binding<Double>
    var neutralValue: Double
    var enabledBounds: ClosedRange<Double>?
    var onEditingChanged: (Bool) -> Void
    var skipDistance: Double
    var discreteValueCount: Int
    var ticks: [SliderTick<Double>]?
    var marks: [SliderMark<Double>]?
    var hasCustomMinMaxValueLabels: Bool
    var accessibilityValue: AccessibilityBoundedNumber?
}

struct ResolvedSliderStyle: View {
    var configuration: SliderStyleConfiguration

    var body: some View {
        SystemSlider(configuration: configuration)
    }
}

private final class SliderTrackMetrics: @unchecked Sendable {
    var width: CGFloat = 1
}

private final class SliderInteractionState: @unchecked Sendable {
    var isEditing = false
}

private struct SystemSlider: View {
    var configuration: SliderStyleConfiguration
    private let metrics = SliderTrackMetrics()
    private let interaction = SliderInteractionState()

    @ViewBuilder
    var body: some View {
        if configuration.hasCustomMinMaxValueLabels {
            VStack(alignment: .leading, spacing: 4) {
                configuration.label
                HStack(spacing: 8) {
                    configuration.minimumValueLabel
                    SliderTrack(
                        configuration: configuration,
                        metrics: metrics,
                        interaction: interaction
                    )
                    configuration.maximumValueLabel
                }
            }
        } else {
            SliderTrack(
                configuration: configuration,
                metrics: metrics,
                interaction: interaction
            )
        }
    }
}

private struct SliderTrack: View {
    var configuration: SliderStyleConfiguration
    var metrics: SliderTrackMetrics
    var interaction: SliderInteractionState

    var body: some View {
        SliderTrackLayout(
            fraction: configuration._value.wrappedValue,
            metrics: metrics
        ) {
            Capsule().fill(Color.primaryFill)
            Capsule().fill(Color.blue)
            ZStack {
                Circle().fill(BackgroundStyle())
                Circle().strokeBorder(Color.secondaryFill, lineWidth: 1)
            }
        }
        .frame(
            minWidth: 80,
            idealWidth: 160,
            maxWidth: .infinity,
            minHeight: 22,
            idealHeight: 22,
            maxHeight: 22
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !interaction.isEditing {
                        interaction.isEditing = true
                        configuration.onEditingChanged(true)
                    }
                    update(at: value.location.x)
                }
                .onEnded { value in
                    _ = value
                    if interaction.isEditing {
                        interaction.isEditing = false
                        configuration.onEditingChanged(false)
                    }
                }
        )
    }

    private func update(at x: CGFloat) {
        let width = max(metrics.width, 1)
        var fraction = min(max(Double(x / width), 0), 1)
        if let enabled = configuration.enabledBounds,
           let domain = configuration.accessibilityValue {
            let lower = Slider<EmptyView, EmptyView>.normalized(
                enabled.lowerBound,
                lower: domain.lowerBound,
                upper: domain.upperBound
            )
            let upper = Slider<EmptyView, EmptyView>.normalized(
                enabled.upperBound,
                lower: domain.lowerBound,
                upper: domain.upperBound
            )
            fraction = min(max(fraction, lower), upper)
        }
        configuration._value.wrappedValue = fraction
    }
}

private struct SliderTrackLayout: Layout {
    var fraction: Double
    var metrics: SliderTrackMetrics

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        CGSize(width: proposal.width ?? 160, height: proposal.height ?? 22)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard subviews.count >= 3 else { return }
        metrics.width = bounds.width
        let trackHeight: CGFloat = 4
        let thumbSize: CGFloat = 18
        let clamped = CGFloat(min(max(fraction, 0), 1))
        let fillWidth = bounds.width * clamped
        let centerY = bounds.midY

        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: centerY - trackHeight / 2),
            proposal: ProposedViewSize(
                width: bounds.width,
                height: trackHeight
            )
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: centerY - trackHeight / 2),
            proposal: ProposedViewSize(
                width: fillWidth,
                height: trackHeight
            )
        )
        subviews[2].place(
            at: CGPoint(x: bounds.minX + fillWidth, y: centerY),
            anchor: .center,
            proposal: ProposedViewSize(
                width: thumbSize,
                height: thumbSize
            )
        )
    }
}
