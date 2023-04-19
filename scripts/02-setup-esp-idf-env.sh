#!/bin/bash

echo "--------------------------------------------------------------------------------"
echo -e "START $(basename $0) $@\n"

if [ -z "$SRCROOT" ]; then
  SRCROOT="$PWD"
fi

# Config:
ENV_PATH="$SRCROOT/env"
export IDF_TOOLS_PATH="$ENV_PATH/esp-idf-tools"
IDF_PATH="$ENV_PATH/esp-idf"
IDF_TOOLS_JSON_PATH="$IDF_TOOLS_PATH/idf-env.json"
HOMEBREW_PATH="$ENV_PATH/homebrew"

# Homebrew
HOMEBREW_PACKAGES=("cmake" "ninja" "dfu-util" "ccache") # , "platformio"
export PATH="$HOMEBREW_PATH/bin:$HOMEBREW_PATH/sbin:$PATH"
if [ ! -e "$HOMEBREW_PATH" ]; then
  echo "[+] > Installing Homebrew"
  git clone -q --depth=1 "https://github.com/Homebrew/brew" "$HOMEBREW_PATH"
  eval "$($HOMEBREW_PATH/bin/brew shellenv)"
  brew update -q
else
  echo "[-] > Skipping Homebrew (already installed)"
  eval "$($HOMEBREW_PATH/bin/brew shellenv)"
fi
# Install required packages
for PACKAGE in "${HOMEBREW_PACKAGES[@]}"; do
  if [[ $($HOMEBREW_PATH/bin/brew list "$PACKAGE" 2>/dev/null) == "" ]]; then
    echo "[+] > Installing $PACKAGE"
      eval "$HOMEBREW_PATH/bin/brew install \"$PACKAGE\" -q"
  else
    echo "[-] > Skipping $PACKAGE (already installed)"
  fi
done

# ESP-IDF:
if [ ! -e "$IDF_PATH" ]; then
    echo "[+] > Install ESP-IDF"
    git clone -q --recursive https://github.com/espressif/esp-idf.git "$IDF_PATH"
else
    echo "[-] > env/esp-idf already exists. Skipping."
fi

# ESP-IDF-TOOLS:
# if TOOLS already exists, but have different path than expected - reinstall.
SAVED_PATH=`cat $IDF_TOOLS_JSON_PATH | sed -n 's/.*"path":.*"\(.*\)".*/\1/p'`
if [ ! -e "$IDF_TOOLS_PATH" ] || [ "$SAVED_PATH" != "$IDF_PATH" ]; then
    rm -rf "$IDF_TOOLS_PATH" 2>&1 > /dev/null
    echo "[+] > Install ESP-IDF-TOOLS"
    echo "$IDF_TOOLS_PATH"
    CMD="cd \"$IDF_PATH\"; . ./install.sh"
    eval "$CMD"
else
    echo "[-] > env/esp-idf-tools already exists. Skipping."
fi

echo -e "\nDONE $(basename $0) $@"
echo "--------------------------------------------------------------------------------"
