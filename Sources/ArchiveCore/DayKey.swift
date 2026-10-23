//
//  DayKey.swift
//  日期鍵 yyyymmdd。官方資料以民國年 7 位(`1151020`)或 6 位表示。
//

import Foundation

public enum DayKey {

    /// 民國日期 → dayKey;格式或日期不合法回傳 nil。
    public static func fromROC(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.count == 6 || digits.count == 7,
              digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let number = Int(digits) else { return nil }
        let rocYear = number / 10_000
        let month = (number / 100) % 100
        let day = number % 100
        return make(year: rocYear + 1911, month: month, day: day)
    }

    public static func make(year: Int, month: Int, day: Int) -> Int? {
        guard year >= 1912, (1...12).contains(month), (1...daysIn(year: year, month: month)).contains(day) else { return nil }
        return year * 10_000 + month * 100 + day
    }

    /// 某一時刻在台灣(Asia/Taipei)的日期。
    public static func taiwan(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year! * 10_000 + parts.month! * 100 + parts.day!
    }

    /// `YYYY-MM-DD`
    public static func text(_ dayKey: Int) -> String {
        String(format: "%04d-%02d-%02d", dayKey / 10_000, (dayKey / 100) % 100, dayKey % 100)
    }

    private static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
