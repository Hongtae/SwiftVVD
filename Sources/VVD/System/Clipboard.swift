//
//  File: Clipboard.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Content type identifiers shared by clipboard backends.
public enum ClipboardContentType {
    /// UTF-8 encoded plain text.
    public static let utf8PlainText = "public.utf8-plain-text"
}

/// An application-wide system clipboard service.
///
/// Type identifiers are strings so each backend can bridge its native format
/// system without exposing platform types. Apple backends can use uniform type
/// identifiers directly, while other backends map known identifiers to native
/// clipboard formats or MIME types.
public protocol Clipboard: AnyObject {
    /// Type identifiers currently advertised by the clipboard.
    var types: [String] { get }

    /// Returns whether `type` is currently available without loading its data.
    ///
    /// Backends may recognize native aliases or types that conform to the
    /// requested identifier even when `types` advertises a canonical type.
    func containsData(forType type: String) -> Bool

    /// Replaces the clipboard with alternate representations of one value.
    ///
    /// Passing an empty dictionary clears the clipboard. Each dictionary key
    /// is a content type identifier and its value is the encoded representation
    /// for that type. The backend retains its own snapshot for as long as its
    /// native clipboard ownership requires.
    func setData(_ representations: [String: Data]) throws

    /// Returns the encoded representation for `type`, or `nil` when that type
    /// is not currently available.
    func data(forType type: String) throws -> Data?
}

public extension Clipboard {
    func containsData(forType type: String) -> Bool {
        types.contains(type)
    }

    func setData(_ data: Data, forType type: String) throws {
        try setData([type: data])
    }

    func clear() throws {
        try setData([:])
    }
}
