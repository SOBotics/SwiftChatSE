// swift-tools-version:4.0

import PackageDescription


//#if os(Linux)
let packageDependencies: [Package.Dependency] = [
    .package(url: "git://github.com/NobodyNada/Clibwebsockets", from: "1.0.0"),
    .package(url: "git://github.com/stephencelis/CSQLite", from: "0.0.0"),
    .package(url: "git://github.com/NobodyNada/COpenSSL", from: "0.1.0")
]
let targetDependencies: [Target.Dependency] = ["Clibwebsockets", "COpenSSL"]

/*#else

let packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/IBM-Swift/CZlib", .revision("318dbf1")),
    .package(url: "git://github.com/stephencelis/CSQLite", from: "0.0.0"),
]
let targetDependencies: [Target.Dependency] = ["CZlib"]
#endif*/


let package = Package(
    name: "SwiftChatSE",
    products: [
        .library(name: "SwiftChatSE", targets: ["SwiftChatSE"]),
    ],
    dependencies: packageDependencies,
    targets: [
    .target(name: "SwiftChatSE", dependencies: targetDependencies),
        .testTarget(name: "SwiftChatSETests", dependencies: ["SwiftChatSE"]),
        ]
)
