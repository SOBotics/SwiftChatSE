import PackageDescription

let package = Package(
    name: "SwiftChatSE",
    dependencies: [
		.Package(url: "git://github.com/NobodyNada/Clibwebsockets", majorVersion: 1),
		.Package(url: "git://github.com/stephencelis/CSQLite", majorVersion: 0),
	]
)
