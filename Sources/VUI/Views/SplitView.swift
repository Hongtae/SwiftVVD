//
//  File: SplitView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Observation
import VVD

enum InspectorColumnWidth {
    case fixed(CGFloat)
    case flexible(min: CGFloat?, ideal: CGFloat, max: CGFloat?)
}

struct InspectorState {
    var isPresented: StateOrBinding<Bool>
    var isActive: Bool
    var width: InspectorColumnWidth?
}

public struct HSplitView<Content>: ~Sendable where Content: View {
    var content: Content
    var inspectorState: InspectorState?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.inspectorState = nil
    }
}

extension HSplitView: View {
    public typealias Body = Never
}

extension HSplitView: PrimitiveView {}

extension HSplitView: PubliclyPrimitiveView {
    var internalBody: some View {
        _VariadicView.Tree(
            root: _SplitViewContainer(
                axis: .horizontal,
                inspectorState: inspectorState
            ),
            content: content
        )
    }
}

public struct VSplitView<Content>: ~Sendable where Content: View {
    var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

extension VSplitView: View {
    public typealias Body = Never
}

extension VSplitView: PrimitiveView {}

extension VSplitView: PubliclyPrimitiveView {
    var internalBody: some View {
        _VariadicView.Tree(
            root: _SplitViewContainer(
                axis: .vertical,
                inspectorState: nil
            ),
            content: content
        )
    }
}

public struct _SplitViewContainer: _VariadicView_UnaryViewRoot, ~Sendable {
    var axis: Axis
    var inspectorState: InspectorState?

    public func body(children: _VariadicView.Children) -> some View {
        SystemSplitView(
            axis: axis,
            content: children.content,
            inspectorState: inspectorState
        )
    }
}

private struct SystemSplitView: View {
    var axis: Axis
    var content: _ViewList_Backing
    var inspectorState: InspectorState?

    var body: some View {
        SplitViewBody(
            axis: axis,
            children: _VariadicView_Children(
                list: content.list,
                contentSubgraph: nil
            )
        )
    }
}

private struct SplitViewPane: Identifiable {
    var index: Int
    var element: _VariadicView_Children.Element

    var id: AnyHashable { element.id }
}

private struct SplitViewDividerID: Hashable, @unchecked Sendable {
    var leading: AnyHashable
    var trailing: AnyHashable
}

@Observable
private final class SplitViewPositionState {
    var offsets: [SplitViewDividerID: CGFloat] = [:]

    @ObservationIgnored
    private var dragOrigins: [SplitViewDividerID: CGFloat] = [:]

    func update(
        divider: SplitViewDividerID,
        translation: CGFloat,
        ended: Bool
    ) {
        let origin = dragOrigins[divider] ?? offsets[divider, default: 0]
        if dragOrigins[divider] == nil {
            dragOrigins[divider] = origin
        }
        offsets[divider] = origin + translation
        if ended {
            dragOrigins.removeValue(forKey: divider)
        }
    }
}

private final class SplitViewCursorTarget {
    weak var host: WindowController?
    // A moving divider can replace its hover responder. The captured drag
    // keeps cursor ownership independently until its terminal event.
    private var hoveredDividers: Set<SplitViewDividerID> = []
    private var draggedDividers: Set<SplitViewDividerID> = []
    private var publishedAxis: Axis?

    func updateHover(
        divider: SplitViewDividerID,
        axis: Axis,
        isActive: Bool
    ) {
        if isActive {
            hoveredDividers.insert(divider)
        } else {
            hoveredDividers.remove(divider)
        }
        publish(axis: axis)
    }

    func updateDrag(
        divider: SplitViewDividerID,
        axis: Axis,
        isActive: Bool
    ) {
        if isActive {
            draggedDividers.insert(divider)
        } else {
            draggedDividers.remove(divider)
        }
        publish(axis: axis)
    }

    private func publish(axis: Axis) {
        let nextAxis = hoveredDividers.isEmpty && draggedDividers.isEmpty
            ? nil
            : axis
        guard nextAxis != publishedAxis else { return }
        publishedAxis = nextAxis
        let cursor: Cursor? = nextAxis.map {
            $0 == .horizontal ? .resizeLeftRight : .resizeUpDown
        }
        host?.requestSplitViewCursor(cursor)
    }
}

private struct SplitViewCursorHostModifier:
    ViewModifier, MultiViewModifier, PrimitiveViewModifier
{
    var target: SplitViewCursorTarget

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard _AGGraph.current != nil else {
            fatalError(
                "SplitViewCursorHostModifier._makeView called outside an active _AGGraph context."
            )
        }
        modifier._attribute.value.target.host =
            EventBindingManager.current?.host as? WindowController
        return body(_Graph(), inputs)
    }

    typealias Body = Never
}

private struct SplitViewBody: View {
    var axis: Axis
    var children: _VariadicView_Children

    @State private var positions = SplitViewPositionState()
    @State private var cursorTarget = SplitViewCursorTarget()

    var body: some View {
        let panes = children.indices.map {
            SplitViewPane(index: $0, element: children[$0])
        }
        let offsets = positions.offsets

        SplitViewLayout(axis: axis, offsets: offsets) {
            ForEach(panes) { pane in
                pane.element
                if pane.index + 1 < panes.count {
                    let divider = SplitViewDividerID(
                        leading: pane.id,
                        trailing: panes[pane.index + 1].id
                    )
                    SplitViewDivider(
                        axis: axis,
                        id: divider,
                        positions: positions,
                        cursorTarget: cursorTarget
                    )
                    .layoutValue(
                        key: SplitViewDividerLayoutKey.self,
                        value: divider
                    )
                }
            }
        }
        .modifier(SplitViewCursorHostModifier(target: cursorTarget))
    }
}

private struct SplitViewDivider: View {
    var axis: Axis
    var id: SplitViewDividerID
    var positions: SplitViewPositionState
    var cursorTarget: SplitViewCursorTarget

    var body: some View {
        ZStack {
            _ShapeView(
                shape: Rectangle(),
                style: SeparatorShapeStyle()
            )
            .frame(
                width: axis == .horizontal ? SplitViewLayout.dividerThickness : nil,
                height: axis == .vertical ? SplitViewLayout.dividerThickness : nil
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            cursorTarget.updateHover(
                divider: id,
                axis: axis,
                isActive: hovering
            )
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    cursorTarget.updateDrag(
                        divider: id,
                        axis: axis,
                        isActive: true
                    )
                    positions.update(
                        divider: id,
                        translation: axis == .horizontal
                            ? value.translation.width
                            : value.translation.height,
                        ended: false
                    )
                }
                .onEnded { value in
                    positions.update(
                        divider: id,
                        translation: axis == .horizontal
                            ? value.translation.width
                            : value.translation.height,
                        ended: true
                    )
                    cursorTarget.updateDrag(
                        divider: id,
                        axis: axis,
                        isActive: false
                    )
                }
        )
    }
}

private struct SplitViewDividerLayoutKey: LayoutValueKey {
    static var defaultValue: SplitViewDividerID? { nil }
}

struct SplitViewLayout: Layout {
    static let dividerThickness: CGFloat = 1
    static let dividerHitThickness: CGFloat = 5

    struct PaneMetric: Equatable, Sendable {
        var minimum: CGFloat
        var ideal: CGFloat
        var maximum: CGFloat
        var priority: Double

        init(
            minimum: CGFloat,
            ideal: CGFloat,
            maximum: CGFloat,
            priority: Double = 0
        ) {
            self.minimum = minimum
            self.ideal = ideal
            self.maximum = maximum
            self.priority = priority
        }
    }

    var axis: Axis
    private var offsets: [SplitViewDividerID: CGFloat]

    fileprivate init(
        axis: Axis,
        offsets: [SplitViewDividerID: CGFloat]
    ) {
        self.axis = axis
        self.offsets = offsets
    }

    static func resolveLengths(
        available: CGFloat?,
        metrics: [PaneMetric],
        dividerOffsets: [CGFloat]
    ) -> [CGFloat] {
        guard !metrics.isEmpty else { return [] }

        var lengths: [CGFloat]
        if let available, available.isFinite {
            let total = max(0, available)
            var remaining = total
            var unresolved = metrics.indices.map { $0 }
            unresolved.sort { lhs, rhs in
                let left = metrics[lhs]
                let right = metrics[rhs]
                if left.priority != right.priority {
                    return left.priority > right.priority
                }
                let leftFlexibility = left.maximum - left.minimum
                let rightFlexibility = right.maximum - right.minimum
                if leftFlexibility.isFinite != rightFlexibility.isFinite {
                    return leftFlexibility.isFinite
                }
                if leftFlexibility.isFinite,
                   leftFlexibility != rightFlexibility {
                    return leftFlexibility < rightFlexibility
                }
                if !leftFlexibility.isFinite,
                   left.minimum != right.minimum {
                    return left.minimum > right.minimum
                }
                return lhs < rhs
            }

            lengths = Array(repeating: 0, count: metrics.count)
            for (offset, index) in unresolved.enumerated() {
                let count = CGFloat(unresolved.count - offset)
                let proposed = max(0, remaining / count)
                let metric = metrics[index]
                let length = min(
                    max(proposed, metric.minimum),
                    metric.maximum
                )
                lengths[index] = length
                remaining -= length
            }
        } else {
            lengths = metrics.map {
                min(max($0.ideal, $0.minimum), $0.maximum)
            }
        }

        for divider in dividerOffsets.indices {
            guard divider < lengths.count - 1 else { break }
            let requested = dividerOffsets[divider]
            let leading = metrics[divider]
            let trailing = metrics[divider + 1]
            let minimumDelta = max(
                leading.minimum - lengths[divider],
                lengths[divider + 1] - trailing.maximum
            )
            let maximumDelta = min(
                leading.maximum - lengths[divider],
                lengths[divider + 1] - trailing.minimum
            )
            let delta = min(max(requested, minimumDelta), maximumDelta)
            lengths[divider] += delta
            lengths[divider + 1] -= delta
        }
        return lengths
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let paneIndices = self.paneIndices(in: subviews)
        guard !paneIndices.isEmpty else { return .zero }
        let crossProposal = cross(of: proposal)
        let metrics = paneIndices.map {
            metric(for: subviews[$0], crossProposal: crossProposal)
        }
        let dividerCount = max(0, paneIndices.count - 1)
        let proposedMajor = major(of: proposal).map {
            $0 - CGFloat(dividerCount) * Self.dividerThickness
        }
        let lengths = Self.resolveLengths(
            available: proposedMajor,
            metrics: metrics,
            dividerOffsets: dividerOffsets(in: subviews)
        )
        let cross = crossProposal ?? paneIndices.enumerated().reduce(0) {
            result, item in
            let size = subviews[item.element].sizeThatFits(
                self.proposal(major: lengths[item.offset], cross: nil)
            )
            return max(result, self.cross(of: size))
        }
        let major = lengths.reduce(0, +)
            + CGFloat(dividerCount) * Self.dividerThickness
        return size(major: major, cross: cross)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let panes = paneIndices(in: subviews)
        guard !panes.isEmpty else { return }
        let crossLength = cross(of: bounds.size)
        let metrics = panes.map {
            metric(for: subviews[$0], crossProposal: crossLength)
        }
        let dividerCount = max(0, panes.count - 1)
        let available = major(of: bounds.size)
            - CGFloat(dividerCount) * Self.dividerThickness
        let lengths = Self.resolveLengths(
            available: available,
            metrics: metrics,
            dividerOffsets: dividerOffsets(in: subviews)
        )
        let dividers = dividerIndices(in: subviews)
        var majorPosition = major(of: bounds.origin)

        for paneOffset in panes.indices {
            let paneProposal = proposal(
                major: lengths[paneOffset],
                cross: crossLength
            )
            subviews[panes[paneOffset]].place(
                at: point(
                    major: majorPosition,
                    cross: cross(of: bounds.origin)
                ),
                anchor: .topLeading,
                proposal: paneProposal
            )
            majorPosition += lengths[paneOffset]

            if paneOffset < dividers.count {
                let hitOrigin = majorPosition
                    - (Self.dividerHitThickness - Self.dividerThickness) / 2
                subviews[dividers[paneOffset]].place(
                    at: point(
                        major: hitOrigin,
                        cross: cross(of: bounds.origin)
                    ),
                    anchor: .topLeading,
                    proposal: proposal(
                        major: Self.dividerHitThickness,
                        cross: crossLength
                    )
                )
                majorPosition += Self.dividerThickness
            }
        }
    }

    private func paneIndices(in subviews: Subviews) -> [Int] {
        subviews.indices.filter {
            subviews[$0][SplitViewDividerLayoutKey.self] == nil
        }
    }

    private func dividerIndices(in subviews: Subviews) -> [Int] {
        subviews.indices.filter {
            subviews[$0][SplitViewDividerLayoutKey.self] != nil
        }
    }

    private func dividerOffsets(in subviews: Subviews) -> [CGFloat] {
        dividerIndices(in: subviews).map {
            guard let id = subviews[$0][SplitViewDividerLayoutKey.self] else {
                return 0
            }
            return offsets[id, default: 0]
        }
    }

    private func metric(
        for subview: LayoutSubview,
        crossProposal: CGFloat?
    ) -> PaneMetric {
        let minimum = sanitized(
            major(of: subview.sizeThatFits(
                proposal(major: 0, cross: crossProposal)
            )),
            fallback: 0
        )
        let maximum = max(
            minimum,
            sanitized(
                major(of: subview.sizeThatFits(
                    proposal(major: .infinity, cross: crossProposal)
                )),
                fallback: .infinity
            )
        )
        let ideal = min(
            max(
                sanitized(
                    major(of: subview.sizeThatFits(
                        proposal(major: nil, cross: crossProposal)
                    )),
                    fallback: minimum
                ),
                minimum
            ),
            maximum
        )
        return PaneMetric(
            minimum: minimum,
            ideal: ideal,
            maximum: maximum,
            priority: subview.priority
        )
    }

    private func sanitized(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isNaN || value < 0 ? fallback : value
    }

    private func proposal(major: CGFloat?, cross: CGFloat?) -> ProposedViewSize {
        switch axis {
        case .horizontal:
            ProposedViewSize(width: major, height: cross)
        case .vertical:
            ProposedViewSize(width: cross, height: major)
        }
    }

    private func size(major: CGFloat, cross: CGFloat) -> CGSize {
        switch axis {
        case .horizontal:
            CGSize(width: major, height: cross)
        case .vertical:
            CGSize(width: cross, height: major)
        }
    }

    private func point(major: CGFloat, cross: CGFloat) -> CGPoint {
        switch axis {
        case .horizontal:
            CGPoint(x: major, y: cross)
        case .vertical:
            CGPoint(x: cross, y: major)
        }
    }

    private func major(of size: CGSize) -> CGFloat {
        axis == .horizontal ? size.width : size.height
    }

    private func cross(of size: CGSize) -> CGFloat {
        axis == .horizontal ? size.height : size.width
    }

    private func major(of point: CGPoint) -> CGFloat {
        axis == .horizontal ? point.x : point.y
    }

    private func cross(of point: CGPoint) -> CGFloat {
        axis == .horizontal ? point.y : point.x
    }

    private func major(of proposal: ProposedViewSize) -> CGFloat? {
        axis == .horizontal ? proposal.width : proposal.height
    }

    private func cross(of proposal: ProposedViewSize) -> CGFloat? {
        axis == .horizontal ? proposal.height : proposal.width
    }
}
