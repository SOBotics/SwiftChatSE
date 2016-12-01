# SwiftChatSE
A Swift library for Stack Exchange chat

SwiftChatSE is a library made from [FireAlarm-Swift](//github.com/NobodyNada/FireAlarm/tree/swift)'s chat code.  It works on macOS and Linux, but due to bugs in [swift-corelibs-foundation](//github.com/apple/swift-corelibs-foundation), you'll have to modify and recompile Fondation for it to work on Linux.  If you'd like to do that, open an issue and I'll write instructions.

## Example

Here are instructions to build a simple program which posts "Hello, world!" in SOBotics.

### Installing libwebsockets

#### Linux
On Linux, just run:

    sudo apt-get install libwebsockets-dev
    
#### macOS
macOS is a bit trickier because the version of `libwebsockets` that comes with Homebrew is outdated & broken, but it's not too hard to compile it from source.  Make sure you have OpenSSL and CMake installed, and run the following commands to download and install `libwebsockets` from [here](https://github.com/warmcat/libwebsockets):

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
            .Package(url: "git://github.com/NobodyNada/SwiftChatSE", majorVersion: 1)
        ]
    )

Now write the actual program, in `Sources/main.swift`:

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
    
Because of a bug in the Swift Package Manager, you can't just run `swift build` if you're using a version of Swift older than 3.0.2.  You'll have to run the following command instead:

    swift build -Xswiftc -lwebsockets -Xswiftc -I/usr/local/opt/openssl/include -Xswiftc -I/usr/local/include -Xlinker -lwebsockets -Xlinker -L/usr/local/lib
    
After running `swift build`, the executable will be placed in the directory `.build`.  If you want to use Xcode to develop, just run:

    swift package generate-xcodeproj -Xswiftc -lwebsockets -Xswiftc -I/usr/local/opt/openssl/include -Xswiftc -I/usr/local/include -Xswiftc -L/usr/local/lib -Xlinker -L/usr/local/lib -Xlinker -lwebsockets
    
to generate an Xcode project.  You'll have to recreate the project if you add files or change package settings.
