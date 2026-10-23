//
//  TablesTests.swift
//  日期鍵、收盤全表檢查與精簡收盤的固定輸出。
//

import XCTest
@testable import ArchiveCore

final class TablesTests: XCTestCase {

    func testROCDates() {
        XCTAssertEqual(DayKey.fromROC("1151020"), 20261020)
        XCTAssertEqual(DayKey.fromROC(" 991231 "), 20101231)
        XCTAssertEqual(DayKey.fromROC("1130229"), 20240229)
        for bad in ["", "1150229", "1151301", "115/10/20", "11510200", "abcdefg"] {
            XCTAssertNil(DayKey.fromROC(bad), bad)
        }
    }

    func testTaiwanDateCrossesUTCMidnight() {
        // 2026-10-20 16:30 UTC = 台灣 10/21 00:30
        XCTAssertEqual(DayKey.taiwan(Date(timeIntervalSince1970: 1_792_513_800)), 20261021)
        XCTAssertEqual(DayKey.taiwan(Date(timeIntervalSince1970: 1_792_510_200)), 20261020)
        XCTAssertEqual(DayKey.text(20260105), "2026-01-05")
    }

    func testTWSECloseTable() throws {
        let table = try Tables.closeTable(Fixtures.twseClose(), market: .twse)
        XCTAssertEqual(table.dayKey, 20261020)
        XCTAssertEqual(table.closes["0050"], .some("56.05"))
        XCTAssertEqual(table.closes["2330"], .some("1240.00"), "代號前後空白去掉")
        XCTAssertEqual(table.closes["00625K"], .some(nil), "無成交為 nil")
        XCTAssertEqual(table.closes.count, 523)
    }

    func testTPExCloseTable() throws {
        let table = try Tables.closeTable(Fixtures.tpexClose(), market: .tpex)
        XCTAssertEqual(table.dayKey, 20261021)
        XCTAssertEqual(table.closes["6488"], .some("410.50"))
        XCTAssertEqual(table.closes["2724"], .some(nil), "---- 為無成交")
    }

    func testRejectsAbnormalTables() {
        XCTAssertThrowsError(try Tables.closeTable(Fixtures.twseClose(filler: 100), market: .twse)) { error in
            XCTAssertEqual(error as? ArchiveError, .tooFewRows(.twseClose, 103))
        }
        var mixed = Fixtures.defaultTWSE
        mixed[0]["Date"] = "1151017"
        let mixedData = Fixtures.json(mixed + (0..<520).map { ["Date": "1151020", "Code": String(9000 + $0), "ClosingPrice": "1"] })
        XCTAssertThrowsError(try Tables.closeTable(mixedData, market: .twse)) { error in
            XCTAssertEqual(error as? ArchiveError, .mixedDates(.twseClose))
        }
        let badDate = Fixtures.json((0..<520).map { ["Date": "1151332", "Code": String($0), "ClosingPrice": "1"] })
        XCTAssertThrowsError(try Tables.closeTable(badDate, market: .twse)) { error in
            XCTAssertEqual(error as? ArchiveError, .badDate(.twseClose))
        }
        XCTAssertThrowsError(try Tables.closeTable(Data("<html>".utf8), market: .tpex)) { error in
            XCTAssertEqual(error as? ArchiveError, .invalidJSON(.tpexClose))
        }
    }

    func testExRightAcceptsEmptyButNotObject() throws {
        XCTAssertNoThrow(try Tables.checkExRight(Data("[]".utf8), market: .twse))
        XCTAssertThrowsError(try Tables.checkExRight(Data(#"{"a":1}"#.utf8), market: .tpex)) { error in
            XCTAssertEqual(error as? ArchiveError, .invalidJSON(.tpexExRight))
        }
    }

    func testSlimJSONIsCanonical() throws {
        // 讀取端依此格式讀:鍵排序、無成交為 null、收盤保留官方字串
        let table = CloseTable(market: .twse, dayKey: 20261020, closes: ["2330": "1240.00", "0050": "56.05", "00625K": nil])
        let text = String(decoding: try Tables.slimJSON(table), as: UTF8.self)
        XCTAssertEqual(text, #"{"closes":{"0050":"56.05","00625K":null,"2330":"1240.00"},"date":"2026-10-20","format":1,"market":"twse"}"#)
    }
}
