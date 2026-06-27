//
//  File: ObservationCenter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

final class ObservationCenter: @unchecked Sendable {
    static let current = ObservationCenter()

    @TaskLocal private static var activeRecorder: ObservationAccessRecorder?

    private init() {}

    func _withObservationStashed<R>(
        do action: () throws -> R
    ) rethrows -> (value: R, accessOccurred: Bool) {
        let recorder = ObservationAccessRecorder()
        let value = try Self.$activeRecorder.withValue(recorder) {
            try action()
        }
        return (value, recorder.accessOccurred)
    }

    func accessOccurred() {
        Self.activeRecorder?.accessOccurred = true
    }
}

private final class ObservationAccessRecorder: @unchecked Sendable {
    var accessOccurred = false
}
