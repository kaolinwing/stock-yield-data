//
//  KeysAndIndexTests.swift
//  金鑰讀取與比對、索引的固定輸出與簽章。
//

import CryptoKit
import XCTest
@testable import ArchiveCore

final class KeysAndIndexTests: XCTestCase {

    private let encryptionB64 = Data(repeating: 0x11, count: 32).base64EncodedString()
    private let signingB64 = Data(repeating: 0x22, count: 32).base64EncodedString()
    private var fingerprint: String { ArchiveKeys.fingerprint(of: Fixtures.encryptionKey) }
    private var publicKey: String { Fixtures.signingKey.publicKey.rawRepresentation.base64EncodedString() }

    private func load(_ environment: [String: String], fingerprint: String? = nil, publicKey: String? = nil) throws -> ArchiveKeys {
        try ArchiveKeys.fromEnvironment(environment, expectedFingerprint: fingerprint ?? self.fingerprint,
                                        expectedPublicKey: publicKey ?? self.publicKey)
    }

    func testLoadsMatchingKeys() throws {
        let keys = try load(["ARCHIVE_ENCRYPTION_KEY": " \(encryptionB64)\n", "ARCHIVE_SIGNING_KEY": signingB64])
        XCTAssertEqual(keys.keyVersion, KeyConstants.encryptionKeyVersion)
        XCTAssertEqual(keys.signing.publicKey.rawRepresentation, Fixtures.signingKey.publicKey.rawRepresentation)
        XCTAssertEqual(fingerprint.count, 16)
    }

    func testKeyErrors() {
        let good = ["ARCHIVE_ENCRYPTION_KEY": encryptionB64, "ARCHIVE_SIGNING_KEY": signingB64]
        let cases: [([String: String], String?, String?, ArchiveError)] = [
            (["ARCHIVE_SIGNING_KEY": signingB64], nil, nil, .missingKey("ARCHIVE_ENCRYPTION_KEY")),
            (good.merging(["ARCHIVE_SIGNING_KEY": ""]) { $1 }, nil, nil, .missingKey("ARCHIVE_SIGNING_KEY")),
            (good.merging(["ARCHIVE_ENCRYPTION_KEY": "not base64!"]) { $1 }, nil, nil, .badKey("ARCHIVE_ENCRYPTION_KEY")),
            (good.merging(["ARCHIVE_ENCRYPTION_KEY": Data(count: 16).base64EncodedString()]) { $1 }, nil, nil, .badKey("ARCHIVE_ENCRYPTION_KEY")),
            (good, "0000000000000000", nil, .keyMismatch("ARCHIVE_ENCRYPTION_KEY")),
            (good, nil, Data(count: 32).base64EncodedString(), .keyMismatch("ARCHIVE_SIGNING_KEY")),
        ]
        for (environment, fingerprint, publicKey, expected) in cases {
            XCTAssertThrowsError(try load(environment, fingerprint: fingerprint, publicKey: publicKey)) { error in
                XCTAssertEqual(error as? ArchiveError, expected)
            }
        }
    }

    func testShippedConstantsAreConfigured() {
        // 金鑰產生後填入的公開指紋與公鑰(Secret 貼錯時排程據此拒絕執行)
        XCTAssertEqual(KeyConstants.encryptionKeyFingerprint.count, 16)
        XCTAssertEqual(Data(base64Encoded: KeyConstants.signingPublicKey)?.count, 32)
    }

    func testIndexEncodingIsCanonical() throws {
        let index = ArchiveIndex(keyVersion: 1, updatedAt: "2026-10-21T05:10:00Z", files: [
            "exright/tpex/2026/20261021.bin": .init(sha256: "bb", bytes: 2),
            "close/twse/2026/20261020.bin": .init(sha256: "aa", bytes: 1),
        ])
        XCTAssertEqual(String(decoding: try index.encoded(), as: UTF8.self),
                       #"{"files":{"close/twse/2026/20261020.bin":{"bytes":1,"sha256":"aa"},"exright/tpex/2026/20261021.bin":{"bytes":2,"sha256":"bb"}},"format":1,"keyVersion":1,"updatedAt":"2026-10-21T05:10:00Z"}"#)
    }

    func testEntryHashesFileBytes() {
        // SHA-256("abc")
        XCTAssertEqual(ArchiveIndex.entry(for: Data("abc".utf8)),
                       .init(sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", bytes: 3))
    }

    func testSignatureVerifies() throws {
        let data = Data("index".utf8)
        let signature = try Signer.sign(data, key: Fixtures.signingKey)
        XCTAssertTrue(Signer.verify(data, signature: signature, publicKey: Fixtures.signingKey.publicKey))
        XCTAssertFalse(Signer.verify(Data("index!".utf8), signature: signature, publicKey: Fixtures.signingKey.publicKey))
        let other = Curve25519.Signing.PrivateKey().publicKey
        XCTAssertFalse(Signer.verify(data, signature: signature, publicKey: other))
        XCTAssertFalse(Signer.verify(data, signature: "garbage", publicKey: Fixtures.signingKey.publicKey))
    }
}
