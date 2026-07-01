//
//  File: ScrollStateRequest.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Runtime scroll target that can apply queued scroll state requests.
protocol Scrollable {
    func scroll<ID>(to id: ID) -> Bool where ID: Hashable
    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool
    var allowsContentOffsetAdjustments: Bool { get }
    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool
    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B?
}

extension Scrollable {
    func scrollToPosition(_ position: ScrollPosition) -> Bool {
        if let id = position._anyViewID {
            return scroll(to: id)
        }
        if let edge = position.edge {
            return setContentTarget { geometry, layoutDirection in
                ScrollTarget(rect: geometry.targetRect(edge: edge, layoutDirection: layoutDirection))
            }
        }
        if let point = position.point {
            return setContentTarget { geometry, layoutDirection in
                ScrollTarget(rect: geometry.targetRect(point: point, layoutDirection: layoutDirection))
            }
        }
        if let x = position.x {
            return setContentTarget { geometry, layoutDirection in
                ScrollTarget(rect: geometry.targetRect(x: x, layoutDirection: layoutDirection))
            }
        }
        if let y = position.y {
            return setContentTarget { geometry, _ in
                ScrollTarget(rect: geometry.targetRect(y: y))
            }
        }
        return true
    }
}

private extension ScrollGeometry {
    func targetRect(edge: Edge, layoutDirection: LayoutDirection) -> CGRect {
        var rect = visibleRect
        switch resolved(edge: edge, layoutDirection: layoutDirection) {
        case .top:
            rect.origin.y = 0
        case .leading:
            rect.origin.x = 0
        case .bottom:
            rect.origin.y = contentSize.height - containerSize.height
        case .trailing:
            rect.origin.x = contentSize.width - containerSize.width
        }
        return rect
    }

    func targetRect(point: CGPoint, layoutDirection: LayoutDirection) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: resolved(x: point.x, layoutDirection: layoutDirection),
                y: point.y
            ),
            size: containerSize
        )
    }

    func targetRect(x: CGFloat, layoutDirection: LayoutDirection) -> CGRect {
        var rect = visibleRect
        rect.origin.x = resolved(x: x, layoutDirection: layoutDirection)
        return rect
    }

    func targetRect(y: CGFloat) -> CGRect {
        var rect = visibleRect
        rect.origin.y = y
        return rect
    }

    func resolved(edge: Edge, layoutDirection: LayoutDirection) -> Edge {
        guard layoutDirection == .rightToLeft else {
            return edge
        }
        switch edge {
        case .leading:
            return .trailing
        case .trailing:
            return .leading
        case .top, .bottom:
            return edge
        }
    }

    func resolved(x: CGFloat, layoutDirection: LayoutDirection) -> CGFloat {
        guard layoutDirection == .rightToLeft else {
            return x
        }
        return contentSize.width - x
    }
}

/// Concrete content rect and optional anchor requested from a scrollable host.
public struct ScrollTarget: Hashable {
    public var rect: CGRect
    public var anchor: UnitPoint?

    init(rect: CGRect, anchor: UnitPoint? = nil) {
        self.rect = rect
        self.anchor = anchor
    }
}

/// Reason code passed to scrollable hosts when content offset is adjusted.
enum ContentOffsetAdjustmentReason {
    case scrollPosition
}

/// Stable classification used to coalesce compatible scroll state requests.
enum ScrollStateRequestKind: CustomStringConvertible, Equatable {
    struct UpdateValueConfig: Equatable {
        var targetDistance: CGFloat
    }

    case updateValue(UpdateValueConfig)
    case scrollTo

    var description: String {
        switch self {
        case let .updateValue(config):
            return "updateValue(\(config.targetDistance))"
        case .scrollTo:
            return "scrollTo"
        }
    }
}

/// Deferred mutation that synchronizes scroll state bindings or scroll position targets.
protocol ScrollStateRequest: CustomStringConvertible {
    var id: ObjectIdentifier { get }
    var kind: ScrollStateRequestKind { get }
    var transaction: Transaction { get }
    var hasUpdate: Bool { get }

    mutating func updateScrollable(_ scrollable: Attribute<any Scrollable>)
    mutating func update() -> Bool
}

extension ScrollStateRequest {
    mutating func updateScrollable(_ scrollable: Attribute<any Scrollable>) {}

    func overrides(_ other: (any ScrollStateRequest)?) -> Bool {
        guard let other else { return true }
        return id == other.id && kind == other.kind
    }
}

/// Writes a newly observed visible scroll position back into its binding.
struct UpdateScrollStateRequest: ScrollStateRequest {
    var binding: Binding<ScrollPosition>
    var newPosition: ScrollPosition
    var isVisible: Bool
    var targetDistance: CGFloat

    var id: ObjectIdentifier {
        ObjectIdentifier(binding.location)
    }

    var kind: ScrollStateRequestKind {
        .updateValue(.init(targetDistance: targetDistance))
    }

    var transaction: Transaction {
        var transaction = binding.transaction
        transaction.isScrollStateValueUpdate = true
        transaction.animation = nil
        return transaction
    }

    var hasUpdate: Bool {
        isVisible && binding.wrappedValue.wantsUpdate(toPosition: newPosition)
    }

    var description: String {
        "UpdateScrollStateRequest(id: \(id), hasUpdate: \(hasUpdate))"
    }

    mutating func update() -> Bool {
        guard hasUpdate else { return false }
        let scopedTransaction = transaction
        Transaction.withScopedThreadTransaction(scopedTransaction) {
            binding.location.setValue(newPosition, transaction: Transaction.current)
        }
        return true
    }
}

/// Marks a bound scroll position as user-positioned after a direct scroll interaction.
struct PositionedByUserScrollStateRequest: ScrollStateRequest {
    var binding: Binding<ScrollPosition>
    var id: ObjectIdentifier
    var currentPosition: ScrollPosition
    var positionedByUserPosition: ScrollPosition

    var kind: ScrollStateRequestKind {
        .updateValue(.init(targetDistance: 0))
    }

    var transaction: Transaction {
        var transaction = binding.transaction
        transaction.isScrollStateValueUpdate = true
        transaction.animation = nil
        return transaction
    }

    var hasUpdate: Bool {
        binding.wrappedValue.wantsUpdate(toPosition: positionedByUserPosition)
    }

    var description: String {
        "PositionedByUserScrollStateRequest(id: \(id), hasUpdate: \(hasUpdate))"
    }

    init(binding: Binding<ScrollPosition>) {
        self.binding = binding
        self.id = ObjectIdentifier(binding.location)
        self.currentPosition = binding.wrappedValue
        var positioned = currentPosition
        positioned.isPositionedByUser = true
        self.positionedByUserPosition = positioned
    }

    mutating func update() -> Bool {
        let scopedTransaction = transaction
        Transaction.withScopedThreadTransaction(scopedTransaction) {
            binding.location.setValue(positionedByUserPosition, transaction: Transaction.current)
        }
        return true
    }
}

/// Applies a bound scroll position change to the current scrollable host.
struct ScrollToScrollStateRequest: ScrollStateRequest {
    var binding: Binding<ScrollPosition>
    var anchor: UnitPoint?
    var id: ObjectIdentifier
    var value: ScrollPosition
    var baseTransaction: Transaction
    var scrollableAttribute: Attribute<any Scrollable>?

    var scrollable: (any Scrollable)? {
        scrollableAttribute?.value
    }

    var transaction: Transaction {
        var transaction = baseTransaction
        if let anchor {
            transaction.scrollTargetAnchor = anchor
        }
        return transaction
    }

    var kind: ScrollStateRequestKind {
        .scrollTo
    }

    var hasUpdate: Bool {
        scrollable != nil
    }

    var description: String {
        "ScrollToScrollStateRequest(id: \(id), hasUpdate: \(hasUpdate))"
    }

    init(
        binding: Binding<ScrollPosition>,
        anchor: UnitPoint?,
        id: ObjectIdentifier,
        value: ScrollPosition,
        baseTransaction: Transaction
    ) {
        self.binding = binding
        self.anchor = anchor
        self.id = id
        self.value = value
        self.baseTransaction = baseTransaction
        self.scrollableAttribute = nil
    }

    mutating func updateScrollable(_ scrollable: Attribute<any Scrollable>) {
        self.scrollableAttribute = scrollable
    }

    mutating func update() -> Bool {
        guard let scrollable else { return false }
        let didScroll = Transaction.withScopedThreadTransaction(transaction) {
            scrollable.scrollToPosition(value)
        }
        guard didScroll else { return false }
        binding.wrappedValue = value
        return true
    }
}

/// Preference channel for scroll state requests emitted by scrollable content.
struct UpdateScrollStateRequestKey: PreferenceKey {
    static var defaultValue: [any ScrollStateRequest] { [] }

    static func reduce(
        value: inout [any ScrollStateRequest],
        nextValue: () -> [any ScrollStateRequest]
    ) {
        value.append(contentsOf: nextValue())
    }
}

/// Consumes pending scroll requests and dispatches them through the update queue.
struct ScrollStateEnqueueRequests: StatefulRule {
    typealias Value = Void

    var phaseState: Attribute<ScrollPhaseState>
    var scrollable: Attribute<any Scrollable>
    var inputs: _ViewInputs
    var outputs: _ViewOutputs
    var requestStore: MutableBox<[ObjectIdentifier: any ScrollStateRequest]>
    var previousPhase: ScrollPhase?

    var requests: [ObjectIdentifier: any ScrollStateRequest] {
        get { requestStore.value }
        set { requestStore.value = newValue }
    }

    init(
        phaseState: Attribute<ScrollPhaseState>,
        scrollable: Attribute<any Scrollable>,
        inputs: _ViewInputs,
        outputs: _ViewOutputs
    ) {
        self.phaseState = phaseState
        self.scrollable = scrollable
        self.inputs = inputs
        self.outputs = outputs
        self.requestStore = MutableBox([:])
        self.previousPhase = nil
    }

    mutating func updateValue() {
        let phaseState = phaseState.value
        let pendingRequests = updateRequests(for: phaseState)

        guard phaseState.shouldUpdateValue else {
            _AGGraph.setStatefulOutput(())
            return
        }

        enqueueRequests(pendingRequests)
        _AGGraph.setStatefulOutput(())
    }

    mutating func updateRequests(for phaseState: ScrollPhaseState) -> [any ScrollStateRequest] {
        if let requestAttr = inputs.base.updateScrollStateRequest.attribute,
           let request = requestAttr.value {
            previousPhase = phaseState.phase
            return [request]
        }
        return adjustedUpdateRequests(for: phaseState)
    }

    mutating func adjustedUpdateRequests(for phaseState: ScrollPhaseState) -> [any ScrollStateRequest] {
        defer { previousPhase = phaseState.phase }

        if let preferenceAttr = outputs.preferences.value(for: UpdateScrollStateRequestKey.self) {
            let requests = Attribute<UpdateScrollStateRequestKey.Value>(preferenceAttr).value
            if !requests.isEmpty {
                return requests
            }
        }

        guard phaseState.shouldUpdateValue,
              previousPhase != phaseState.phase,
              let bindingAttr = inputs.base.scrollPositionBinding(kind: .scrollContent).attribute else {
            return []
        }

        let request = PositionedByUserScrollStateRequest(binding: bindingAttr.value)
        return request.hasUpdate ? [request] : []
    }

    mutating func enqueueRequests(_ newRequests: [any ScrollStateRequest]) {
        guard !newRequests.isEmpty else { return }

        let scrollable = scrollable
        let requestStore = requestStore
        Update.enqueueAction(reason: 0x11) {
            for var request in newRequests {
                request.updateScrollable(scrollable)
                _ = Transaction.withScopedThreadTransaction(request.transaction) {
                    request.update()
                }
                requestStore.value[request.id] = request
            }
        }
    }
}

/// Converts visible scrollable collection geometry into binding update requests.
struct ScrollStateRequestTransform: StatefulRule {
    typealias Value = [any ScrollStateRequest]
    private static let targetDistanceUpdateTolerance = CGFloat(0.1)

    var collection: Attribute<any ScrollableCollection>
    var layoutDirection: Attribute<LayoutDirection>
    var inputs: _ViewInputs
    var request: (any ScrollStateRequest)?
    var phaseRawValue: UInt32?

    init(collection: Attribute<any ScrollableCollection>, inputs: _ViewInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollStateRequestTransform.init(collection:inputs:) called outside an active _AGGraph context.")
        }
        self.collection = collection
        self.layoutDirection = graph.makeRule {
            inputs.base.cachedEnvironment.value.environment.value.layoutDirection
        }
        self.inputs = inputs
        self.request = nil
        self.phaseRawValue = nil
    }

    mutating func updateValue() {
        let currentPhase = inputs.base.phase.value
        if phaseRawValue != currentPhase.rawValue {
            request = nil
            phaseRawValue = currentPhase.rawValue
        }

        guard let binding = inputs.base.scrollPositionBinding(kind: .scrollContent).attribute?.value else {
            _AGGraph.setStatefulOutput([])
            return
        }

        let anchor = inputs.base.scrollPositionAnchor(kind: .scrollContent).attribute?.value
        let collection = collection.value
        findClosestSubview(
            in: collection,
            to: currentVisibleRect(),
            binding: binding,
            anchor: anchor,
            layoutDirection: layoutDirection.value
        )

        if let request {
            _AGGraph.setStatefulOutput([request])
        } else {
            _AGGraph.setStatefulOutput([])
        }
    }

    mutating func findClosestSubview(
        in collection: any ScrollableCollection,
        to rect: CGRect,
        binding: Binding<ScrollPosition>,
        anchor: UnitPoint?,
        layoutDirection: LayoutDirection
    ) {
        var selected: (id: AnyHashable, distance: CGFloat)?

        collection.forEachVisibleSubview { subview, stop in
            guard let id = subview.id.canonicalID.explicitID else {
                return
            }

            let candidateRect = subview.frame.convertedToScrollCoordinateSpace(
                using: subview.transform
            )
            let distance = candidateRect.distance(to: rect)
            if selected == nil || distance < selected!.distance {
                selected = (id, distance)
            }
            stop = false
        }

        guard let selected else {
            return
        }
        updateRequest(
            id: selected.id,
            targetDistance: selected.distance,
            isVisible: true,
            binding: binding,
            anchor: anchor,
            layoutDirection: layoutDirection
        )
    }

    mutating func updateRequest(
        id: AnyHashable,
        targetDistance: CGFloat,
        isVisible: Bool,
        binding: Binding<ScrollPosition>,
        anchor: UnitPoint?,
        layoutDirection: LayoutDirection
    ) {
        let current = binding.wrappedValue
        guard current.matches(id: id) else {
            request = nil
            return
        }

        let newPosition = ScrollPosition(_scrollPositionID: id, anchor: anchor)
        let newRequest = UpdateScrollStateRequest(
            binding: binding,
            newPosition: newPosition,
            isVisible: isVisible,
            targetDistance: targetDistance
        )

        guard shouldUpdate(to: newRequest) else {
            return
        }
        request = newRequest
    }

    func shouldUpdate(to newRequest: UpdateScrollStateRequest) -> Bool {
        guard let stored = request as? UpdateScrollStateRequest else {
            return true
        }
        if !stored.newPosition.hasSameStorage(as: newRequest.newPosition) {
            return true
        }
        if stored.isVisible != newRequest.isVisible {
            return true
        }
        return abs(stored.targetDistance - newRequest.targetDistance) >= Self.targetDistanceUpdateTolerance
    }

    private func currentVisibleRect() -> CGRect {
        var rect = CGRect(origin: .zero, size: inputs.size.value.value)
        inputs.transform.value.forEach(inverted: false) { item, stop in
            if case let .scrollGeometry(geometry, _) = item {
                rect = CGRect(origin: geometry.contentOffset, size: geometry.containerSize)
                stop = true
            }
        }
        return rect
    }
}

private extension CGRect {
    func convertedToScrollCoordinateSpace(using transform: ViewTransform) -> CGRect {
        var points = [
            CGPoint(x: minX, y: minY),
            CGPoint(x: maxX, y: minY),
            CGPoint(x: maxX, y: maxY),
            CGPoint(x: minX, y: maxY),
        ]
        transform.convertGlobal(from: .local, points: &points)
        return CGRect(cornerPoints: points)
    }

    init(cornerPoints points: [CGPoint]) {
        guard let first = points.first else {
            self = .null
            return
        }

        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        self = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func distance(to other: CGRect) -> CGFloat {
        let dx = midX - other.midX
        let dy = midY - other.midY
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Selects whether a scroll-position input targets the scroll view or its content.
enum ScrollStateInputKind: Hashable {
    case scrollView
    case scrollContent
}

/// Stores either a fixed scroll position or a mutable scroll-position binding.
enum ScrollPositionStorage {
    case value(Attribute<ScrollPosition>)
    case binding(Attribute<Binding<ScrollPosition>>)

    var value: Attribute<ScrollPosition>? {
        guard case let .value(attribute) = self else { return nil }
        return attribute
    }

    var binding: Attribute<Binding<ScrollPosition>>? {
        guard case let .binding(attribute) = self else { return nil }
        return attribute
    }
}

/// Projection from a scroll-position binding to a typed optional id binding.
struct ScrollPositionToValue<Value>: Projection where Value: Hashable {
    var anchor: UnitPoint?

    init(_ binding: Binding<Value?>, anchor: UnitPoint?) {
        self.anchor = anchor
    }

    func get(base: ScrollPosition) -> Value? {
        base._viewID(type: Value.self)
    }

    func set(base: inout ScrollPosition, newValue: Value?) {
        if let newValue {
            base._scrollTo(id: newValue, anchor: anchor)
        } else {
            base = ScrollPosition(_scrollPositionIDType: Value.self)
        }
    }
}

/// Projection from a typed optional id binding back to a scroll-position value.
struct ValueToScrollPosition<Value>: Projection where Value: Hashable {
    var anchor: UnitPoint?

    init(_ binding: Binding<Value?>, anchor: UnitPoint?) {
        self.anchor = anchor
    }

    func get(base: Value?) -> ScrollPosition {
        if let base {
            return ScrollPosition(_scrollPositionID: base, anchor: anchor)
        }
        return ScrollPosition(_scrollPositionIDType: Value.self)
    }

    func set(base: inout Value?, newValue: ScrollPosition) {
        let nextValue = newValue._viewID(type: Value.self)
        if base != nextValue {
            base = nextValue
        }
    }
}

/// Installs a fixed scroll position value into graph inputs for a scroll view.
public struct ScrollValueModifier: ViewModifier, _GraphInputsModifier {
    public typealias Body = Never

    public var value: ScrollPosition

    public init(value: ScrollPosition) {
        self.value = value
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }
        inputs.resetScrollPosition(kind: .scrollView)
        let value = graph.makeRule {
            modifier._attribute.value.value
        }
        inputs.setScrollPosition(storage: .value(value), kind: .scrollView)
    }
}

/// Installs a binding-backed scroll position and emits scroll state requests when it changes.
public struct ScrollPositionBindingModifier: ViewModifier, _GraphInputsModifier {
    public typealias Body = Never

    public var binding: Binding<ScrollPosition>
    public var anchor: UnitPoint?

    public init(binding: Binding<ScrollPosition>, anchor: UnitPoint?) {
        self.binding = binding
        self.anchor = anchor
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeInputs called outside an active _AGGraph context.")
        }

        let binding = graph.makeRule {
            modifier._attribute.value.binding
        }
        let anchor = graph.makeRule {
            modifier._attribute.value.anchor
        }
        let adjustedAnchor = graph.makeRule(AdjustedAnchor(anchor: anchor))
        let request = graph.makeStatefulRule(MakeRequest(
            binding: binding,
            anchor: adjustedAnchor,
            transaction: inputs.transaction
        ))

        inputs.resetScrollPosition(kind: .scrollView)
        inputs.setScrollPositionAnchor(OptionalAttribute(adjustedAnchor), kind: .scrollView)
        inputs.setScrollPosition(storage: .binding(binding), kind: .scrollView)
        inputs.updateScrollStateRequest = OptionalAttribute(request)
    }

    private struct AdjustedAnchor: Rule {
        typealias Value = UnitPoint?

        var anchor: Attribute<UnitPoint?>

        func updateValue() -> UnitPoint? {
            let value = anchor.value
            guard !_SemanticFeature<Semantics_v6>.isEnabled else {
                return value
            }
            return value ?? .zero
        }
    }

    private struct MakeRequest: StatefulRule {
        typealias Value = (any ScrollStateRequest)?

        var binding: Attribute<Binding<ScrollPosition>>
        var anchor: Attribute<UnitPoint?>
        var transaction: Attribute<Transaction>
        var previousValue: ScrollPosition?

        mutating func updateValue() {
            let hadOutput = context.hasValue
            let binding = binding.value
            let value = binding.wrappedValue
            let baseTransaction = transaction.value

            defer { previousValue = binding.wrappedValue }

            guard hadOutput else {
                _AGGraph.setStatefulOutput(Optional<any ScrollStateRequest>.none)
                return
            }
            guard !baseTransaction.isScrollStateValueUpdate else {
                _AGGraph.setStatefulOutput(Optional<any ScrollStateRequest>.none)
                return
            }
            if let previousValue,
               previousValue == value {
                _AGGraph.setStatefulOutput(Optional<any ScrollStateRequest>.none)
                return
            }

            let request = ScrollToScrollStateRequest(
                binding: binding,
                anchor: anchor.value,
                id: ObjectIdentifier(binding.location),
                value: value,
                baseTransaction: baseTransaction
            )
            _AGGraph.setStatefulOutput(Optional<any ScrollStateRequest>.some(request))
        }
    }
}

extension _GraphInputs {
    var scrollable: OptionalAttribute<any Scrollable> {
        get { self[ScrollableKey.self] }
        set { self[ScrollableKey.self] = newValue }
    }

    var updateScrollStateRequest: OptionalAttribute<(any ScrollStateRequest)?> {
        get { self[UpdateScrollStateRequestInputKey.self] }
        set { self[UpdateScrollStateRequestInputKey.self] = newValue }
    }

    mutating func setScrollPosition(storage: ScrollPositionStorage?, kind: ScrollStateInputKind) {
        switch kind {
        case .scrollView:
            self[ScrollPositionKey.self] = storage
        case .scrollContent:
            self[ContentScrollPositionKey.self] = storage
        }
    }

    mutating func resetScrollPosition(kind: ScrollStateInputKind) {
        setScrollPosition(storage: nil, kind: kind)
        setScrollPositionAnchor(OptionalAttribute(), kind: kind)
    }

    func scrollPositionValue() -> OptionalAttribute<ScrollPosition> {
        guard case let .value(attribute) = self[ScrollPositionKey.self] else {
            return OptionalAttribute()
        }
        return OptionalAttribute(attribute)
    }

    func scrollPositionBinding(kind: ScrollStateInputKind) -> OptionalAttribute<Binding<ScrollPosition>> {
        let storage: ScrollPositionStorage?
        switch kind {
        case .scrollView:
            storage = self[ScrollPositionKey.self]
        case .scrollContent:
            storage = self[ContentScrollPositionKey.self]
        }
        guard case let .binding(attribute) = storage else {
            return OptionalAttribute()
        }
        return OptionalAttribute(attribute)
    }

    func hasValueScrollPosition(kind: ScrollStateInputKind) -> Bool {
        let storage: ScrollPositionStorage?
        switch kind {
        case .scrollView:
            storage = self[ScrollPositionKey.self]
        case .scrollContent:
            storage = self[ContentScrollPositionKey.self]
        }
        guard case .value = storage else { return false }
        return true
    }

    mutating func setScrollPositionAnchor(
        _ attribute: OptionalAttribute<UnitPoint?>,
        kind: ScrollStateInputKind
    ) {
        switch kind {
        case .scrollView:
            self[ScrollPositionAnchorKey.self] = attribute
        case .scrollContent:
            self[ContentScrollPositionAnchorKey.self] = attribute
        }
    }

    func scrollPositionAnchor(kind: ScrollStateInputKind) -> OptionalAttribute<UnitPoint?> {
        switch kind {
        case .scrollView:
            return self[ScrollPositionAnchorKey.self]
        case .scrollContent:
            return self[ContentScrollPositionAnchorKey.self]
        }
    }
}

extension _ViewInputs {
    var scrollable: OptionalAttribute<any Scrollable> {
        get { base.scrollable }
        set { base.scrollable = newValue }
    }

    var weakScrollable: WeakAttribute<any Scrollable> {
        guard let scrollable = scrollable.attribute else {
            return WeakAttribute()
        }
        return scrollable.asWeak()
    }
}

extension View {
    public func scrollPosition(
        _ position: Binding<ScrollPosition>,
        anchor: UnitPoint? = nil
    ) -> some View {
        modifier(ScrollPositionBindingModifier(binding: position, anchor: anchor))
    }

    public func scrollPosition<ID>(
        id: Binding<ID?>,
        anchor: UnitPoint? = nil
    ) -> some View where ID: Hashable {
        let projection = ValueToScrollPosition(id, anchor: anchor)
        return scrollPosition(id.projecting(projection), anchor: anchor)
    }
}

/// Graph input key for the nearest scrollable host.
private struct ScrollableKey: GraphInput {
    static var defaultValue: OptionalAttribute<any Scrollable> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ a: OptionalAttribute<any Scrollable>,
        _ b: OptionalAttribute<any Scrollable>
    ) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

/// Graph input key for scroll-view-level scroll position storage.
private struct ScrollPositionKey: GraphInput {
    static var defaultValue: ScrollPositionStorage? {
        nil
    }

    static func valuesEqual(_ a: ScrollPositionStorage?, _ b: ScrollPositionStorage?) -> Bool {
        scrollPositionStorageValuesEqual(a, b)
    }
}

/// Graph input key for scroll-content-level scroll position storage.
private struct ContentScrollPositionKey: GraphInput {
    static var defaultValue: ScrollPositionStorage? {
        nil
    }

    static func valuesEqual(_ a: ScrollPositionStorage?, _ b: ScrollPositionStorage?) -> Bool {
        scrollPositionStorageValuesEqual(a, b)
    }
}

/// Graph input key for the scroll-view-level target anchor.
private struct ScrollPositionAnchorKey: GraphInput {
    static var defaultValue: OptionalAttribute<UnitPoint?> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ a: OptionalAttribute<UnitPoint?>,
        _ b: OptionalAttribute<UnitPoint?>
    ) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

/// Graph input key for the scroll-content-level target anchor.
private struct ContentScrollPositionAnchorKey: GraphInput {
    static var defaultValue: OptionalAttribute<UnitPoint?> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ a: OptionalAttribute<UnitPoint?>,
        _ b: OptionalAttribute<UnitPoint?>
    ) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

private func scrollPositionStorageValuesEqual(
    _ a: ScrollPositionStorage?,
    _ b: ScrollPositionStorage?
) -> Bool {
    switch (a, b) {
    case (nil, nil):
        return true
    case let (.value(lhs)?, .value(rhs)?):
        return lhs.identifier == rhs.identifier
    case let (.binding(lhs)?, .binding(rhs)?):
        return lhs.identifier == rhs.identifier
    default:
        return false
    }
}

/// Graph input key carrying a pending scroll state request from modifiers to containers.
private struct UpdateScrollStateRequestInputKey: GraphInput {
    static var defaultValue: OptionalAttribute<(any ScrollStateRequest)?> {
        OptionalAttribute()
    }

    static func valuesEqual(
        _ a: OptionalAttribute<(any ScrollStateRequest)?>,
        _ b: OptionalAttribute<(any ScrollStateRequest)?>
    ) -> Bool {
        a.base.identifier == b.base.identifier
    }
}

/// Transaction flag for binding writes produced by scroll state synchronization.
private struct IsScrollStateValueUpdateKey: TransactionKey {
    static let defaultValue = false
}

extension Transaction {
    var isScrollStateValueUpdate: Bool {
        get { self[IsScrollStateValueUpdateKey.self] }
        set { self[IsScrollStateValueUpdateKey.self] = newValue }
    }
}
