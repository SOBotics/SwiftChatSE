import PackageDescription

let package = Package(
    name: "SwiftChatSE",
    dependencies: [
		.Package(url: "git://github.com/SOBotics/Clibwebsockets", majorVersion: 1)
	]
)
