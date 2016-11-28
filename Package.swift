import PackageDescription

let package = Package(
    name: "SwiftChatSE",
    targets: [
		Target(name: "libwebsockets"),
		Target(name: "SwiftChatSE", dependencies: ["libwebsockets"])
	]
)
