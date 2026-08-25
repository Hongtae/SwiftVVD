//
//  File: ScrollTargetBehavior.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation

public protocol ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: Self.TargetContext)
    func properties(context: Self.PropertiesContext) -> Self.Properties

    typealias TargetContext = ScrollTargetBehaviorContext
    typealias Properties = ScrollTargetBehaviorProperties
    typealias PropertiesContext = ScrollTargetBehaviorPropertiesContext

    static func _makeInputs(_ behavior: _GraphValue<Self>, inputs: inout _ViewInputs)
    func _updateEnvironment(_ env: inout EnvironmentValues, context: _ScrollTargetBehaviorEnvironmentContext)
}

extension ScrollTargetBehavior {
    public static func _makeInputs(_ behavior: _GraphValue<Self>, inputs: inout _ViewInputs) {
    }

    public func _updateEnvironment(
        _ env: inout EnvironmentValues,
        context: _ScrollTargetBehaviorEnvironmentContext
    ) {
    }

    public func properties(context: Self.PropertiesContext) -> Self.Properties {
        ScrollTargetBehaviorProperties()
    }
}

public struct ScrollTargetBehaviorProperties: Equatable, Sendable {
    var _limitsScrolls: Bool
    var _bouncesScrolls: Bool
    var _deceleratesLinearly: Bool

    public var limitsScrolls: Bool {
        get { _limitsScrolls }
        set { _limitsScrolls = newValue }
    }

    public init() {
        self._limitsScrolls = false
        self._bouncesScrolls = false
        self._deceleratesLinearly = false
    }
}

public struct ScrollTargetBehaviorPropertiesContext {
    public let environment: EnvironmentValues
    public let axes: Axis.Set

    init(environment: EnvironmentValues, axes: Axis.Set) {
        self.environment = environment
        self.axes = axes
    }
}

public struct ScrollIndicatorVisibility: Equatable {
    struct Role: Equatable, Hashable, Sendable {
        var rawValue: UInt8
    }

    var role: Role

    public static var automatic: ScrollIndicatorVisibility {
        ScrollIndicatorVisibility(role: Role(rawValue: 0))
    }

    public static var visible: ScrollIndicatorVisibility {
        ScrollIndicatorVisibility(role: Role(rawValue: 1))
    }

    public static var hidden: ScrollIndicatorVisibility {
        ScrollIndicatorVisibility(role: Role(rawValue: 2))
    }

    public static var never: ScrollIndicatorVisibility {
        ScrollIndicatorVisibility(role: Role(rawValue: 3))
    }
}

public struct ScrollEdgeEffectStyle: Hashable, Sendable {
    struct Role: Equatable, Hashable, Sendable {
        var rawValue: UInt8
    }

    var role: Role

    public static var automatic: ScrollEdgeEffectStyle {
        ScrollEdgeEffectStyle(role: Role(rawValue: 0))
    }

    public static var hard: ScrollEdgeEffectStyle {
        ScrollEdgeEffectStyle(role: Role(rawValue: 1))
    }

    public static var soft: ScrollEdgeEffectStyle {
        ScrollEdgeEffectStyle(role: Role(rawValue: 2))
    }
}

struct ScrollClipDisabledBehavior: Equatable, Sendable {
    struct Role: Equatable, Hashable, Sendable {
        var rawValue: UInt8
    }

    var role: Role

    static let automatic = ScrollClipDisabledBehavior(role: Role(rawValue: 0))
    static let expandsVisibleRegion = ScrollClipDisabledBehavior(role: Role(rawValue: 1))
}

public struct ScrollDismissesKeyboardMode: Hashable, Sendable {
    struct Role: Equatable, Hashable, Sendable {
        var rawValue: UInt8
    }

    var role: Role

    public static var automatic: ScrollDismissesKeyboardMode {
        ScrollDismissesKeyboardMode(role: Role(rawValue: 0))
    }

    public static var immediately: ScrollDismissesKeyboardMode {
        ScrollDismissesKeyboardMode(role: Role(rawValue: 1))
    }

    public static var interactively: ScrollDismissesKeyboardMode {
        ScrollDismissesKeyboardMode(role: Role(rawValue: 2))
    }

    public static var never: ScrollDismissesKeyboardMode {
        ScrollDismissesKeyboardMode(role: Role(rawValue: 3))
    }
}

/// Selects which scroll lifecycle consumes a role-specific default anchor.
public struct ScrollAnchorRole: Hashable, Sendable {
    var role: ScrollAnchorStorage.Role

    public static var initialOffset: ScrollAnchorRole {
        ScrollAnchorRole(role: .initialOffset)
    }

    public static var sizeChanges: ScrollAnchorRole {
        ScrollAnchorRole(role: .sizeChanges)
    }

    public static var alignment: ScrollAnchorRole {
        ScrollAnchorRole(role: .alignment)
    }
}

public struct ScrollBounceBehavior: Sendable {
    struct Role: Equatable, Hashable, Sendable {
        var rawValue: UInt8
    }

    var role: Role

    public static var automatic: ScrollBounceBehavior {
        ScrollBounceBehavior(role: Role(rawValue: 0))
    }

    public static var always: ScrollBounceBehavior {
        ScrollBounceBehavior(role: Role(rawValue: 1))
    }

    public static var basedOnSize: ScrollBounceBehavior {
        ScrollBounceBehavior(role: Role(rawValue: 2))
    }
}

struct ScrollIndicatorOptions: OptionSet, Equatable, Sendable {
    var rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let revealsInitially = ScrollIndicatorOptions(rawValue: 1)
}

/// Selects whether scroll indicators overlay content or reserve viewport space.
public struct ScrollIndicatorStyle: Equatable, Sendable {
    /// The internal presentation mode consumed by the logical scroll host.
    enum Value: Equatable, Sendable {
        case automatic
        case overlay
        case legacy
    }

    var value: Value

    public static let automatic = ScrollIndicatorStyle(value: .automatic)
    public static let overlay = ScrollIndicatorStyle(value: .overlay)

    /// Reserves a persistent scrollbar area outside the content viewport.
    public static let fixedArea = ScrollIndicatorStyle(value: .legacy)

    static let legacy = ScrollIndicatorStyle(value: .legacy)
}

struct ScrollIndicatorConfiguration: Equatable {
    var visibility: ScrollIndicatorVisibility
    var options: ScrollIndicatorOptions
    var style: ScrollIndicatorStyle

    init(
        visibility: ScrollIndicatorVisibility = .automatic,
        options: ScrollIndicatorOptions = [],
        style: ScrollIndicatorStyle = .automatic
    ) {
        self.visibility = visibility
        self.options = options
        self.style = style
    }
}

enum HandGestureShortcutPaginationDirection: CaseIterable, Hashable, Sendable {
    case forward
    case reverse
    case none
}

struct NavigationBarScrollMetrics: Equatable {
    var minHeight: Double
    var maxHeight: Double
    var preferredHeight: Double
    var scrollTargets: [ScrollTarget]
}

struct ScrollDecelerationRate: Equatable, Sendable {
    struct Role: Equatable, Hashable, Sendable {
        var rawValue: UInt8
    }

    var role: Role

    static let automatic = ScrollDecelerationRate(role: Role(rawValue: 0))
    static let viewAligned = ScrollDecelerationRate(role: Role(rawValue: 1))
    static let fast = ScrollDecelerationRate(role: Role(rawValue: 2))
    static let paging = ScrollDecelerationRate(role: Role(rawValue: 3))
    static let standard = ScrollDecelerationRate(role: Role(rawValue: 4))
}

struct ScrollTargetBehaviorDecelerationContext {
    var defaultDecelerationRate: ScrollDecelerationRate
    var axes: Axis.Set
    var environment: EnvironmentValues
}

public struct _ScrollTargetBehaviorEnvironmentContext {
    public init() {
    }
}

struct ScrollTargetRole {
    enum Role: Hashable, Sendable {
        case container
        case target
    }

    var role: Role

    static var container: ScrollTargetRole {
        ScrollTargetRole(role: .container)
    }

    static var target: ScrollTargetRole {
        ScrollTargetRole(role: .target)
    }

    struct ContentKey: PreferenceKey {
        static var defaultValue: [Role: [any ScrollableCollection]] { [:] }

        static func reduce(
            value: inout [Role: [any ScrollableCollection]],
            nextValue: () -> [Role: [any ScrollableCollection]]
        ) {
            for (role, collections) in nextValue() {
                value[role, default: []].append(contentsOf: collections)
            }
        }
    }

    struct Key: PreferenceKey {
        static var defaultValue: [Role: [any ScrollableCollection]] { [:] }

        static func reduce(
            value: inout [Role: [any ScrollableCollection]],
            nextValue: () -> [Role: [any ScrollableCollection]]
        ) {
            for (role, collections) in nextValue() {
                value[role, default: []].append(contentsOf: collections)
            }
        }
    }

    struct SetLayout: Rule {
        typealias Value = (inout [Role: [any ScrollableCollection]]) -> Void

        var role: Attribute<Role?>
        var collection: Attribute<any ScrollableCollection>

        var value: Value {
            let role = role.value
            let collection = collection.value
            return { value in
                guard let role else { return }
                value[role, default: []].append(collection)
            }
        }
    }
}

private struct ScrollTargetRoleInputKey: GraphInput {
    static var defaultValue: OptionalAttribute<ScrollTargetRole.Role?> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ a: OptionalAttribute<ScrollTargetRole.Role?>,
        _ b: OptionalAttribute<ScrollTargetRole.Role?>
    ) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

extension _GraphInputs {
    var scrollTargetRole: OptionalAttribute<ScrollTargetRole.Role?> {
        get { self[ScrollTargetRoleInputKey.self] }
        set { self[ScrollTargetRoleInputKey.self] = newValue }
    }
}

extension _ViewInputs {
    var scrollTargetRole: OptionalAttribute<ScrollTargetRole.Role?> {
        base.scrollTargetRole
    }
}

@dynamicMemberLookup
public struct ScrollTargetBehaviorContext {
    var _originalTarget: ScrollTarget
    var _velocity: CGVector
    var geometry: ScrollGeometry
    var _axes: Axis.Set
    var decelerationRate: ScrollDecelerationRate
    var collections: [any ScrollableCollection]
    var targets: [any ScrollableCollection]
    var environment: EnvironmentValues

    init(
        originalTarget: ScrollTarget,
        velocity: CGVector,
        geometry: ScrollGeometry,
        axes: Axis.Set,
        decelerationRate: ScrollDecelerationRate = .paging,
        collections: [any ScrollableCollection] = [],
        targets: [any ScrollableCollection] = [],
        environment: EnvironmentValues = EnvironmentValues()
    ) {
        self._originalTarget = originalTarget
        self._velocity = velocity
        self.geometry = geometry
        self._axes = axes
        self.decelerationRate = decelerationRate
        self.collections = collections
        self.targets = targets
        self.environment = environment
    }

    public var originalTarget: ScrollTarget {
        _originalTarget
    }

    public var velocity: CGVector {
        _velocity
    }

    public var contentSize: CGSize {
        geometry.contentSize
    }

    public var containerSize: CGSize {
        geometry.containerSize
    }

    public var axes: Axis.Set {
        _axes
    }

    var contentInsets: EdgeInsets {
        geometry.contentInsets
    }

    var contentOffset: CGPoint {
        geometry.contentOffset
    }

    var viewportSize: CGSize {
        geometry.visibleRect.size
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
        environment[keyPath: keyPath]
    }
}

struct ResolvedScrollBehavior {
    var base: any ScrollTargetBehavior
    var baseSeed: UInt32
    var axes: Axis.Set?
    var _collections: WeakAttribute<[any ScrollableCollection]>
    var _targets: WeakAttribute<[any ScrollableCollection]>
    var _environment: WeakAttribute<EnvironmentValues>

    init(
        base: any ScrollTargetBehavior,
        baseSeed: UInt32 = 0,
        axes: Axis.Set? = nil,
        collections: WeakAttribute<[any ScrollableCollection]> = WeakAttribute(),
        targets: WeakAttribute<[any ScrollableCollection]> = WeakAttribute(),
        environment: WeakAttribute<EnvironmentValues> = WeakAttribute()
    ) {
        self.base = base
        self.baseSeed = baseSeed
        self.axes = axes
        self._collections = collections
        self._targets = targets
        self._environment = environment
    }
}

extension ResolvedScrollBehavior: Equatable {
    static func == (lhs: ResolvedScrollBehavior, rhs: ResolvedScrollBehavior) -> Bool {
        ObjectIdentifier(type(of: lhs.base)) == ObjectIdentifier(type(of: rhs.base))
            && lhs.baseSeed == rhs.baseSeed
            && lhs.axes == rhs.axes
            && lhs._collections == rhs._collections
            && lhs._targets == rhs._targets
            && lhs._environment == rhs._environment
    }
}

extension ResolvedScrollBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard let axes else {
            fatalError("ResolvedScrollBehavior requires resolved axes before target updates.")
        }
        guard let graph = _AGGraph.current else {
            fatalError("ResolvedScrollBehavior.updateTarget requires an active _AGGraph context.")
        }

        var context = context
        context._axes = axes
        context.collections = _collections.isValid(in: graph)
            ? _collections.toStrong().value
            : []
        context.targets = _targets.isValid(in: graph)
            ? _targets.toStrong().value
            : []
        context.environment = _environment.isValid(in: graph)
            ? _environment.toStrong().value
            : EnvironmentValues()
        base.updateTarget(&target, context: context)
    }

    func properties(context: PropertiesContext) -> Properties {
        base.properties(context: context)
    }
}

protocol ScrollEnvironmentTransform {
    func update(properties: inout ScrollEnvironmentProperties)
}

struct ScrollEnvironmentProperties: Equatable {
    struct Options: OptionSet, Equatable, Sendable {
        var rawValue: Int8

        init(rawValue: Int8) {
            self.rawValue = rawValue
        }
    }

    var isEnabled: Bool
    var isClippingEnabled: Bool
    var clipDisabledBehavior: ScrollClipDisabledBehavior
    var dismissKeyboardMode: ScrollDismissesKeyboardMode.Role
    var scrollBehavior: ResolvedScrollBehavior?
    var decelerationRate: ScrollDecelerationRate
    var layoutDirection: LayoutDirection
    var options: Options
    var indicatorFlashSeed: UInt32
    var accessoryEdge: Edge?
    var accessoryVisibility: Visibility
    var edgeEffectStyle: [Edge: ScrollEdgeEffectStyle]
    var edgeEffectHidden: [Edge: Bool]
    var edgeEffectDisabled: Bool
    var verticalIndicator: ScrollIndicatorConfiguration
    var verticalBounceBehavior: ScrollBounceBehavior.Role
    var horizontalIndicator: ScrollIndicatorConfiguration
    var horizontalBounceBehavior: ScrollBounceBehavior.Role
    var allowedAutoScrollAxes: Axis.Set?
    var autoScrollAllowsPaginated: Bool
    var isContainedInPlatter: Bool
    var crownScrollingAxis: Axis?
    var handGestureShortcutPaginationDirection: HandGestureShortcutPaginationDirection
    var navigationBarScrollMetrics: NavigationBarScrollMetrics?
    var gradientMaskLengths: EdgeInsets
    var gradientMaskEdgeInsets: EdgeInsets

    init() {
        self.isEnabled = true
        self.isClippingEnabled = true
        self.clipDisabledBehavior = .automatic
        self.dismissKeyboardMode = ScrollDismissesKeyboardMode.automatic.role
        self.scrollBehavior = nil
        self.decelerationRate = .standard
        self.layoutDirection = .leftToRight
        self.options = []
        self.indicatorFlashSeed = 0
        self.accessoryEdge = nil
        self.accessoryVisibility = .automatic
        self.edgeEffectStyle = [:]
        self.edgeEffectHidden = [:]
        self.edgeEffectDisabled = false
        self.verticalIndicator = ScrollIndicatorConfiguration()
        self.verticalBounceBehavior = ScrollBounceBehavior.automatic.role
        self.horizontalIndicator = ScrollIndicatorConfiguration()
        self.horizontalBounceBehavior = ScrollBounceBehavior.automatic.role
        self.allowedAutoScrollAxes = []
        self.autoScrollAllowsPaginated = false
        self.isContainedInPlatter = false
        self.crownScrollingAxis = .vertical
        self.handGestureShortcutPaginationDirection = .reverse
        self.navigationBarScrollMetrics = nil
        self.gradientMaskLengths = EdgeInsets()
        self.gradientMaskEdgeInsets = EdgeInsets()
    }

    init(environment: EnvironmentValues) {
        self.init()
        self = environment.scrollEnvironmentStorage.properties
        self.layoutDirection = environment.layoutDirection
        if !isEnabled {
            verticalBounceBehavior = ScrollBounceBehavior.Role(rawValue: 3)
            horizontalBounceBehavior = ScrollBounceBehavior.Role(rawValue: 3)
        }
    }
}

final class ScrollEnvironmentStorage: Observable {
    var _baseProperties: ScrollEnvironmentProperties
    var _transform: (any ScrollEnvironmentTransform)?
    var _$observationRegistrar: ObservationRegistrar

    init(
        _ properties: ScrollEnvironmentProperties,
        transform: (any ScrollEnvironmentTransform)? = nil
    ) {
        self._baseProperties = properties
        self._transform = transform
        self._$observationRegistrar = ObservationRegistrar()
    }

    var baseProperties: ScrollEnvironmentProperties {
        get {
            _$observationRegistrar.access(self, keyPath: \._baseProperties)
            return _baseProperties
        }
        set {
            _$observationRegistrar.withMutation(of: self, keyPath: \._baseProperties) {
                _baseProperties = newValue
            }
        }
    }

    var transform: (any ScrollEnvironmentTransform)? {
        get {
            _$observationRegistrar.access(self, keyPath: \._transform)
            return _transform
        }
        set {
            _$observationRegistrar.withMutation(of: self, keyPath: \._transform) {
                _transform = newValue
            }
        }
    }

    var properties: ScrollEnvironmentProperties {
        var properties = baseProperties
        transform?.update(properties: &properties)
        return properties
    }
}

struct TransformScrollStorageEnvironment<Transform: ScrollEnvironmentTransform>: StatefulRule {
    typealias Value = EnvironmentValues

    var _environment: Attribute<EnvironmentValues>
    var _transform: Attribute<Transform>
    var previousProperties: ScrollEnvironmentProperties?

    mutating func updateValue() {
        var values = _environment.value.trackingCopy()
        let properties = ScrollEnvironmentProperties(environment: values)
        let storage = ScrollEnvironmentStorage(properties, transform: _transform.value)
        values.scrollEnvironmentStorage = storage
        previousProperties = storage.properties
        _AGGraph.setStatefulOutput(values)
    }
}

struct TransformScrollStorageModifier<Transform>: ViewModifier, _GraphInputsModifier
where Transform: ScrollEnvironmentTransform {
    typealias Body = Never

    var transform: Transform

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }
        let environment = inputs.cachedEnvironment.value.environment
        let transformedEnvironment: Attribute<EnvironmentValues> = graph.makeStatefulRule(
            TransformScrollStorageEnvironment(
                _environment: environment,
                _transform: modifier[\.transform]._attribute,
                previousProperties: nil
            )
        )
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(transformedEnvironment)
        )
    }
}

private struct ScrollEnvironmentKey: EnvironmentKey {
    static var defaultValue: ScrollEnvironmentStorage {
        ScrollEnvironmentStorage(ScrollEnvironmentProperties())
    }
}

extension EnvironmentValues {
    var scrollEnvironmentStorage: ScrollEnvironmentStorage {
        get { self[ScrollEnvironmentKey.self] }
        set { self[ScrollEnvironmentKey.self] = newValue }
    }

    public var scrollDismissesKeyboardMode: ScrollDismissesKeyboardMode {
        get {
            ScrollDismissesKeyboardMode(
                role: scrollEnvironmentStorage.properties.dismissKeyboardMode
            )
        }
        set {
            var properties = scrollEnvironmentStorage.properties
            // Replacing this policy preserves every unrelated scroll property.
            properties.dismissKeyboardMode = newValue.role
            scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
        }
    }

    public var verticalScrollBounceBehavior: ScrollBounceBehavior {
        get {
            ScrollBounceBehavior(
                role: scrollEnvironmentStorage.properties.verticalBounceBehavior
            )
        }
        set {
            var properties = scrollEnvironmentStorage.properties
            // Each axis publishes a fresh storage value without rewriting the other axis.
            properties.verticalBounceBehavior = newValue.role
            scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
        }
    }

    public var horizontalScrollBounceBehavior: ScrollBounceBehavior {
        get {
            ScrollBounceBehavior(
                role: scrollEnvironmentStorage.properties.horizontalBounceBehavior
            )
        }
        set {
            var properties = scrollEnvironmentStorage.properties
            // Each axis publishes a fresh storage value without rewriting the other axis.
            properties.horizontalBounceBehavior = newValue.role
            scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
        }
    }

    public var isScrollEnabled: Bool {
        get { scrollEnvironmentStorage.properties.isEnabled }
        set {
            var properties = scrollEnvironmentStorage.properties
            // A disabled ancestor remains disabled when a descendant requests scrolling.
            properties.isEnabled = properties.isEnabled && newValue
            scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
        }
    }
}

private struct DismissKeyboardTransform: ScrollEnvironmentTransform {
    var mode: ScrollDismissesKeyboardMode.Role

    func update(properties: inout ScrollEnvironmentProperties) {
        // The closest transform replaces the inherited dismissal policy.
        properties.dismissKeyboardMode = mode
    }
}

private struct TransformScrollBounceBehavior: ScrollEnvironmentTransform {
    var behavior: ScrollBounceBehavior.Role
    var axes: Axis.Set

    func update(properties: inout ScrollEnvironmentProperties) {
        // The selected axes replace their inherited roles independently.
        if axes.contains(.vertical) {
            properties.verticalBounceBehavior = behavior
        }
        if axes.contains(.horizontal) {
            properties.horizontalBounceBehavior = behavior
        }
    }
}

private struct ScrollEnabledTransform: ScrollEnvironmentTransform {
    var isEnabled: Bool

    func update(properties: inout ScrollEnvironmentProperties) {
        properties.isEnabled = properties.isEnabled && isEnabled
    }
}

private struct ScrollClipTransform: ScrollEnvironmentTransform {
    var isEnabled: Bool
    var behavior: ScrollClipDisabledBehavior?

    func update(properties: inout ScrollEnvironmentProperties) {
        // A descendant cannot re-enable clipping after an ancestor disables it.
        properties.isClippingEnabled = properties.isClippingEnabled && isEnabled
        // A nil behavior preserves the clipping policy inherited from the parent.
        if let behavior {
            properties.clipDisabledBehavior = behavior
        }
    }
}

extension View {
    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        transformEnvironment(\.scrollAnchors) { anchors in
            // A nil argument preserves inherited storage rather than resetting it.
            guard let anchor else { return }
            anchors.defaultValue = anchor
        }
    }

    nonisolated public func defaultScrollAnchor(
        _ anchor: UnitPoint?,
        for role: ScrollAnchorRole
    ) -> some View {
        transformEnvironment(\.scrollAnchors) { anchors in
            // Role entries override only their matching lifecycle consumer.
            guard let anchor else { return }
            anchors.updateRole(role.role, anchor: anchor)
        }
    }

    nonisolated public func scrollBounceBehavior(
        _ behavior: ScrollBounceBehavior,
        axes: Axis.Set = [.vertical]
    ) -> some View {
        modifier(TransformScrollStorageModifier(
            transform: TransformScrollBounceBehavior(
                behavior: behavior.role,
                axes: axes
            )
        ))
    }

    nonisolated public func scrollDisabled(_ disabled: Bool) -> some View {
        modifier(TransformScrollStorageModifier(
            transform: ScrollEnabledTransform(isEnabled: !disabled)
        ))
    }

    nonisolated public func scrollClipDisabled(_ disabled: Bool = true) -> some View {
        modifier(TransformScrollStorageModifier(
            transform: ScrollClipTransform(
                isEnabled: !disabled,
                behavior: nil
            )
        ))
    }

    nonisolated public func scrollDismissesKeyboard(
        _ mode: ScrollDismissesKeyboardMode
    ) -> some View {
        modifier(TransformScrollStorageModifier(
            transform: DismissKeyboardTransform(mode: mode.role)
        ))
    }
}

public struct PagingScrollTargetBehavior: ScrollTargetBehavior {
    public init() {
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        if context.axes.contains(.horizontal) {
            updateTarget(&target, context: context, axis: .horizontal)
        }
        if context.axes.contains(.vertical) {
            updateTarget(&target, context: context, axis: .vertical)
        }
    }

    public static func _makeInputs(_ behavior: _GraphValue<PagingScrollTargetBehavior>, inputs: inout _ViewInputs) {
    }

    public func properties(context: PropertiesContext) -> Properties {
        ScrollTargetBehaviorProperties()
    }

    private enum PageAxis {
        case horizontal
        case vertical
    }

    private func updateTarget(
        _ target: inout ScrollTarget,
        context: TargetContext,
        axis: PageAxis
    ) {
        let pageLength: CGFloat
        let contentLength: CGFloat
        let targetOrigin: CGFloat
        let originalOrigin: CGFloat
        let velocity: CGFloat

        switch axis {
        case .horizontal:
            pageLength = context.containerSize.width
            contentLength = context.contentSize.width
            targetOrigin = target.rect.origin.x
            originalOrigin = context.originalTarget.rect.origin.x
            velocity = context.environment.layoutDirection == .rightToLeft
                ? -context.velocity.dx
                : context.velocity.dx
        case .vertical:
            pageLength = context.containerSize.height
            contentLength = context.contentSize.height
            targetOrigin = target.rect.origin.y
            originalOrigin = context.originalTarget.rect.origin.y
            velocity = context.velocity.dy
        }

        guard pageLength > 0 else { return }
        let maxOrigin = contentLength - pageLength
        guard maxOrigin >= 0, targetOrigin >= 0, targetOrigin <= maxOrigin else {
            return
        }

        let pageIndex: CGFloat
        if velocity > 0 {
            pageIndex = (originalOrigin / pageLength).rounded(.toNearestOrAwayFromZero) + 1
        } else if velocity < 0 {
            pageIndex = (originalOrigin / pageLength).rounded(.toNearestOrAwayFromZero) - 1
        } else {
            pageIndex = (targetOrigin / pageLength).rounded(.toNearestOrAwayFromZero)
        }

        let alignedOrigin = pageIndex * pageLength
        guard alignedOrigin >= 0, alignedOrigin <= maxOrigin else {
            return
        }

        switch axis {
        case .horizontal:
            target.rect.origin.x = alignedOrigin
        case .vertical:
            target.rect.origin.y = alignedOrigin
        }
    }
}

extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    public static var paging: PagingScrollTargetBehavior {
        .init()
    }
}

public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior {
    public struct LimitBehavior {
        struct Role: Equatable {
            var rawValue: UInt8
        }

        var role: Role

        public static var automatic: LimitBehavior {
            LimitBehavior(role: Role(rawValue: 0))
        }

        public static var always: LimitBehavior {
            LimitBehavior(role: Role(rawValue: 1))
        }

        public static var alwaysByFew: LimitBehavior {
            LimitBehavior(role: Role(rawValue: 2))
        }

        public static var alwaysByOne: LimitBehavior {
            LimitBehavior(role: Role(rawValue: 1))
        }

        public static var never: LimitBehavior {
            LimitBehavior(role: Role(rawValue: 3))
        }
    }

    var limitBehavior: LimitBehavior
    var anchor: UnitPoint?

    public init(limitBehavior: LimitBehavior = .automatic) {
        self.limitBehavior = limitBehavior
        self.anchor = nil
    }

    public init(limitBehavior: LimitBehavior, anchor: UnitPoint?) {
        self.limitBehavior = limitBehavior
        self.anchor = anchor
    }

    public init(anchor: UnitPoint?) {
        self.limitBehavior = .automatic
        self.anchor = anchor
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard !context.collections.isEmpty,
              let axis = ViewAlignedScrollAxis(axes: context.axes) else {
            return
        }

        let targetCoordinate = axis.coordinate(of: target.rect.origin)
        let maximumTargetCoordinate =
            axis.length(of: context.contentSize) - axis.length(of: context.containerSize)
        guard targetCoordinate > 0,
              targetCoordinate < maximumTargetCoordinate else {
            return
        }

        guard var alignedRect = makeTargetRect(
            for: target,
            context: context,
            collections: context.collections,
            axis: axis
        ) else {
            return
        }
        if let anchor {
            alignedRect = alignedRect.offsetBy(
                dx: context.containerSize.width * anchor.x - alignedRect.width * anchor.x,
                dy: context.containerSize.height * anchor.y - alignedRect.height * anchor.y
            )
        }
        axis.apply(originOf: alignedRect, to: &target.rect)
    }

    public static func _makeInputs(_ behavior: _GraphValue<ViewAlignedScrollTargetBehavior>, inputs: inout _ViewInputs) {
    }

    public func properties(context: PropertiesContext) -> Properties {
        ScrollTargetBehaviorProperties()
    }

    private func makeTargetRect(
        for target: ScrollTarget,
        context: TargetContext,
        collections: [any ScrollableCollection],
        axis: ViewAlignedScrollAxis
    ) -> CGRect? {
        let maximumCandidateLength = axis.length(of: context.containerSize) * 1.1
        var candidates: [CGRect] = []

        for collection in collections {
            collection.forEachVisibleSubview { subview, stop in
                appendCandidate(
                    subview.frameInContent,
                    maximumLength: maximumCandidateLength,
                    axis: axis,
                    to: &candidates
                )
                stop = false
            }
            if let closest = collection.subviewClosestTo(rect: target.rect) {
                appendCandidate(
                    closest.frameInContent,
                    maximumLength: maximumCandidateLength,
                    axis: axis,
                    to: &candidates
                )
            }
        }

        return findClosestRect(
            in: candidates,
            targetOffset: target.rect.origin,
            context: context,
            axis: axis
        )
    }

    private func appendCandidate(
        _ rect: CGRect,
        maximumLength: CGFloat,
        axis: ViewAlignedScrollAxis,
        to candidates: inout [CGRect]
    ) {
        guard axis.length(of: rect) <= maximumLength,
              !candidates.contains(rect) else {
            return
        }
        candidates.append(rect)
    }

    private func findClosestRect(
        in rects: [CGRect],
        targetOffset: CGPoint,
        context: TargetContext,
        axis: ViewAlignedScrollAxis
    ) -> CGRect? {
        let sorted = rects.sorted { lhs, rhs in
            axis.min(of: lhs) < axis.min(of: rhs)
        }
        guard let first = sorted.first,
              let last = sorted.last else {
            return nil
        }

        let minimum = axis.min(of: first) - axis.length(of: first)
        let maximum = axis.max(of: last) + axis.length(of: last)
        let targetCoordinate = axis.coordinate(of: targetOffset)
        guard minimum <= targetCoordinate, targetCoordinate <= maximum else {
            return nil
        }

        guard let targetIndex = closestRectIndex(in: sorted, to: targetOffset) else {
            return nil
        }

        let originalIndex = closestRectIndex(in: sorted, to: context.originalTarget.rect.origin)
        let velocity = axis.velocity(of: context.velocity, layoutDirection: context.environment.layoutDirection)
        if originalIndex == targetIndex,
           context.decelerationRate != .standard,
           velocity != 0 {
            let step = velocity > 0 ? 1 : -1
            let currentOrigin = axis.min(of: sorted[targetIndex])
            var nextIndex = targetIndex + step
            while sorted.indices.contains(nextIndex) {
                if axis.min(of: sorted[nextIndex]) != currentOrigin {
                    return sorted[nextIndex]
                }
                nextIndex += step
            }
        }

        return sorted[targetIndex]
    }

    private func closestRectIndex(in rects: [CGRect], to point: CGPoint) -> Int? {
        guard !rects.isEmpty else { return nil }
        var closestIndex = rects.startIndex
        var closestDistance = rects[closestIndex].origin.distance(to: point)
        for index in rects.indices.dropFirst() {
            let distance = rects[index].origin.distance(to: point)
            if distance < closestDistance {
                closestIndex = index
                closestDistance = distance
            }
        }
        return closestIndex
    }
}

private enum ViewAlignedScrollAxis {
    case horizontal
    case vertical

    init?(axes: Axis.Set) {
        if axes == .vertical {
            self = .vertical
        } else if axes == .horizontal {
            self = .horizontal
        } else {
            return nil
        }
    }

    func length(of size: CGSize) -> CGFloat {
        switch self {
        case .horizontal:
            return size.width
        case .vertical:
            return size.height
        }
    }

    func length(of rect: CGRect) -> CGFloat {
        switch self {
        case .horizontal:
            return rect.width
        case .vertical:
            return rect.height
        }
    }

    func min(of rect: CGRect) -> CGFloat {
        switch self {
        case .horizontal:
            return rect.minX
        case .vertical:
            return rect.minY
        }
    }

    func max(of rect: CGRect) -> CGFloat {
        switch self {
        case .horizontal:
            return rect.maxX
        case .vertical:
            return rect.maxY
        }
    }

    func coordinate(of point: CGPoint) -> CGFloat {
        switch self {
        case .horizontal:
            return point.x
        case .vertical:
            return point.y
        }
    }

    func velocity(of vector: CGVector, layoutDirection: LayoutDirection) -> CGFloat {
        switch self {
        case .horizontal:
            return layoutDirection == .rightToLeft ? -vector.dx : vector.dx
        case .vertical:
            return vector.dy
        }
    }

    func apply(originOf selected: CGRect, to target: inout CGRect) {
        switch self {
        case .horizontal:
            target.origin.x = selected.origin.x
        case .vertical:
            target.origin.y = selected.origin.y
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    public static var viewAligned: ViewAlignedScrollTargetBehavior {
        .init()
    }

    public static func viewAligned(
        limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior
    ) -> Self {
        .init(limitBehavior: limitBehavior)
    }

    public static func viewAligned(anchor: UnitPoint?) -> Self {
        .init(anchor: anchor)
    }

    public static func viewAligned(
        limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior,
        anchor: UnitPoint?
    ) -> Self {
        .init(limitBehavior: limitBehavior, anchor: anchor)
    }
}

public struct AnyScrollTargetBehavior: ScrollTargetBehavior {
    public var base: any ScrollTargetBehavior

    public init(_ base: some ScrollTargetBehavior) {
        self.base = base
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        base.updateTarget(&target, context: context)
    }

    public func _updateEnvironment(
        _ env: inout EnvironmentValues,
        context: _ScrollTargetBehaviorEnvironmentContext
    ) {
        base._updateEnvironment(&env, context: context)
    }

    public func properties(context: PropertiesContext) -> Properties {
        base.properties(context: context)
    }
}

private struct ScrollTargetModifier: ViewModifier, _GraphInputsModifier {
    var role: ScrollTargetRole.Role?

    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }
        let role: Attribute<ScrollTargetRole.Role?> = graph.makeRule {
            modifier._attribute.value.role
        }
        inputs.scrollTargetRole = OptionalAttribute(role)
    }
}

private struct ScrollBehaviorModifier<Behavior: ScrollTargetBehavior>: UnaryViewModifier, PrimitiveViewModifier {
    var behavior: Behavior

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }
        let shouldForwardRoleLayouts = inputs.preferences.keys.contains(ScrollTargetRole.ContentKey.self)
        var inputs = inputs
        inputs.preferences.keys.add(ScrollTargetRole.ContentKey.self)
        let layouts: Attribute<[ScrollTargetRole.Role: [any ScrollableCollection]]> =
            graph.makeIndirectAttribute(defaultValue: ScrollTargetRole.ContentKey.defaultValue)
        Self._makeViewInputs(modifier: modifier, inputs: &inputs, layouts: layouts)
        var outputs = body(_Graph(), inputs)
        if let childLayouts = outputs.preferences.value(for: ScrollTargetRole.ContentKey.self) {
            graph.setIndirectTarget(layouts, to: Attribute<[ScrollTargetRole.Role: [any ScrollableCollection]]>(childLayouts))
        } else {
            graph.setIndirectTarget(layouts, to: nil)
        }
        if !shouldForwardRoleLayouts {
            outputs.preferences.setValue(nil, for: ScrollTargetRole.ContentKey.self)
        }
        return outputs
    }

    static func _makeViewInputs(modifier: _GraphValue<Self>, inputs: inout _ViewInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active _AGGraph context.")
        }

        let layouts: Attribute<[ScrollTargetRole.Role: [any ScrollableCollection]]> =
            graph.makeIndirectAttribute(defaultValue: ScrollTargetRole.ContentKey.defaultValue)
        Self._makeViewInputs(modifier: modifier, inputs: &inputs, layouts: layouts)
    }

    private static func _makeViewInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _ViewInputs,
        layouts: Attribute<[ScrollTargetRole.Role: [any ScrollableCollection]]>
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeViewInputs called outside an active _AGGraph context.")
        }

        let collections: Attribute<[any ScrollableCollection]> = graph.makeRule(
            LayoutRoleFilter(role: .container, _layouts: layouts)
        )
        let targets: Attribute<[any ScrollableCollection]> = graph.makeRule(
            LayoutRoleFilter(role: .target, _layouts: layouts)
        )
        let resolvedBehavior: Attribute<ResolvedScrollBehavior> = graph.makeStatefulRule(
            ScrollBehaviorProvider(
                _behavior: modifier[\.behavior]._attribute,
                _collections: OptionalAttribute(collections),
                _targets: OptionalAttribute(targets),
                seed: 0
            )
        )
        let parentEnvironment = inputs.base.cachedEnvironment.value.environment
        let environment: Attribute<EnvironmentValues> = graph.makeRule(
            ChildEnvironment(
                _environment: parentEnvironment,
                _resolvedBehavior: resolvedBehavior
            )
        )
        inputs.base.cachedEnvironment = MutableBox(
            inputs.base.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    private struct LayoutRoleFilter: Rule {
        typealias Value = [any ScrollableCollection]

        var role: ScrollTargetRole.Role
        var _layouts: Attribute<[ScrollTargetRole.Role: [any ScrollableCollection]]>

        var value: [any ScrollableCollection] {
            _layouts.value[role] ?? []
        }
    }

    private struct ScrollBehaviorProvider: StatefulRule {
        typealias Value = ResolvedScrollBehavior

        var _behavior: Attribute<Behavior>
        var _collections: OptionalAttribute<[any ScrollableCollection]>
        var _targets: OptionalAttribute<[any ScrollableCollection]>
        var seed: UInt32

        mutating func updateValue() {
            if _AGGraph.currentStatefulOutput(Value.self) != nil,
               _AGGraphAnyInputsChanged() {
                seed &+= 1
            }

            _AGGraph.setStatefulOutput(ResolvedScrollBehavior(
                base: _behavior.value,
                baseSeed: seed,
                collections: _collections.attribute?.asWeak() ?? WeakAttribute(),
                targets: _targets.attribute?.asWeak() ?? WeakAttribute()
            ))
        }
    }

    private struct ChildEnvironment: Rule {
        typealias Value = EnvironmentValues

        var _environment: Attribute<EnvironmentValues>
        var _resolvedBehavior: Attribute<ResolvedScrollBehavior>

        var value: EnvironmentValues {
            var values = _environment.value.trackingCopy()
            var properties = ScrollEnvironmentProperties(environment: values)
            properties.scrollBehavior = _resolvedBehavior.value
            values.scrollEnvironmentStorage = ScrollEnvironmentStorage(properties)
            return values
        }
    }
}

extension View {
    public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        modifier(ScrollTargetModifier(role: isEnabled ? .container : nil))
    }

    public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        modifier(ScrollBehaviorModifier(behavior: behavior))
    }
}
