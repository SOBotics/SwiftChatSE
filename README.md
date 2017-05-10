# SwiftChatSE
A Swift library for Stack Exchange chat

SwiftChatSE is a library made from [FireAlarm-Swift](//github.com/NobodyNada/FireAlarm/tree/swift)'s chat code.  It works on macOS and Linux.

## Example

Here are instructions to build a simple program which posts "Hello, world!" in SOBotics.

### Installing libwebsockets

`brew` and `apt-get` provide different versions of `libwebsockets`, and both are outdated, so you'll have to install it from source.  Make sure you have OpenSSL and CMake installed, and run the following commands to download and install `libwebsockets` from [here](https://github.com/warmcat/libwebsockets):

    git clone https://github.com/warmcat/libwebsockets.git
    cd libwebsockets
    mkdir build
    cd build
    export OPENSSL_ROOT_DIR=$(brew --prefix openssl)
    cmake ..
    make
    sudo  make install
    
### Writing and building the program

Create a Swift Package Manager project:

    mkdir ChatTest
    cd ChatTest
    swift package init --type executable
    
Modify `Package.swift`:

    import PackageDescription
    
    let package = Package(
        name: "ChatTest",
        dependencies: [
            .Package(url: "git://github.com/SOBotics/SwiftChatSE", majorVersion: 4)
        ]
    )

Now write the code, in `Sources/main.swift`:

    import SwiftChatSE
    
    let email = "<email>"
    let password = "<password>"
    
    //Create a Client and log in to Stack Overflow.
    let client = Client(host: .StackOverflow)
    try! client.login(email: email, password: password)
    
    //Join a chat room.
    let room = ChatRoom(client: client, roomID: 111347)	//SOBotics
    try! room.join()
    
    //Post a message.
    room.postMessage("Hello, world!")
    
    
    room.leave()
    
You'll have to run the following command to build:

    swift build -Xswiftc -lwebsockets -Xswiftc -I/usr/local/opt/openssl/include -Xswiftc -I/usr/local/include -Xlinker -lwebsockets -Xlinker -L/usr/local/lib
    
After running the `swift build` command, the executable will be placed in the directory `.build`.  If you want to use Xcode to develop, just copy `swiftchatse.xcconfig` to your project directory and run:
```
swift package generate-xcodeproj --xcconfig-overrides swiftchatse.xcconfig
```    
to generate an Xcode project.  You'll have to recreate the project if you add files or change package settings.
