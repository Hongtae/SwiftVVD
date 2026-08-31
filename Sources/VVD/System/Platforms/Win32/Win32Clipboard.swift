//
//  File: Win32Clipboard.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import Foundation
import WinSDK

private let utf8PlainTextType = ClipboardContentType.utf8PlainText
private let registeredTypePrefix = "VVD.ContentType:"
private let registeredDataSignature: [UInt8] = [
    0x56, 0x56, 0x44, 0x00, 0x44, 0x41, 0x54, 0x01,
]

private let plainTextTypes: Set<String> = [
    utf8PlainTextType,
    "public.plain-text",
    "text/plain",
    "text/plain;charset=utf-8",
]

private struct ClipboardError: Error, CustomStringConvertible {
    let operation: String
    let code: DWORD

    var description: String {
        "\(operation) failed with Win32 error \(code)"
    }
}

final class Win32Clipboard: Clipboard {
    private struct PreparedFormat {
        let format: UINT
        var handle: HGLOBAL?
    }

    private let ownerWindow: HWND?

    init() {
        ownerWindow = Win32Clipboard.makeOwnerWindow()
    }

    deinit {
        if let ownerWindow {
            DestroyWindow(ownerWindow)
        }
    }

    var types: [String] {
        guard OpenClipboard(nil) else { return [] }
        defer { CloseClipboard() }

        var result: [String] = []
        var seen: Set<String> = []
        var format: UINT = 0

        while true {
            format = EnumClipboardFormats(format)
            guard format != 0 else { break }

            if format == UINT(CF_UNICODETEXT) || format == UINT(CF_TEXT) {
                if seen.insert(utf8PlainTextType).inserted {
                    result.append(utf8PlainTextType)
                }
                continue
            }

            guard let type = Self.registeredType(for: format),
                  seen.insert(type).inserted else {
                continue
            }
            result.append(type)
        }
        return result
    }

    func containsData(forType type: String) -> Bool {
        if plainTextTypes.contains(type),
           (IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)) ||
            IsClipboardFormatAvailable(UINT(CF_TEXT))) {
            return true
        }

        guard let registered = try? Self.registeredFormat(for: type) else {
            return false
        }
        return IsClipboardFormatAvailable(registered)
    }

    func setData(_ representations: [String: Data]) throws {
        var prepared: [PreparedFormat] = []

        do {
            prepared.reserveCapacity(representations.count + 1)
            for (type, data) in representations.sorted(by: { $0.key < $1.key }) {
                let format = try Self.registeredFormat(for: type)
                let encoded = Self.encodedRegisteredData(data)
                let handle = try Self.makeGlobalMemory(encoded)
                prepared.append(PreparedFormat(format: format, handle: handle))
            }

            if let textData = Self.preferredPlainText(in: representations) {
                guard let utf16 = Self.utf16Data(fromUTF8: textData) else {
                    throw ClipboardError(
                        operation: "Decode UTF-8 clipboard text",
                        code: DWORD(ERROR_NO_UNICODE_TRANSLATION)
                    )
                }
                let handle = try Self.makeGlobalMemory(utf16)
                prepared.append(
                    PreparedFormat(format: UINT(CF_UNICODETEXT), handle: handle)
                )
            }
        } catch {
            Self.release(&prepared)
            throw error
        }

        guard let ownerWindow else {
            Self.release(&prepared)
            throw ClipboardError(
                operation: "Create clipboard owner window",
                code: DWORD(ERROR_INVALID_WINDOW_HANDLE)
            )
        }
        guard OpenClipboard(ownerWindow) else {
            Self.release(&prepared)
            throw Self.lastError("OpenClipboard")
        }
        defer { CloseClipboard() }

        guard EmptyClipboard() else {
            Self.release(&prepared)
            throw Self.lastError("EmptyClipboard")
        }

        for index in prepared.indices {
            guard let handle = prepared[index].handle else { continue }
            if SetClipboardData(prepared[index].format, handle) != nil {
                // The system owns the handle after SetClipboardData succeeds.
                prepared[index].handle = nil
            } else {
                Self.release(&prepared)
                throw Self.lastError("SetClipboardData")
            }
        }
    }

    func data(forType type: String) throws -> Data? {
        guard OpenClipboard(nil) else {
            throw Self.lastError("OpenClipboard")
        }
        defer { CloseClipboard() }

        let registered = try Self.registeredFormat(for: type)
        if IsClipboardFormatAvailable(registered),
           let data = try Self.data(for: registered) {
            return Self.decodedRegisteredData(data)
        }

        guard plainTextTypes.contains(type) else {
            return nil
        }
        if IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)),
           let utf16 = try Self.data(for: UINT(CF_UNICODETEXT)) {
            return Self.utf8Data(fromUTF16: utf16)
        }
        if IsClipboardFormatAvailable(UINT(CF_TEXT)),
           let ansi = try Self.data(for: UINT(CF_TEXT)) {
            return Self.utf8Data(fromANSI: ansi)
        }
        return nil
    }

    private static func preferredPlainText(
        in representations: [String: Data]
    ) -> Data? {
        let preferredTypes = [
            utf8PlainTextType,
            "text/plain;charset=utf-8",
            "text/plain",
            "public.plain-text",
        ]
        return preferredTypes.lazy.compactMap { representations[$0] }.first
    }

    private static func makeOwnerWindow() -> HWND? {
        let messageOnlyParent = HWND(bitPattern: -3)
        return "STATIC".withCString(encodedAs: UTF16.self) { className in
            CreateWindowExW(
                0,
                className,
                nil,
                0,
                0,
                0,
                0,
                0,
                messageOnlyParent,
                nil,
                GetModuleHandleW(nil),
                nil
            )
        }
    }

    private static func registeredFormatName(for type: String) -> String {
        registeredTypePrefix + type
    }

    private static func utf16Data(fromUTF8 data: Data) -> Data? {
        guard let string = String(data: data, encoding: .utf8) else { return nil }
        var codeUnits = Array(string.utf16)
        codeUnits.append(0)
        return codeUnits.withUnsafeBytes { Data($0) }
    }

    private static func utf8Data(fromUTF16 data: Data) -> Data? {
        guard data.count >= MemoryLayout<WCHAR>.size else { return nil }
        let count = data.count / MemoryLayout<WCHAR>.size
        return data.withUnsafeBytes { bytes in
            let units = bytes.bindMemory(to: WCHAR.self)
            let length = units.prefix(count).firstIndex(of: 0) ?? count
            let string = String(decoding: units.prefix(length), as: UTF16.self)
            return string.data(using: .utf8)
        }
    }

    private static func utf8Data(fromANSI data: Data) -> Data? {
        let byteCount = data.firstIndex(of: 0) ?? data.endIndex
        guard byteCount > 0 else { return Data() }
        guard byteCount <= Int(Int32.max) else { return nil }

        let requiredCount = data.withUnsafeBytes { bytes in
            MultiByteToWideChar(
                UINT(CP_ACP),
                0,
                bytes.bindMemory(to: CHAR.self).baseAddress,
                Int32(byteCount),
                nil,
                0
            )
        }
        guard requiredCount > 0 else { return nil }

        var codeUnits = [WCHAR](
            repeating: 0,
            count: Int(requiredCount)
        )
        let writtenCount = data.withUnsafeBytes { bytes in
            MultiByteToWideChar(
                UINT(CP_ACP),
                0,
                bytes.bindMemory(to: CHAR.self).baseAddress,
                Int32(byteCount),
                &codeUnits,
                requiredCount
            )
        }
        guard writtenCount == requiredCount else { return nil }
        let string = String(decoding: codeUnits, as: UTF16.self)
        return string.data(using: .utf8)
    }

    private static func encodedRegisteredData(_ data: Data) -> Data {
        var result = Data(registeredDataSignature)
        var length = UInt64(data.count).littleEndian
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        result.append(data)
        return result
    }

    private static func decodedRegisteredData(_ data: Data) -> Data? {
        let headerSize = registeredDataSignature.count + MemoryLayout<UInt64>.size
        guard data.count >= headerSize,
              data.prefix(registeredDataSignature.count)
                .elementsEqual(registeredDataSignature) else {
            // Preserve interoperability with raw producers that registered the
            // same content-type format without VVD's length envelope.
            return data
        }

        var payloadLength: UInt64 = 0
        for offset in 0..<MemoryLayout<UInt64>.size {
            payloadLength |= UInt64(data[registeredDataSignature.count + offset])
                << UInt64(offset * 8)
        }
        guard payloadLength <= UInt64(Int.max) else { return nil }
        let length = Int(payloadLength)
        guard length <= data.count - headerSize else { return nil }
        return data.subdata(in: headerSize..<(headerSize + length))
    }

    private static func registeredFormat(for type: String) throws -> UINT {
        let name = registeredFormatName(for: type)
        let format = name.withCString(encodedAs: UTF16.self) {
            RegisterClipboardFormatW($0)
        }
        guard format != 0 else { throw lastError("RegisterClipboardFormatW") }
        return format
    }

    private static func registeredType(for format: UINT) -> String? {
        var buffer = [WCHAR](repeating: 0, count: 512)
        let count = GetClipboardFormatNameW(
            format,
            &buffer,
            Int32(buffer.count)
        )
        guard count > 0 else { return nil }
        let name = String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
        guard name.hasPrefix(registeredTypePrefix) else { return nil }
        return String(name.dropFirst(registeredTypePrefix.count))
    }

    private static func makeGlobalMemory(_ data: Data) throws -> HGLOBAL {
        let size = max(data.count, 1)
        guard let handle = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(size)) else {
            throw lastError("GlobalAlloc")
        }
        guard let destination = GlobalLock(handle) else {
            let error = lastError("GlobalLock")
            GlobalFree(handle)
            throw error
        }

        if !data.isEmpty {
            data.copyBytes(
                to: destination.assumingMemoryBound(to: UInt8.self),
                count: data.count
            )
        }
        GlobalUnlock(handle)
        return handle
    }

    private static func data(for format: UINT) throws -> Data? {
        guard let handle = GetClipboardData(format) else { return nil }
        let size = GlobalSize(handle)
        guard size > 0 else { return Data() }
        guard let source = GlobalLock(handle) else {
            throw lastError("GlobalLock")
        }
        defer { GlobalUnlock(handle) }
        return Data(bytes: source, count: Int(size))
    }

    private static func release(_ prepared: inout [PreparedFormat]) {
        for index in prepared.indices {
            if let handle = prepared[index].handle {
                GlobalFree(handle)
                prepared[index].handle = nil
            }
        }
    }

    private static func lastError(_ operation: String) -> ClipboardError {
        ClipboardError(operation: operation, code: GetLastError())
    }
}

#endif // ENABLE_WIN32
