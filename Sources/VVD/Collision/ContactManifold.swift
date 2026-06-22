//
//  File: ContactManifold.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

/// Contact geometry generated for a pair of collision primitives.
///
/// This type intentionally stores geometric contact data only. Solver-specific
/// cached impulses and warm-starting state should live in the dynamics layer.
public struct ContactManifold: Hashable, Sendable {
    public var contacts: [Contact]

    public init(contacts: [Contact] = []) {
        self.contacts = contacts
    }

    public init(_ contact: Contact) {
        self.contacts = [contact]
    }

    public var isEmpty: Bool {
        contacts.isEmpty
    }
}
