#!/bin/bash

# Parameters.
ACTION="$1"
VAR_1="$2"
VAR_2="$3" # Depending on action

# Helper variables.
if [ -z "$SRCROOT" ]; then
    SRCROOT="$PWD"
fi
PROJECT_DIR="$SRCROOT/$VAR_1"
ENV_PATH="$SRCROOT/env"
CACHED_ENV_PATH="$ENV_PATH/cached_env.sh"
HOMEBREW_PATH="$ENV_PATH/homebrew"
IDF_PATH="$ENV_PATH/esp-idf"
IDF_TOOLS_PATH="$ENV_PATH/esp-idf-tools"
PATH="$HOMEBREW_PATH/bin:$HOMEBREW_PATH/sbin:$PATH"

HOMEBREW_PACKAGES=(
    "python3"
    "cmake"
    "ninja"
    "dfu-util"
    "ccache"
) # , "platformio", "xcodegen" # additional dependencies will be installed when running accorging scripts.
CACHED_ENV_VARIABLES=(
    "IDF_PATH"
    "IDF_PYTHON_ENV_PATH"
    "IDF_TOOLS_EXPORT_CMD"
    "IDF_DEACTIVATE_FILE_PATH"
    "IDF_TOOLS_INSTALL_CMD"
    "OPENOCD_SCRIPTS"
    "ESP_IDF_VERSION"
    "ESP_ROM_ELF_DIR"
    "PATH"
)

function print_help() {
    echo " - help: Show help"
    echo " - install_dependencies: Installs Rosetta 2 and xcode-select"
    echo " - setup_env: Install Homebrew, ESP-IDF and ESP-IDF-TOOLS"
    echo " - fix_env [force]: Detect if environment needs some fixes and apply"
    echo " - create <PROJECT_NAME>: Create new project"
    echo " - build <PROJECT_NAME>: Build project"
    echo " - run <PROJECT_NAME>: Flash and monitor project"
    echo " - autorun <PROJECT_NAME>: Build, flash and monitor project"
    echo " - clean <PROJECT_NAME>: Clean project"
    echo " - set_target <PROJECT_NAME> <ESP_TARGET>: Set ESP device target"
    echo " - configure <PROJECT_NAME>: Configure project"
    echo " - build_xcode_project <PROJECT_NAME>: Adds Xcode project"
}

# Loads cached environment variables or exports new one if possible.
function load_env_variables() {

    # Global ENV Variables:
    export IDF_PATH
    export IDF_TOOLS_PATH
    export PATH

    # Load TMP env if prepared.
    if [ -e "$CACHED_ENV_PATH" ]; then
        source "$CACHED_ENV_PATH"
    else
        # Load Homebrew.
        if [ -e "$HOMEBREW_PATH" ]; then
            eval "$($HOMEBREW_PATH/bin/brew shellenv)"
        fi

        # Load ESP-IDF.
        if [ -e "$IDF_PATH" ] && [ -e "$IDF_TOOLS_PATH" ]; then
            source $IDF_PATH/export.sh
        fi
    fi
}

function install_dependencies() {
    # Install Xcode Command Line Tools.
    if [[ $(command -v xcode-select) == "" ]]; then
        xcode-select --install
    fi

    # Install Rosetta 2 if needed.
    if [[ $(uname -m) == "arm64" ]]; then
        if [[ $(sysctl -n machdep.cpu.brand_string | grep -c "Intel") -eq 1 ]]; then
            /usr/sbin/softwareupdate --install-rosetta --agree-to-license
        fi
    fi
}

function setup_env() {
    load_env_variables
    
    # Install Homebrew.
    if [ ! -e "$HOMEBREW_PATH" ]; then
        git clone --depth=1 "https://github.com/Homebrew/brew" "$HOMEBREW_PATH"
        eval "$($HOMEBREW_PATH/bin/brew shellenv)"
        brew update
    fi

    # Install Homebrew packages.
    for PACKAGE in "${HOMEBREW_PACKAGES[@]}"; do
        if [[ $($HOMEBREW_PATH/bin/brew list "$PACKAGE" 2>/dev/null) == "" ]]; then
            eval "$HOMEBREW_PATH/bin/brew install \"$PACKAGE\""
        fi
    done

    # Install ESP-IDF.
    if [ ! -e "$IDF_PATH" ]; then
        git clone --recursive https://github.com/espressif/esp-idf.git "$IDF_PATH"
    fi
        
    if [ ! -e "$IDF_TOOLS_PATH" ]; then
        cd "$IDF_PATH" && ./install.sh
        cd "$SRCROOT" && source $IDF_PATH/export.sh
        
        # Save TMP environment variables for Quick version of builder
        rm -rf "$CACHED_ENV_PATH" 2>&1 > /dev/null
        for var in "${CACHED_ENV_VARIABLES[@]}"; do
            VAL=$(printenv "$var")
            echo "$var=\"$VAL\"" >> "$CACHED_ENV_PATH"
        done
    fi
}

function fix_env() {
    load_env_variables

    if [ "$VAR_1" == "force" ]; then
        rm -rf "$ENV_PATH"
    elif [ "$IDF_PATH" != "$ENV_PATH/esp-idf" ]; then
        rm -rf "$IDF_PATH" "$IDF_TOOLS_PATH" "$CACHED_ENV_PATH"
    fi
    setup_env
}

function create() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$SRCROOT" && idf.py create-project "$VAR_1" && echo "! Remember to run set_target and configure"
}

function build() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py build
}

function run() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py flash monitor
}

function autorun() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py build flash monitor
}

function clean() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py clean
}

function configure() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py menuconfig
}

function set_target() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET>"; exit 1; }
    [ -z "$VAR_2" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py set-target $VAR_2
}

function build_xcode_project() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    XCODE_TEMPLATE_URL="https://github.com/damiandudycz/ESP_macOS_Sandbox/blob/main/Xcode_Template.tar?raw=true"
    curl "$XCODE_TEMPLATE_URL" | tar -xz
}

case "$ACTION" in
    ("help") print_help ;;
    ("install_dependencies") install_dependencies ;;
    ("setup_env") setup_env ;;
    ("fix_env") fix_env ;;
    ("create") create ;;
    ("build") build ;;
    ("run") run ;;
    ("autorun") autorun ;;
    ("clean") clean ;;
    ("set_target") set_target ;;
    ("configure") configure ;;
    ("build_xcode_project") build_xcode_project ;;
    (*) print_help ;;
esac

# TODO:
# - Add actions to create projects for Xcode, PlatformIO, etc.
# - Add action bootstrap, which will install and prepare all, including Xcode project if required.
