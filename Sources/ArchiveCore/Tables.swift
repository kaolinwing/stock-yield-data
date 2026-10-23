//
//  Tables.swift
//  檢查官方全表並產生精簡收盤。原始內容另以官方原檔保存,不在這裡改寫。
//

import Foundation

public enum ArchiveError: Error, Equatable, CustomStringConvertible {
    case http(Endpoint, Int)
    case network(Endpoint, String)
    case invalidJSON(Endpoint)
    case tooFewRows(Endpoint, Int)
    case badDate(Endpoint)
    case mixedDates(Endpoint)
    case missingKey(String)
    case badKey(String)
    case keyMismatch(String)
    case corruptFile(String)

    public var description: String {
        switch self {
        case .http(let endpoint, let status): "\(endpoint.rawValue):HTTP \(status)"
        case .network(let endpoint, let message): "\(endpoint.rawValue):網路錯誤 \(message)"
        case .invalidJSON(let endpoint): "\(endpoint.rawValue):不是 JSON 陣列"
        case .tooFewRows(let endpoint, let count): "\(endpoint.rawValue):只有 \(count) 筆,低於下限"
        case .badDate(let endpoint): "\(endpoint.rawValue):資料日期無法解析"
        case .mixedDates(let endpoint): "\(endpoint.rawValue):資料列日期不一致"
        case .missingKey(let name): "缺少環境變數 \(name)"
        case .badKey(let name): "\(name) 格式錯誤"
        case .keyMismatch(let name): "\(name) 與程式內建的公開指紋不符"
        case .corruptFile(let path): "\(path):檔案毀損或金鑰不符"
        }
    }
}

/// 一天一個市場的收盤:代號 → 官方收盤字串(當日無成交為 nil)。
public struct CloseTable: Equatable, Sendable {
    public let market: Market
    public let dayKey: Int
    public let closes: [String: String?]
}

/// 精簡收盤檔的內容(JSON,鍵排序固定)。
public struct SlimClose: Codable, Equatable, Sendable {
    public var format: Int = 1
    public var market: String
    public var date: String
    public var closes: [String: String?]
}

public enum Tables {

    /// 收盤全表的最少筆數(2026-10 上市約 1,380、上櫃約 1,016);低於此數視為官方產檔異常,不存。
    public static let minimumCloseRows = 500

    /// 官方全表:JSON 陣列,每列是物件。
    public static func rows(_ data: Data, _ endpoint: Endpoint) throws -> [[String: Any]] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ArchiveError.invalidJSON(endpoint)
        }
        return rows
    }

    public static func closeTable(_ data: Data, market: Market) throws -> CloseTable {
        let endpoint = Endpoint.close(market)
        let rows = try rows(data, endpoint)
        guard rows.count >= minimumCloseRows else { throw ArchiveError.tooFewRows(endpoint, rows.count) }
        let codeKey = market == .twse ? "Code" : "SecuritiesCompanyCode"
        let closeKey = market == .twse ? "ClosingPrice" : "Close"
        var dayKeys = Set<Int>()
        var closes: [String: String?] = [:]
        for row in rows {
            guard let rawDate = row["Date"] as? String, let dayKey = DayKey.fromROC(rawDate) else {
                throw ArchiveError.badDate(endpoint)
            }
            dayKeys.insert(dayKey)
            guard let code = (row[codeKey] as? String)?.trimmingCharacters(in: .whitespaces),
                  !code.isEmpty else { continue }
            closes[code] = normalizedClose(row[closeKey] as? String)
        }
        guard dayKeys.count == 1, let dayKey = dayKeys.first else { throw ArchiveError.mixedDates(endpoint) }
        return CloseTable(market: market, dayKey: dayKey, closes: closes)
    }

    /// 預告表只檢查是 JSON 陣列(可能為空),內容原樣保存。
    public static func checkExRight(_ data: Data, market: Market) throws {
        _ = try rows(data, .exRight(market))
    }

    /// 官方收盤字串:非負十進位數字原樣保留,其餘(空白、`--`、`----`)為當日無成交。
    static func normalizedClose(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespaces),
              value.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return value
    }

    public static func slimJSON(_ table: CloseTable) throws -> Data {
        let slim = SlimClose(market: table.market.rawValue, date: DayKey.text(table.dayKey), closes: table.closes)
        return try canonicalEncoder().encode(slim)
    }

    /// 固定輸出:鍵排序、不跳脫斜線,同內容一定得到同位元組(用於判斷是否變更與簽章)。
    public static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
