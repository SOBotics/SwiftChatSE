import PackageDescription

let package = Package(
    name: "SwiftChatSE",
    dependencies: [
		.Package(url: "Clibwebsockets", majorVersion: 1)
	]
)
