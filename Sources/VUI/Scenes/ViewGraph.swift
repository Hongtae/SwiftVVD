//
//  File: ViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewGraphDelegate — receives view graph state change callbacks.
protocol ViewGraphDelegate: AnyObject {
    func setNeedsUpdate()
}

// ViewRendererHost — protocol for types that own a ViewGraph and drive rendering.
// TODO: Add valuesNeedingUpdate after ViewGraphRootValues is defined.
protocol ViewRendererHost: AnyObject {
    var viewGraph: ViewGraph { get }
}

// ViewGraphHostDelegate — lifecycle delegate for ViewGraphHost.
// TODO: Add lifecycle methods when needed.
protocol ViewGraphHostDelegate: AnyObject {}

// ViewGraphRenderDelegate — delegate for rendering callbacks.
// TODO: Add render callback methods when needed.
protocol ViewGraphRenderDelegate: AnyObject {}

// ViewGraphRootValueUpdater — delegate for root value update notifications.
// TODO: Add update callback methods when needed.
protocol ViewGraphRootValueUpdater: AnyObject {}

// ViewGraphHost — base class for view-graph lifecycle, display timing, and
// environment management.
// TODO: Add stored state as lifecycle, rendering, and update support grows.
// TODO: Implement display timing, update scheduling, and environment methods.
class ViewGraphHost {
    weak var delegate: (any ViewGraphHostDelegate)?

    // Returns self as the concrete ViewGraph.
    var viewGraph: ViewGraph { self as! ViewGraph }

    init() {}
}

// ViewGraph — view-level AG host.
// Stored directly by WindowController.viewGraph.
// Responsibilities include root view instantiation, output tracking, display
// list production, and event routing.
// TODO: Move view construction into AttributeGraph and register _makeView closures.
// TODO: Implement displayList() and connect it to the WindowContext render loop.
class ViewGraph: ViewGraphHost {
    weak var viewGraphDelegate: (any ViewGraphDelegate)?

    // Outputs — requested output bit flags (OptionSet, RawValue: UInt8).
    // Items: displayList, viewResponders, platformItemList, focus, layout,
    // defaults, and all.
    struct Outputs: OptionSet {
        let rawValue: UInt8
        static let displayList     = Outputs(rawValue: 1 << 0)
        static let viewResponders  = Outputs(rawValue: 1 << 1)
        static let platformItemList = Outputs(rawValue: 1 << 2)
        static let focus           = Outputs(rawValue: 1 << 3)
        static let layout          = Outputs(rawValue: 1 << 4)
        // defaults and all use placeholder raw values for now.
        static let defaults        = Outputs(rawValue: 0xFF)
        static let all             = Outputs(rawValue: 0xFF)
    }

    // NextUpdate — value type for update scheduling.
    // Stored by ViewGraph as nextUpdate: (views: NextUpdate, gestures: NextUpdate).
    struct NextUpdate {
        var time: Double = .infinity   // TODO: Replace with Time.
        var interval: Double = .infinity
        var reasons: Set<UInt32> = []

        mutating func at(_ t: Double) { time = t }
        mutating func interval(_ dt: Double, reason: UInt32? = nil) {
            self.interval = dt
            if let r = reason { reasons.insert(r) }
        }
        mutating func maxVelocity(_ v: Double) {}  // TODO: Implement.
    }

    // TODO: requestedOutputs — outputs requested during ViewGraph initialization.
    // TODO: rootView: AGAttribute
    // TODO: Add AG attribute properties such as proposedSize and rootGeometry.

    override init() {
        super.init()
        self.delegate = nil
    }
}
