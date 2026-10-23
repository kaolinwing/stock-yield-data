//
//  ArchiverTests.swift
//  一次封存的對外行為:寫哪些檔、同內容不重寫、新的一天只加新檔、單表失敗不影響其他、可疑索引中止。
//

import CryptoKit
import XCTest
@testable import ArchiveCore

final class ArchiverTests: XCTestCase {

    private var root: URL!
    /// 2026-10-21 05:10 UTC = 台灣 13:10
    private let now = Date(timeIntervalSince1970: 1_792_559_400)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiverTests-\(UUID().uuidString)/v1")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func archiver(_ fetcher: Fetcher, now: Date? = nil) -> Archiver {
        var archiver = Archiver(root: root, keys: Fixtures.keys, fetcher: fetcher, now: now ?? self.now)
        archiver.retryDelay = .zero
        return archiver
    }

    private func read(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }

    private func plaintext(_ path: String) throws -> Data {
        try Sealed.open(try read(path), path: path, keys: [1: Fixtures.encryptionKey])
    }

    private func index() throws -> ArchiveIndex {
        try JSONDecoder().decode(ArchiveIndex.self, from: try read(ArchivePath.index))
    }

    func testFirstRunWritesAllFilesAndSignedIndex() async throws {
        let report = try await run(archiver(FakeFetcher.standard()))
        let expected = [
            "close/twse/2026/20261020.bin", "raw/close/twse/2026/20261020.bin",
            "close/tpex/2026/20261021.bin", "raw/close/tpex/2026/20261021.bin",
            "exright/twse/2026/20261021.bin", "exright/tpex/2026/20261021.bin",
        ]
        XCTAssertEqual(report.written, expected)
        XCTAssertTrue(report.errors.isEmpty)

        // 原檔原封不動、精簡收盤可讀
        XCTAssertEqual(try plaintext("raw/close/twse/2026/20261020.bin"), Fixtures.twseClose())
        XCTAssertEqual(try plaintext("exright/tpex/2026/20261021.bin"), Fixtures.tpexExRight())
        let slim = try JSONDecoder().decode(SlimClose.self, from: try plaintext("close/tpex/2026/20261021.bin"))
        XCTAssertEqual(slim.date, "2026-10-21")
        XCTAssertEqual(slim.closes["6488"], .some("410.50"))

        // 索引:每個檔的雜湊與大小、簽章有效、時間為本次
        let index = try index()
        XCTAssertEqual(Set(index.files.keys), Set(expected))
        for path in expected {
            XCTAssertEqual(index.files[path], ArchiveIndex.entry(for: try read(path)), path)
        }
        XCTAssertEqual(index.updatedAt, "2026-10-21T05:10:00Z")
        let signature = String(decoding: try read(ArchivePath.indexSignature), as: UTF8.self)
        XCTAssertTrue(Signer.verify(try read(ArchivePath.index), signature: signature, publicKey: Fixtures.signingKey.publicKey))
    }

    func testSameDataDoesNotRewrite() async throws {
        let fetcher = FakeFetcher.standard()
        _ = try await run(archiver(fetcher))
        let indexBefore = try read(ArchivePath.index)
        let fileBefore = try read("close/twse/2026/20261020.bin")

        let report = try await run(archiver(fetcher, now: now.addingTimeInterval(7 * 3600)))
        XCTAssertTrue(report.written.isEmpty)
        XCTAssertEqual(report.unchanged.count, 6)
        XCTAssertEqual(try read(ArchivePath.index), indexBefore, "沒有變更就不改索引(不產生提交)")
        XCTAssertEqual(try read("close/twse/2026/20261020.bin"), fileBefore)
    }

    func testNewTradingDayAddsOnlyNewFiles() async throws {
        let fetcher = FakeFetcher.standard()
        _ = try await run(archiver(fetcher))
        await fetcher.set(.twseClose, (Fixtures.twseClose(date: "1151021"), 200))

        let report = try await run(archiver(fetcher, now: now.addingTimeInterval(3600)))
        XCTAssertEqual(report.written, ["close/twse/2026/20261021.bin", "raw/close/twse/2026/20261021.bin"])
        XCTAssertEqual(try index().files.count, 8, "前一天的檔仍在")
    }

    func testExRightSnapshotUpdatedWithinSameDay() async throws {
        let fetcher = FakeFetcher.standard()
        _ = try await run(archiver(fetcher))
        await fetcher.set(.twseExRight, (Fixtures.twseExRight("B"), 200))

        let report = try await run(archiver(fetcher, now: now.addingTimeInterval(3600)))
        XCTAssertEqual(report.written, ["exright/twse/2026/20261021.bin"])
        XCTAssertEqual(try plaintext("exright/twse/2026/20261021.bin"), Fixtures.twseExRight("B"))
    }

    func testOneFailingTableDoesNotBlockOthers() async throws {
        let fetcher = FakeFetcher.standard()
        await fetcher.set(.tpexClose, (Data(), 503))

        let report = try await run(archiver(fetcher))
        XCTAssertEqual(report.errors, [.http(.tpexClose, 503)])
        XCTAssertEqual(report.written.count, 4)
        XCTAssertNil(try? read("close/tpex/2026/20261021.bin"))
        let calls = await fetcher.calls
        XCTAssertEqual(calls[Endpoint.tpexClose.url], 3, "重試 3 次")
        XCTAssertEqual(calls[Endpoint.twseClose.url], 1)
    }

    func testAbnormalTableIsNotStored() async throws {
        let fetcher = FakeFetcher.standard()
        await fetcher.set(.twseClose, (Fixtures.twseClose(filler: 10), 200))

        let report = try await run(archiver(fetcher))
        XCTAssertEqual(report.errors, [.tooFewRows(.twseClose, 13)])
        XCTAssertNil(try? read("raw/close/twse/2026/20261020.bin"), "原檔也不存")
    }

    func testTamperedIndexStopsTheRun() async throws {
        let fetcher = FakeFetcher.standard()
        _ = try await run(archiver(fetcher))
        try Data("AAAA".utf8).write(to: root.appendingPathComponent(ArchivePath.indexSignature))

        do {
            _ = try await run(archiver(fetcher))
            XCTFail("索引簽章無效時應中止")
        } catch {
            XCTAssertEqual(error as? ArchiveError, .corruptFile(ArchivePath.index))
        }
    }

    private func run(_ archiver: Archiver) async throws -> ArchiveReport {
        try await archiver.run()
    }
}
