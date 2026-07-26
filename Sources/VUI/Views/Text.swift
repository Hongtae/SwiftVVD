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
}

final class _TextDisplayListContentState {
    private var resolvedVersion: Int?
    private var size: CGSize?
    private var needsDrawingGroup: Bool?
    private var rendererID: ObjectIdentifier?
    private var seed = DisplayList.Seed()

    func contentSeed(
        resolvedVersion: Int,
        size: CGSize,
        needsDrawingGroup: Bool,
        renderer: TextRendererBoxBase? = nil
    ) -> DisplayList.Seed {
        let rendererID = renderer.map(ObjectIdentifier.init)
        if seed.value == 0 ||
            self.resolvedVersion != resolvedVersion ||
            self.size != size ||
            self.needsDrawingGroup != needsDrawingGroup ||
            self.rendererID != rendererID {
            seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
            self.resolvedVersion = resolvedVersion
            self.size = size
            self.needsDrawingGroup = needsDrawingGroup
            self.rendererID = rendererID
        }
        return seed
    }
}

private extension DisplayList {
    func translatedTextPresentation(x: CGFloat, y: CGFloat) -> DisplayList {
        guard x != 0 || y != 0 else {
            return self
        }

        let transform = CGAffineTransform(translationX: x, y: y)
        var result = DisplayList()
        for item in items {
            result.appendTransformedItem(item, affineTransform: transform)
        }
        for item in debugItems {
            result.appendTransformedDebugItem(item, affineTransform: transform)
        }
        result.numericValue = numericValue
        return result
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


class AnyTextStorage: CustomDebugStringConvertible {
    var debugDescription: String {
        let typeName = String(describing: type(of: self))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let text = resolveText(in: EnvironmentValues())
        return "<\(typeName): \(pointer)>: \(String(reflecting: text))"
    }

    func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
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
        context: GraphicsContext,
        referenceDate: Date
    ) -> GraphicsContext.ResolvedText {
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

private func _dynamicArchiveStorage(
    for resolved: GraphicsContext.ResolvedText,
    enabled: Bool
) -> NSAttributedString? {
    guard enabled else { return nil }
    let storage = NSMutableAttributedString(attributedString: resolved.attributedStorage)
    if storage.length > 0 {
        storage.addAttribute(
            .updateSchedule,
            value: true,
            range: NSRange(location: 0, length: storage.length)
        )
    }
    return storage
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
        let output = format.locale(locale).format(input)
        if let string = output as? String {
            return .init(
                runs: [.text(typefaces, string)],
                scaleFactor: context.contentScaleFactor
            )
        }
        if let attributed = output as? AttributedString {
            return _resolvedAttributedText(
                attributed,
                defaultTypefaces: typefaces,
                context: context
            )
        }
        return .init(runs: [], scaleFactor: context.contentScaleFactor)
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
        .init(
            runs: [.text(typefaces, resolveText(in: context.environment))],
            scaleFactor: context.contentScaleFactor
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
        let startDesignator = (
            startHour < 12 ? formatter.amSymbol : formatter.pmSymbol
        ) ?? ""
        let endDesignator = (
            endHour < 12 ? formatter.amSymbol : formatter.pmSymbol
        ) ?? ""
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
        .init(
            runs: [.text(typefaces, output)],
            scaleFactor: context.contentScaleFactor
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
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
        context: GraphicsContext
    ) -> GraphicsContext.ResolvedText {
        resolve(typefaces: typefaces, context: context, referenceDate: Date())
    }

    override func resolve(
        typefaces: [Typeface],
        context: GraphicsContext,
        referenceDate: Date
    ) -> GraphicsContext.ResolvedText {
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

    override func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let segments = resolve(locale: context.environment.locale)
        let runs = segments.flatMap { segment -> [GraphicsContext.ResolvedText.Run] in
            switch segment {
            case let .attributedString(value):
                return _resolvedAttributedText(
                    value,
                    defaultTypefaces: typefaces,
                    context: context
                ).runs
            case let .text(text):
                return text._resolve(context: context).runs.map {
                    $0.applying(foregroundColor: text.foregroundColor)
                }
            }
        }
        return .init(runs: runs, scaleFactor: context.contentScaleFactor)
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

    private func resolve(locale: Locale) -> [LocalizedStringKey.ResolvedSegment] {
        key.resolve(
            table: table,
            bundle: localizedBundle(for: locale),
            locale: locale
        )
    }

    private func localizedBundle(for locale: Locale) -> Bundle {
        let rootBundle = bundle ?? .main
        let availableLocalizations = rootBundle.localizations
        guard !availableLocalizations.isEmpty else {
            return rootBundle
        }

        var candidates = Bundle.preferredLocalizations(
            from: availableLocalizations,
            forPreferences: [locale.identifier]
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

    override func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let first = first._resolve(context: context)
        let second = second._resolve(context: context)
        return .init(runs: first.runs + second.runs, scaleFactor: context.contentScaleFactor)
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

    override func resolve(typefaces: [Typeface], context: GraphicsContext) -> GraphicsContext.ResolvedText {
        let image = context.resolve(self.image)
        return .init(runs: [.attachment(typefaces, image)], scaleFactor: context.contentScaleFactor)
    }

    override func resolveText(in environment: EnvironmentValues) -> String {
        String()
    }

    override func resolveTransitionText(in environment: EnvironmentValues) -> String? {
        nil
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

    let storage: Storage

    public enum Case: Hashable {
        case lowercase
        case uppercase
    }

    public struct LineStyle: Hashable, Sendable {
        public struct Pattern: Equatable, Sendable {
            let rawValue: Int

            private init(rawValue: Int) {
                self.rawValue = rawValue
            }

            public static let solid = Pattern(rawValue: 0)
            public static let dot = Pattern(rawValue: 0x100)
            public static let dash = Pattern(rawValue: 0x200)
            public static let dashDot = Pattern(rawValue: 0x300)
            public static let dashDotDot = Pattern(rawValue: 0x400)
        }

        let nsUnderlineStyleValue: Int
        let color: Color?

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
        case font(Font)
        case fontWeight(Font.Weight)
        case foregroundColor(Color)
        case bold(Bool)
        case italic(Bool)
        case strikethrough(Bool, LineStyle.Pattern, Color?)
        case underline(Bool, LineStyle.Pattern, Color?)
        case monospacedDigit
        case kerning(CGFloat)
        case tracking(CGFloat)
        case baselineOffset(CGFloat)
        case textCase(Case)
        case customAttribute(_AnyTextAttribute)
    }

    let modifiers: [Modifier]

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
        let displayScale = context.sceneResources.contentScaleFactor
        var font = self.font ?? context.environment.font
        if font == nil {
            font = .system(.body)
        }
        if let fontWeight {
            font = font?.weight(fontWeight)
        } else if boldValue == true {
            font = font?.bold()
        }
        if italicValue == true {
            font = font?.italic()
        }
        var resolutionContext = context
        resolutionContext.environment.font = font
        font = font?.resolved(in: context.environment)
        font = font?.displayScale(displayScale)
        let defaultFace = font?.typeface(forContext: context.sceneResources)
        let fallbackFaces = font?.fallbackTypefaces ?? []
        let faces = ([defaultFace] + fallbackFaces).compactMap {$0 }

        if faces.isEmpty == false {
            var runs: [GraphicsContext.ResolvedText.Run] = []
            if case let .verbatim(text) = self.storage {
                runs = [.text(faces, text)]
                return GraphicsContext.ResolvedText(
                    runs: runs.map { $0.applying(customAttributes) },
                    scaleFactor: context.contentScaleFactor
                )
            }
            else if case let .anyTextStorage(text) = self.storage {
                let resolved = text.resolve(
                    typefaces: faces,
                    context: resolutionContext,
                    referenceDate: referenceDate
                )
                guard !customAttributes.isEmpty else { return resolved }
                return GraphicsContext.ResolvedText(
                    runs: resolved.runs.map { $0.applying(customAttributes) },
                    scaleFactor: context.contentScaleFactor
                )
            }
        }
        return .init(runs: [], scaleFactor: context.contentScaleFactor)
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

    func _resolveSizeVariants(
        context: GraphicsContext,
        referenceDate: Date = Date()
    ) -> [(TextSizeVariant, GraphicsContext.ResolvedText)]? {
        guard let variants = _sizeVariantTexts(
            in: context.environment,
            referenceDate: referenceDate
        ),
              variants.count > 1 else {
            return nil
        }

        let displayScale = context.sceneResources.contentScaleFactor
        var font = self.font ?? context.environment.font ?? .system(.body)
        if let fontWeight {
            font = font.weight(fontWeight)
        } else if boldValue == true {
            font = font.bold()
        }
        if italicValue == true {
            font = font.italic()
        }
        font = font.resolved(in: context.environment).displayScale(displayScale)
        let faces = ([font.typeface(forContext: context.sceneResources)] + font.fallbackTypefaces)
            .compactMap { $0 }
        guard !faces.isEmpty else { return nil }

        return variants.map { variant, string in
            let runs: [GraphicsContext.ResolvedText.Run] = [.text(faces, string)]
            let resolved = GraphicsContext.ResolvedText(
                runs: runs.map { $0.applying(customAttributes) },
                scaleFactor: context.contentScaleFactor
            )
            return (variant, resolved)
        }
    }
}

extension Text {
    public func foregroundColor(_ color: Color?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .foregroundColor(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let color {
            modifiers.append(.foregroundColor(color))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var foregroundColor: Color? {
        self.modifiers.compactMap {
            if case let .foregroundColor(color) = $0 { return color }
            return nil
        }.first
    }

    func foregroundShading(in environment: EnvironmentValues) -> GraphicsContext.Shading {
        if let foregroundColor {
            return .color(foregroundColor)
        }
        if let styles = environment.foregroundStyleLevels {
            var shape = _ShapeStyle_Shape()
            shape.foregroundStyle = (
                primary: styles.primary,
                secondary: styles.secondary,
                tertiary: styles.tertiary
            )
            styles.primary._apply(to: &shape)
            if let shading = shape.shading {
                return shading
            }
        }
        return .foreground
    }

    public func font(_ font: Font?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .font(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let font {
            modifiers.append(.font(font))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var font: Font? {
        self.modifiers.compactMap {
            if case let .font(font) = $0 { return font }
            return nil
        }.first
    }

    public func fontWeight(_ weight: Font.Weight?) -> Text {
        var modifiers: [Modifier] = []
        self.modifiers.forEach {
            if case .fontWeight(_) = $0 { } else {
                modifiers.append($0)
            }
        }
        if let weight {
            modifiers.append(.fontWeight(weight))
        }
        return Text(storage: self.storage, modifiers: modifiers)
    }

    var fontWeight: Font.Weight? {
        self.modifiers.compactMap {
            if case let .fontWeight(weight) = $0 { return weight }
            return nil
        }.first
    }

    public func bold() -> Text {
        bold(true)
    }

    public func bold(_ isActive: Bool) -> Text {
        var modifiers = modifiers.filter {
            guard case .bold = $0 else { return true }
            return false
        }
        modifiers.append(.bold(isActive))
        return Text(storage: storage, modifiers: modifiers)
    }

    var boldValue: Bool? {
        for modifier in modifiers {
            if case let .bold(value) = modifier { return value }
        }
        return nil
    }

    public func italic() -> Text {
        italic(true)
    }

    public func italic(_ isActive: Bool) -> Text {
        var modifiers = modifiers.filter {
            guard case .italic = $0 else { return true }
            return false
        }
        modifiers.append(.italic(isActive))
        return Text(storage: storage, modifiers: modifiers)
    }

    var italicValue: Bool? {
        for modifier in modifiers {
            if case let .italic(value) = modifier { return value }
        }
        return nil
    }
}

extension Text {
    public func customAttribute<T>(_ value: T) -> Text where T: TextAttribute {
        let attribute = _AnyTextAttribute(value)
        var modifiers = modifiers.filter {
            guard case let .customAttribute(existing) = $0 else { return true }
            return existing.type != attribute.type
        }
        modifiers.append(.customAttribute(attribute))
        return Text(storage: storage, modifiers: modifiers)
    }

    var customAttributes: _TextAttributeValues {
        var attributes = _TextAttributeValues()
        for modifier in modifiers {
            guard case let .customAttribute(attribute) = modifier else { continue }
            attributes.set(attribute)
        }
        return attributes
    }

    public static func + (lhs: Text, rhs: Text) -> Text {
        .init(storage: .anyTextStorage(ConcatenatedTextStorage(first: lhs,
                                                               second: rhs)),
              modifiers: [])
    }
}

extension Text: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        // 1. Internal state nodes for communication between the resource and layout passes.
        // Caches the fully resolved styled text object (including glyphs/metrics).
        let initialResolvedStyledText = ResolvedStyledText()
        let resolvedStyledTextAttr = graph.makeInput(value: initialResolvedStyledText)
        let resolvedStyledTextTransactionAttr = graph.makeInput(value: Transaction())
        let resourceResolutionState = _TextResourceResolutionState()
        let inheritedTransactionAttr = inputs.base.transaction
        let displayListContentState = _TextDisplayListContentState()
        // Resource resolution runs after graph construction. This indirection lets the
        // resource pass initialize the unresolved interpolation surface before publishing
        // the first drawable text payload.
        let interpolatorPrimeAttr = graph.makeIndirectAttribute(
            defaultValue: DisplayList()
        )

        // Extract inputs to avoid capturing the entire `inputs` struct
        let cachedEnvironmentAttr = inputs.base.cachedEnvironment
        let environmentAttr = cachedEnvironmentAttr.value.environment
        let timeAttr = inputs.base.time
        let inbox = graph.inbox
        let targetPositionAttr = inputs.position
        let animatedPositionAttr: Attribute<CGPoint>
        let animatedSizeAttr: Attribute<ViewSize>
        let targetSizeAttr: Attribute<ViewSize>
        if inputs.needsGeometry {
            var cachedEnvironment = cachedEnvironmentAttr.value
            animatedPositionAttr = cachedEnvironment.animatedPosition(for: inputs)
            animatedSizeAttr = cachedEnvironment.animatedSize(for: inputs)
            guard let animatedFrame = cachedEnvironment.animatedFrame else {
                fatalError("Text geometry animation requires an animated frame.")
            }
            targetSizeAttr = animatedFrame.size
            cachedEnvironmentAttr.value = cachedEnvironment
        } else {
            animatedPositionAttr = inputs.position
            animatedSizeAttr = inputs.size
            targetSizeAttr = inputs.size
        }
        let textRendererAttr = inputs[TextRendererInput.self]
        let archiveOptions = inputs[ArchivedViewInput.self]
        let usesSizeFittingText = inputs.base[VariantThatFitsFlag.self]

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
            let transitionText = text._resolveTransitionText(in: environment)
            let needsDynamicArchive = text._needsDynamicRenderingInArchive(in: environment)
            let layoutProperties = TextLayoutProperties(environment)

            // Generate a unique hash (version) combining text content and environment factors.
            var hasher = Hasher()
            text._contentHash(
                into: &hasher,
                environment: environment,
                referenceDate: referenceDate
            )
            hasher.combine(environment.font?.hashValue ?? 0)
            hasher.combine(environment.defaultFontRenderingMode)
            hasher.combine(environment.displayScale)
            text.customAttributes.hash(into: &hasher)
            let currentVersion = hasher.finalize()

            if let delay = text._nextUpdateDelay(
                in: environment,
                referenceDate: referenceDate
            ), delay.isFinite, delay > 0,
               let viewGraph = _AGGraphContext.current?.context as? ViewGraph {
                let currentTime = timeAttr.value
                viewGraph.nextUpdate.views.at(currentTime + delay)
            }

            // Optimization (Cache Hit): Return an empty list if the resolved version matches and the text is already cached.
            let resolvedStyledText = resolvedStyledTextAttr.value
            if resolvedStyledText.version == currentVersion, resolvedStyledText.resolvedText != nil {
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
                _ = interpolatorPrimeAttr.value
                var context = context
                context.environment = renderEnvironment
                // 1. [Synchronous Loading] Parse the text and generate glyphs using the provided context.
                let resolved = text._resolve(
                    context: context,
                    referenceDate: referenceDate
                )
                let boxedResolved = UnsafeBox(resolved)
                let boxedVariants = UnsafeBox(
                    usesSizeFittingText ? text._resolveSizeVariants(
                        context: context,
                        referenceDate: referenceDate
                    ) : nil
                )
                let boxedTransaction = UnsafeBox(resourceTransaction)
                let boxedLayoutProperties = UnsafeBox(layoutProperties)

                // 2. [State Invalidation] Notify completion and trigger a layout recomputation.
                let publish: @Sendable () -> Void = {
                    let variantValues = boxedVariants.value
                    var styledVariants: [ResolvedStyledText] = []
                    if let variantValues {
                        styledVariants = variantValues.map { _, resolved in
                            ResolvedStyledText(
                                storage: _dynamicArchiveStorage(
                                    for: resolved,
                                    enabled: needsDynamicArchive
                                ),
                                layoutProperties: boxedLayoutProperties.value,
                                archiveOptions: archiveOptions,
                                features: resolved.resolvedFeatures.union(.isUniqueSizeVariant),
                                resolvedText: resolved,
                                version: currentVersion,
                                transitionText: transitionText
                            )
                        }
                        if let terminalResolved = variantValues.last?.1 {
                            styledVariants.append(
                                ResolvedStyledText(
                                    storage: _dynamicArchiveStorage(
                                        for: terminalResolved,
                                        enabled: needsDynamicArchive
                                    ),
                                    layoutProperties: boxedLayoutProperties.value,
                                    archiveOptions: archiveOptions,
                                    features: terminalResolved.resolvedFeatures,
                                    resolvedText: terminalResolved,
                                    version: currentVersion,
                                    transitionText: transitionText
                                )
                            )
                        }
                        if let first = styledVariants.first {
                            first.setSizeVariantCandidates(styledVariants)
                        }
                    }

                    resolvedStyledTextTransactionAttr.setValue(boxedTransaction.value)
                    resolvedStyledTextAttr.setValue(
                        styledVariants.first ?? ResolvedStyledText(
                            storage: _dynamicArchiveStorage(
                                for: boxedResolved.value,
                                enabled: needsDynamicArchive
                            ),
                            layoutProperties: boxedLayoutProperties.value,
                            archiveOptions: archiveOptions,
                            features: boxedResolved.value.resolvedFeatures,
                            resolvedText: boxedResolved.value,
                            version: currentVersion,
                            transitionText: transitionText
                        ),
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
                resolver: ResolvedTextHelper(),
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
                    text: resolvedStyledTextAttr,
                    environment: environmentAttr,
                    renderer: textRendererAttr?.asWeak() ?? WeakAttribute(),
                    cache: cache
                )
            )
        } else {
            displayedStyledTextAttr = resolvedStyledTextAttr
            lcAttr = graph.makeRule {
                let resolved = resolvedStyledTextAttr.value.resolvedText
                let renderer = textRendererAttr?.value

                func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
                    guard let resolved else { return .zero }
                    if let renderer {
                        return renderer.sizeThatFits(
                            proposal: proposal,
                            text: TextProxy(resolved)
                        )
                    }
                    if proposal == .zero {
                        return .zero
                    }
                    if proposal.width == 0 {
                        let measured = resolved.measure(
                            maxWidth: 0,
                            maxHeight: proposal.height
                        )
                        return CGSize(width: 0, height: measured.height)
                    }
                    if proposal == .infinity {
                        return resolved.measure()
                    }
                    return resolved.measure(
                        maxWidth: proposal.width,
                        maxHeight: proposal.height
                    )
                }

                return LayoutComputer(
                    sizeThatFits: { sizeThatFits(ProposedViewSize($0)) },
                    spacing: ViewSpacing.text.spacing,
                    explicitAlignment: { key, size in
                        guard let resolved else { return nil }
                        if key == VerticalAlignment.firstTextBaseline.key {
                            return resolved.firstBaseline(in: size.value)
                        }
                        if key == VerticalAlignment.lastTextBaseline.key {
                            return resolved.lastBaseline(in: size.value)
                        }
                        return nil
                    }
                )
            }
        }

        let interpolatorGroup = _ShapeStyle_InterpolatorGroup()
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let text = view._attribute.value // Dependency: text modifiers/colors
            let environment = cachedEnvironmentAttr.value.environment.value
            let targetSize = targetSizeAttr.value.value
            let targetPosition = targetPositionAttr.value
            let styledText = displayedStyledTextAttr.value
            let resolved = styledText.resolvedText
            let debugLayout = debugLayoutAttr.value
            let foreground = text.foregroundShading(in: environment)
            let renderer = textRendererAttr?.value

            var list = DisplayList()

            if let resolved = resolved {
                var frame = CGRect(origin: targetPosition, size: targetSize)
                let measuredSize = renderer?.sizeThatFits(
                    proposal: ProposedViewSize(frame.size),
                    text: TextProxy(resolved)
                ) ?? resolved.measure(maxWidth: frame.width, maxHeight: frame.height)

                if measuredSize.height < frame.height {
                    let offset = frame.height - measuredSize.height
                    frame = frame.offsetBy(dx: 0, dy: offset * 0.5)
                    frame.size.height = measuredSize.height
                }
                let styledTextContent = StyledTextContentView(
                    text: styledText,
                    renderer: renderer,
                    needsDrawingGroup: styledText.needsDrawingGroup
                )
                let contentSeed = displayListContentState.contentSeed(
                    resolvedVersion: styledText.version,
                    size: frame.size,
                    needsDrawingGroup: styledText.needsDrawingGroup,
                    renderer: renderer
                )
                let padding = renderer?.displayPadding ?? EdgeInsets()
                let displayBounds = CGRect(
                    x: frame.minX - padding.leading,
                    y: frame.minY - padding.top,
                    width: frame.width + padding.leading + padding.trailing,
                    height: frame.height + padding.top + padding.bottom
                )
                list.appendTextItem(
                    styledTextContent,
                    size: frame.size,
                    foreground: foreground,
                    bounds: frame,
                    displayBounds: displayBounds,
                    seed: contentSeed,
                    environment: environment.untrackedCopy()
                )
            } else {
                // Keep an interpolation endpoint without emitting a render command.
                list.appendDebugItem(
                    bounds: CGRect(origin: targetPosition, size: targetSize)
                ) { _ in }
            }
            if debugLayout {
                appendDebugOverlay(
                    to: &list,
                    frame: CGRect(origin: targetPosition, size: targetSize),
                    category: .primitiveView
                )
            }
            return list
        }
        let presentationDlAttr: Attribute<DisplayList> = graph.makeRule {
            let displayedStyledText = displayedStyledTextAttr.value
            guard displayedStyledText.resolvedText != nil else {
                return dlAttr.value
            }
            let targetPosition = targetPositionAttr.value
            let presentationPosition = animatedPositionAttr.value
            return dlAttr.value.translatedTextPresentation(
                x: presentationPosition.x - targetPosition.x,
                y: presentationPosition.y - targetPosition.y
            )
        }

        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(lcAttr)

        // 5. Propagate ResourceList and DisplayList upwards via the Preference channel!
        outputs.preferences.append(ResourceList.Key.self, node: resourceAttr.identifier)
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        var interpolatorInputs = inputs
        interpolatorInputs.base.transaction = resolvedStyledTextTransactionAttr
        interpolatorInputs.size = targetSizeAttr
        outputs.applyInterpolatorGroup(
            interpolatorGroup,
            content: displayedStyledTextAttr,
            inputs: interpolatorInputs,
            animatedPosition: animatedPositionAttr,
            animatedSize: animatedSizeAttr,
            presentationDisplayList: presentationDlAttr,
            animatesSize: false,
            defersRender: false
        )
        if let interpolated = outputs.preferences.reducedValue(
            for: DisplayList.Key.self,
            in: graph
        ) {
            graph.setIndirectTarget(interpolatorPrimeAttr, to: interpolated)
        }
        if platformItemListShouldCollectStaticItemContributors(inputs) {
            // Plain Text under MenuStyleContext contributes a disabled platform item.
            let textAttr = view._attribute
            let itemID = PlatformItemList.stableID(textAttr.identifier)
            let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
                var list = PlatformItemList()
                list.append(PlatformItemList.Item(
                    id: itemID,
                    label: AnyView(textAttr.value),
                    action: nil,
                    role: nil,
                    isEnabled: false
                ))
                return list
            }
            outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
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
