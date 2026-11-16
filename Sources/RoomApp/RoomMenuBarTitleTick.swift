import Foundation

/// Counts in the unit the person sees; a change of units or value mode swaps immediately.
nonisolated enum RoomMenuBarTitleTick {
    static func titles(from: String, to: String, previousMode: RoomMenuBarValueMode?,
                       mode: RoomMenuBarValueMode, locale: Locale = .current) -> [String] {
        guard previousMode == mode, mode == .memory || mode == .disk else { return [] }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        guard let old = parse(from, mode: mode, formatter: formatter),
              let new = parse(to, mode: mode, formatter: formatter),
              old.suffix == new.suffix,
              abs(new.number.decimalValue - old.number.decimalValue) >= Decimal(1) / Decimal(10)
        else { return [] }

        let start = old.number.doubleValue
        var target = new.number.doubleValue
        // Decimal tenths can fall just below the threshold after conversion to binary Double.
        if abs(target - start) < RoomMenuBarMotion.tickThreshold {
            target = target > start ? target.nextUp : target.nextDown
        }
        let values = RoomMenuBarMotion.tickValues(from: start, to: target)
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(1, max(old.fractionDigits, new.fractionDigits))
        return values.enumerated().map { index, value in
            index == values.count - 1 ? to : (formatter.string(from: NSNumber(value: value)) ?? to) + new.suffix
        }
    }

    private struct Figure {
        let number: NSNumber
        let suffix: String
        let fractionDigits: Int
    }

    private static func parse(_ title: String, mode: RoomMenuBarValueMode,
                              formatter: NumberFormatter) -> Figure? {
        guard let unitStart = title.firstIndex(where: { character in
            character.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }) else { return nil }
        let numberText = String(title[..<unitStart]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numberText.isEmpty,
              let numberRange = title.range(of: numberText, options: .anchored) else { return nil }
        let suffix = String(title[numberRange.upperBound...])
        guard suffix.first?.isWhitespace == true,
              mode != .disk || suffix.hasSuffix(" free") else { return nil }

        var allowed = CharacterSet.decimalDigits
        allowed.formUnion(CharacterSet(charactersIn: formatter.decimalSeparator + formatter.groupingSeparator))
        guard numberText.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let number = formatter.number(from: numberText), number.doubleValue.isFinite else { return nil }
        let fractionDigits: Int
        if let decimal = numberText.range(of: formatter.decimalSeparator) {
            fractionDigits = numberText[decimal.upperBound...].filter(\.isNumber).count
        } else {
            fractionDigits = 0
        }
        return Figure(number: number, suffix: suffix, fractionDigits: fractionDigits)
    }
}
