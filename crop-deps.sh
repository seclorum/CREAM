#!/bin/bash

# Exit on error
set -e

# Update package lists
echo "Updating package lists..."
sudo apt-get update

# Install Debian packages
echo "Installing Debian packages..."
sudo apt-get install -y \
    luajit \
    libluajit-5.1-dev \
    libsqlite3-dev \
    openssl \
    curl \
    alsa-utils \
    build-essential \
    libssl-dev \
    git

# Install LuaRocks if not present
if ! command -v luarocks &> /dev/null; then
    echo "Installing LuaRocks..."
    wget https://luarocks.org/releases/luarocks-3.9.2.tar.gz
    tar zxpf luarocks-3.9.2.tar.gz
    cd luarocks-3.9.2
    ./configure --with-lua=/usr
    make
    sudo make install
    cd ..
    rm -rf luarocks-3.9.2 luarocks-3.9.2.tar.gz
fi

# Install Lua modules
echo "Installing Lua modules..."
#luarocks --verbose install turbo --local
luarocks --verbose install luasql-sqlite3 --local
luarocks --verbose install luafilesystem --local
luarocks --verbose install luaossl --local
luarocks --verbose install lua-cjson --local
luarocks --verbose install luaposix --local
luarocks --verbose install luasocket --local

# Initialize IPFS if not already done
if [ ! -d ~/.ipfs ]; then
    echo "Initializing IPFS..."
    ipfs init
fi

echo "Dependencies installed successfully!"
