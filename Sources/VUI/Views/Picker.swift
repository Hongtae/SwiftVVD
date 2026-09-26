//
//  File: Picker.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Picker<Label, SelectionValue, Content>: View
where Label: View, SelectionValue: Hashable, Content: View {
    var selection: [Binding<SelectionValue>]
    let label: Label
    let content: Content
    let currentValueLabel: AnyView?

    private init(
        selection: [Binding<SelectionValue>],
        label: Label,
        content: Content,
        currentValueLabel: AnyView?
    ) {
        precondition(
            !selection.isEmpty,
            "Picker requires at least one selection binding."
        )
        self.selection = selection
        self.label = label
        self.content = content
        self.currentValueLabel = currentValueLabel
    }

    public init(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            selection: [selection],
            label: label(),
            content: content(),
            currentValueLabel: nil
        )
    }

    public init<C>(
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) where C: RandomAccessCollection {
        self.init(
            selection: sources.map { $0[keyPath: selection] },
            label: label(),
            content: content(),
            currentValueLabel: nil
        )
    }

    public init<CurrentValueLabel>(
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where CurrentValueLabel: View {
        self.init(
            selection: [selection],
            label: label(),
            content: content(),
            currentValueLabel: AnyView(currentValueLabel())
        )
    }

    public init<C, CurrentValueLabel>(
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where C: RandomAccessCollection, CurrentValueLabel: View {
        self.init(
            selection: sources.map { $0[keyPath: selection] },
            label: label(),
            content: content(),
            currentValueLabel: AnyView(currentValueLabel())
        )
    }

    public var body: some View {
        ResolvedPicker(
            configuration: PickerStyleConfiguration(
                selection: selection[0],
                multiSelection: Array(selection.dropFirst()),
                hasCurrentValueLabel: currentValueLabel != nil
            )
        )
        .modifier(
            StaticSourceWriter<
                PickerStyleConfiguration<SelectionValue>.Label,
                Label
            >(source: label)
        )
        .modifier(
            StaticSourceWriter<
                PickerStyleConfiguration<SelectionValue>.Content,
                Content
            >(source: content)
        )
        .modifier(
            OptionalSourceWriter<
                PickerStyleConfiguration<SelectionValue>.CurrentValueLabel,
                AnyView
            >(source: currentValueLabel)
        )
    }
}

extension Picker where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(selection: selection, content: content) {
            Text(title)
        }
    }

    public init<C>(
        _ titleKey: LocalizedStringKey,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) where C: RandomAccessCollection {
        self.init(
            sources: sources,
            selection: selection,
            content: content
        ) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init<C>(
        _ titleResource: LocalizedStringResource,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) where C: RandomAccessCollection {
        self.init(
            sources: sources,
            selection: selection,
            content: content
        ) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<C, S>(
        _ title: S,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) where C: RandomAccessCollection, S: StringProtocol {
        self.init(
            sources: sources,
            selection: selection,
            content: content
        ) {
            Text(title)
        }
    }

    public init<CurrentValueLabel>(
        _ titleKey: LocalizedStringKey,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where CurrentValueLabel: View {
        self.init(
            selection: selection,
            content: content,
            label: { Text(titleKey) },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<CurrentValueLabel>(
        _ titleResource: LocalizedStringResource,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where CurrentValueLabel: View {
        self.init(
            selection: selection,
            content: content,
            label: { Text(titleResource) },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<S, CurrentValueLabel>(
        _ title: S,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where S: StringProtocol, CurrentValueLabel: View {
        self.init(
            selection: selection,
            content: content,
            label: { Text(title) },
            currentValueLabel: currentValueLabel
        )
    }

    public init<C, CurrentValueLabel>(
        _ titleKey: LocalizedStringKey,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where C: RandomAccessCollection, CurrentValueLabel: View {
        self.init(
            sources: sources,
            selection: selection,
            content: content,
            label: { Text(titleKey) },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<C, CurrentValueLabel>(
        _ titleResource: LocalizedStringResource,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where C: RandomAccessCollection, CurrentValueLabel: View {
        self.init(
            sources: sources,
            selection: selection,
            content: content,
            label: { Text(titleResource) },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<C, S, CurrentValueLabel>(
        _ title: S,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where
        C: RandomAccessCollection,
        S: StringProtocol,
        CurrentValueLabel: View
    {
        self.init(
            sources: sources,
            selection: selection,
            content: content,
            label: { Text(title) },
            currentValueLabel: currentValueLabel
        )
    }
}

extension Picker where Label == VUI.Label<Text, Image> {
    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            Label(titleKey, systemImage: systemImage)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(selection: selection, content: content) {
            Label {
                Text(titleResource)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(selection: selection, content: content) {
            Label(title, systemImage: systemImage)
        }
    }

    public init<C>(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) where
        C: RandomAccessCollection,
        C.Element == Binding<SelectionValue>
    {
        self.init(sources: sources, selection: selection, content: content) {
            Label(titleKey, systemImage: systemImage)
        }
    }

    @_disfavoredOverload
    public init<C>(
        _ titleResource: LocalizedStringResource,
        systemImage: String,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) where
        C: RandomAccessCollection,
        C.Element == Binding<SelectionValue>
    {
        self.init(sources: sources, selection: selection, content: content) {
            Label {
                Text(titleResource)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    @_disfavoredOverload
    public init<C, S>(
        _ title: S,
        systemImage: String,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content
    ) where
        C: RandomAccessCollection,
        S: StringProtocol,
        C.Element == Binding<SelectionValue>
    {
        self.init(sources: sources, selection: selection, content: content) {
            Label(title, systemImage: systemImage)
        }
    }

    public init<CurrentValueLabel>(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where CurrentValueLabel: View {
        self.init(
            selection: selection,
            content: content,
            label: { Label(titleKey, systemImage: systemImage) },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<CurrentValueLabel>(
        _ titleResource: LocalizedStringResource,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where CurrentValueLabel: View {
        self.init(
            selection: selection,
            content: content,
            label: {
                Label {
                    Text(titleResource)
                } icon: {
                    Image(systemName: systemImage)
                }
            },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<S, CurrentValueLabel>(
        _ title: S,
        systemImage: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where S: StringProtocol, CurrentValueLabel: View {
        self.init(
            selection: selection,
            content: content,
            label: { Label(title, systemImage: systemImage) },
            currentValueLabel: currentValueLabel
        )
    }

    public init<C, CurrentValueLabel>(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where
        C: RandomAccessCollection,
        C.Element == Binding<SelectionValue>,
        CurrentValueLabel: View
    {
        self.init(
            sources: sources,
            selection: selection,
            content: content,
            label: { Label(titleKey, systemImage: systemImage) },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<C, CurrentValueLabel>(
        _ titleResource: LocalizedStringResource,
        systemImage: String,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where
        C: RandomAccessCollection,
        C.Element == Binding<SelectionValue>,
        CurrentValueLabel: View
    {
        self.init(
            sources: sources,
            selection: selection,
            content: content,
            label: {
                Label {
                    Text(titleResource)
                } icon: {
                    Image(systemName: systemImage)
                }
            },
            currentValueLabel: currentValueLabel
        )
    }

    @_disfavoredOverload
    public init<C, S, CurrentValueLabel>(
        _ title: S,
        systemImage: String,
        sources: C,
        selection: KeyPath<C.Element, Binding<SelectionValue>>,
        @ViewBuilder content: () -> Content,
        @ViewBuilder currentValueLabel: () -> CurrentValueLabel
    ) where
        C: RandomAccessCollection,
        S: StringProtocol,
        C.Element == Binding<SelectionValue>,
        CurrentValueLabel: View
    {
        self.init(
            sources: sources,
            selection: selection,
            content: content,
            label: { Label(title, systemImage: systemImage) },
            currentValueLabel: currentValueLabel
        )
    }
}
