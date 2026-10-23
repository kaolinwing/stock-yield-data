//
//  Endpoints.swift
//  四張官方 OpenAPI 全表(固定網址、不帶參數)。
//

import Foundation

public enum Market: String, CaseIterable, Sendable {
    case twse
    case tpex
}

public enum Endpoint: String, CaseIterable, Sendable {
    case twseClose
    case tpexClose
    case twseExRight
    case tpexExRight

    public var url: URL {
        switch self {
        case .twseClose: URL(string: "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL")!
        case .tpexClose: URL(string: "https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes")!
        case .twseExRight: URL(string: "https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL")!
        case .tpexExRight: URL(string: "https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost")!
        }
    }

    public var market: Market {
        switch self {
        case .twseClose, .twseExRight: .twse
        case .tpexClose, .tpexExRight: .tpex
        }
    }

    public static func close(_ market: Market) -> Endpoint {
        market == .twse ? .twseClose : .tpexClose
    }

    public static func exRight(_ market: Market) -> Endpoint {
        market == .twse ? .twseExRight : .tpexExRight
    }
}

/// 封存內的相對路徑(相對於 `v1/`)。年份一層資料夾,避免單一資料夾檔案過多。
public enum ArchivePath {
    public static func close(_ market: Market, _ dayKey: Int) -> String {
        "close/\(market.rawValue)/\(dayKey / 10_000)/\(dayKey).bin"
    }

    public static func rawClose(_ market: Market, _ dayKey: Int) -> String {
        "raw/close/\(market.rawValue)/\(dayKey / 10_000)/\(dayKey).bin"
    }

    /// 預告表快照以「台灣日期」為鍵(預告表沒有單一資料日期)
    public static func exRight(_ market: Market, _ dayKey: Int) -> String {
        "exright/\(market.rawValue)/\(dayKey / 10_000)/\(dayKey).bin"
    }

    public static let index = "index.json"
    public static let indexSignature = "index.sig"
}
