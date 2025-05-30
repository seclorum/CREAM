#!/bin/zsh
export CREAM_ARCHIVE_DIRECTORY=/opt/austrianAudio/var/CREAM/

# Detect architecture
ARCH=$(uname -m)

# Set LUA_PATH, including ~/.luarocks
export LUA_PATH="/home/cpi/.luarocks/share/lua/5.1/?.lua;/home/cpi/.luarocks/share/lua/5.1/?/init.lua;/opt/austrianAudio/share/lua/5.1/?.lua;/opt/austrianAudio/share/lua/5.1/?/init.lua;/opt/austrianAudio/lib/share/lua/5.1/?.lua;/opt/austrianAudio/lib/share/lua/5.1/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;./?.lua;/usr/local/lib/lua/5.1/?.lua;/usr/local/lib/lua/5.1/?/init.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua"

# Set LUA_CPATH based on architecture, including ~/.luarocks
if [ "$ARCH" = "aarch64" ]; then
    export LUA_CPATH="/home/cpi/.luarocks/lib/lua/5.1/?.so;/opt/austrianAudio/lib/lua/5.1/?.so;/opt/austrianAudio/lib/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?.so;./?.so;/usr/lib/aarch64-linux-gnu/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so"
else
    export LUA_CPATH="/home/cpi/.luarocks/lib/lua/5.1/?.so;/opt/austrianAudio/lib/lua/5.1/?.so;/opt/austrianAudio/lib/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/?.so;./?.so;/usr/lib/arm-linux-gnueabihf/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;/usr/local/lib/lua/5.1/loadall.so"
fi

# Explicit path to the LIBTFFI module
export TURBO_LIBTFFI=/opt/austrianAudio/lib/libtffi_wrap.so
