#!/usr/bin/env sh

TEMP_DIR=$(mktemp -d)

curl -L -o $TEMP_DIR/linux-x64.zip "https://github.com/EmmyLua/EmmyLuaDebugger/releases/download/1.7.1/linux-x64.zip"

mkdir -p ./.devbox/emmylua/

unzip $TEMP_DIR/linux-x64.zip -d ./.devbox/emmylua/