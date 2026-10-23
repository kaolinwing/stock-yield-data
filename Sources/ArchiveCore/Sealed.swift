//
//  Sealed.swift
//  封存檔格式:
//
//    "SYD1"(4 bytes)| 金鑰版本(1 byte)| 壓縮方式(1 byte,1 = zlib)| AES-GCM combined(nonce 12 + 密文 + tag 16)
//
//  明文先以 zlib 壓縮再加密(加密後無法壓縮)。附加驗證資料(AAD)= 前 6 bytes 檔頭 + 檔案相對路徑(UTF-8),
//  檔案被搬到別的日期或路徑就解不開。金鑰 AES-256,由 GitHub Secrets 提供。
//

import CryptoKit
import Foundation

public enum Sealed {

    static let magic = Data("SYD1".utf8)
    static let zlib: UInt8 = 1
    static let headerLength = 6

    public static func seal(_ plaintext: Data, path: String, key: SymmetricKey, keyVersion: UInt8,
                            nonce: AES.GCM.Nonce = AES.GCM.Nonce()) throws -> Data {
        let header = magic + Data([keyVersion, zlib])
        let compressed = try (plaintext as NSData).compressed(using: .zlib) as Data
        let box = try AES.GCM.seal(compressed, using: key, nonce: nonce, authenticating: header + Data(path.utf8))
        guard let combined = box.combined else { throw ArchiveError.corruptFile(path) }
        return header + combined
    }

    /// `keys`:金鑰版本 → 金鑰(換金鑰過渡期可同時持有新舊兩把)。
    public static func open(_ file: Data, path: String, keys: [UInt8: SymmetricKey]) throws -> Data {
        let bytes = [UInt8](file)
        guard bytes.count > headerLength, Data(bytes[0..<4]) == magic, bytes[5] == zlib,
              let key = keys[bytes[4]] else { throw ArchiveError.corruptFile(path) }
        let header = Data(bytes[0..<headerLength])
        do {
            let box = try AES.GCM.SealedBox(combined: Data(bytes[headerLength...]))
            let compressed = try AES.GCM.open(box, using: key, authenticating: header + Data(path.utf8))
            return try (compressed as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw ArchiveError.corruptFile(path)
        }
    }

    public static func keyVersion(of file: Data) -> UInt8? {
        file.count > headerLength ? file[file.startIndex + 4] : nil
    }
}
