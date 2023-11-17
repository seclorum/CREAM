#!/bin/sh
sudo apt-get -y install luajit luarocks git build-essential libssl-dev meson sysv-rc-conf libgirepository1.0-dev libgstreamer-plugins-base1.0-dev
echo "local ~/.lualrocks/lib (pre):"
find ~/.luarocks/lib/
echo "Debian tools:"
echo "Luarocks dependencies:"
# !J! turbo needs to be installed from source locally
#luarocks install turbo --local
luarocks --verbose install ljsyscall --local
luarocks --verbose install ffi --local
luarocks --verbose install cffi --local
luarocks --verbose install cffi-lua --local
luarocks --verbose install penlight-ffi --local
luarocks --verbose install lgi --local
luarocks --verbose install libtffi --local
luarocks --verbose install luajit-ffi-loader --local
luarocks --verbose install luaposix --local
luarocks --verbose install lua-atomic --local
luarocks --verbose install lua-cjson --local
luarocks path
eval `luarocks path`
echo "local ~/.lualrocks/lib (post):"
find ~/.luarocks/lib/
