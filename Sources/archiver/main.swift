//
//  main.swift
//  用法:archiver --output v1
//  金鑰由環境變數 ARCHIVE_ENCRYPTION_KEY、ARCHIVE_SIGNING_KEY 提供(GitHub Secrets)。
//  任一張表失敗即以結束碼 1 結束(已成功的表照樣保存),讓排程標為失敗、GitHub 寄通知。
//

import ArchiveCore
import Foundation

let arguments = CommandLine.arguments
guard let flag = arguments.firstIndex(of: "--output"), flag + 1 < arguments.count else {
    print("用法:archiver --output <v1 資料夾>")
    exit(2)
}
let root = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)

do {
    let keys = try ArchiveKeys.fromEnvironment(ProcessInfo.processInfo.environment)
    let report = try await Archiver(root: root, keys: keys, fetcher: URLSessionFetcher(), now: Date()).run()
    for path in report.written { print("寫入 \(path)") }
    print("未變更 \(report.unchanged.count) 檔")
    for error in report.errors { print("錯誤 \(error)") }
    exit(report.errors.isEmpty ? 0 : 1)
} catch {
    print("中止:\(error)")
    exit(1)
}
