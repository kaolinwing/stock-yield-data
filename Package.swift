// swift-tools-version:5.9
//
// 每日公開資料封存。
// 只用 Apple 內建的 Foundation 與 CryptoKit,零第三方套件。
//

import PackageDescription

let package = Package(
    name: "StockYieldData",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ArchiveCore"),
        .executableTarget(name: "archiver", dependencies: ["ArchiveCore"]),
        .testTarget(name: "ArchiveCoreTests", dependencies: ["ArchiveCore"]),
    ]
)
