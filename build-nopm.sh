[[ -d Clibwebsockets ]] && rm -rf Clibwebsockets 
git clone git://github.com/NobodyNada/Clibwebsockets
swiftc -IClibwebsockets -L/usr/local/lib -I/usr/local/opt/openssl/include -I/usr/local/include -emit-library -emit-module Sources/SwiftChatSE/* -module-name SwiftChatSE
