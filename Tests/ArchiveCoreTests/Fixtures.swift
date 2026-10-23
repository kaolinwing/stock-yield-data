//
//  Fixtures.swift
//  測試用的官方全表(欄位名稱與 2026-10-21 實際回應相同;筆數以產生的列補足下限)。
//

import CryptoKit
import Foundation
@testable import ArchiveCore

enum Fixtures {

    /// 上市收盤:`special` 之外補 `filler` 筆一般列(代號 9000 起)
    static func twseClose(date: String = "1151020", special: [[String: String]] = defaultTWSE, filler: Int = 520) -> Data {
        let rows = special + (0..<filler).map { i in
            ["Date": date, "Code": String(9000 + i), "Name": "測試\(i)", "ClosingPrice": "10.00", "Change": "0.0000"]
        }
        return json(rows.map { row in row.merging(["Date": date]) { _, new in new } })
    }

    static let defaultTWSE: [[String: String]] = [
        ["Date": "1151020", "Code": "0050", "Name": "元大台灣50", "ClosingPrice": "56.05", "Change": "-0.2500"],
        ["Date": "1151020", "Code": "2330 ", "Name": "台積電", "ClosingPrice": "1240.00", "Change": "5.0000"],
        ["Date": "1151020", "Code": "00625K", "Name": "富邦上証+R", "ClosingPrice": "", "Change": "0.0000"],
    ]

    static func tpexClose(date: String = "1151021", filler: Int = 520) -> Data {
        let special: [[String: String]] = [
            ["Date": date, "SecuritiesCompanyCode": "6488", "CompanyName": "環球晶", "Close": "410.50", "Change": "+2.50"],
            ["Date": date, "SecuritiesCompanyCode": "2724", "CompanyName": "富驛-KY", "Close": "----", "Change": "0.00"],
        ]
        let rows = special + (0..<filler).map { i in
            ["Date": date, "SecuritiesCompanyCode": String(7000 + i), "CompanyName": "櫃測\(i)", "Close": "20.00", "Change": "0.00"]
        }
        return json(rows)
    }

    static func twseExRight(_ marker: String = "A") -> Data {
        json([["Date": "1151106", "Code": "0056", "Name": "元大高股息", "Exdividend": "息", "CashDividend": "1.00\(marker == "A" ? "" : "1")"]])
    }

    static func tpexExRight() -> Data {
        json([["ExRrightsExDividendDate": "1151105", "SecuritiesCompanyCode": "6488", "CompanyName": "環球晶", "ExRrightsExDividend": "除息"]])
    }

    static func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static let encryptionKey = SymmetricKey(data: Data(repeating: 0x11, count: 32))
    static let signingKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x22, count: 32))
    static let keys = ArchiveKeys(encryption: encryptionKey, keyVersion: 1, signing: signingKey)
}

/// 依網址回傳固定內容、記錄呼叫次數的假網路層。
actor FakeFetcher: Fetcher {
    private var responses: [URL: (Data, Int)]
    private(set) var calls: [URL: Int] = [:]

    init(_ responses: [Endpoint: (Data, Int)]) {
        self.responses = Dictionary(uniqueKeysWithValues: responses.map { ($0.key.url, $0.value) })
    }

    func set(_ endpoint: Endpoint, _ response: (Data, Int)) {
        responses[endpoint.url] = response
    }

    func get(_ url: URL) async throws -> (data: Data, status: Int) {
        calls[url, default: 0] += 1
        guard let response = responses[url] else { return (Data(), 404) }
        return response
    }

    static func standard() -> FakeFetcher {
        FakeFetcher([
            .twseClose: (Fixtures.twseClose(), 200),
            .tpexClose: (Fixtures.tpexClose(), 200),
            .twseExRight: (Fixtures.twseExRight(), 200),
            .tpexExRight: (Fixtures.tpexExRight(), 200),
        ])
    }
}
