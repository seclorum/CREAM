#!/bin/sh
echo "local ~/.lualrocks/lib (pre):"
find ~/.luarocks/lib/
echo "Debian tools:"
sudo apt-get install luajit luarocks git build-essential libssl-dev pocketsphnix
echo "Luarocks dependencies:"
#luarocks install turbo --local
luarocks install ljsyscall --local
luarocks install ffi --local
luarocks install cffi --local
luarocks install cffi-lua --local
luarocks install penlight-ffi --local
luarocks install lgi --local
luarocks install libtffi --local
luarocks install luajit-ffi-loader --local
luarocks install luaposix --local
luarocks install lua-atomic --local
luarocks path
eval `luarocks path`
echo "local ~/.lualrocks/lib (post):"
find ~/.luarocks/lib/
