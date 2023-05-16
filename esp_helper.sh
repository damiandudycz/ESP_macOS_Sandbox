#!/bin/bash

ACTION="$1"
VAR_1="$2"
VAR_2="$3"
VAR_3="$4"

if [ -z "$SRCROOT" ]; then
    SRCROOT="$PWD"
fi

ENV_PATH="$SRCROOT/env"
CACHED_ENV_PATH="$ENV_PATH/cached_env.sh"
HOMEBREW_PATH="$ENV_PATH/homebrew"
IDF_PATH="$ENV_PATH/esp-idf"
IDF_TOOLS_PATH="$ENV_PATH/esp-idf-tools"
PROJECT_DIR="$SRCROOT/$VAR_1"
PATH="$HOMEBREW_PATH/bin:$HOMEBREW_PATH/sbin:$PATH"

# , "platformio", "xcodegen" # additional dependencies will be installed when running accorging scripts.
HOMEBREW_PACKAGES=("python3" "cmake" "ninja" "dfu-util" "ccache")
CACHED_ENV_VARIABLES=(
    "IDF_PATH" "IDF_PYTHON_ENV_PATH" "IDF_TOOLS_EXPORT_CMD" "IDF_DEACTIVATE_FILE_PATH"
    "IDF_TOOLS_INSTALL_CMD" "OPENOCD_SCRIPTS" "ESP_IDF_VERSION" "ESP_ROM_ELF_DIR" "PATH"
)

function joinByChar() {
    local IFS="$1"
    shift
    echo "$*"
}

function print_help() {
    echo " - ENVIRONMENT AND DEPENDENCIES:"
    echo " - install_dependencies: Installs Rosetta 2 and xcode-select"
    echo " - setup_env: Install Homebrew, ESP-IDF and ESP-IDF-TOOLS"
    echo " - fix_env [force]: Detect if environment needs some fixes and apply"
    echo " - "
    echo " - ESPTool management:"
    echo " - create <PROJECT_NAME>: Create new project"
    echo " - build <PROJECT_NAME>: Build project"
    echo " - flash <PROJECT_NAME>:"
    echo " - monitor <PROJECT_NAME>:"
    echo " - run <PROJECT_NAME>: Flash and monitor project"
    echo " - clean <PROJECT_NAME>: Clean project"
    echo " - fullclean <PROJECT_NAME>: Clean project"
    echo " - set_target <PROJECT_NAME> <ESP_TARGET>: Set ESP device target"
    echo " - configure <PROJECT_NAME>: Configure project"
    echo " - "
    echo " - ADD IDE SUPPORT:"
    echo " - build_xcode_project <PROJECT_NAME>: Adds Xcode project"
    echo " - "
    echo " - OTHER:"
    echo " - bootstrap_project <PROJECT_NAME> <ESP_TARGET> [xcode]: Setup environment, project and IDE"
    echo " - update_xcode_project <PROJECT_NAME>"
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

# Create and configure new ESP-IDF project.
function create() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$SRCROOT" && idf.py create-project "$VAR_1" && echo "! Remember to run set_target and configure"
    # Set custom project CMake configuration
    echo "FILE(GLOB_RECURSE app_sources \${CMAKE_SOURCE_DIR}/main/*)" > "$PROJECT_DIR/main/CMakeLists.txt"
    echo "idf_component_register(SRCS \${app_sources})" >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo "spiffs_create_partition_image(storage ../data FLASH_IN_PROJECT)" >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo "# include_directories()" >> "$PROJECT_DIR/main/CMakeLists.txt"
    
    echo "nvs,      data, nvs,     ,        24K," >> "$PROJECT_DIR/partitions.csv"
    echo "phy_init, data, phy,     ,        4k," >> "$PROJECT_DIR/partitions.csv"
    echo "factory,  app,  factory, ,        1984K," >> "$PROJECT_DIR/partitions.csv"
    echo "storage,  data, spiffs,  ,        2048K" >> "$PROJECT_DIR/partitions.csv"
}

# Build project.
function build() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py build && cd "$SRCROOT"
}

# Flash project.
function flash() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py flash && cd "$SRCROOT"
}

# Monitor project.
function monotor() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py monitor && cd "$SRCROOT"
}

# Flash and monitor.
function run() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py flash monitor && cd "$SRCROOT"
}

# Perform soft cleaning.
function clean() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py clean && cd "$SRCROOT"
}

# Perform full cleaning.
function fullclean() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py fullclean && cd "$SRCROOT"
}

# Execute menuconfig of the project.
function configure() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py menuconfig && cd "$SRCROOT"
}

# Select project target (eq esp32s3). After this perform configure.
function set_target() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET>"; exit 1; }
    [ -z "$VAR_2" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py set-target $VAR_2 && cd "$SRCROOT"
}

# Setup Xcode HEADER_SEARCH_PATHS and GCC_PREPROCESSOR_DEFINITIONS, using CMake settings and SDKConfig file.
function update_xcode_project() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    
    local SDKCONFIG_PATH="${SRCROOT}/${VAR_1}/sdkconfig"
    local XCODEPROJ_PATH="${SRCROOT}/${VAR_1}.xcodeproj/project.pbxproj"
    
    cd "$SRCROOT"
    
    # HEADER_SEARCH_PATHS
    # TOOLCHAIN_HEADERS
    local TOOLCHAIN_PATH=$( cat $VAR_1/build/compile_commands.json | grep "command" -m1 | sed 's/.*"command": "\(.*\)\/bin.*/\1/' | sed -e "s|$SRCROOT|\$(SRCROOT)|" )
    local TOOLCHAIN_FILENAME=$( basename "$TOOLCHAIN_PATH" )
    local TOOLCHAIN_VERSION=$( echo "$TOOLCHAIN_PATH" | awk -F'-elf/esp-|_' '{print $2}' )
    local TOOLCHAIN_HEADERS=(
        "\\\"$TOOLCHAIN_PATH/$TOOLCHAIN_FILENAME/include\\\""
        "\\\"$TOOLCHAIN_PATH/lib/gcc/$TOOLCHAIN_FILENAME/$TOOLCHAIN_VERSION/include\\\""
    )
    # INCLUDED HEADERS
    IFS=$'\n' read -d '' -ra NEW_HEADERS_PATHS_CONTENTS_ARRAY <<< "$(cat $VAR_1/build/compile_commands.json | grep '"command":' | sed -e "s/\"command\": \"//g" | sed -e "s/\"//g" | xargs | sed "s/ /\n/g" | grep -- "^-I" | sort | uniq | sed -e "s/^-I//" | sed -e "s|$SRCROOT|\$(SRCROOT)|" | sed 's/.*/\\"&\\"/')"
    # ALL HEADERS
    local ALL_HEADERS=("${TOOLCHAIN_HEADERS[@]}" "${NEW_HEADERS_PATHS_CONTENTS_ARRAY[@]}")
    local ALL_HEADERS_STRING=$( joinByChar "," "${ALL_HEADERS[@]}" )
    sed -i '' -e "s|HEADER_SEARCH_PATHS = (\(.*\));|HEADER_SEARCH_PATHS = ($ALL_HEADERS_STRING);|g" "$XCODEPROJ_PATH"

    # GCC_PREPROCESSOR_DEFINITIONS
    local NEW_SDKCONFIG_CONTENTS_ARRAY=$(grep -vE '^\s*($|#)' "${SDKCONFIG_PATH}" | sed 's/"//g' | sed 's/.*/\\"&\\"/')
    local NEW_SDKCONFIG_CONTENTS=$( joinByChar "," $NEW_SDKCONFIG_CONTENTS_ARRAY )
    sed -i '' -e "s|GCC_PREPROCESSOR_DEFINITIONS = (\(.*\));|GCC_PREPROCESSOR_DEFINITIONS = ($NEW_SDKCONFIG_CONTENTS);|g" "$XCODEPROJ_PATH"
}

# Create new Xcode project and setup it.
function build_xcode_project() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    [ -e "$VAR_1.xcodeproj" ] && { echo "Project $VAR_1.xcodeproj already exists!"; exit 1; }
    load_env_variables
    
    local XCODE_TEMPLATE_URL="https://raw.githubusercontent.com/damiandudycz/ESP_macOS_Sandbox/main/Xcode_Template.tar"
    if [ -f "Xcode_Template.tar" ]; then
        tar -xf Xcode_Template.tar
    else
        curl "$XCODE_TEMPLATE_URL" -O
        tar -xf Xcode_Template.tar
        rm Xcode_Template.tar
    fi
    mv -f "__PROJECT_NAME__.xcodeproj" "$VAR_1.xcodeproj"
    local RENAMES_IN_FILES=(
        "$VAR_1.xcodeproj/project.pbxproj"
        "$VAR_1.xcodeproj/xcshareddata/xcschemes/ESPTool.xcscheme"
    )
    for file in "${RENAMES_IN_FILES[@]}"; do
        sed -i '' "s/__PROJECT_NAME__/$VAR_1/g" "$file"
    done
    xcodebuild -project "$VAR_1.xcodeproj" -scheme ESPTool
    update_xcode_project
}

# Perform all actions to create and configure new project, including environment and xcode project.
function bootstrap_project() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET> [xcode]"; exit 1; }
    [ -z "$VAR_2" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET> [xcode]"; exit 1; }
    install_dependencies &&
    setup_env &&
    create &&
    set_target &&
    if [ "$VAR_3" == "xcode" ] || [ "$VAR_4" == "xcode" ]; then
        build_xcode_project
    fi
}

case "$ACTION" in
    ("install_dependencies") install_dependencies ;;
    ("setup_env") setup_env ;;
    ("fix_env") fix_env ;;
    ("create") create ;;
    ("set_target") set_target ;;
    ("configure") configure ;;
    ("build") build ;;
    ("flash") flash ;;
    ("monitor") monitor ;;
    ("run") run ;;
    ("clean") clean ;;
    ("fullclean") fullclean ;;
    ("bootstrap_project") bootstrap_project ;;
    ("build_xcode_project") build_xcode_project ;;
    ("update_xcode_project") update_xcode_project ;;
    (*) print_help ;;
esac

# TODO:
# - Add actions to create projects for PlatformIO.
# - Join some actions into one. setup_env+fix_env, clean+fullclean, build_xcode_project+setup_xcode_project, flash+monitor(maybe)=run
