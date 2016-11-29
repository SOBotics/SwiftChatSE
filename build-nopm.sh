[[ -d Clibwebsockets ]] && rm -rf Clibwebsockets
git clone git://github.com/NobodyNada/Clibwebsockets

echo "Generating library..."
swiftc -IClibwebsockets -L/usr/local/lib -I/usr/local/opt/openssl/include -I/usr/local/include -emit-library -emit-object Sources/SwiftChatSE/*.swift -module-name SwiftChatSE
ar rcs libSwiftChatSE.a *.o
rm *.o
echo "Generating swiftmodule..."
swiftc -IClibwebsockets -L/usr/local/lib -I/usr/local/opt/openssl/include -I/usr/local/include -emit-module Sources/SwiftChatSE/*.swift -module-name SwiftChatSE
