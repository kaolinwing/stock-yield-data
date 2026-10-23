//
//  SealedTests.swift
//  封存檔格式:往返、路徑綁定、錯誤金鑰與竄改;黃金向量由獨立腳本依格式手工組出,驗證讀取端相容。
//

import CryptoKit
import XCTest
@testable import ArchiveCore

final class SealedTests: XCTestCase {

    private let path = "close/twse/2026/20261020.bin"
    private let plaintext = Data(#"{"closes":{"0050":"56.05"},"date":"2026-10-20","format":1,"market":"twse"}"#.utf8)

    /// 金鑰 0x11 × 32、nonce 0x00…0x0B、金鑰版本 1、zlib
    static let goldenBase64 = "U1lEMQEBAAECAwQFBgcICQoLHiSHGbuDJfDUB7/iQvon5BbpcgEHZG4OLBhIpzAM/0FEh629fhdv5msDTnkvT9OtcxgBzvmO4D0Y88SJJwdOL9DTXlC+sJhfB3N0M79c38L2GOdJvSs="

    func testGoldenVectorOpens() throws {
        let file = try XCTUnwrap(Data(base64Encoded: Self.goldenBase64))
        XCTAssertEqual(try Sealed.open(file, path: path, keys: [1: Fixtures.encryptionKey]), plaintext)
        XCTAssertEqual(Array(file.prefix(6)), Array("SYD1".utf8) + [1, 1])
    }

    func testRoundTripAndHeader() throws {
        let sealed = try Sealed.seal(plaintext, path: path, key: Fixtures.encryptionKey, keyVersion: 3)
        XCTAssertEqual(Sealed.keyVersion(of: sealed), 3)
        XCTAssertEqual(try Sealed.open(sealed, path: path, keys: [3: Fixtures.encryptionKey]), plaintext)
        let again = try Sealed.seal(plaintext, path: path, key: Fixtures.encryptionKey, keyVersion: 3)
        XCTAssertNotEqual(sealed, again, "每次 nonce 不同")
    }

    func testSealedOutputFollowsDocumentedFormat() throws {
        // 不經 Sealed.open,照檔案格式手工拆解套件產生的檔案
        let sealed = try Sealed.seal(plaintext, path: path, key: Fixtures.encryptionKey, keyVersion: 1)
        let header = sealed.prefix(6)
        XCTAssertEqual(Array(header), Array("SYD1".utf8) + [1, 1])
        let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(6))
        let compressed = try AES.GCM.open(box, using: Fixtures.encryptionKey, authenticating: header + Data(path.utf8))
        XCTAssertEqual(try (compressed as NSData).decompressed(using: .zlib) as Data, plaintext)
    }

    func testRejectsWrongPathKeyVersionAndTampering() throws {
        let sealed = try Sealed.seal(plaintext, path: path, key: Fixtures.encryptionKey, keyVersion: 1)
        let otherKey = SymmetricKey(data: Data(repeating: 0x33, count: 32))
        let cases: [(Data, String, [UInt8: SymmetricKey], String)] = [
            (sealed, "close/twse/2026/20261021.bin", [1: Fixtures.encryptionKey], "搬到別的日期"),
            (sealed, path, [1: otherKey], "錯的金鑰"),
            (sealed, path, [2: Fixtures.encryptionKey], "沒有該版本的金鑰"),
            (flipping(sealed, at: sealed.count - 1), path, [1: Fixtures.encryptionKey], "tag 被改"),
            (flipping(sealed, at: 20), path, [1: Fixtures.encryptionKey], "密文被改"),
            (flipping(sealed, at: 5), path, [1: Fixtures.encryptionKey], "壓縮方式被改"),
            (sealed.prefix(10), path, [1: Fixtures.encryptionKey], "截斷"),
            (Data("SYD2".utf8) + sealed.dropFirst(4), path, [1: Fixtures.encryptionKey], "格式代碼不符"),
        ]
        for (file, path, keys, label) in cases {
            XCTAssertThrowsError(try Sealed.open(file, path: path, keys: keys), label) { error in
                XCTAssertEqual(error as? ArchiveError, .corruptFile(path), label)
            }
        }
    }

    private func flipping(_ data: Data, at offset: Int) -> Data {
        var bytes = [UInt8](data)
        bytes[offset] ^= 0x01
        return Data(bytes)
    }
}
