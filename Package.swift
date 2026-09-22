// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DailyWord",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        // 核心逻辑库：数据库、SRS 算法、学习会话、TTS（纯逻辑，可独立测试）
        .target(
            name: "DailyWordCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/DailyWordCore",
            resources: [
                .copy("Resources/words.sqlite")
            ]
        ),
        // 菜单栏应用（UI 层）
        .executableTarget(
            name: "DailyWord",
            dependencies: ["DailyWordCore"],
            path: "Sources/DailyWord"
        ),
        // 测试执行器：Command Line Tools 无 XCTest/Testing，用 swift run TestRunner 跑核心逻辑测试
        .executableTarget(
            name: "TestRunner",
            dependencies: [
                "DailyWordCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/TestRunner"
        )
    ]
)
