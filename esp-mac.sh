#!/bin/bash

ACTION="$1"
VAR_1="$2"
VAR_2="$3"
VAR_3="$4"
shift 3
EXEC_VARS="$@"

if [ -z "$SRCROOT" ]; then
    SRCROOT="$PWD"
fi

ENV_PATH="$SRCROOT/env"
CACHED_ENV_PATH="$ENV_PATH/cached_env.sh"
HOMEBREW_PATH="$ENV_PATH/homebrew"
GEM_PATH="$ENV_PATH/gem"
IDF_PATH="$ENV_PATH/esp-idf"
IDF_TOOLS_PATH="$ENV_PATH/esp-idf-tools"
PROJECT_DIR="$SRCROOT/$VAR_1"
PATH="$HOMEBREW_PATH/bin:$HOMEBREW_PATH/sbin:$GEM_PATH/bin:$GEM_PATH/sbin:$PATH"

# , "platformio", "xcodegen" # additional dependencies will be installed when running accorging scripts.
HOMEBREW_PACKAGES=("python3" "cmake" "ninja" "dfu-util" "ccache")
GEM_PACKAGES=("xcodeproj")
CACHED_ENV_VARIABLES=(
    "IDF_PATH" "IDF_PYTHON_ENV_PATH" "IDF_TOOLS_EXPORT_CMD" "IDF_DEACTIVATE_FILE_PATH"
    "IDF_TOOLS_INSTALL_CMD" "OPENOCD_SCRIPTS" "ESP_IDF_VERSION" "ESP_ROM_ELF_DIR" "PATH"
    "RUBYLIB"
)

joinByChar() {
    local IFS="$1"
    shift
    echo "$*"
}

print_help() {
    echo " - ENVIRONMENT AND DEPENDENCIES:"
    echo " - install_dependencies: Installs Rosetta 2 and xcode-select"
    echo " - setup_env: Install Homebrew, ESP-IDF and ESP-IDF-TOOLS"
    echo " - fix_env [force]: Detect if environment needs some fixes and apply"
    echo " - "
    echo " - ESPTool management:"
    echo " - create <PROJECT_NAME>: Create new project"
    echo " - build <PROJECT_NAME>: Build project"
    echo " - run <PROJECT_NAME>: Flash and monitor project"
    echo " - clean <PROJECT_NAME> [full]: Clean project"
    echo " - set_target <PROJECT_NAME> <ESP_TARGET>: Set ESP device target"
    echo " - configure <PROJECT_NAME>: Configure project"
    echo " - "
    echo " - ADD IDE SUPPORT:"
    echo " - create_xcode_project <PROJECT_NAME>: Adds Xcode project"
    echo " - "
    echo " - OTHER:"
    echo " - bootstrap_project <PROJECT_NAME> <ESP_TARGET> [xcode]: Setup environment, project and IDE"
    echo " - create_xcode_project <PROJECT_NAME>: Create new Xcode project from existing ESP-IDF project"
    echo " - update_xcode_project <PROJECT_NAME>: Fix xcode project header paths directories"
    echo " - exec <PROJECT_NAME> <command> [parameters...]: Run custom command inside project dir"
}

# Loads cached environment variables or exports new one if possible.
load_env_variables() {
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

install_dependencies() {
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

setup_env() {
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
    
    # Install GEM packages.
    for PACKAGE in "${GEM_PACKAGES[@]}"; do
        eval "gem install \"$PACKAGE\" --install-dir '$GEM_PATH'"
    done
    
    # Establish RUBYLIB.
    xcodeproj_version=$(ls -1 "$GEM_PATH/gems" | grep "xcodeproj-" | sed 's/xcodeproj-//')
    RUBYLIB="$GEM_PATH/gems/xcodeproj-$xcodeproj_version/lib"
    export RUBYLIB

    # Install ESP-IDF.
    if [ ! -e "$IDF_PATH" ]; then
        git clone --recursive https://github.com/espressif/esp-idf.git -b "release/v5.1" "$IDF_PATH"
    fi
        
    if [ ! -e "$IDF_TOOLS_PATH" ]; then
        cd "$IDF_PATH" && ./install.sh
        cd "$SRCROOT" && source $IDF_PATH/export.sh
        
        # Save TMP environment variables for Quick version of builder
        rm -rf "$CACHED_ENV_PATH" 2>&1 > /dev/null
        for var in "${CACHED_ENV_VARIABLES[@]}"; do
            VAL=$(printenv "$var")
            echo "export $var=\"$VAL\"" >> "$CACHED_ENV_PATH"
        done
    fi
}

fix_env() {
    load_env_variables
    if [ "$VAR_1" == "force" ]; then
        rm -rf "$ENV_PATH"
    elif [ "$IDF_PATH" != "$ENV_PATH/esp-idf" ]; then
        rm -rf "$IDF_PATH" "$IDF_TOOLS_PATH" "$CACHED_ENV_PATH"
    fi
    setup_env
}

# Create and configure new ESP-IDF project.
create() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$SRCROOT" && idf.py create-project "$VAR_1" && echo "! Remember to run set_target and configure"
    mkdir "$PROJECT_DIR/partitions"
    mkdir "$PROJECT_DIR/components"
    # Set custom project CMake configuration

    echo 'FILE(GLOB_RECURSE app_sources ${CMAKE_SOURCE_DIR}/main/*)' > "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'idf_component_register(SRCS ${app_sources})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'function(include_main_directories)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    set(MAIN_DIRECTORY ${CMAKE_SOURCE_DIR}/main)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    file(GLOB SUBDIRECTORIES ${MAIN_DIRECTORY}/*)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    include_directories(${MAIN_DIRECTORY})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    foreach(subdirectory ${SUBDIRECTORIES})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        if(IS_DIRECTORY ${subdirectory})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        include_directories(${subdirectory})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    endif()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    endforeach()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'endFunction()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'function(spiffs_copy_partition_image partition source_file)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    set(options FLASH_IN_PROJECT)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    set(multi DEPENDS)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    cmake_parse_arguments(arg "${options}" "" "${multi}" "${ARGN}")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    idf_build_get_property(idf_path IDF_PATH)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    set(spiffsgen_py ${PYTHON} ${idf_path}/components/spiffs/spiffsgen.py)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    get_filename_component(source_file_full_path "${source_file}" ABSOLUTE)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    if(EXISTS "${source_file_full_path}")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        set(image_file ${CMAKE_BINARY_DIR}/${partition}.bin)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        add_custom_target(spiffs_${partition}_bin ALL' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            COMMAND ${CMAKE_COMMAND} -E copy "${source_file_full_path}" "${image_file}"' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            DEPENDS ${arg_DEPENDS}' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        )' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            ADDITIONAL_CLEAN_FILES' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            ${image_file})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        idf_component_get_property(main_args esptool_py FLASH_ARGS)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        idf_component_get_property(sub_args esptool_py FLASH_SUB_ARGS)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        esptool_py_flash_target(${partition}-flash "${main_args}" "${sub_args}" ALWAYS_PLAINTEXT)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        esptool_py_flash_to_partition(${partition}-flash "${partition}" "${image_file}")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        add_dependencies(${partition}-flash spiffs_${partition}_bin)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        if(arg_FLASH_IN_PROJECT)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            esptool_py_flash_to_partition(flash "${partition}" "${image_file}")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            add_dependencies(flash spiffs_${partition}_bin)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        endif()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    else()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        set(message "Source file '${source_file_full_path}' not found.")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        fail_at_build_time(spiffs_${partition}_bin "${message}")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    endif()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'endfunction()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'function(process_partitions_directory)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    set(partitions_directory ${CMAKE_SOURCE_DIR}/partitions)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    file(GLOB partitions_files "${partitions_directory}/*")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    foreach(partition_item ${partitions_files})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        if(${partition_item} MATCHES "/\\..*")' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            continue()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        endif()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        get_filename_component(partition_name ${partition_item} NAME)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        get_filename_component(partition_name_we ${partition_item} NAME_WE)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        if(IS_DIRECTORY ${partition_item})' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            spiffs_create_partition_image(${partition_name} ../partitions/${partition_name} FLASH_IN_PROJECT)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        else()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            get_filename_component(file_extension ${partition_item} EXT)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '            spiffs_copy_partition_image(${partition_name_we} ../partitions/${partition_name} FLASH_IN_PROJECT)' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '        endif()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '    endforeach()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'endfunction()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo '' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'include_main_directories()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    echo 'process_partitions_directory()' >> "$PROJECT_DIR/main/CMakeLists.txt"
    
    echo "factory_nvs, data, nvs,     , 24K," >> "$PROJECT_DIR/partitions.csv"
    echo "nvs,         data, nvs,     , 24K," >> "$PROJECT_DIR/partitions.csv"
    echo "phy_init,    data, phy,     , 4k," >> "$PROJECT_DIR/partitions.csv"
    echo "factory,     app,  factory, , 1536K," >> "$PROJECT_DIR/partitions.csv"
    echo "storage,     data, spiffs,  , 2048K" >> "$PROJECT_DIR/partitions.csv"
}

# Build project.
build() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py build && cd "$SRCROOT"
}

# Flash and monitor.
run() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py flash && idf.py monitor && cd "$SRCROOT"
}

# Perform soft cleaning.
clean() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> [full]"; exit 1; }
    load_env_variables
    if [ "$VAR_1" == "full" ]; then
        cd "$PROJECT_DIR" && idf.py fullclean && cd "$SRCROOT"
    else
        cd "$PROJECT_DIR" && idf.py clean && cd "$SRCROOT"
    fi
}

# Execute menuconfig of the project.
configure() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py menuconfig && cd "$SRCROOT"
}

# Select project target (eq esp32s3). After this perform configure.
set_target() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET>"; exit 1; }
    [ -z "$VAR_2" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET>"; exit 1; }
    load_env_variables
    cd "$PROJECT_DIR" && idf.py set-target $VAR_2 && cd "$SRCROOT"
}

# Setup Xcode HEADER_SEARCH_PATHS and GCC_PREPROCESSOR_DEFINITIONS, using CMake settings and SDKConfig file.
update_xcode_project() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME>"; exit 1; }
    load_env_variables
        
    local SDKCONFIG_PATH="${SRCROOT}/${VAR_1}/sdkconfig"
    local PROJECT_PATH="${SRCROOT}/${VAR_1}.xcodeproj"
    local XCODEPROJ_PATH="${PROJECT_PATH}/project.pbxproj"
    local UPDATE_SCRIPT_PATH="${PROJECT_PATH}/xcodesupport/UpdateXcodeProject.rb"
    
    cd "$SRCROOT"
    
    # TODO: Fix updating patches for project which already has values set. It might be hard for multiline values. Might be best to first run some script that will replace multilines with empty ().
    
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
    
    # ADD MAIN GROUP STRUCTURE TO THE PROJECT
    ruby "$UPDATE_SCRIPT_PATH" "$PROJECT_PATH"
    
    cd "$SRCROOT"
}

# Create new Xcode project and setup it.
create_xcode_project() {
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
        "$VAR_1.xcodeproj/xcshareddata/xcschemes/Run.xcscheme"
        "$VAR_1.xcodeproj/xcshareddata/xcschemes/Update files.xcscheme"
    )
    for file in "${RENAMES_IN_FILES[@]}"; do
        sed -i '' "s/__PROJECT_NAME__/$VAR_1/g" "$file"
    done
    xcodebuild -project "$VAR_1.xcodeproj" -scheme Run
    update_xcode_project
}

# Perform all actions to create and configure new project, including environment and xcode project.
bootstrap_project() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET> [xcode]"; exit 1; }
    [ -z "$VAR_2" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <ESP_TARGET> [xcode]"; exit 1; }
    install_dependencies &&
    setup_env &&
    create &&
    set_target &&
    if [ "$VAR_3" == "xcode" ] || [ "$VAR_4" == "xcode" ]; then
        create_xcode_project
    fi
}

exec_custom_code() {
    [ -z "$VAR_1" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <command> [parameters...]"; exit 1; }
    [ -z "$VAR_2" ] && { echo "Usage: $0 $ACTION <PROJECT_NAME> <command> [parameters...]"; exit 1; }
    load_env_variables
    CMD_FULL="$VAR_2 $EXEC_VARS"
    echo ">> $CMD_FULL"
    cd "$PROJECT_DIR" && eval "$CMD_FULL" && cd "$SRCROOT"
}

case "$ACTION" in
    ("install_dependencies") install_dependencies ;;
    ("setup_env") setup_env ;;
    ("fix_env") fix_env ;;
    ("create") create ;;
    ("set_target") set_target ;;
    ("configure") configure ;;
    ("build") build ;;
    ("run") run ;;
    ("clean") clean ;;
    ("bootstrap_project") bootstrap_project ;;
    ("create_xcode_project") create_xcode_project ;;
    ("update_xcode_project") update_xcode_project ;;
    ("exec") exec_custom_code ;;
    (*) print_help ;;
esac

# TODO:
# - Add actions to create projects for PlatformIO.
