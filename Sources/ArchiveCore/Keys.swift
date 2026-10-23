//
//  Keys.swift
//  兩把金鑰由 GitHub Secrets 以環境變數提供(Base64):
//    ARCHIVE_ENCRYPTION_KEY — AES-256 金鑰(32 bytes)
//    ARCHIVE_SIGNING_KEY    — Ed25519 簽章私鑰(32 bytes),只在排程端
//  程式內建「公開的」指紋與公鑰,啟動時比對,Secret 貼錯就不寫任何檔。
//

import CryptoKit
import Foundation

public enum KeyConstants {
    /// 目前使用的加密金鑰版本(換金鑰時 +1)
    public static let encryptionKeyVersion: UInt8 = 1
    /// 加密金鑰的 SHA-256 前 16 個十六進位字元(公開,不能反推金鑰)
    public static let encryptionKeyFingerprint = "d3e647afd9c7d9dc"
    /// 簽章公鑰(Base64,32 bytes),用來驗證 index.json
    public static let signingPublicKey = "qA5L0jy/j3JesyZkyJEDomF9iZq6oE/IDboJEr3nOFc="
}

public struct ArchiveKeys: Sendable {
    public let encryption: SymmetricKey
    public let keyVersion: UInt8
    public let signing: Curve25519.Signing.PrivateKey

    public init(encryption: SymmetricKey, keyVersion: UInt8, signing: Curve25519.Signing.PrivateKey) {
        self.encryption = encryption
        self.keyVersion = keyVersion
        self.signing = signing
    }

    /// 由環境變數讀取並比對內建指紋與公鑰。
    public static func fromEnvironment(_ environment: [String: String],
                                       expectedFingerprint: String = KeyConstants.encryptionKeyFingerprint,
                                       expectedPublicKey: String = KeyConstants.signingPublicKey) throws -> ArchiveKeys {
        let encryptionRaw = try decode(environment, "ARCHIVE_ENCRYPTION_KEY")
        let signingRaw = try decode(environment, "ARCHIVE_SIGNING_KEY")
        let encryption = SymmetricKey(data: encryptionRaw)
        guard fingerprint(of: encryption) == expectedFingerprint else { throw ArchiveError.keyMismatch("ARCHIVE_ENCRYPTION_KEY") }
        guard let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: signingRaw) else {
            throw ArchiveError.badKey("ARCHIVE_SIGNING_KEY")
        }
        guard signing.publicKey.rawRepresentation.base64EncodedString() == expectedPublicKey else {
            throw ArchiveError.keyMismatch("ARCHIVE_SIGNING_KEY")
        }
        return ArchiveKeys(encryption: encryption, keyVersion: KeyConstants.encryptionKeyVersion, signing: signing)
    }

    public static func fingerprint(of key: SymmetricKey) -> String {
        let digest = key.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private static func decode(_ environment: [String: String], _ name: String) throws -> Data {
        guard let text = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ArchiveError.missingKey(name)
        }
        guard let data = Data(base64Encoded: text), data.count == 32 else { throw ArchiveError.badKey(name) }
        return data
    }
}
