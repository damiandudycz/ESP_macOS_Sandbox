#!/bin/bash

echo "--------------------------------------------------------------------------------"
echo -e "START $(basename $0) $@\n"

if [ -z "$SRCROOT" ]; then
    SRCROOT="$PWD"
fi
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="$1"
fi

# Config:
ENV_PATH="$SRCROOT/env"
export IDF_TOOLS_PATH="$ENV_PATH/esp-idf-tools"
IDF_PATH="$ENV_PATH/esp-idf"
PROJECT_DIR="$SRCROOT/$PROJECT_NAME"
HOMEBREW_PATH="$ENV_PATH/homebrew"
export PATH="$HOMEBREW_PATH/bin:$HOMEBREW_PATH/sbin:$PATH"
eval "$($HOMEBREW_PATH/bin/brew shellenv)"

# Read variables:
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $0 <PROJECT_NAME>"; exit 1
fi

# Export IDF:
echo "[+] > Loading ESP-IDF Environment"
cd "$IDF_PATH" && . ./export.sh 2>&1 > /dev/null

# Build:
echo "[+] > Building project"
cd "$PROJECT_DIR" && idf.py build

echo -e "\nDONE $(basename $0) $@"
echo "--------------------------------------------------------------------------------"
