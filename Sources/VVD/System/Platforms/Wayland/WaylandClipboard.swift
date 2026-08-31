//
//  File: WaylandClipboard.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
import Glibc
@preconcurrency
import Wayland

private let waylandUTF8PlainTextType = ClipboardContentType.utf8PlainText
private let waylandPlainTextMIMETypes = [
    "text/plain;charset=utf-8",
    "text/plain",
]
private let waylandPlainTextTypes: Set<String> = [
    waylandUTF8PlainTextType,
    "public.plain-text",
    "text/plain;charset=utf-8",
    "text/plain",
]

private struct WaylandClipboardError: Error, CustomStringConvertible, Sendable {
    let operation: String
    let code: Int32?

    var description: String {
        if let code {
            return "\(operation) failed with POSIX error \(code)"
        }
        return "\(operation) failed"
    }
}

private enum WaylandClipboardRead: Sendable {
    case immediate(Data?)
    case fileDescriptor(Int32)
}

private final class WaylandClipboardOffer {
    private(set) var native: OpaquePointer?
    private(set) var mimeTypes: [String] = []

    init(native: OpaquePointer) {
        self.native = native
    }

    func addMIMEType(_ type: String) {
        if !mimeTypes.contains(type) {
            mimeTypes.append(type)
        }
    }

    func destroy() {
        if let native {
            wl_data_offer_destroy(native)
            self.native = nil
        }
    }
}

private final class WaylandClipboardSource: @unchecked Sendable {
    weak var owner: WaylandClipboard?
    private(set) var native: OpaquePointer?
    let representations: [String: Data]

    init?(
        manager: OpaquePointer,
        owner: WaylandClipboard,
        representations: [String: Data]
    ) {
        guard let native = wl_data_device_manager_create_data_source(manager) else {
            return nil
        }
        self.owner = owner
        self.native = native
        self.representations = representations

        wl_data_source_add_listener(
            native,
            &waylandDataSourceListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
        for type in WaylandClipboard.advertisedMIMETypes(
            for: Array(representations.keys)
        ) {
            type.withCString { wl_data_source_offer(native, $0) }
        }
    }

    var commonTypes: [String] {
        WaylandClipboard.normalizedTypes(Array(representations.keys).sorted())
    }

    func contains(_ type: String) -> Bool {
        data(forRequestedType: type) != nil
    }

    func data(forRequestedType type: String) -> Data? {
        if let data = representations[type] {
            return data
        }
        guard waylandPlainTextTypes.contains(type) else { return nil }
        let preferredTypes = [
            waylandUTF8PlainTextType,
            "text/plain;charset=utf-8",
            "text/plain",
            "public.plain-text",
        ]
        return preferredTypes.lazy.compactMap { self.representations[$0] }.first
    }

    func sendData(forMIMEType type: String, fileDescriptor: Int32) {
        guard fileDescriptor >= 0 else { return }
        guard let data = data(forRequestedType: type) else {
            Glibc.close(fileDescriptor)
            return
        }

        // The receiver controls pipe backpressure. Writing on the Wayland
        // dispatch thread can therefore deadlock the entire display if a
        // payload exceeds the pipe capacity. A dedicated short-lived thread
        // keeps the immutable source generation alive until this transfer
        // closes its descriptor.
        let source = self
        Thread.detachNewThread {
            source.write(data, to: fileDescriptor)
        }
    }

    func destroy() {
        if let native {
            wl_data_source_destroy(native)
            self.native = nil
        }
    }

    private func write(_ data: Data, to fileDescriptor: Int32) {
        var blockedSignals = sigset_t()
        sigemptyset(&blockedSignals)
        sigaddset(&blockedSignals, SIGPIPE)
        pthread_sigmask(SIG_BLOCK, &blockedSignals, nil)

        defer { Glibc.close(fileDescriptor) }
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Glibc.write(
                    fileDescriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }
}

nonisolated(unsafe)
private var waylandDataOfferListener = wl_data_offer_listener(
    offer: { data, offer, mimeType in
        guard let data, let offer, let mimeType else { return }
        let clipboard = Unmanaged<WaylandClipboard>
            .fromOpaque(data)
            .takeUnretainedValue()
        clipboard.didOfferMIMEType(
            String(cString: mimeType),
            for: offer
        )
    },
    source_actions: { _, _, _ in },
    action: { _, _, _ in }
)

nonisolated(unsafe)
private var waylandDataSourceListener = wl_data_source_listener(
    target: { _, _, _ in },
    send: { data, _, mimeType, fileDescriptor in
        guard let data, let mimeType else {
            if fileDescriptor >= 0 { Glibc.close(fileDescriptor) }
            return
        }
        let source = Unmanaged<WaylandClipboardSource>
            .fromOpaque(data)
            .takeUnretainedValue()
        source.sendData(
            forMIMEType: String(cString: mimeType),
            fileDescriptor: fileDescriptor
        )
    },
    cancelled: { data, _ in
        guard let data else { return }
        let source = Unmanaged<WaylandClipboardSource>
            .fromOpaque(data)
            .takeUnretainedValue()
        source.owner?.sourceWasCancelled(source)
    },
    dnd_drop_performed: { _, _ in },
    dnd_finished: { _, _ in },
    action: { _, _, _ in }
)

nonisolated(unsafe)
private var waylandDataDeviceListener = wl_data_device_listener(
    data_offer: { data, _, offer in
        guard let data, let offer else { return }
        let clipboard = Unmanaged<WaylandClipboard>
            .fromOpaque(data)
            .takeUnretainedValue()
        clipboard.didCreateOffer(offer)
    },
    enter: { data, _, serial, _, _, _, offer in
        guard let data else { return }
        let clipboard = Unmanaged<WaylandClipboard>
            .fromOpaque(data)
            .takeUnretainedValue()
        clipboard.didEnterDrag(serial: serial, offer: offer)
    },
    leave: { data, _ in
        guard let data else { return }
        let clipboard = Unmanaged<WaylandClipboard>
            .fromOpaque(data)
            .takeUnretainedValue()
        clipboard.didLeaveDrag()
    },
    motion: { _, _, _, _, _ in },
    drop: { _, _ in },
    selection: { data, _, offer in
        guard let data else { return }
        let clipboard = Unmanaged<WaylandClipboard>
            .fromOpaque(data)
            .takeUnretainedValue()
        clipboard.didSelectOffer(offer)
    }
)

final class WaylandClipboard: Clipboard, @unchecked Sendable {
    private let display: OpaquePointer
    private let manager: OpaquePointer
    private var dataDevice: OpaquePointer?
    private var latestInputSerial: UInt32?
    private var pendingOffers: [OpaquePointer: WaylandClipboardOffer] = [:]
    private var selectionOffer: WaylandClipboardOffer?
    private var dragOffer: WaylandClipboardOffer?
    private var sources: [OpaquePointer: WaylandClipboardSource] = [:]
    private var currentSource: WaylandClipboardSource?
    private var isValid = true

    init?(
        display: OpaquePointer,
        manager: OpaquePointer,
        seat: OpaquePointer
    ) {
        guard let dataDevice = wl_data_device_manager_get_data_device(
            manager,
            seat
        ) else {
            return nil
        }
        self.display = display
        self.manager = manager
        self.dataDevice = dataDevice
        wl_data_device_add_listener(
            dataDevice,
            &waylandDataDeviceListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    deinit {
        invalidate()
    }

    var types: [String] {
        runOnMainQueueSync {
            if let currentSource {
                return currentSource.commonTypes
            }
            return Self.normalizedTypes(selectionOffer?.mimeTypes ?? [])
        }
    }

    func containsData(forType type: String) -> Bool {
        runOnMainQueueSync {
            if let currentSource {
                return currentSource.contains(type)
            }
            return Self.preferredOfferedType(
                for: type,
                in: selectionOffer?.mimeTypes ?? []
            ) != nil
        }
    }

    func setData(_ representations: [String: Data]) throws {
        let result: Result<Void, WaylandClipboardError> = runOnMainQueueSync {
            do {
                try setDataOnMain(representations)
                return .success(())
            } catch let error as WaylandClipboardError {
                return .failure(error)
            } catch {
                return .failure(
                    WaylandClipboardError(operation: "Set selection", code: nil)
                )
            }
        }
        try result.get()
    }

    func data(forType type: String) throws -> Data? {
        let result: Result<WaylandClipboardRead, WaylandClipboardError> =
            runOnMainQueueSync {
                do {
                    return .success(try prepareReadOnMain(forType: type))
                } catch let error as WaylandClipboardError {
                    return .failure(error)
                } catch {
                    return .failure(
                        WaylandClipboardError(
                            operation: "Receive selection",
                            code: nil
                        )
                    )
                }
            }

        switch try result.get() {
        case let .immediate(data):
            return data
        case let .fileDescriptor(fileDescriptor):
            return try Self.readAll(from: fileDescriptor)
        }
    }

    func updateInputSerial(_ serial: UInt32) {
        latestInputSerial = serial
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false

        selectionOffer?.destroy()
        selectionOffer = nil
        dragOffer?.destroy()
        dragOffer = nil
        for offer in pendingOffers.values {
            offer.destroy()
        }
        pendingOffers.removeAll()

        for source in sources.values {
            source.destroy()
        }
        sources.removeAll()
        currentSource = nil

        if let dataDevice {
            if wl_data_device_get_version(dataDevice) >= 2 {
                wl_data_device_release(dataDevice)
            } else {
                wl_data_device_destroy(dataDevice)
            }
            self.dataDevice = nil
        }
    }

    fileprivate func didCreateOffer(_ native: OpaquePointer) {
        let offer = WaylandClipboardOffer(native: native)
        pendingOffers[native] = offer
        wl_data_offer_add_listener(
            native,
            &waylandDataOfferListener,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    fileprivate func didOfferMIMEType(
        _ type: String,
        for native: OpaquePointer
    ) {
        // Offer events are delivered immediately after data_offer and before
        // either selection or drag enter identifies the offer's final role.
        pendingOffers[native]?.addMIMEType(type)
    }

    fileprivate func didSelectOffer(_ native: OpaquePointer?) {
        selectionOffer?.destroy()
        selectionOffer = nil
        guard let native else { return }
        selectionOffer = pendingOffers.removeValue(forKey: native)
    }

    fileprivate func didEnterDrag(
        serial: UInt32,
        offer native: OpaquePointer?
    ) {
        dragOffer?.destroy()
        dragOffer = nil
        guard let native else { return }
        dragOffer = pendingOffers.removeValue(forKey: native)
        wl_data_offer_accept(native, serial, nil)
    }

    fileprivate func didLeaveDrag() {
        dragOffer?.destroy()
        dragOffer = nil
    }

    fileprivate func sourceWasCancelled(_ source: WaylandClipboardSource) {
        if currentSource === source {
            currentSource = nil
        }
        if let native = source.native {
            sources.removeValue(forKey: native)
        }
        source.destroy()
    }

    static func normalizedTypes(_ nativeTypes: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for type in nativeTypes {
            let normalized = waylandPlainTextTypes.contains(type)
                ? waylandUTF8PlainTextType
                : type
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    static func advertisedMIMETypes(for representationTypes: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for type in representationTypes.sorted() where seen.insert(type).inserted {
            result.append(type)
        }
        if representationTypes.contains(where: waylandPlainTextTypes.contains) {
            for type in waylandPlainTextMIMETypes where seen.insert(type).inserted {
                result.append(type)
            }
        }
        return result
    }

    static func preferredOfferedType(
        for type: String,
        in offeredTypes: [String]
    ) -> String? {
        if offeredTypes.contains(type) {
            return type
        }
        guard waylandPlainTextTypes.contains(type) else { return nil }
        let preferredTypes = waylandPlainTextMIMETypes + [
            waylandUTF8PlainTextType,
            "public.plain-text",
        ]
        return preferredTypes.first { offeredTypes.contains($0) }
    }

    @MainActor
    private func setDataOnMain(
        _ representations: [String: Data]
    ) throws {
        guard isValid, let dataDevice else {
            throw WaylandClipboardError(
                operation: "Access Wayland data device",
                code: nil
            )
        }
        guard let serial = latestInputSerial else {
            throw WaylandClipboardError(
                operation: "Set selection without an input serial",
                code: nil
            )
        }
        guard representations.keys.allSatisfy({ !$0.utf8.contains(0) }) else {
            throw WaylandClipboardError(
                operation: "Set selection with an invalid content type",
                code: nil
            )
        }

        if representations.isEmpty {
            wl_data_device_set_selection(dataDevice, nil, serial)
            try flushDisplay()
            selectionOffer?.destroy()
            selectionOffer = nil
            currentSource = nil
            return
        }

        guard let source = WaylandClipboardSource(
            manager: manager,
            owner: self,
            representations: representations
        ), let native = source.native else {
            throw WaylandClipboardError(
                operation: "Create Wayland data source",
                code: nil
            )
        }
        sources[native] = source
        wl_data_device_set_selection(dataDevice, native, serial)
        do {
            try flushDisplay()
            selectionOffer?.destroy()
            selectionOffer = nil
            currentSource = source
        } catch {
            sources.removeValue(forKey: native)
            source.destroy()
            throw error
        }
    }

    @MainActor
    private func prepareReadOnMain(
        forType type: String
    ) throws -> WaylandClipboardRead {
        if let currentSource {
            return .immediate(currentSource.data(forRequestedType: type))
        }
        guard let selectionOffer,
              let native = selectionOffer.native,
              let offeredType = Self.preferredOfferedType(
                  for: type,
                  in: selectionOffer.mimeTypes
              ) else {
            return .immediate(nil)
        }

        var descriptors = [Int32](repeating: -1, count: 2)
        let pipeResult = descriptors.withUnsafeMutableBufferPointer {
            Glibc.pipe($0.baseAddress!)
        }
        guard pipeResult == 0 else {
            throw WaylandClipboardError(
                operation: "Create selection pipe",
                code: errno
            )
        }

        offeredType.withCString {
            wl_data_offer_receive(native, $0, descriptors[1])
        }
        Glibc.close(descriptors[1])
        descriptors[1] = -1

        do {
            try flushDisplay()
            return .fileDescriptor(descriptors[0])
        } catch {
            Glibc.close(descriptors[0])
            throw error
        }
    }

    @MainActor
    private func flushDisplay() throws {
        while true {
            if wl_display_flush(display) >= 0 {
                return
            }
            if errno == EINTR {
                continue
            }
            guard errno == EAGAIN else {
                throw WaylandClipboardError(
                    operation: "Flush Wayland display",
                    code: errno
                )
            }

            var descriptor = pollfd(
                fd: wl_display_get_fd(display),
                events: Int16(POLLOUT),
                revents: 0
            )
            var pollResult: Int32
            repeat {
                pollResult = Glibc.poll(&descriptor, 1, -1)
            } while pollResult < 0 && errno == EINTR
            guard pollResult > 0,
                  descriptor.revents & Int16(POLLERR | POLLHUP) == 0 else {
                throw WaylandClipboardError(
                    operation: "Wait for Wayland display",
                    code: pollResult < 0 ? errno : nil
                )
            }
        }
    }

    private static func readAll(from fileDescriptor: Int32) throws -> Data {
        defer { Glibc.close(fileDescriptor) }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes {
                Glibc.read(fileDescriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                result.append(buffer, count: count)
            } else if count == 0 {
                return result
            } else if errno == EINTR {
                continue
            } else {
                throw WaylandClipboardError(
                    operation: "Read selection pipe",
                    code: errno
                )
            }
        }
    }
}

#endif // ENABLE_WAYLAND
