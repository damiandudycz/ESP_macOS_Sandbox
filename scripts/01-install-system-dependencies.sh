#!/bin/bash

echo "--------------------------------------------------------------------------------"
echo -e "START $(basename $0) $@\n"

# Install Xcode Command Line Tools
if [[ $(command -v xcode-select) == "" ]]; then
  echo "[+] > Installing Xcode Command Line Tools"
  xcode-select --install
else
  echo "[-] > Skipping Xcode Command Line Tools (already installed)"
fi

# Check if Rosetta 2 is needed and install if running on Apple Silicon
if [[ $(uname -m) == "arm64" ]]; then
  if [[ $(sysctl -n machdep.cpu.brand_string | grep -c "Intel") -eq 1 ]]; then
    echo "[+] > Installing Rosetta 2"
    /usr/sbin/softwareupdate --install-rosetta --agree-to-license
  else
    echo "[-] > Skipping Rosetta 2 (already installed)"
  fi
else
  echo "[-] > Skipping Rosetta 2 (not needed)"
fi

echo -e "\nDONE $(basename $0) $@"
echo "--------------------------------------------------------------------------------"
