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
    ipfs \
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
sudo luarocks install turbo
sudo luarocks install luasql-sqlite3
sudo luarocks install luafilesystem
sudo luarocks install luaossl
sudo luarocks install lua-cjson
sudo luarocks install luaposix
sudo luarocks install luasocket

# Ensure WAV directory exists
echo "Creating WAV directory..."
sudo mkdir -p /home/user/wavs
sudo chmod 755 /home/user/wavs

# Initialize IPFS if not already done
if [ ! -d ~/.ipfs ]; then
    echo "Initializing IPFS..."
    ipfs init
fi

echo "Dependencies installed successfully!"
