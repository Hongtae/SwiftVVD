//
//  File: AppKitClipboard.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
@_implementationOnly import AppKit

private struct AppKitClipboardError: Error, CustomStringConvertible {
    let operation: String
    let type: String?

    var description: String {
        if let type {
            return "\(operation) failed for pasteboard type \(type)"
        }
        return "\(operation) failed"
    }
}

final class AppKitClipboard: Clipboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var types: [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    func containsData(forType type: String) -> Bool {
        pasteboard.availableType(
            from: [NSPasteboard.PasteboardType(type)]
        ) != nil
    }

    func setData(_ representations: [String: Data]) throws {
        guard representations.isEmpty == false else {
            pasteboard.clearContents()
            return
        }

        let item = NSPasteboardItem()
        for (type, data) in representations.sorted(by: { $0.key < $1.key }) {
            guard item.setData(
                data,
                forType: NSPasteboard.PasteboardType(type)
            ) else {
                throw AppKitClipboardError(
                    operation: "Prepare clipboard data",
                    type: type
                )
            }
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw AppKitClipboardError(
                operation: "Write clipboard contents",
                type: nil
            )
        }
    }

    func data(forType type: String) throws -> Data? {
        guard let availableType = pasteboard.availableType(
            from: [NSPasteboard.PasteboardType(type)]
        ) else {
            return nil
        }
        return pasteboard.data(forType: availableType)
    }
}

#endif // ENABLE_APPKIT
