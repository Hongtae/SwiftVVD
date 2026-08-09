//
//  File: ScrapeableContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct ScrapeableID: Equatable, Hashable, GraphReusable {
    var value: UInt32

    init() {
        value = UInt32(truncatingIfNeeded: AGMakeUniqueID())
    }

    init(value: UInt32) {
        self.value = value
    }

    static var none: Self {
        Self(value: 0)
    }

    static var isTriviallyReusable: Bool { true }

    mutating func tryToReuse(
        by other: Self,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        self == other
    }
}

struct ScrapeableContent {
    enum Content {
    }
}

extension _ViewInputs {
    struct ScrapeableParentID: GraphInput {
        static var defaultValue: ScrapeableID {
            .none
        }
    }

    var scrapeableParentID: ScrapeableID {
        get { base[ScrapeableParentID.self] }
        set { base[ScrapeableParentID.self] = newValue }
    }

    var isScrapeable: Bool {
        get {
            needsGeometry
                && preferences.keys.contains(DisplayList.Key.self)
                && !base.options.contains(.doNotScrape)
        }
        set {
            if newValue {
                base.options.remove(.doNotScrape)
            } else {
                base.options.insert(.doNotScrape)
            }
        }
    }
}

extension _ViewListInputs {
    var scrapeableParentID: ScrapeableID {
        get { base[_ViewInputs.ScrapeableParentID.self] }
        set { base[_ViewInputs.ScrapeableParentID.self] = newValue }
    }

    var isScrapeable: Bool {
        get {
            base.options.contains(.viewNeedsGeometry)
                && !base.options.contains(.doNotScrape)
        }
        set {
            if newValue {
                base.options.remove(.doNotScrape)
            } else {
                base.options.insert(.doNotScrape)
            }
        }
    }
}
