//
//  File: FontFeatures.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
private import HarfBuzz

/// The selected face's feature metadata, independent of per-call lookup ranges.
package struct FontFeatures: Sendable {
    package struct Setting: Sendable {
        package let tag: UInt32
        package let value: UInt32
        package let type: UInt16?
        package let selector: UInt16?
    }

    /// Equality of selected settings is independent of request order and raw aliases.
    /// Keep this relation separate from hashing the original feature requests.
    package static func settingsEqual(_ lhs: [Setting], _ rhs: [Setting]) -> Bool {
        func equal(_ a: Setting, _ b: Setting) -> Bool {
            if let type = a.type, let selector = a.selector,
               type == b.type && selector == b.selector { return true }
            return a.tag == b.tag && a.value == b.value
        }
        return lhs.allSatisfy { a in rhs.contains { equal(a, $0) } } &&
            rhs.allSatisfy { b in lhs.contains { equal($0, b) } }
    }

    /// Retain portable original requests independently of the primary face's
    /// supported settings. Cascades keep the first occurrence of each exact
    /// request; primary selection still consumes the complete ordered input.
    package static func cascadeRequests(_ requests: [Font.ShapingFeature]) -> [Font.ShapingFeature] {
        precondition(requests.allSatisfy { $0.range == nil })
        var seen: Set<Font.ShapingFeature> = []
        return requests.filter { request in
            guard let entry = entries[request.tag], entry.type != 35,
                  entry.flags & 0x8040 == 0 else { return false }
            // Required script mappings and required ligatures have common
            // semantics even though they do not expose a selectable setting.
            guard entry.flags & 8 == 0 || entry.flags == 0xe ||
                  entry.flags & 0x180 == 0x80 else { return false }
            return seen.insert(request).inserted
        }
    }

    private struct Entry: Sendable {
        let type: UInt16
        let selector: UInt16
        let flags: UInt32
    }

    private let tables: [[UInt32]]
    private let available: Set<UInt32>
    private let selectors: Set<UInt32>
    private let variants: [UInt32: UInt32]
    private let morph: MorphFeatures?

    init(face: OpaquePointer) {
        morph = MorphFeatures(face: face)
        func tags(_ table: UInt32) -> [UInt32] {
            var count = hb_ot_layout_table_get_feature_tags(face, table, 0, nil, nil)
            var values = [UInt32](repeating: 0, count: Int(count))
            values.withUnsafeMutableBufferPointer {
                _ = hb_ot_layout_table_get_feature_tags(face, table, 0, &count, $0.baseAddress)
            }
            return values
        }
        let substitutionTags = tags(0x4753_5542)
        tables = [Array(Set(substitutionTags)).sorted(), Array(Set(tags(0x4750_4f53))).sorted()]
        available = Set(tables.flatMap { $0 })
        selectors = Set(available.compactMap { tag in
            Self.entries[tag].map { UInt32($0.type) << 16 | UInt32($0.selector) }
        })
        var variants: [UInt32: UInt32] = [:]
        for (index, tag) in substitutionTags.enumerated() where (Self.entries[tag]?.flags ?? 0) & 0x40 != 0 {
            var count = hb_ot_layout_feature_get_lookups(face, 0x4753_5542, UInt32(index), 0, nil, nil)
            var lookups = [UInt32](repeating: 0, count: Int(count))
            lookups.withUnsafeMutableBufferPointer {
                _ = hb_ot_layout_feature_get_lookups(face, 0x4753_5542, UInt32(index), 0, &count, $0.baseAddress)
            }
            var maximum: UInt32 = 0
            for lookup in lookups {
                guard let glyphs = hb_set_create() else { continue }
                defer { hb_set_destroy(glyphs) }
                hb_ot_layout_lookup_collect_glyphs(face, 0x4753_5542, lookup, nil, glyphs, nil, nil)
                var glyph = UInt32.max
                while hb_set_next(glyphs, &glyph) != 0 {
                    maximum = max(maximum, 1,
                        hb_ot_layout_lookup_get_glyph_alternates(face, lookup, glyph, 0, nil, nil))
                }
            }
            variants[tag] = max(variants[tag, default: 0], maximum)
        }
        self.variants = variants
    }

    /// Keep the final valid request for each tag, including default selections.
    /// Mapped and custom settings occupy separate, ordered portions of the list.
    package func select(_ requests: [Font.ShapingFeature]) -> [Setting] {
        precondition(requests.allSatisfy { $0.range == nil })
        var seen: Set<UInt32> = []
        var mapped: [Setting] = []
        var custom: [Setting] = []
        for request in requests.reversed() where !seen.contains(request.tag) {
            guard let entry = Self.entries[request.tag] else {
                if available.contains(request.tag), !Self.reservedTags.contains(request.tag) {
                    seen.insert(request.tag)
                    if request.value != 0 {
                        custom.append(Setting(tag: request.tag, value: request.value, type: nil, selector: nil))
                    }
                }
                continue
            }
            guard entry.type != 0 else { continue }
            let selector: UInt16
            let isDefault: Bool
            if let morph {
                if entry.flags & 1 == 0 {
                    selector = request.value == 0 ? entry.selector | 1 : entry.selector & ~1
                } else if request.value == 0 && entry.flags & 2 == 0 {
                    selector = Self.disabledSelectors[request.tag] ?? entry.selector
                } else {
                    selector = entry.flags & 0x40 == 0 ? entry.selector : UInt16(truncatingIfNeeded: request.value)
                }
                guard let selectedDefault = morph.isDefault(type: entry.type, selector: selector) else { continue }
                isDefault = selectedDefault
            } else if entry.flags & 1 != 0 {
                guard selectors.contains(UInt32(entry.type) << 16 | UInt32(entry.selector)) else { continue }
                if entry.flags & 0x40 != 0 {
                    selector = UInt16(truncatingIfNeeded: request.value)
                    guard UInt32(selector) <= variants[request.tag, default: 0] else { continue }
                } else {
                    selector = entry.selector
                }
                isDefault = (entry.flags & 0x40 != 0 ? selector == 0 : request.value == 0) ||
                    entry.flags & 2 != 0
            } else {
                guard selectors.contains(UInt32(entry.type) << 16 | UInt32(entry.selector)) else { continue }
                selector = request.value == 0 ? entry.selector | 1 : entry.selector & ~1
                isDefault = (request.value != 0) == (entry.flags & 2 != 0)
            }
            seen.insert(request.tag)
            if !isDefault {
                mapped.append(Setting(tag: request.tag, value: request.value,
                                      type: entry.type, selector: selector))
            }
        }
        return mapped + custom
    }

    /// Lower font settings to global lookup requests. Required script features
    /// stay with the script shaper; descriptor features never acquire source ranges.
    package func shapingFeatures(_ settings: [Setting], vertical: Bool) -> [Font.ShapingFeature] {
        if morph != nil {
            // Morph chains own their defaults. Apply the retained selections in
            // request order, keeping numeric selectors distinct from Boolean tags.
            return settings.reversed().map { setting in
                let value: UInt32
                if setting.type == nil { value = setting.value }
                else if (Self.entries[setting.tag]?.flags ?? 0) & 0x40 != 0 {
                    value = UInt32(setting.selector!)
                } else { value = setting.value == 0 ? 0 : 1 }
                return Font.ShapingFeature(tag: setting.tag, value: value)
            }
        }
        var result: [Font.ShapingFeature] = []
        for tags in tables {
            var values: [UInt32: UInt32] = [:]
            var flags: UInt32 = 0
            for tag in tags {
                guard let entry = Self.entries[tag], entry.type != 0 else { continue }
                var value: UInt32 = 0
                if entry.flags & (vertical ? 0x20 : 0x10) == 0 {
                    if entry.flags & 2 != 0 {
                        let disabledSelector = entry.flags & 1 != 0 ? entry.selector : entry.selector ^ 1
                        value = settings.contains { $0.type == entry.type && $0.selector == disabledSelector } ? 0 : 1
                    } else if let setting = settings.first(where: {
                        $0.type == entry.type && $0.tag == tag &&
                        (entry.flags & 0x40 != 0 || $0.selector == entry.selector)
                    }) {
                        value = entry.flags & 0x40 != 0 ? UInt32(setting.selector!) : 1
                    }
                }
                values[tag] = value
                if value != 0 { flags |= entry.flags & ~0x1ff }
            }
            if flags & 0x200 != 0 {
                for tag: UInt32 in [0x6b65_726e, 0x766b_726e] where values[tag] != nil { values[tag] = 0 }
            }
            if flags & 0x800 != 0, values[0x7061_6c74] != nil { values[0x7061_6c74] = 0 }
            if flags & 0x2000 != 0, values[0x7672_7432] != nil { values[0x7672_7432] = 0 }
            else if flags & 0x1000 != 0, values[0x7665_7274] != nil { values[0x7665_7274] = 0 }
            result += values.keys.sorted().map { Font.ShapingFeature(tag: $0, value: values[$0]!) }
        }
        result += settings.reversed().filter { $0.type == nil && $0.value != 0 }.map {
            Font.ShapingFeature(tag: $0.tag, value: $0.value)
        }
        return result
    }

    private struct MorphFeatures: Sendable {
        private struct Feature: Sendable {
            let exclusive: Bool
            let defaults: [UInt16: Bool]
        }
        private let features: [UInt16: Feature]

        init?(face: OpaquePointer) {
            let chain = Table(face: face, tag: 0x6d6f_7278)
            guard !chain.bytes.isEmpty else { return nil }
            let table = Table(face: face, tag: 0x6665_6174)
            let version = table.uint32(0)
            guard table.contains(0, count: 12), version == 0x10000 || version == 0x10001 else {
                features = [:]; return
            }
            // Version 1.0 obtains selected defaults from the first active chain
            // setting of each type. Exclusive types without one use selector zero.
            var selected: [UInt16: UInt16] = [0: 0]
            if version == 0x10000, chain.contains(0, count: 8) {
                var offset = 8
                for _ in 0..<chain.uint32(4) {
                    guard chain.contains(offset, count: 16) else { break }
                    let flags = chain.uint32(offset), length = Int(chain.uint32(offset + 4))
                    let count = min(Int(chain.uint32(offset + 8)), (chain.bytes.count - offset - 16) / 12)
                    for index in 0..<count {
                        let at = offset + 16 + index * 12, type = chain.uint16(offset + 16 + index * 12)
                        if flags & chain.uint32(at + 4) != 0, selected[type] == nil {
                            selected[type] = chain.uint16(at + 2)
                        }
                    }
                    guard length >= 16, chain.contains(offset, count: length) else { break }
                    offset += length
                }
            }
            var features: [UInt16: Feature] = [:]
            let count = min(Int(table.uint16(4)), (table.bytes.count - 12) / 12)
            for index in 0..<count {
                let at = 12 + index * 12, type = table.uint16(at), flags = table.uint16(at + 8)
                let exclusive = flags & 0x8000 != 0
                let offset = Int(table.uint32(at + 4))
                guard table.contains(offset, count: 0) else { continue }
                let count = min(Int(table.uint16(at + 2)), (table.bytes.count - offset) / 4)
                guard count > (exclusive ? 1 : 0) else { continue }
                let defaultIndex = flags & 0xc000 == 0xc000 ? Int(flags & 0xff) : 0
                var defaults: [UInt16: Bool] = [:]
                for item in 0..<count {
                    let selector = table.uint16(offset + item * 4)
                    let isDefault: Bool
                    if version == 0x10000 {
                        isDefault = selector == (selected[type] ?? (exclusive ? 0 : nil))
                    } else { isDefault = exclusive ? item == defaultIndex : selector & 1 == 0 }
                    let key = exclusive ? selector : selector & ~1
                    if defaults[key] == nil { defaults[key] = isDefault }
                }
                features[type] = Feature(exclusive: exclusive, defaults: defaults)
            }
            self.features = features
        }

        func isDefault(type: UInt16, selector: UInt16) -> Bool? {
            guard let feature = features[type],
                  let value = feature.defaults[feature.exclusive ? selector : selector & ~1] else { return nil }
            return feature.exclusive ? value : value != (selector & 1 != 0)
        }

        private struct Table {
            let bytes: [UInt8]

            init(face: OpaquePointer, tag: UInt32) {
                guard let blob = hb_face_reference_table(face, tag) else { bytes = []; return }
                defer { hb_blob_destroy(blob) }
                var count: UInt32 = 0
                guard let data = hb_blob_get_data(blob, &count) else { bytes = []; return }
                bytes = Array(UnsafeRawBufferPointer(start: data, count: Int(count)))
            }
            func contains(_ offset: Int, count: Int) -> Bool {
                offset >= 0 && offset <= bytes.count && count >= 0 && count <= bytes.count - offset
            }
            func uint16(_ offset: Int) -> UInt16 {
                guard contains(offset, count: 2) else { return 0 }
                return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            }
            func uint32(_ offset: Int) -> UInt32 {
                guard contains(offset, count: 4) else { return 0 }
                return UInt32(uint16(offset)) << 16 | UInt32(uint16(offset + 2))
            }
        }
    }

    private static let disabledSelectors: [UInt32: UInt16] = [
        0x61616c74: 0, 0x61667263: 0, 0x63327063: 0, 0x63327363: 0,
        0x65787074: 16, 0x66726163: 0, 0x66776964: 7, 0x68616c74: 7,
        0x686e676c: 0, 0x686f6a6f: 16, 0x68776964: 7, 0x6a703034: 16,
        0x6a703738: 16, 0x6a703833: 16, 0x6a703930: 16, 0x6c6e756d: 2,
        0x6e6c636b: 16, 0x6f6e756d: 2, 0x6f72646e: 0, 0x70616c74: 7,
        0x70636170: 0, 0x706b6e61: 7, 0x706e756d: 4, 0x70776964: 7,
        0x71776964: 7, 0x73696e66: 0, 0x736d6370: 0, 0x736d706c: 16,
        0x73756273: 0, 0x73757073: 0, 0x7469746c: 0, 0x746e616d: 16,
        0x746e756d: 4, 0x74726164: 16, 0x74776964: 7, 0x76616c74: 7,
        0x7668616c: 7, 0x7670616c: 7,
    ]

    private static let reservedTags: Set<UInt32> = [
        0x00000001, 0x61616c74, 0x61627666, 0x6162766d, 0x61627673, 0x61667263,
        0x616b686e, 0x626c7766, 0x626c776d, 0x626c7773, 0x63327063, 0x63327363,
        0x63616c74, 0x63617365, 0x63636d70, 0x63666172, 0x636a6374, 0x636c6967,
        0x63707370, 0x63737768, 0x63757273, 0x64697374, 0x646c6967, 0x65787074,
        0x66616c74, 0x66696e32, 0x66696e33, 0x66696e61, 0x66726163, 0x66776964,
        0x68616c66, 0x68616c6e, 0x68616c74, 0x68697374, 0x686b6e61, 0x686c6967,
        0x686e676c, 0x686f6a6f, 0x68776964, 0x696e6974, 0x69736f6c, 0x6974616c,
        0x6a703034, 0x6a703738, 0x6a703833, 0x6a703930, 0x6b65726e, 0x6c696761,
        0x6c6a6d6f, 0x6c6e756d, 0x6c6f636c, 0x6c747261, 0x6c74726d, 0x6d61726b,
        0x6d656432, 0x6d656469, 0x6d67726b, 0x6d6b6d6b, 0x6d736574, 0x6e6c636b,
        0x6e756b74, 0x6f6e756d, 0x6f72646e, 0x70616c74, 0x70636170, 0x706b6e61,
        0x706e756d, 0x70726566, 0x70726573, 0x70737466, 0x70737473, 0x70776964,
        0x71776964, 0x72636c74, 0x726b7266, 0x726c6967, 0x72706866, 0x72746c61,
        0x72746c6d, 0x72756279, 0x7276726e, 0x73696e66, 0x73697a65, 0x736d6370,
        0x736d706c, 0x73733031, 0x73733032, 0x73733033, 0x73733034, 0x73733035,
        0x73733036, 0x73733037, 0x73733038, 0x73733039, 0x73733130, 0x73733131,
        0x73733132, 0x73733133, 0x73733134, 0x73733135, 0x73733136, 0x73733137,
        0x73733138, 0x73733139, 0x73733230, 0x73756273, 0x73757073, 0x73777368,
        0x7469746c, 0x746a6d6f, 0x746e616d, 0x746e756d, 0x74726164, 0x74776964,
        0x756e6963, 0x76616c74, 0x76617475, 0x76657274, 0x7668616c, 0x766a6d6f,
        0x766b6e61, 0x766b726e, 0x7670616c, 0x76727432, 0x76727472, 0x7a65726f,
    ]

    private static let entries: [UInt32: Entry] = [
        0x61616c74: Entry(type: 17, selector: 0, flags: 0x45), // aalt
        0x61627666: Entry(type: 0, selector: 0, flags: 0xe), // abvf
        0x6162766d: Entry(type: 0, selector: 0, flags: 0xa), // abvm
        0x61627673: Entry(type: 0, selector: 0, flags: 0xe), // abvs
        0x61667263: Entry(type: 11, selector: 1, flags: 0x1), // afrc
        0x616b686e: Entry(type: 0, selector: 0, flags: 0xe), // akhn
        0x626c7766: Entry(type: 0, selector: 0, flags: 0xe), // blwf
        0x626c776d: Entry(type: 0, selector: 0, flags: 0xa), // blwm
        0x626c7773: Entry(type: 0, selector: 0, flags: 0xe), // blws
        0x63327063: Entry(type: 38, selector: 2, flags: 0x1), // c2pc
        0x63327363: Entry(type: 38, selector: 1, flags: 0x1), // c2sc
        0x63616c74: Entry(type: 36, selector: 0, flags: 0x2), // calt
        0x63617365: Entry(type: 33, selector: 0, flags: 0x0), // case
        0x63636d70: Entry(type: 0, selector: 0, flags: 0xe), // ccmp
        0x63666172: Entry(type: 0, selector: 0, flags: 0xe), // cfar
        0x636a6374: Entry(type: 0, selector: 0, flags: 0xe), // cjct
        0x636c6967: Entry(type: 1, selector: 18, flags: 0x102), // clig
        0x63707370: Entry(type: 33, selector: 2, flags: 0x0), // cpsp
        0x63737768: Entry(type: 36, selector: 4, flags: 0x8000), // cswh
        0x63757273: Entry(type: 0, selector: 0, flags: 0x2a), // curs
        0x64697374: Entry(type: 0, selector: 0, flags: 0x2a), // dist
        0x646c6967: Entry(type: 1, selector: 4, flags: 0x180), // dlig
        0x65787074: Entry(type: 20, selector: 10, flags: 0x1), // expt
        0x66616c74: Entry(type: 0, selector: 0, flags: 0xe), // falt
        0x66696e32: Entry(type: 0, selector: 0, flags: 0xe), // fin2
        0x66696e33: Entry(type: 0, selector: 0, flags: 0xe), // fin3
        0x66696e61: Entry(type: 0, selector: 0, flags: 0xe), // fina
        0x66726163: Entry(type: 11, selector: 2, flags: 0x1), // frac
        0x66776964: Entry(type: 22, selector: 1, flags: 0xa01), // fwid
        0x68616c66: Entry(type: 0, selector: 0, flags: 0xe), // half
        0x68616c6e: Entry(type: 0, selector: 0, flags: 0xe), // haln
        0x68616c74: Entry(type: 22, selector: 6, flags: 0xa21), // halt
        0x68697374: Entry(type: 40, selector: 0, flags: 0x0), // hist
        0x686b6e61: Entry(type: 34, selector: 0, flags: 0x20), // hkna
        0x686c6967: Entry(type: 1, selector: 22, flags: 0x180), // hlig
        0x686e676c: Entry(type: 23, selector: 1, flags: 0x1), // hngl
        0x686f6a6f: Entry(type: 20, selector: 12, flags: 0x1), // hojo
        0x68776964: Entry(type: 22, selector: 2, flags: 0xa01), // hwid
        0x696e6974: Entry(type: 0, selector: 0, flags: 0xe), // init
        0x69736f6c: Entry(type: 0, selector: 0, flags: 0xe), // isol
        0x6974616c: Entry(type: 32, selector: 2, flags: 0x0), // ital
        0x6a703034: Entry(type: 20, selector: 11, flags: 0x1), // jp04
        0x6a703738: Entry(type: 20, selector: 2, flags: 0x1), // jp78
        0x6a703833: Entry(type: 20, selector: 3, flags: 0x1), // jp83
        0x6a703930: Entry(type: 20, selector: 4, flags: 0x1), // jp90
        0x6b65726e: Entry(type: 22, selector: 7, flags: 0x4023), // kern
        0x6c696761: Entry(type: 1, selector: 2, flags: 0x102), // liga
        0x6c6a6d6f: Entry(type: 0, selector: 0, flags: 0xe), // ljmo
        0x6c6e756d: Entry(type: 21, selector: 1, flags: 0x1), // lnum
        0x6c6f636c: Entry(type: 0, selector: 0, flags: 0xe), // locl
        0x6c747261: Entry(type: 0, selector: 0, flags: 0xe), // ltra
        0x6c74726d: Entry(type: 0, selector: 0, flags: 0xe), // ltrm
        0x6d61726b: Entry(type: 0, selector: 0, flags: 0xa), // mark
        0x6d656432: Entry(type: 0, selector: 0, flags: 0xe), // med2
        0x6d656469: Entry(type: 0, selector: 0, flags: 0xe), // medi
        0x6d67726b: Entry(type: 15, selector: 10, flags: 0x0), // mgrk
        0x6d6b6d6b: Entry(type: 0, selector: 0, flags: 0xa), // mkmk
        0x6d736574: Entry(type: 0, selector: 0, flags: 0xe), // mset
        0x6e6c636b: Entry(type: 20, selector: 13, flags: 0x1), // nlck
        0x6e756b74: Entry(type: 0, selector: 0, flags: 0xe), // nukt
        0x6f6e756d: Entry(type: 21, selector: 0, flags: 0x1), // onum
        0x6f72646e: Entry(type: 10, selector: 3, flags: 0x1), // ordn
        0x70616c74: Entry(type: 22, selector: 5, flags: 0x21), // palt
        0x70636170: Entry(type: 37, selector: 2, flags: 0x1), // pcap
        0x706b6e61: Entry(type: 22, selector: 0, flags: 0x801), // pkna
        0x706e756d: Entry(type: 6, selector: 1, flags: 0x1), // pnum
        0x70726566: Entry(type: 0, selector: 0, flags: 0xe), // pref
        0x70726573: Entry(type: 0, selector: 0, flags: 0xe), // pres
        0x70737466: Entry(type: 0, selector: 0, flags: 0xe), // pstf
        0x70737473: Entry(type: 0, selector: 0, flags: 0xe), // psts
        0x70776964: Entry(type: 22, selector: 0, flags: 0x801), // pwid
        0x71776964: Entry(type: 22, selector: 4, flags: 0xa01), // qwid
        0x72636c74: Entry(type: 0, selector: 0, flags: 0xa), // rclt
        0x726b7266: Entry(type: 0, selector: 0, flags: 0xe), // rkrf
        0x726c6967: Entry(type: 0, selector: 0, flags: 0x8a), // rlig
        0x72706866: Entry(type: 0, selector: 0, flags: 0xe), // rphf
        0x72746c61: Entry(type: 0, selector: 0, flags: 0xe), // rtla
        0x72746c6d: Entry(type: 0, selector: 0, flags: 0xe), // rtlm
        0x72756279: Entry(type: 28, selector: 2, flags: 0x0), // ruby
        0x7276726e: Entry(type: 0, selector: 0, flags: 0xe), // rvrn
        0x73696e66: Entry(type: 10, selector: 4, flags: 0x1), // sinf
        0x736d6370: Entry(type: 37, selector: 1, flags: 0x1), // smcp
        0x736d706c: Entry(type: 20, selector: 1, flags: 0x1), // smpl
        0x73733031: Entry(type: 35, selector: 2, flags: 0x0), // ss01
        0x73733032: Entry(type: 35, selector: 4, flags: 0x0), // ss02
        0x73733033: Entry(type: 35, selector: 6, flags: 0x0), // ss03
        0x73733034: Entry(type: 35, selector: 8, flags: 0x0), // ss04
        0x73733035: Entry(type: 35, selector: 10, flags: 0x0), // ss05
        0x73733036: Entry(type: 35, selector: 12, flags: 0x0), // ss06
        0x73733037: Entry(type: 35, selector: 14, flags: 0x0), // ss07
        0x73733038: Entry(type: 35, selector: 16, flags: 0x0), // ss08
        0x73733039: Entry(type: 35, selector: 18, flags: 0x0), // ss09
        0x73733130: Entry(type: 35, selector: 20, flags: 0x0), // ss10
        0x73733131: Entry(type: 35, selector: 22, flags: 0x0), // ss11
        0x73733132: Entry(type: 35, selector: 24, flags: 0x0), // ss12
        0x73733133: Entry(type: 35, selector: 26, flags: 0x0), // ss13
        0x73733134: Entry(type: 35, selector: 28, flags: 0x0), // ss14
        0x73733135: Entry(type: 35, selector: 30, flags: 0x0), // ss15
        0x73733136: Entry(type: 35, selector: 32, flags: 0x0), // ss16
        0x73733137: Entry(type: 35, selector: 34, flags: 0x0), // ss17
        0x73733138: Entry(type: 35, selector: 36, flags: 0x0), // ss18
        0x73733139: Entry(type: 35, selector: 38, flags: 0x0), // ss19
        0x73733230: Entry(type: 35, selector: 40, flags: 0x0), // ss20
        0x73756273: Entry(type: 10, selector: 2, flags: 0x1), // subs
        0x73757073: Entry(type: 10, selector: 1, flags: 0x1), // sups
        0x73777368: Entry(type: 36, selector: 2, flags: 0x8000), // swsh
        0x7469746c: Entry(type: 19, selector: 4, flags: 0x1), // titl
        0x746a6d6f: Entry(type: 0, selector: 0, flags: 0xe), // tjmo
        0x746e616d: Entry(type: 20, selector: 14, flags: 0x1), // tnam
        0x746e756d: Entry(type: 6, selector: 0, flags: 0x1), // tnum
        0x74726164: Entry(type: 20, selector: 0, flags: 0x1), // trad
        0x74776964: Entry(type: 22, selector: 3, flags: 0xa01), // twid
        0x756e6963: Entry(type: 3, selector: 14, flags: 0x0), // unic
        0x76616c74: Entry(type: 22, selector: 5, flags: 0xa11), // valt
        0x76617475: Entry(type: 0, selector: 0, flags: 0xe), // vatu
        0x76657274: Entry(type: 4, selector: 0, flags: 0x12), // vert
        0x7668616c: Entry(type: 22, selector: 6, flags: 0xa11), // vhal
        0x766a6d6f: Entry(type: 0, selector: 0, flags: 0xe), // vjmo
        0x766b6e61: Entry(type: 34, selector: 2, flags: 0x10), // vkna
        0x766b726e: Entry(type: 22, selector: 7, flags: 0x4013), // vkrn
        0x7670616c: Entry(type: 22, selector: 5, flags: 0x811), // vpal
        0x76727432: Entry(type: 4, selector: 0, flags: 0x1012), // vrt2
        0x76727472: Entry(type: 4, selector: 2, flags: 0x20), // vrtr
        0x7a65726f: Entry(type: 14, selector: 4, flags: 0x0), // zero
    ]
}
