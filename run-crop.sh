#!/bin/sh

# Source environment
. ./env.sh

# Evaluate luarocks path to ensure local modules are found
eval "$(luarocks --local path)"

# Run crop.lua
luajit crop.lua
