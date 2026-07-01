//
//  File: ScrollGeometryState.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Preference payload that couples scroll geometry with its active axes and transform.
struct ScrollGeometryState: Equatable {
    var geometry: ScrollGeometry
    var scrollableAxes: Axis.Set
    var transformAttribute: WeakAttribute<ViewTransform>

    static var zero: ScrollGeometryState {
        ScrollGeometryState(
            geometry: ScrollGeometry(),
            scrollableAxes: [],
            transform: WeakAttribute()
        )
    }

    init(
        geometry: ScrollGeometry,
        scrollableAxes: Axis.Set,
        transform: WeakAttribute<ViewTransform>
    ) {
        self.geometry = geometry
        self.scrollableAxes = scrollableAxes
        self.transformAttribute = transform
    }

    var transform: ViewTransform? {
        guard let graph = _AGGraph.current,
              transformAttribute.isValid(in: graph) else {
            return nil
        }
        return transformAttribute.toStrong().value
    }
}

/// Collects scroll geometry states published by scroll containers.
struct ScrollGeometryPreferenceKey: PreferenceKey {
    static var defaultValue: [ScrollGeometryState] { [] }

    static func reduce(value: inout [ScrollGeometryState], nextValue: () -> [ScrollGeometryState]) {
        value.append(contentsOf: nextValue())
    }
}

/// Builds the one-element geometry preference for a concrete scroll container.
struct ScrollGeometryStateProvider: Rule {
    typealias Value = [ScrollGeometryState]

    var geometry: Attribute<ScrollGeometry>
    var scrollableAxes: Attribute<Axis.Set>
    var transform: Attribute<ViewTransform>

    init(
        geometry: Attribute<ScrollGeometry>,
        scrollableAxes: Attribute<Axis.Set>,
        transform: Attribute<ViewTransform>
    ) {
        self.geometry = geometry
        self.scrollableAxes = scrollableAxes
        self.transform = transform
    }

    func updateValue() -> [ScrollGeometryState] {
        [
            ScrollGeometryState(
                geometry: geometry.value,
                scrollableAxes: scrollableAxes.value,
                transform: transform.asWeak()
            )
        ]
    }
}
