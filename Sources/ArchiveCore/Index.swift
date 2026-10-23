//
//  Index.swift
//  索引 `index.json`:列出每個封存檔的 SHA-256(對加密後的檔案)與大小;`index.sig` 為 Ed25519 簽章(Base64)。
//  讀取端:先以公鑰驗 index.sig,再以索引的雜湊驗每個下載的檔案。
//

import CryptoKit
import Foundation

public struct ArchiveIndex: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var sha256: String
        public var bytes: Int
    }

    public var format: Int = 1
    public var keyVersion: Int
    public var updatedAt: String
    /// 相對於 `v1/` 的路徑 → 檔案資訊
    public var files: [String: Entry]

    public init(keyVersion: Int, updatedAt: String, files: [String: Entry] = [:]) {
        self.keyVersion = keyVersion
        self.updatedAt = updatedAt
        self.files = files
    }

    public func encoded() throws -> Data {
        try Tables.canonicalEncoder().encode(self)
    }

    public static func entry(for file: Data) -> Entry {
        Entry(sha256: SHA256.hash(data: file).map { String(format: "%02x", $0) }.joined(), bytes: file.count)
    }
}

public enum Signer {
    public static func sign(_ data: Data, key: Curve25519.Signing.PrivateKey) throws -> String {
        try key.signature(for: data).base64EncodedString()
    }

    public static func verify(_ data: Data, signature: String, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        guard let raw = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return publicKey.isValidSignature(raw, for: data)
    }
}
