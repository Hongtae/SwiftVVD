//
//  File: Text.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

final class _TextResourceResolutionState {
    private(set) var pendingVersion: Int?
    private var pendingTransaction = Transaction()
    private var preparedVersion: Int?

    func transaction(for version: Int, candidate: Transaction) -> Transaction {
        guard pendingVersion != version else {
            return pendingTransaction
        }
        pendingVersion = version
        pendingTransaction = candidate
        return candidate
    }

    func didResolve(version: Int) {
        guard pendingVersion == version else { return }
        pendingVersion = nil
        pendingTransaction = Transaction()
    }

    func requiresPreparation(version: Int) -> Bool {
        preparedVersion != version
    }

    func didPrepare(version: Int) {
        preparedVersion = version
    }
}

// TextAlignment: horizontal alignment for multi-line text.
public enum TextAlignment: Hashable, CaseIterable {
    case leading
    case center
    case trailing
}

private struct MultilineTextAlignmentKey: EnvironmentKey {
    static var defaultValue: TextAlignment { .leading }
}

extension EnvironmentValues {
    public var multilineTextAlignment: TextAlignment {
        get { self[MultilineTextAlignmentKey.self] }
        set { self[MultilineTextAlignmentKey.self] = newValue }
    }
}

extension View {
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
        environment(\.multilineTextAlignment, alignment)
    }
}

protocol TextResolutionContext {
    var environment: EnvironmentValues { get set }
    var sceneResources: SceneResources { get }
    var contentScaleFactor: CGFloat { get }

    func resolveTextAttachment(_ image: Image) -> GraphicsContext.ResolvedImage?
}

extension TextResolutionContext {
    var displayScale: CGFloat {
        environment.displayScale
    }

    var contentScaleFactor: CGFloat {
        environment._contentScaleFactor
    }
}

extension GraphicsContext: TextResolutionContext {
    func resolveTextAttachment(_ image: Image) -> ResolvedImage? {
        resolve(image)
    }
}

struct GraphTextResolutionContext: TextResolutionContext {
    var environment: EnvironmentValues
    let sceneResources: SceneResources

    func resolveTextAttachment(_ image: Image) -> GraphicsContext.ResolvedImage? {
        var resolved: GraphicsContext.ResolvedImage
        if let symbol = image.provider.makeVectorSymbol() {
            resolved = GraphicsContext.ResolvedImage(
                symbol: symbol.applyingEffectiveFontMetrics(in: environment)
            )
        } else if let svg = image.provider.makeSVG() {
            resolved = GraphicsContext.ResolvedImage(svg: svg)
        } else {
            return nil
        }
        resolved.applyResizingProvider(image.provider)
        return resolved
    }
}

class AnyTextStorage: CustomDebugStringConvertible {
    var debugDescription: String {
        let typeName = String(describing: type(of: self))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let text = resolveText(in: EnvironmentValues())
        return "<\(typeName): \(pointer)>: \(String(reflecting: text))"
    }

    func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveText(in environment: EnvironmentValues) -> String {
        fatalError("This method should be overridden by subclasses.")
    }
    func resolveText(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> String {
        resolveText(in: environment)
    }
    func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext,
        referenceDate: Date
    ) -> GraphicsContext.ResolvedText? {
        resolve(typefaces: typefaces, context: context)
    }
    func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        resolveText(in: environment)
    }
    func sizeVariantTexts(in environment: EnvironmentValues) -> [(TextSizeVariant, String)]? {
        nil
    }
    func sizeVariantTexts(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> [(TextSizeVariant, String)]? {
        sizeVariantTexts(in: environment)
    }
    func nextUpdateDelay(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> TimeInterval? {
        nil
    }
    func needsDynamicRenderingInArchive(in environment: EnvironmentValues) -> Bool {
        false
    }
    func requiresBackendResolution(in environment: EnvironmentValues) -> Bool {
        false
    }
    func contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        hasher.combine(resolveText(in: environment, referenceDate: referenceDate))
    }
    func isEqual(to other: AnyTextStorage) -> Bool {
        self === other
    }
}

class AnyTextModifier {
    func isEqual(to other: AnyTextModifier) -> Bool {
        self === other
    }

    func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

private func _dynamicArchiveStorage(
    for storage: NSAttributedString,
    enabled: Bool
) -> NSAttributedString? {
    guard enabled else { return nil }
    let dynamicStorage = NSMutableAttributedString(attributedString: storage)
    if dynamicStorage.length > 0 {
        dynamicStorage.addAttribute(
            .updateSchedule,
            value: true,
            range: NSRange(location: 0, length: dynamicStorage.length)
        )
    }
    return dynamicStorage
}

private struct CodableRawRepresentable<Value>: Codable, Equatable, @unchecked Sendable
where Value: RawRepresentable & Equatable,
      Value.RawValue: Codable & Equatable {
    var wrappedValue: Value

    init(_ wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Value.RawValue.self)
        guard let value = Value(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid raw value for \(Value.self)."
            )
        }
        wrappedValue = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.rawValue)
    }
}

private class AnyFormatStyleBox {
    func resolve(
        locale: Locale,
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        fatalError("This method should be overridden by subclasses.")
    }

    func resolveText(locale: Locale) -> String {
        fatalError("This method should be overridden by subclasses.")
    }

    func isEqual(to other: AnyFormatStyleBox) -> Bool {
        false
    }
}

private final class FormatStyleBox<Style>: AnyFormatStyleBox
where Style: FormatStyle, Style.FormatInput: Equatable {
    let input: Style.FormatInput
    let format: Style

    init(input: Style.FormatInput, format: Style) {
        self.input = input
        self.format = format
    }

    override func resolve(
        locale: Locale,
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        let output = format.locale(locale).format(input)
        if let string = output as? String {
            return .init(
                runs: [.text(typefaces, string)],
                scaleFactor: context.contentScaleFactor,
                displayScale: context.displayScale
            )
        }
        if let attributed = output as? AttributedString {
            return _resolvedAttributedText(
                attributed,
                defaultTypefaces: typefaces,
                context: context
            )
        }
        return .init(
            runs: [],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(locale: Locale) -> String {
        let output = format.locale(locale).format(input)
        if let string = output as? String { return string }
        if let attributed = output as? AttributedString {
            return String(attributed.characters)
        }
        return String(describing: output)
    }

    override func isEqual(to other: AnyFormatStyleBox) -> Bool {
        guard let other = other as? FormatStyleBox<Style> else {
            return false
        }
        return input == other.input && format == other.format
    }
}

private final class FormatStyleStorage: AnyTextStorage {
    let storage: AnyFormatStyleBox

    init<Style>(input: Style.FormatInput, format: Style)
    where Style: FormatStyle, Style.FormatInput: Equatable {
        self.storage = FormatStyleBox(input: input, format: format)
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        storage.resolve(
            locale: context.environment.locale,
            typefaces: typefaces,
            context: context
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        storage.resolveText(locale: environment.locale)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? FormatStyleStorage else { return false }
        return storage.isEqual(to: other.storage)
    }
}

private final class LocalizedStringResourceStorage: AnyTextStorage {
    let resource: LocalizedStringResource

    init(_ resource: LocalizedStringResource) {
        self.resource = resource
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        _resolvedAttributedText(
            AttributedString(localized: resource),
            defaultTypefaces: typefaces,
            context: context
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String(localized: resource)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? LocalizedStringResourceStorage else {
            return false
        }
        return resource == other.resource
    }
}

private final class DateTextStorage: AnyTextStorage {
    enum Storage: Equatable {
        case interval(interval: DateInterval)
    }

    let storage: Storage

    init(_ storage: Storage) {
        self.storage = storage
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        .init(
            runs: [.text(typefaces, resolveText(in: context.environment))],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        switch storage {
        case let .interval(interval):
            format(interval: interval, environment: environment)
        }
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? DateTextStorage else { return false }
        return storage == other.storage
    }

    private func format(
        interval: DateInterval,
        environment: EnvironmentValues
    ) -> String {
        var calendar = environment.calendar
        calendar.timeZone = environment.timeZone

        let formatter = DateFormatter()
        formatter.locale = environment.locale
        formatter.calendar = calendar
        formatter.timeZone = environment.timeZone

        let day = calendar.dateComponents(
            [.day],
            from: interval.start,
            to: interval.end
        ).day
        if day != 0 {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: interval.start) +
                " – " + formatter.string(from: interval.end)
        }

        formatter.setLocalizedDateFormatFromTemplate("jm")
        var start = formatter.string(from: interval.start)
        let end = formatter.string(from: interval.end)
        let startHour = calendar.component(.hour, from: interval.start)
        let endHour = calendar.component(.hour, from: interval.end)
        // Foundation exposes different nullability for these symbols by platform.
        let startDesignatorSymbol: String? = (
            startHour < 12 ? formatter.amSymbol : formatter.pmSymbol
        )
        let endDesignatorSymbol: String? = (
            endHour < 12 ? formatter.amSymbol : formatter.pmSymbol
        )
        let startDesignator = startDesignatorSymbol ?? ""
        let endDesignator = endDesignatorSymbol ?? ""
        if !startDesignator.isEmpty,
           startDesignator == endDesignator,
           let range = start.range(of: startDesignator) {
            start.removeSubrange(range)
            start = start.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return start + "–" + end
    }
}

private protocol _TimeDataFormattingSource: Equatable {
    associatedtype Value

    func value(referenceDate: Date) -> Value
    func date(for value: Value) -> Date?
    var pausesUpdates: Bool { get }
}

private extension _TimeDataFormattingSource {
    var pausesUpdates: Bool { false }
}

private struct _DateTimeDataSourceStorage: _TimeDataFormattingSource {
    var date: Date

    func value(referenceDate: Date) -> Date {
        date
    }

    func date(for value: Date) -> Date? { value }
}

private struct _TimerIntervalTimeDataSourceStorage: _TimeDataFormattingSource {
    enum Storage: Equatable {
        case identity
        case identityWithPause(Date)
    }

    var storage: Storage

    var pausesUpdates: Bool {
        if case .identityWithPause = storage { return true }
        return false
    }

    func value(referenceDate: Date) -> Date {
        switch storage {
        case .identity:
            referenceDate
        case .identityWithPause(let pauseDate):
            pauseDate
        }
    }

    func date(for value: Date) -> Date? { value }
}

private struct _PublicTimeDataSourceStorage<Value>: _TimeDataFormattingSource {
    var source: TimeDataSource<Value>

    func value(referenceDate: Date) -> Value {
        source.box.value(for: referenceDate)
    }

    func date(for value: Value) -> Date? {
        source.box.date(for: value)
    }

    static func == (
        lhs: _PublicTimeDataSourceStorage<Value>,
        rhs: _PublicTimeDataSourceStorage<Value>
    ) -> Bool {
        lhs.source.box.identity == rhs.source.box.identity
    }
}

private protocol _TimeDataFormat: Equatable {
    associatedtype Input
    associatedtype Output: Equatable & Hashable

    func format(
        _ input: Input,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> Output
    func resolvedText(
        _ output: Output,
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText?
    func plainText(_ output: Output) -> String
    func nextUpdateDelay(
        for input: Input,
        referenceDate: Date,
        sourceDate: (Input) -> Date?
    ) -> TimeInterval
    var producesRelativeSizeVariants: Bool { get }
}

private extension _TimeDataFormat where Output == String {
    func resolvedText(
        _ output: String,
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        .init(
            runs: [.text(typefaces, output)],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    func plainText(_ output: String) -> String { output }
}

private struct _DateStyleTimeDataFormat: _TimeDataFormat {
    var style: Text.DateStyle

    var producesRelativeSizeVariants: Bool {
        style == .relative
    }

    func format(
        _ date: Date,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        switch style.kind {
        case .time:
            date.formatted(.dateTime.hour().minute())
        case .date:
            date.formatted(.dateTime.year().month().day())
        case .relative:
            Duration.seconds(abs(date.timeIntervalSince(referenceDate))).formatted(
                .units(
                    allowed: [.days, .hours, .minutes, .seconds],
                    width: unitsStyle == .narrow ? .narrow : .abbreviated,
                    maximumUnitCount: 2
                ).locale(locale)
            )
        case .offset:
            offsetString(for: date, referenceDate: referenceDate, locale: locale)
        case .timer:
            timerString(for: date, referenceDate: referenceDate)
        }
    }

    func nextUpdateDelay(
        for date: Date,
        referenceDate: Date,
        sourceDate: (Date) -> Date?
    ) -> TimeInterval {
        let interval = date.timeIntervalSince(referenceDate)
        let magnitude = abs(interval)
        let unit: TimeInterval
        switch style.kind {
        case .relative:
            if magnitude >= 86_400 {
                unit = 3_600
            } else if magnitude >= 3_600 {
                unit = 60
            } else {
                unit = 1
            }
        case .offset:
            if magnitude >= 86_400 {
                unit = 86_400
            } else if magnitude >= 3_600 {
                unit = 3_600
            } else if magnitude >= 60 {
                unit = 60
            } else {
                unit = 1
            }
        case .timer:
            unit = 1
        case .time, .date:
            return .infinity
        }

        let remainder = magnitude.truncatingRemainder(dividingBy: unit)
        let delay = interval >= 0 ? remainder : unit - remainder
        return delay > 1e-6 ? delay : unit
    }

    private func offsetString(
        for date: Date,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        let interval = date.timeIntervalSince(referenceDate)
        let value = Duration.seconds(abs(interval)).formatted(
            .units(
                allowed: [.days, .hours, .minutes, .seconds],
                width: .wide,
                maximumUnitCount: 1
            ).locale(locale)
        )
        return interval > 0 ? "−\(value)" : "+\(value)"
    }

    private func timerString(for date: Date, referenceDate: Date) -> String {
        Duration.seconds(abs(date.timeIntervalSince(referenceDate))).formatted(
            .time(pattern: .hourMinuteSecond)
        )
    }
}

private struct _TimerIntervalTimeDataFormat: _TimeDataFormat {
    var interval: ClosedRange<Date>
    var countsDown: Bool
    var showsHours: Bool

    var producesRelativeSizeVariants: Bool { false }

    func format(
        _ date: Date,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        let duration = max(interval.upperBound.timeIntervalSince(interval.lowerBound), 0)
        let elapsed = min(
            max(date.timeIntervalSince(interval.lowerBound), 0),
            duration
        )
        let seconds: Int
        if countsDown {
            seconds = Int(ceil(max(duration - elapsed, 0)))
        } else {
            seconds = Int(floor(elapsed))
        }
        return timerString(seconds: seconds)
    }

    func nextUpdateDelay(
        for date: Date,
        referenceDate: Date,
        sourceDate: (Date) -> Date?
    ) -> TimeInterval {
        guard date >= interval.lowerBound, date < interval.upperBound else {
            if date < interval.lowerBound {
                return interval.lowerBound.timeIntervalSince(date)
            }
            return .infinity
        }
        let elapsed = date.timeIntervalSince(interval.lowerBound)
        let remainder = elapsed.truncatingRemainder(dividingBy: 1)
        return remainder > 1e-6 ? 1 - remainder : 1
    }

    private func timerString(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if showsHours, hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        let totalMinutes = seconds / 60
        return String(format: "%d:%02d", totalMinutes, remainingSeconds)
    }
}

private struct _DiscreteStringTimeDataFormat<Format>: _TimeDataFormat
where Format: DiscreteFormatStyle, Format.FormatOutput == String {
    var style: Format

    var producesRelativeSizeVariants: Bool { false }

    func format(
        _ input: Format.FormatInput,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> String {
        style.locale(locale).format(input)
    }

    func nextUpdateDelay(
        for input: Format.FormatInput,
        referenceDate: Date,
        sourceDate: (Format.FormatInput) -> Date?
    ) -> TimeInterval {
        guard let nextInput = style.discreteInput(after: input),
              let nextDate = sourceDate(nextInput) else {
            return .infinity
        }
        let delay = nextDate.timeIntervalSince(referenceDate)
        return delay > 1e-6 ? delay : .infinity
    }
}

private struct _DiscreteAttributedTimeDataFormat<Format>: _TimeDataFormat
where Format: DiscreteFormatStyle, Format.FormatOutput == AttributedString {
    var style: Format

    var producesRelativeSizeVariants: Bool { false }

    func format(
        _ input: Format.FormatInput,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle,
        referenceDate: Date,
        locale: Locale
    ) -> AttributedString {
        style.locale(locale).format(input)
    }

    func resolvedText(
        _ output: AttributedString,
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        _resolvedAttributedText(
            output,
            defaultTypefaces: typefaces,
            context: context
        )
    }

    func plainText(_ output: AttributedString) -> String {
        String(output.characters)
    }

    func nextUpdateDelay(
        for input: Format.FormatInput,
        referenceDate: Date,
        sourceDate: (Format.FormatInput) -> Date?
    ) -> TimeInterval {
        guard let nextInput = style.discreteInput(after: input),
              let nextDate = sourceDate(nextInput) else {
            return .infinity
        }
        let delay = nextDate.timeIntervalSince(referenceDate)
        return delay > 1e-6 ? delay : .infinity
    }
}

private final class TimeDataFormattingStorage<Source, Format>: AnyTextStorage
where Source: _TimeDataFormattingSource,
      Format: _TimeDataFormat,
      Source.Value == Format.Input {
    let source: Source
    let format: Format
    let reducedLuminanceBudget: Double?

    init(source: Source, format: Format, reducedLuminanceBudget: Double? = nil) {
        self.source = source
        self.format = format
        self.reducedLuminanceBudget = reducedLuminanceBudget
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        resolve(typefaces: typefaces, context: context, referenceDate: Date())
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext,
        referenceDate: Date
    ) -> GraphicsContext.ResolvedText? {
        let value = source.value(referenceDate: referenceDate)
        let output = format.format(
            value,
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: context.environment.locale
        )
        return format.resolvedText(output, typefaces: typefaces, context: context)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        resolveText(in: environment, referenceDate: Date())
    }

    override func resolveText(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> String {
        format.plainText(format.format(
            source.value(referenceDate: referenceDate),
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
    }

    override func sizeVariantTexts(
        in environment: EnvironmentValues
    ) -> [(TextSizeVariant, String)]? {
        sizeVariantTexts(in: environment, referenceDate: Date())
    }

    override func sizeVariantTexts(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> [(TextSizeVariant, String)]? {
        guard format.producesRelativeSizeVariants else { return nil }
        let value = source.value(referenceDate: referenceDate)
        let regular = format.plainText(format.format(
            value,
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
        let compact = format.plainText(format.format(
            value,
            unitsStyle: .narrow,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
        guard regular != compact else {
            return [(.regular, regular)]
        }
        return [(.regular, regular), (.compact, compact)]
    }

    override func nextUpdateDelay(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> TimeInterval? {
        guard !source.pausesUpdates else { return nil }
        let value = source.value(referenceDate: referenceDate)
        let delay = format.nextUpdateDelay(
            for: value,
            referenceDate: referenceDate,
            sourceDate: source.date(for:)
        )
        return delay.isFinite ? delay : nil
    }

    override func needsDynamicRenderingInArchive(in environment: EnvironmentValues) -> Bool {
        true
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        guard let other = other as? TimeDataFormattingStorage<Source, Format> else {
            return false
        }
        return source == other.source &&
            format == other.format &&
            reducedLuminanceBudget == other.reducedLuminanceBudget
    }

    override func contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        hasher.combine(format.format(
            source.value(referenceDate: referenceDate),
            unitsStyle: .wide,
            referenceDate: referenceDate,
            locale: environment.locale
        ))
    }
}

class LocalizedTextStorage: AnyTextStorage {
    let key: LocalizedStringKey
    let table: String?
    let bundle: Bundle?
    init(key: LocalizedStringKey, table: String?, bundle: Bundle?) {
        self.key = key
        self.table = table
        self.bundle = bundle
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        let segments = resolve(locale: context.environment.locale)
        var runs: [GraphicsContext.ResolvedText.Run] = []
        for segment in segments {
            switch segment {
            case let .attributedString(value):
                runs.append(contentsOf: _resolvedAttributedText(
                    value,
                    defaultTypefaces: typefaces,
                    context: context
                ).runs)
            case let .text(text):
                guard let resolved = text._resolve(
                    context: context,
                    referenceDate: Date()
                ) else {
                    return nil
                }
                runs.append(contentsOf: resolved.runs.map {
                    $0.applying(foregroundColor: text.foregroundColor)
                })
            }
        }
        return .init(
            runs: runs,
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        resolve(locale: environment.locale).reduce(into: String()) { result, segment in
            switch segment {
            case let .attributedString(value):
                result.append(contentsOf: value.characters)
            case let .text(text):
                result.append(text._resolveText(in: environment))
            }
        }
    }

    override func requiresBackendResolution(
        in environment: EnvironmentValues
    ) -> Bool {
        resolve(locale: environment.locale).contains { segment in
            guard case let .text(text) = segment else { return false }
            return text._requiresBackendResolution(in: environment)
        }
    }

    private func resolve(locale: Locale) -> [LocalizedStringKey.ResolvedSegment] {
        key.resolve(
            table: table,
            bundle: localizedBundle(for: locale),
            locale: locale
        )
    }

    private func localizedBundle(for locale: Locale) -> Bundle {
        let rootBundle = bundle ?? .main
        #if !canImport(Darwin)
        // The compatibility resolver owns explicit locale selection and
        // strings-dictionary loading on ports without localized initializers.
        return rootBundle
        #else
        let availableLocalizations = rootBundle.localizations
        guard !availableLocalizations.isEmpty else {
            return rootBundle
        }

        var candidates = LocalizationResolver.localizationCandidates(
            from: availableLocalizations,
            for: locale
        )
        if let developmentLocalization = rootBundle.developmentLocalization,
           !candidates.contains(developmentLocalization) {
            candidates.append(developmentLocalization)
        }
        for localization in Bundle.preferredLocalizations(from: availableLocalizations)
        where !candidates.contains(localization) {
            candidates.append(localization)
        }

        let tableName = table ?? "Localizable"
        for localization in candidates {
            let tableURL = rootBundle.url(
                forResource: tableName,
                withExtension: "strings",
                subdirectory: nil,
                localization: localization
            ) ?? rootBundle.url(
                forResource: tableName,
                withExtension: "stringsdict",
                subdirectory: nil,
                localization: localization
            )
            if let tableURL,
               let localizedBundle = Bundle(url: tableURL.deletingLastPathComponent()) {
                return localizedBundle
            }
        }
        return rootBundle
        #endif
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.key == other.key && self.table == other.table && self.bundle == other.bundle
        }
        return false
    }
}

class ConcatenatedTextStorage: AnyTextStorage {
    let first: Text
    let second: Text
    init(first: Text, second: Text) {
        self.first = first
        self.second = second
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        guard let first = first._resolve(context: context, referenceDate: Date()),
              let second = second._resolve(context: context, referenceDate: Date()) else {
            return nil
        }
        return .init(
            runs: first.runs + second.runs,
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        first._resolveText(in: environment) + second._resolveText(in: environment)
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        guard let first = first._resolveTransitionText(in: environment),
              let second = second._resolveTransitionText(in: environment) else {
            return nil
        }
        return first + second
    }

    override func requiresBackendResolution(
        in environment: EnvironmentValues
    ) -> Bool {
        first._requiresBackendResolution(in: environment) ||
            second._requiresBackendResolution(in: environment)
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.first == other.first && self.second == other.second
        }
        return false
    }
}

class AttachmentTextStorage: AnyTextStorage {
    let image: Image
    init(_ image: Image) {
        self.image = image
    }

    override func resolve(
        typefaces: [Typeface],
        context: any TextResolutionContext
    ) -> GraphicsContext.ResolvedText? {
        guard let image = context.resolveTextAttachment(self.image) else {
            return nil
        }
        return .init(
            runs: [.attachment(typefaces, image)],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String()
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        nil
    }

    override func requiresBackendResolution(
        in environment: EnvironmentValues
    ) -> Bool {
        image.provider.requiresBackendResolution
    }

    override func isEqual(to other: AnyTextStorage) -> Bool {
        if let other = other as? Self {
            return self.image == other.image
        }
        return false
    }
}

public struct Text: Equatable {
    enum Storage: Equatable {
        case verbatim(String)
        case anyTextStorage(AnyTextStorage)

        static func == (lhs: Text.Storage, rhs: Text.Storage) -> Bool {
            if case let .verbatim(s1) = lhs, case let .verbatim(s2) = rhs {
                return s1 == s2
            }
            if case let .anyTextStorage(s1) = lhs, case let .anyTextStorage(s2) = rhs {
                return s1.isEqual(to: s2)
            }
            return false
        }
    }

    var storage: Storage

    public enum Case: Hashable {
        case lowercase
        case uppercase
    }

    public struct LineStyle: Hashable, Sendable {
        public struct Pattern: Equatable, Sendable {
            let rawValue: Int

            public static let solid = Pattern(rawValue: 0)
            public static let dot = Pattern(rawValue: 0x100)
            public static let dash = Pattern(rawValue: 0x200)
            public static let dashDot = Pattern(rawValue: 0x300)
            public static let dashDotDot = Pattern(rawValue: 0x400)
        }

        let nsUnderlineStyleValue: Int
        let color: Color?
        var pattern: Pattern {
            Pattern(rawValue: nsUnderlineStyleValue & 0xF00)
        }

        public init(pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) {
            self.nsUnderlineStyleValue = 1 | pattern.rawValue
            self.color = color
        }

        public static let single = LineStyle()
    }

    public struct DateStyle: Equatable, Codable, Sendable {
        fileprivate enum Storage: UInt8, Codable, Sendable {
            case time
            case date
            case relative
            case offset
            case timer
        }

        private struct UnitsConfiguration: Equatable, Codable, @unchecked Sendable {
            enum Style: UInt8, Codable, Sendable {
                case short
                case brief
                case full
            }

            var _units: CodableRawRepresentable<NSCalendar.Unit>
            var style: Style
        }

        private var storage: Storage
        private var unitConfiguration: UnitsConfiguration?

        fileprivate var kind: Storage {
            storage
        }

        private init(_ storage: Storage) {
            self.storage = storage
            self.unitConfiguration = nil
        }

        public static let time = DateStyle(.time)
        public static let date = DateStyle(.date)
        public static let relative = DateStyle(.relative)
        public static let offset = DateStyle(.offset)
        public static let timer = DateStyle(.timer)

        private enum CodingKeys: String, CodingKey {
            case storage
            case unitConfiguration
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            storage = try container.decode(Storage.self, forKey: .storage)
            unitConfiguration = try container.decodeIfPresent(
                UnitsConfiguration.self,
                forKey: .unitConfiguration
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(storage, forKey: .storage)
            try container.encodeIfPresent(unitConfiguration, forKey: .unitConfiguration)
        }
    }

    enum Modifier: Equatable {
        case color(Color?)
        case font(Font?)
        case italic
        case weight(Font.Weight?)
        case kerning(CGFloat)
        case tracking(CGFloat)
        case baseline(CGFloat)
        case rounded
        case anyTextModifier(AnyTextModifier)

        static func == (lhs: Modifier, rhs: Modifier) -> Bool {
            switch (lhs, rhs) {
            case let (.color(lhs), .color(rhs)):
                lhs == rhs
            case let (.font(lhs), .font(rhs)):
                lhs == rhs
            case (.italic, .italic), (.rounded, .rounded):
                true
            case let (.weight(lhs), .weight(rhs)):
                lhs == rhs
            case let (.kerning(lhs), .kerning(rhs)),
                 let (.tracking(lhs), .tracking(rhs)),
                 let (.baseline(lhs), .baseline(rhs)):
                lhs == rhs
            case let (.anyTextModifier(lhs), .anyTextModifier(rhs)):
                lhs.isEqual(to: rhs)
            default:
                false
            }
        }

        func hashResolution(into hasher: inout Hasher) {
            switch self {
            case let .color(value):
                hasher.combine(0)
                hasher.combine(value)
            case let .font(value):
                hasher.combine(1)
                hasher.combine(value)
            case .italic:
                hasher.combine(2)
            case let .weight(value):
                hasher.combine(3)
                hasher.combine(value)
            case let .kerning(value):
                hasher.combine(4)
                hasher.combine(value)
            case let .tracking(value):
                hasher.combine(5)
                hasher.combine(value)
            case let .baseline(value):
                hasher.combine(6)
                hasher.combine(value)
            case .rounded:
                hasher.combine(7)
            case let .anyTextModifier(value):
                hasher.combine(8)
                value.hashResolution(into: &hasher)
            }
        }
    }

    var modifiers: [Modifier]

    public init(
        _ key: LocalizedStringKey,
        tableName: String? = nil,
        bundle: Bundle? = nil,
        comment: StaticString? = nil
    ) {
        self.storage = .anyTextStorage(
            LocalizedTextStorage(key: key, table: tableName, bundle: bundle)
        )
        self.modifiers = []
    }

    @_disfavoredOverload
    public init<S>(_ content: S) where S: StringProtocol {
        self.storage = .verbatim(String(content))
        self.modifiers = []
    }

    public init(verbatim content: String) {
        self.storage = .verbatim(content)
        self.modifiers = []
    }

    @_disfavoredOverload
    public init(_ attributedContent: AttributedString) {
        self.storage = .anyTextStorage(AttributedStringTextStorage(attributedContent))
        self.modifiers = []
    }

    public init(_ image: Image) {
        self.storage = .anyTextStorage(AttachmentTextStorage(image))
        self.modifiers = []
    }

    public init<F>(_ input: F.FormatInput, format: F)
    where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == String {
        self.storage = .anyTextStorage(
            FormatStyleStorage(input: input, format: format)
        )
        self.modifiers = []
    }

    public init<F>(_ input: F.FormatInput, format: F)
    where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        self.storage = .anyTextStorage(
            FormatStyleStorage(input: input, format: format)
        )
        self.modifiers = []
    }

    @_disfavoredOverload
    public init(_ resource: LocalizedStringResource) {
        self.storage = .anyTextStorage(LocalizedStringResourceStorage(resource))
        self.modifiers = []
    }

    public init(_ date: Date, style: DateStyle) {
        switch style.kind {
        case .time:
            self.storage = .anyTextStorage(
                FormatStyleStorage(
                    input: date,
                    format: Date.FormatStyle.dateTime.hour().minute()
                )
            )
        case .date:
            self.storage = .anyTextStorage(
                FormatStyleStorage(
                    input: date,
                    format: Date.FormatStyle.dateTime.year().month().day()
                )
            )
        case .relative, .offset, .timer:
            self.storage = .anyTextStorage(
                TimeDataFormattingStorage(
                    source: _DateTimeDataSourceStorage(date: date),
                    format: _DateStyleTimeDataFormat(style: style)
                )
            )
        }
        self.modifiers = []
    }

    public init(_ dates: ClosedRange<Date>) {
        self.storage = .anyTextStorage(DateTextStorage(
            .interval(interval: DateInterval(
                start: dates.lowerBound,
                end: dates.upperBound
            ))
        ))
        self.modifiers = []
    }

    public init(_ interval: DateInterval) {
        self.storage = .anyTextStorage(DateTextStorage(
            .interval(interval: interval)
        ))
        self.modifiers = []
    }

    public init(
        timerInterval: ClosedRange<Date>,
        pauseTime: Date? = nil,
        countsDown: Bool = true,
        showsHours: Bool = true
    ) {
        let sourceStorage: _TimerIntervalTimeDataSourceStorage.Storage
        if let pauseTime {
            let resolvedPause: Date
            if countsDown {
                resolvedPause = timerInterval.lowerBound.addingTimeInterval(
                    timerInterval.upperBound.timeIntervalSince(pauseTime)
                )
            } else {
                resolvedPause = pauseTime
            }
            sourceStorage = .identityWithPause(resolvedPause)
        } else {
            sourceStorage = .identity
        }
        self.storage = .anyTextStorage(
            TimeDataFormattingStorage(
                source: _TimerIntervalTimeDataSourceStorage(storage: sourceStorage),
                format: _TimerIntervalTimeDataFormat(
                    interval: timerInterval,
                    countsDown: countsDown,
                    showsHours: showsHours
                ),
                reducedLuminanceBudget: 60
            )
        )
        self.modifiers = []
    }

    @_disfavoredOverload
    public init<Value, Format>(
        _ source: TimeDataSource<Value>,
        format: Format
    ) where Value == Format.FormatInput,
            Format: DiscreteFormatStyle,
            Format.FormatOutput == String {
        self.storage = .anyTextStorage(
            TimeDataFormattingStorage(
                source: _PublicTimeDataSourceStorage(source: source),
                format: _DiscreteStringTimeDataFormat(style: format)
            )
        )
        self.modifiers = []
    }

    public init<Value, Format>(
        _ source: TimeDataSource<Value>,
        format: Format
    ) where Value == Format.FormatInput,
            Format: DiscreteFormatStyle,
            Format.FormatOutput == AttributedString {
        self.storage = .anyTextStorage(
            TimeDataFormattingStorage(
                source: _PublicTimeDataSourceStorage(source: source),
                format: _DiscreteAttributedTimeDataFormat(style: format)
            )
        )
        self.modifiers = []
    }

    init(storage: Storage, modifiers: [Modifier]) {
        self.storage = storage
        self.modifiers = modifiers
    }

    public func _resolveText(in environment: EnvironmentValues) -> String {
        _resolveText(in: environment, referenceDate: Date())
    }

    func _resolveText(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> String {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveText(in: environment, referenceDate: referenceDate)
        }
        return String()
    }

    func _resolveTransitionText(in environment: EnvironmentValues) -> String? {
        if case let .verbatim(text) = self.storage {
            return text
        }
        if case let .anyTextStorage(storage) = self.storage {
            return storage.resolveTransitionText(in: environment)
        }
        return nil
    }

    func _resolve(context: GraphicsContext) -> GraphicsContext.ResolvedText {
        _resolve(context: context, referenceDate: Date())
    }

    func _resolve(
        context: GraphicsContext,
        referenceDate: Date
    ) -> GraphicsContext.ResolvedText {
        guard let resolved = _resolve(
            context: context as any TextResolutionContext,
            referenceDate: referenceDate
        ) else {
            fatalError("A graphics text context must resolve every attachment.")
        }
        return resolved
    }

    func _resolve(
        context: any TextResolutionContext,
        referenceDate: Date
    ) -> GraphicsContext.ResolvedText? {
        var font = self.font ?? context.environment.effectiveFont
        if let fontWeight {
            font = font.weight(fontWeight)
        } else if boldValue == true {
            font = font.bold()
        }
        if italicValue == true {
            font = font.italic()
        }
        var resolutionContext = context
        resolutionContext.environment.font = font
        font = font.resolved(in: context.environment)
        let defaultFace = font.typeface(
            forContext: context.sceneResources,
            contentScaleFactor: context.contentScaleFactor
        )
        let fallbackFaces = font.fallbackTypefaces
        let faces = ([defaultFace] + fallbackFaces).compactMap {$0 }

        if faces.isEmpty == false {
            var runs: [GraphicsContext.ResolvedText.Run] = []
            if case let .verbatim(text) = self.storage {
                runs = [.text(faces, text)]
                return GraphicsContext.ResolvedText(
                    runs: runs.map {
                        $0.applying(customAttributes)
                            .applying(textModifiers: modifiers)
                    },
                    scaleFactor: context.contentScaleFactor,
                    displayScale: context.displayScale
                )
            }
            else if case let .anyTextStorage(text) = self.storage {
                guard let resolved = text.resolve(
                    typefaces: faces,
                    context: resolutionContext,
                    referenceDate: referenceDate
                ) else {
                    return nil
                }
                guard !customAttributes.isEmpty || hasResolvedRunModifiers else {
                    return resolved
                }
                return GraphicsContext.ResolvedText(
                    runs: resolved.runs.map {
                        $0.applying(customAttributes)
                            .applying(textModifiers: modifiers)
                    },
                    scaleFactor: context.contentScaleFactor,
                    displayScale: context.displayScale
                )
            }
        }
        return .init(
            runs: [],
            scaleFactor: context.contentScaleFactor,
            displayScale: context.displayScale
        )
    }

    func _sizeVariantTexts(in environment: EnvironmentValues) -> [(TextSizeVariant, String)]? {
        _sizeVariantTexts(in: environment, referenceDate: Date())
    }

    func _sizeVariantTexts(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> [(TextSizeVariant, String)]? {
        guard case let .anyTextStorage(storage) = storage else { return nil }
        return storage.sizeVariantTexts(in: environment, referenceDate: referenceDate)
    }

    func _nextUpdateDelay(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> TimeInterval? {
        guard case let .anyTextStorage(storage) = storage else { return nil }
        return storage.nextUpdateDelay(in: environment, referenceDate: referenceDate)
    }

    func _needsDynamicRenderingInArchive(in environment: EnvironmentValues) -> Bool {
        guard case let .anyTextStorage(storage) = storage else { return false }
        return storage.needsDynamicRenderingInArchive(in: environment)
    }

    func _requiresBackendResolution(in environment: EnvironmentValues) -> Bool {
        guard case let .anyTextStorage(storage) = storage else { return false }
        return storage.requiresBackendResolution(in: environment)
    }

    func _contentHash(
        into hasher: inout Hasher,
        environment: EnvironmentValues,
        referenceDate: Date
    ) {
        switch storage {
        case let .verbatim(text):
            hasher.combine(text)
        case let .anyTextStorage(storage):
            storage.contentHash(
                into: &hasher,
                environment: environment,
                referenceDate: referenceDate
            )
        }
    }

    func _resolutionVersion(
        in environment: EnvironmentValues,
        referenceDate: Date
    ) -> Int {
        var hasher = Hasher()
        _contentHash(
            into: &hasher,
            environment: environment,
            referenceDate: referenceDate
        )
        hasher.combine(environment.effectiveFont.hashValue)
        hasher.combine(environment.defaultFontRenderingMode)
        hasher.combine(environment.displayScale)
        hasher.combine(environment._contentScaleFactor)
        for modifier in modifiers {
            modifier.hashResolution(into: &hasher)
        }
        customAttributes.hash(into: &hasher)
        return hasher.finalize()
    }

    func _resolveStyledText(
        context: any TextResolutionContext,
        referenceDate: Date,
        archiveOptions: ArchivedViewInput.Value,
        features: ResolvedProperties.Features,
        sizeFitting: Bool
    ) -> ResolvedStyledText? {
        guard let resolved = _resolve(
            context: context,
            referenceDate: referenceDate
        ) else {
            return nil
        }

        let environment = context.environment
        let layoutProperties = TextLayoutProperties(environment)
        let transitionText = _resolveTransitionText(in: environment)
        let needsDynamicArchive = _needsDynamicRenderingInArchive(in: environment)
        let version = _resolutionVersion(
            in: environment,
            referenceDate: referenceDate
        )

        func makeStyledText(
            _ source: GraphicsContext.ResolvedText,
            additionalFeatures: ResolvedProperties.Features = []
        ) -> ResolvedStyledText {
            var resolved = source
            resolved.shading = foregroundShading(in: environment)
            let attributedStorage = resolved.attributedStorage
            let resolvedString = _resolveText(
                in: environment,
                referenceDate: referenceDate
            )
            let storage: NSAttributedString
            if attributedStorage.length == 0 && !resolvedString.isEmpty {
                storage = NSAttributedString(string: resolvedString)
            } else {
                storage = attributedStorage
            }
            return ResolvedStyledText(
                storage: needsDynamicArchive
                    ? _dynamicArchiveStorage(
                        for: storage,
                        enabled: true
                    ) ?? storage
                    : storage,
                layoutProperties: layoutProperties,
                archiveOptions: archiveOptions,
                features: features
                    .union(resolved.resolvedFeatures)
                    .union(additionalFeatures),
                resolvedText: resolved,
                version: version,
                transitionText: transitionText
            )
        }

        guard sizeFitting,
              let variants = _resolveSizeVariants(
                context: context,
                referenceDate: referenceDate
              ) else {
            return makeStyledText(resolved)
        }

        var styledVariants = variants.map { _, variant in
            makeStyledText(variant, additionalFeatures: .isUniqueSizeVariant)
        }
        if let terminal = variants.last?.1 {
            styledVariants.append(makeStyledText(terminal))
        }
        guard let first = styledVariants.first else {
            return makeStyledText(resolved)
        }
        first.setSizeVariantCandidates(styledVariants)
        return first
    }

    func _resolveSizeVariants(
        context: any TextResolutionContext,
        referenceDate: Date = Date()
    ) -> [(TextSizeVariant, GraphicsContext.ResolvedText)]? {
        guard let variants = _sizeVariantTexts(
            in: context.environment,
            referenceDate: referenceDate
        ),
              variants.count > 1 else {
            return nil
        }

        var font = self.font ?? context.environment.effectiveFont
        if let fontWeight {
            font = font.weight(fontWeight)
        } else if boldValue == true {
            font = font.bold()
        }
        if italicValue == true {
            font = font.italic()
        }
        font = font.resolved(in: context.environment)
        let faces = ([font.typeface(
            forContext: context.sceneResources,
            contentScaleFactor: context.contentScaleFactor
        )] + font.fallbackTypefaces)
            .compactMap { $0 }
        guard !faces.isEmpty else { return nil }

        return variants.map { variant, string in
            let runs: [GraphicsContext.ResolvedText.Run] = [.text(faces, string)]
            let resolved = GraphicsContext.ResolvedText(
                runs: runs.map {
                    $0.applying(customAttributes)
                        .applying(textModifiers: modifiers)
                },
                scaleFactor: context.contentScaleFactor,
                displayScale: context.displayScale
            )
            return (variant, resolved)
        }
    }
}

final class BoldTextModifier: AnyTextModifier {
    let isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? BoldTextModifier)?.isActive == isActive
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(BoldTextModifier.self))
        hasher.combine(isActive)
    }
}

final class ItalicTextModifier: AnyTextModifier {
    let isActive: Bool

    init(isActive: Bool) {
        self.isActive = isActive
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? ItalicTextModifier)?.isActive == isActive
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(ItalicTextModifier.self))
        hasher.combine(isActive)
    }
}

final class UnderlineTextModifier: AnyTextModifier {
    let lineStyle: Text.LineStyle?

    init(lineStyle: Text.LineStyle?) {
        self.lineStyle = lineStyle
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? UnderlineTextModifier)?.lineStyle == lineStyle
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(UnderlineTextModifier.self))
        hasher.combine(lineStyle)
    }
}

final class StrikethroughTextModifier: AnyTextModifier {
    let lineStyle: Text.LineStyle?

    init(lineStyle: Text.LineStyle?) {
        self.lineStyle = lineStyle
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? StrikethroughTextModifier)?.lineStyle == lineStyle
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(StrikethroughTextModifier.self))
        hasher.combine(lineStyle)
    }
}

class TextAttributeModifierBase: AnyTextModifier {
    func apply(to attributes: inout _TextAttributeValues) {}
}

private final class TextAttributeModifier<Value>: TextAttributeModifierBase
where Value: TextAttribute {
    let value: Value

    init(value: Value) {
        self.value = value
    }

    override func apply(to attributes: inout _TextAttributeValues) {
        attributes.set(_AnyTextAttribute(value))
    }

    override func isEqual(to other: AnyTextModifier) -> Bool {
        (other as? TextAttributeModifier<Value>)?.value == value
    }

    override func hashResolution(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(Value.self))
        hasher.combine(value)
    }
}

extension Text {
    func modified(with modifier: Modifier) -> Text {
        Text(storage: storage, modifiers: modifiers + [modifier])
    }

    public func foregroundColor(_ color: Color?) -> Text {
        modified(with: .color(color))
    }

    var foregroundColor: Color? {
        for modifier in modifiers {
            if case let .color(color) = modifier {
                return color
            }
        }
        return nil
    }

    func foregroundShading(in environment: EnvironmentValues) -> GraphicsContext.Shading {
        if let foregroundColor {
            return .color(foregroundColor)
        }
        if let style = environment.currentForegroundStyle {
            var shape = _ShapeStyle_Shape(
                operation: .fallbackColor(level: 0),
                environment: environment
            )
            style._apply(to: &shape)
            if let shading = shape.resolvedShading {
                return shading
            }
        }
        return .foreground
    }

    public func font(_ font: Font?) -> Text {
        modified(with: .font(font))
    }

    var font: Font? {
        for modifier in modifiers {
            if case let .font(font) = modifier {
                return font
            }
        }
        return nil
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        modified(with: .weight(weight))
    }

    var fontWeight: Font.Weight? {
        for modifier in modifiers {
            if case let .weight(weight) = modifier {
                return weight
            }
        }
        return nil
    }

    public func bold() -> Text {
        bold(true)
    }

    public func bold(_ isActive: Bool) -> Text {
        modified(with: .anyTextModifier(BoldTextModifier(
            isActive: isActive
        )))
    }

    var boldValue: Bool? {
        for modifier in modifiers {
            guard case let .anyTextModifier(value) = modifier,
                  let value = value as? BoldTextModifier else {
                continue
            }
            return value.isActive
        }
        return nil
    }

    public func italic() -> Text {
        modified(with: .italic)
    }

    public func italic(_ isActive: Bool) -> Text {
        if isActive {
            return italic()
        }
        return modified(with: .anyTextModifier(ItalicTextModifier(
            isActive: false
        )))
    }

    var italicValue: Bool? {
        for modifier in modifiers {
            switch modifier {
            case .italic:
                return true
            case let .anyTextModifier(value):
                if let value = value as? ItalicTextModifier {
                    return value.isActive
                }
            default:
                continue
            }
        }
        return nil
    }

    public func strikethrough(
        _ isActive: Bool = true,
        color: Color? = nil
    ) -> Text {
        strikethrough(isActive, pattern: .solid, color: color)
    }

    public func strikethrough(
        _ isActive: Bool = true,
        pattern: LineStyle.Pattern,
        color: Color? = nil
    ) -> Text {
        modified(with: .anyTextModifier(StrikethroughTextModifier(
            lineStyle: isActive
                ? LineStyle(pattern: pattern, color: color)
                : nil
        )))
    }

    public func underline(
        _ isActive: Bool = true,
        color: Color? = nil
    ) -> Text {
        underline(isActive, pattern: .solid, color: color)
    }

    public func underline(
        _ isActive: Bool = true,
        pattern: LineStyle.Pattern,
        color: Color? = nil
    ) -> Text {
        modified(with: .anyTextModifier(UnderlineTextModifier(
            lineStyle: isActive
                ? LineStyle(pattern: pattern, color: color)
                : nil
        )))
    }

    public func kerning(_ kerning: CGFloat) -> Text {
        modified(with: .kerning(kerning))
    }

    public func tracking(_ tracking: CGFloat) -> Text {
        modified(with: .tracking(tracking))
    }

    public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
        modified(with: .baseline(baselineOffset))
    }
}

extension Text {
    public func customAttribute<T>(_ value: T) -> Text where T: TextAttribute {
        modified(with: .anyTextModifier(TextAttributeModifier(value: value)))
    }

    var customAttributes: _TextAttributeValues {
        var attributes = _TextAttributeValues()
        for modifier in modifiers {
            guard case let .anyTextModifier(value) = modifier,
                  let value = value as? TextAttributeModifierBase else {
                continue
            }
            value.apply(to: &attributes)
        }
        return attributes
    }

    var hasResolvedRunModifiers: Bool {
        modifiers.contains { modifier in
            switch modifier {
            case .kerning, .tracking, .baseline:
                return true
            case let .anyTextModifier(value):
                return value is UnderlineTextModifier ||
                    value is StrikethroughTextModifier ||
                    value is TextAttributeModifierBase
            default:
                return false
            }
        }
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        .init(storage: .anyTextStorage(ConcatenatedTextStorage(first: lhs,
                                                               second: rhs)),
              modifiers: [])
    }
}

extension Text: View {
    struct MakeRepresentableContext: Rule {
        var _text: Attribute<ResolvedStyledText>
        var _referenceDate: WeakAttribute<Date?>
        var _environment: Attribute<EnvironmentValues>

        var value: PlatformTextRepresentableContext {
            let context = ResolvableStringResolutionContext(
                referenceDate: _referenceDate.value.flatMap { $0 },
                environment: _environment.value,
                maximumWidth: nil
            )
            let text = _text.value
            return PlatformTextRepresentableContext(
                text: text.resolvedContent(in: context) ?? text.storage
            )
        }
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        // 1. Internal state nodes for the graph-side resolver and backend resource pass.
        let initialResolvedStyledText = ResolvedStyledText()
        let backendResolvedStyledTextAttr = graph.makeInput(value: initialResolvedStyledText)
        let backendResolvedTextTransactionAttr = graph.makeInput(value: Transaction())
        let resourceResolutionState = _TextResourceResolutionState()
        let inheritedTransactionAttr = inputs.base.transaction
        // Extract inputs to avoid capturing the entire `inputs` struct
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let environmentAttr = cachedEnvironmentAttr.value.environment
        let timeAttr = inputs.base.time
        let inbox = graph.inbox
        let animatedSizeAttr: Attribute<ViewSize>
        let targetSizeAttr: Attribute<ViewSize>
        if inputs.needsGeometry {
            var cachedEnvironment = cachedEnvironmentAttr.value
            animatedSizeAttr = cachedEnvironment.animatedSize(for: inputs)
            guard let animatedFrame = cachedEnvironment.animatedFrame else {
                fatalError("Text geometry animation requires an animated frame.")
            }
            targetSizeAttr = animatedFrame.size
            cachedEnvironmentAttr.value = cachedEnvironment
        } else {
            animatedSizeAttr = inputs.size
            targetSizeAttr = inputs.size
        }
        let textRendererAttr = inputs[TextRendererInput.self]
        let archiveOptions = inputs[ArchivedViewInput.self]
        let usesSizeFittingText = inputs.base[VariantThatFitsFlag.self]
        let resolvedTextHelper = ResolvedTextHelper(
            _time: timeAttr,
            _referenceDate: inputs[ReferenceDateInput.self],
            archiveOptions: archiveOptions
        )
        let graphResolvedStyledTextAttr = graph.makeStatefulRule(
            ResolvedTextFilter(
                _text: view._attribute,
                _environment: environmentAttr,
                helper: resolvedTextHelper
            )
        )
        let resolvedStyledTextAttr: Attribute<ResolvedStyledText> = graph.makeRule {
            let graphResolved = graphResolvedStyledTextAttr.value
            guard graphResolved.resolvedText == nil else {
                return graphResolved
            }
            return backendResolvedStyledTextAttr.value
        }
        let resolvedStyledTextTransactionAttr: Attribute<Transaction> = graph.makeRule {
            let graphResolved = graphResolvedStyledTextAttr.value
            if graphResolved.resolvedText != nil {
                return inheritedTransactionAttr.value
            }
            return backendResolvedTextTransactionAttr.value
        }

        let debugLayoutAttr: Attribute<Bool> = graph.makeRule {
            cachedEnvironmentAttr.value.environment.value._debugLayout
        }

        // 2. Resource pass (Resource Rule)
        // Evaluated before drawing (in updateView) to upload resources to the GPU.
        let resourceAttr: Attribute<ResourceList> = graph.makeRule {
            let text = view._attribute.value // Dependency 1: Text content and modifiers
            let environment = cachedEnvironmentAttr.value.environment.value // Dependency 2: Environment (scale, theme, font)
            let referenceDate = Date()
            let renderEnvironment = environment.untrackedCopy()
            let currentVersion = text._resolutionVersion(
                in: environment,
                referenceDate: referenceDate
            )

            let graphResolvedStyledText = graphResolvedStyledTextAttr.value
            if let resolved = graphResolvedStyledText.resolvedText {
                guard resourceResolutionState.requiresPreparation(
                    version: currentVersion
                ) else {
                    return ResourceList()
                }
                var list = ResourceList()
                list.items.append(ResourceList.Task(
                    transaction: Transaction(),
                    updatesGraph: false,
                    isPending: {
                        resourceResolutionState.requiresPreparation(
                            version: currentVersion
                        )
                    }
                ) { _ in
                    resolved.prepareResources()
                    resourceResolutionState.didPrepare(version: currentVersion)
                })
                return list
            }

            let backendResolvedStyledText = backendResolvedStyledTextAttr.value
            if backendResolvedStyledText.version == currentVersion,
               backendResolvedStyledText.resolvedText != nil {
                resourceResolutionState.didResolve(version: currentVersion)
                return ResourceList()
            }

            let contextualTransaction = _AGGraph.currentRuleContextAttribute
                .flatMap { graph.transaction(for: $0) } ?? Transaction()
            let inheritedTransaction = inheritedTransactionAttr.value
            let candidateTransaction = contextualTransaction.isEmpty
                ? inheritedTransaction
                : contextualTransaction
            let resourceTransaction = resourceResolutionState.transaction(
                for: currentVersion,
                candidate: candidateTransaction
            )
            // If loading is required, create a new ResourceList(Task) to propagate upwards.
            var list = ResourceList()

            list.items.append(ResourceList.Task(transaction: resourceTransaction) { context in
                var context = context
                context.environment = renderEnvironment
                guard let resolved = text._resolveStyledText(
                    context: context,
                    referenceDate: referenceDate,
                    archiveOptions: archiveOptions,
                    features: [],
                    sizeFitting: usesSizeFittingText
                ) else {
                    fatalError("A graphics text context must resolve backend attachments.")
                }
                resolved.resolvedText?.prepareResources()
                let boxedResolved = UnsafeBox(resolved)
                let boxedTransaction = UnsafeBox(resourceTransaction)

                let publish: @Sendable () -> Void = {
                    backendResolvedTextTransactionAttr.setValue(boxedTransaction.value)
                    backendResolvedStyledTextAttr.setValue(
                        boxedResolved.value,
                        transaction: boxedTransaction.value
                    )
                }
                if _AGGraph.current === graph {
                    publish()
                } else {
                    inbox.enqueue(transaction: resourceTransaction, publish)
                }
            })

            return list
        }

        // 3. Layout pass (Layout Rule)
        let displayedStyledTextAttr: Attribute<ResolvedStyledText>
        let lcAttr: Attribute<LayoutComputer>
        if usesSizeFittingText {
            let cache = SizeFittingTextCache(
                resolver: resolvedTextHelper,
                logic: StickyTextSizeFittingLogic(),
                input: ResolvedTextHelper.Input(
                    text: initialResolvedStyledText,
                    renderer: nil
                )
            )
            displayedStyledTextAttr = graph.makeStatefulRule(
                SizeFittingTextFilter(
                    size: animatedSizeAttr,
                    text: resolvedStyledTextAttr,
                    environment: environmentAttr,
                    isArchived: archiveOptions.isArchived,
                    cache: cache
                )
            )
            lcAttr = graph.makeStatefulRule(
                SizeFittingTextLayoutComputer(
                    _text: resolvedStyledTextAttr,
                    _environment: environmentAttr,
                    _renderer: textRendererAttr?.asWeak() ?? WeakAttribute(),
                    cache: cache
                )
            )
        } else {
            displayedStyledTextAttr = resolvedStyledTextAttr
            lcAttr = graph.makeStatefulRule(
                StyledTextLayoutComputer(
                    _textView: graph.makeRule {
                        let styledText = resolvedStyledTextAttr.value
                        return StyledTextContentView(
                            text: styledText,
                            renderer: textRendererAttr?.value,
                            needsDrawingGroup: styledText.needsDrawingGroup
                        )
                    }
                )
            )
        }

        let textViewAttr: Attribute<StyledTextContentView> = graph.makeRule {
            let styledText = displayedStyledTextAttr.value
            return StyledTextContentView(
                text: styledText,
                renderer: textRendererAttr?.value,
                needsDrawingGroup: styledText.needsDrawingGroup
            )
        }
        var cachedEnvironment = cachedEnvironmentAttr.value
        let styles = cachedEnvironment.resolvedShapeStyles(
            for: inputs,
            role: .fill
        )
        cachedEnvironmentAttr.value = cachedEnvironment
        let interpolatorGroup = _ShapeStyle_InterpolatorGroup()
        var leafInputs = inputs
        leafInputs.size = targetSizeAttr
        leafInputs.containerPosition = cachedEnvironment.animatedPosition(
            for: inputs
        )
        cachedEnvironmentAttr.value = cachedEnvironment
        var outputs = StyledTextContentView.makeLeafView(
            view: _GraphValue(_attribute: textViewAttr),
            inputs: leafInputs,
            styles: styles,
            interpolatorGroup: interpolatorGroup
        )
        outputs._layoutComputer = OptionalAttribute(lcAttr)

        // 5. Propagate ResourceList and DisplayList upwards via the Preference channel!
        outputs.preferences.append(ResourceList.Key.self, node: resourceAttr.identifier)
        if inputs.preferences.keys.contains(DisplayList.Key.self) {
            let debugDisplayList: Attribute<DisplayList> = graph.makeRule {
                var list = DisplayList()
                if debugLayoutAttr.value {
                    appendDebugOverlay(
                        to: &list,
                        frame: CGRect(
                            origin: .zero,
                            size: targetSizeAttr.value.value
                        ),
                        category: .primitiveView
                    )
                }
                return list
            }
            outputs.preferences.append(
                DisplayList.Key.self,
                node: debugDisplayList.identifier
            )
        }
        var interpolatorInputs = inputs
        interpolatorInputs.base.transaction = resolvedStyledTextTransactionAttr
        interpolatorInputs.size = targetSizeAttr
        outputs.applyInterpolatorGroup(
            interpolatorGroup,
            content: displayedStyledTextAttr,
            inputs: interpolatorInputs,
            animatesSize: false,
            defersRender: false
        )
        if let representable = inputs.requestedTextRepresentation,
           representable.shouldMakeRepresentation(inputs: inputs) {
            _ = representable.representationOptions(inputs: inputs)
            let context: Attribute<PlatformTextRepresentableContext> =
                graph.makeRule(MakeRepresentableContext(
                    _text: resolvedStyledTextAttr,
                    _referenceDate: inputs[ReferenceDateInput.self],
                    _environment: environmentAttr
                ))
            representable.makeRepresentation(
                inputs: inputs,
                context: context,
                outputs: &outputs
            )
        }

        return outputs
    }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }
}

extension Text: PrimitiveView {
}
