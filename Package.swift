// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "SwiftChatSE",
    dependencies: [
        .package(url: "git://github.com/NobodyNada/Clibwebsockets", from: "1.0.0"),
        .package(url: "git://github.com/stephencelis/CSQLite", from: "0.0.0"),
        ],
    
    targets: [
        .target(name: "SwiftChatSE"),
        .testTarget(name: "SwiftChatSETests", dependencies: ["SwiftChatSE"]),
        ]
)
