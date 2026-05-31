//
//  File: Toggle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public enum ToggleState: Sendable, Equatable {
    case off
    case on
    case mixed

    init(isOn: Bool) {
        self = isOn ? .on : .off
    }

    var isOn: Bool {
        self == .on
    }
}

private extension Binding where Value == Bool {
    var toggleStateBinding: Binding<ToggleState> {
        Binding<ToggleState>(
            get: { ToggleState(isOn: self.wrappedValue) },
            set: { state, transaction in
                let binding = self.transaction(transaction)
                binding.wrappedValue = state.isOn
            }
        )
    }
}

private extension Binding where Value == ToggleState {
    var boolBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue.isOn },
            set: { isOn, transaction in
                let binding = self.transaction(transaction)
                binding.wrappedValue = ToggleState(isOn: isOn)
            }
        )
    }
}

public struct Toggle<Label>: View where Label: View {
    var _toggleState: Binding<ToggleState>
    let label: Label
    let appIntentAction: _AppIntentActionStorage?

    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self._toggleState = isOn.toggleStateBinding
        self.label = label()
        self.appIntentAction = nil
    }

    public var body: some View {
        // ResolvedToggleStyle + StaticSourceWriter + Static selects
        // CheckmarkToggleStyle for the menu branch.
        ResolvedToggleStyle(configuration: ToggleStyleConfiguration(
            isOn: _toggleState.boolBinding,
            toggleState: _toggleState
        ))
        .modifier(StaticSourceWriter<ToggleStyleConfiguration.Label, Label>(source: label))
        .modifier(
            StaticIf<StyleContextAcceptsPredicate<MenuStyleContext>,
                     ToggleStyleModifier<CheckmarkToggleStyle>,
                     EmptyModifier>(
                trueBody: ToggleStyleModifier(style: CheckmarkToggleStyle()),
                falseBody: EmptyModifier()
            )
        )
    }
}

extension Toggle where Label == Text {
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(isOn: isOn) {
            Text(titleKey)
        }
    }

    public init<S>(_ title: S, isOn: Binding<Bool>) where S: StringProtocol {
        self.init(isOn: isOn) {
            Text(title)
        }
    }
}

extension Toggle where Label == VUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>) {
        self.init(isOn: isOn) {
            Label(titleKey, systemImage: systemImage)
        }
    }

    public init<S>(_ title: S, systemImage: String, isOn: Binding<Bool>) where S: StringProtocol {
        self.init(isOn: isOn) {
            Label(title, systemImage: systemImage)
        }
    }
}

extension Toggle where Label == ToggleStyleConfiguration.Label {
    public init(_ configuration: ToggleStyleConfiguration) {
        self._toggleState = configuration._toggleState
        self.label = configuration.label
        self.appIntentAction = nil
    }
}

public struct ToggleStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }

    enum Effect: Sendable {
        case binding
    }

    public let label: ToggleStyleConfiguration.Label
    @Binding public var isOn: Bool
    var _toggleState: Binding<ToggleState>
    public var isMixed: Bool
    var effect: Effect

    init(label: ToggleStyleConfiguration.Label = ToggleStyleConfiguration.Label(),
         isOn: Binding<Bool>,
         toggleState: Binding<ToggleState>,
         isMixed: Bool = false,
         effect: Effect = .binding) {
        self.label = label
        self._isOn = isOn
        self._toggleState = toggleState
        self.isMixed = isMixed
        self.effect = effect
    }
}

extension ToggleStyleConfiguration.Label {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        guard let source = inputs.base.customInputs.value(forKey: SourceInput<Self>.self).top else {
            return _ViewOutputs()
        }
        let innerPosAttr = graph.makeInput(value: CGPoint.zero)
        let innerSizeAttr = graph.makeInput(value: ViewSize(.zero))
        var innerInputs = inputs
        innerInputs.position = innerPosAttr
        innerInputs.size = innerSizeAttr
        let innerOutputs = source.makeView(view: view, inputs: innerInputs)
        guard let innerLCAttr = innerOutputs._layoutComputer.attribute else {
            return innerOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let innerLC = innerLCAttr.value
            return LayoutComputer(
                sizeThatFits: { innerLC.sizeThatFits($0) },
                spacing: innerLC.spacing,
                place: { position, anchor, proposal in
                    let size = innerLC.sizeThatFits(proposal)
                    let origin = CGPoint(x: position.x - size.width * anchor.x,
                                         y: position.y - size.height * anchor.y)
                    innerPosAttr.setValue(origin)
                    innerSizeAttr.setValue(ViewSize(size))
                    innerLC.place(at: position, anchor: anchor, proposal: proposal)
                },
                explicitAlignment: { innerLC.explicitAlignment($0, at: $1) }
            )
        }
        return _ViewOutputs(preferences: innerOutputs.preferences, layoutComputer: OptionalAttribute(lcAttr))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToggleStyleConfiguration.Label: _PrimitiveView {}

public protocol ToggleStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ToggleStyleConfiguration
}

struct ResolvedToggleStyle: StyleableView {
    typealias Configuration = ToggleStyleConfiguration
    var configuration: ToggleStyleConfiguration

    var body: some View {
        DefaultToggleStyle().makeBody(configuration: configuration)
    }

    typealias DefaultStyleModifier = ToggleStyleModifier<DefaultToggleStyle>
    static var defaultStyleModifier: ToggleStyleModifier<DefaultToggleStyle> {
        ToggleStyleModifier(style: DefaultToggleStyle())
    }
}

public struct DefaultToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SwitchToggleStyle().makeBody(configuration: configuration)
    }
}

public struct SwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        SwitchToggleStyleBody(configuration: configuration)
    }
}

private struct SwitchToggleStyleBody: View {
    let configuration: ToggleStyleConfiguration

    var body: some View {
        Button(action: toggle) {
            HStack {
                configuration.label
                Text(configuration.isOn ? "On" : "Off")
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle() {
        let binding = configuration.$isOn
        binding.wrappedValue.toggle()
    }
}

public struct ButtonToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            let binding = configuration.$isOn
            binding.wrappedValue.toggle()
        }) {
            configuration.label
        }
    }
}

struct CheckmarkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        CheckmarkToggleBody(configuration: configuration)
    }
}

private struct CheckmarkToggleBody: View {
    typealias Body = Never
    let configuration: ToggleStyleConfiguration

    var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        // Build an action-capable collected item and write ToggleState onto the
        // item model so the ToggleStyleConfiguration.Label source alias remains renderable.
        let labelView = view[\.configuration][\.label]
        var outputs = ToggleStyleConfiguration.Label._makeView(
            view: labelView,
            inputs: platformItemListRenderOnlyInputs(inputs)
        )
        let configurationAttr = view[\.configuration]._attribute
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let source = inputs.base.customInputs.value(forKey: SourceInput<ToggleStyleConfiguration.Label>.self).top
        let itemID = PlatformItemList.stableID(configurationAttr.identifier)
        let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
            let configuration = configurationAttr.value
            let label = source?.snapshot() ?? AnyView(EmptyView())
            let isOn = configuration._toggleState.wrappedValue.isOn
            var list = PlatformItemList()
            list.append(PlatformItemList.Item(
                id: itemID,
                label: label,
                action: {
                    let binding = configuration.$isOn
                    binding.wrappedValue.toggle()
                },
                role: nil,
                keyboardShortcut: environmentAttr.value.keyboardShortcut,
                isEnabled: environmentAttr.value.isEnabled,
                selectionBehavior: .toggle(isOn)
            ))
            return list
        }
        outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToggleStyle where Self == DefaultToggleStyle {
    public static var automatic: DefaultToggleStyle { DefaultToggleStyle() }
}

extension ToggleStyle where Self == SwitchToggleStyle {
    public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}

extension ToggleStyle where Self == ButtonToggleStyle {
    public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

private struct PlatformItemToggleStateModifier: ViewModifier {
    typealias Body = Never
    let state: ToggleState

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        let stateAttr = modifier[\.state]._attribute
        let transformAttr: Attribute<(inout PlatformItemList) -> Void> = graph.makeRule {
            let state = stateAttr.value
            return { itemList in
                itemList.modify { item in
                    item.selectionBehavior = .toggle(state.isOn)
                }
            }
        }
        outputs.preferences.makePreferenceTransformer(
            key: PlatformItemList.Key.self,
            transformAttr: transformAttr,
            transactionAttr: inputs.base.transaction,
            graph: graph
        )
        return outputs
    }
}

extension View {
    func platformItemToggleState(_ state: ToggleState) -> some View {
        modifier(PlatformItemToggleStateModifier(state: state))
    }

    public func toggleStyle<S>(_ style: S) -> some View where S: ToggleStyle {
        modifier(ToggleStyleModifier(style: style))
    }
}
