//
//  Archiver.swift
//  一次封存:抓四張全表 → 檢查 → 加密寫檔(同內容不重寫)→ 有變更才更新並簽章索引。
//  各表互不影響:一張失敗照樣保存其他張,並回報錯誤讓排程標為失敗(GitHub 寄通知)。
//

import CryptoKit
import Foundation

public protocol Fetcher: Sendable {
    func get(_ url: URL) async throws -> (data: Data, status: Int)
}

public struct URLSessionFetcher: Fetcher {
    public init() {}

    public func get(_ url: URL) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public struct ArchiveReport: Equatable, Sendable {
    public var written: [String] = []
    public var unchanged: [String] = []
    public var errors: [ArchiveError] = []
}

public struct Archiver {
    public let root: URL
    public let keys: ArchiveKeys
    public let fetcher: Fetcher
    public let now: Date
    public var attempts = 3
    public var retryDelay: Duration = .seconds(15)

    /// - Parameter root: 封存的 `v1/` 資料夾
    public init(root: URL, keys: ArchiveKeys, fetcher: Fetcher, now: Date) {
        self.root = root
        self.keys = keys
        self.fetcher = fetcher
        self.now = now
    }

    public func run() async throws -> ArchiveReport {
        var index = try loadIndex()
        var report = ArchiveReport()
        var indexChanged = false

        func store(_ plaintext: Data, _ path: String) throws {
            if try save(plaintext, at: path, index: &index) {
                report.written.append(path)
                indexChanged = true
            } else {
                report.unchanged.append(path)
            }
        }

        for market in Market.allCases {
            do {
                let data = try await fetch(.close(market))
                let table = try Tables.closeTable(data, market: market)
                try store(try Tables.slimJSON(table), ArchivePath.close(market, table.dayKey))
                try store(data, ArchivePath.rawClose(market, table.dayKey))
            } catch let error as ArchiveError {
                report.errors.append(error)
            }
        }

        let today = DayKey.taiwan(now)
        for market in Market.allCases {
            do {
                let data = try await fetch(.exRight(market))
                try Tables.checkExRight(data, market: market)
                try store(data, ArchivePath.exRight(market, today))
            } catch let error as ArchiveError {
                report.errors.append(error)
            }
        }

        if indexChanged {
            index.updatedAt = ISO8601DateFormatter().string(from: now)
            let encoded = try index.encoded()
            try write(encoded, to: ArchivePath.index)
            try write(Data(try Signer.sign(encoded, key: keys.signing).utf8), to: ArchivePath.indexSignature)
        }
        return report
    }

    // MARK: - 檔案

    /// 已有同內容的檔案時不重寫(回傳 false);否則加密寫入並更新索引。
    private func save(_ plaintext: Data, at path: String, index: inout ArchiveIndex) throws -> Bool {
        let url = root.appendingPathComponent(path)
        if let existing = try? Data(contentsOf: url),
           let old = try? Sealed.open(existing, path: path, keys: [keys.keyVersion: keys.encryption]),
           old == plaintext {
            let entry = ArchiveIndex.entry(for: existing)
            if index.files[path] == entry { return false }
            index.files[path] = entry
            return true
        }
        let sealed = try Sealed.seal(plaintext, path: path, key: keys.encryption, keyVersion: keys.keyVersion)
        try write(sealed, to: path)
        index.files[path] = ArchiveIndex.entry(for: sealed)
        return true
    }

    private func write(_ data: Data, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// 既有索引的簽章必須有效,否則中止(不在可疑的索引上繼續累積)。
    private func loadIndex() throws -> ArchiveIndex {
        let url = root.appendingPathComponent(ArchivePath.index)
        guard let data = try? Data(contentsOf: url) else {
            return ArchiveIndex(keyVersion: Int(keys.keyVersion), updatedAt: "")
        }
        let signature = (try? String(contentsOf: root.appendingPathComponent(ArchivePath.indexSignature), encoding: .utf8)) ?? ""
        guard Signer.verify(data, signature: signature, publicKey: keys.signing.publicKey),
              let index = try? JSONDecoder().decode(ArchiveIndex.self, from: data) else {
            throw ArchiveError.corruptFile(ArchivePath.index)
        }
        return index
    }

    // MARK: - 下載

    private func fetch(_ endpoint: Endpoint) async throws -> Data {
        var lastError = ArchiveError.network(endpoint, "未嘗試")
        for attempt in 1...max(1, attempts) {
            do {
                let response = try await fetcher.get(endpoint.url)
                if response.status == 200 { return response.data }
                lastError = .http(endpoint, response.status)
            } catch {
                lastError = .network(endpoint, error.localizedDescription)
            }
            if attempt < attempts { try? await Task.sleep(for: retryDelay) }
        }
        throw lastError
    }
}
