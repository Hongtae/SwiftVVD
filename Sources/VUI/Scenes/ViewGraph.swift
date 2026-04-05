//
//  File: ViewGraph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// ViewGraphDelegate — update scheduling callbacks for the view graph.
protocol ViewGraphDelegate: AnyObject {
    func setNeedsUpdate()
    func requestUpdate(after: Double)
    func `as`<T>(_ type: T.Type) -> T?
}

// ViewRendererHost — protocol for types that own a ViewGraph and drive rendering.
protocol ViewRendererHost: AnyObject {
    var viewGraph: ViewGraph { get }
}

// ViewGraphHostDelegate — lifecycle delegate for ViewGraphHost.
protocol ViewGraphHostDelegate: AnyObject {}

// ViewGraphRenderDelegate — rendering callback delegate.
protocol ViewGraphRenderDelegate: AnyObject {}

// ViewGraphRootValueUpdater — root value update notification delegate.
protocol ViewGraphRootValueUpdater: AnyObject {}

// ViewGraphHost — intermediate base class between GraphHost and ViewGraph.
// Handles lifecycle, display link, and environment management.
//
// TODO: Add stored properties after AG ownership structure is migrated to GraphHost
// TODO: Implement display link / update timer / environment methods
class ViewGraphHost: GraphHost {
    weak var delegate: (any ViewGraphHostDelegate)?

    // viewGraph — returns self cast to ViewGraph.
    // Valid because ViewGraph IS-A ViewGraphHost.
    var viewGraph: ViewGraph { self as! ViewGraph }

    override init() { super.init() }
}

// ViewGraph — view-level AG host.
//
// TODO: Register _makeView closure as AG node
// TODO: Implement displayList() and wire to WindowContext render loop
class ViewGraph: ViewGraphHost {

    // delegate — update scheduling callback (ViewGraphDelegate).
    weak var viewDelegate: (any ViewGraphDelegate)?

    // graphDelegate — AG transaction lifecycle callback (GraphDelegate).
    weak var graphDelegate: (any GraphDelegate)?

    struct Outputs: OptionSet {
        let rawValue: UInt8
        static let displayList      = Outputs(rawValue: 0x01)  // bit 0
        static let platformItemList = Outputs(rawValue: 0x02)  // bit 1
        static let viewResponders   = Outputs(rawValue: 0x04)  // bit 2
        // 0x08: unknown member (unused)
        static let layout           = Outputs(rawValue: 0x10)  // bit 4
        static let focus            = Outputs(rawValue: 0x20)  // bit 5
        static let defaults         = Outputs(rawValue: 0x35)  // displayList | viewResponders | layout | focus
        static let all              = Outputs(rawValue: 0xFF)
    }

    // NextUpdate — update scheduling value type (struct).
    // Stored as a tuple: nextUpdate: (views: NextUpdate, gestures: NextUpdate)
    struct NextUpdate {
        var time: Double = .infinity   // TODO: replace with Time type
        var interval: Double = .infinity
        var reasons: Set<UInt32> = []

        mutating func at(_ t: Double) { time = t }
        mutating func interval(_ dt: Double, reason: UInt32? = nil) {
            self.interval = dt
            if let r = reason { reasons.insert(r) }
        }
        mutating func maxVelocity(_ v: Double) {}  // TODO: implement
    }

    // TODO: requestedOutputs — outputs requested at ViewGraph init time
    // TODO: rootView: AGAttribute
    // TODO: Add AG attribute properties: proposedSize, rootGeometry, etc.

    override init() {
        super.init()
    }
}
