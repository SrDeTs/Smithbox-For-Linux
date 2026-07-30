#!/bin/bash
# linoodle-setup.sh — Setup Oodle 2.6 wrapper for Smithbox on Linux
# Automatically detects Steam library and deploys linoodle wrapper

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SMITHBOX_DIR=""
STEAM_LIBRARIES=()
OO2CORE_DLL=""
LINOODLE_SO=""
TIMEOUT=10

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --smithbox-dir DIR    Smithbox installation directory"
    echo "  -l, --linoodle SO_PATH    Path to liboo2corelinux64.so.6 wrapper"
    echo "  -d, --dll DLL_PATH        Path to oo2core_6_win64.dll"
    echo "  -t, --timeout SECONDS     Steam library search timeout (default: 10)"
    echo "  -h, --help                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect everything"
    echo "  $0 -s /path/to/smithbox-linux         # Specify Smithbox dir"
    echo "  $0 -l /path/to/liboo2corelinux64.so.6 # Specify wrapper path"
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

find_steam_libraries() {
    local libs=()
    
    # Common Steam library locations
    local search_paths=(
        "$HOME/.steam/steam"
        "$HOME/.steam/debian-installation"
        "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
        "/run/media"/*/*/SteamLibrary
        "/mnt"/*/SteamLibrary
        "/media"/*/*/SteamLibrary
    )
    
    # Also check for secondary libraries from libraryfolders.vdf
    local vdf_files=(
        "$HOME/.steam/steam/steamapps/libraryfolders.vdf"
        "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf"
    )
    
    for vdf in "${vdf_files[@]}"; do
        if [[ -f "$vdf" ]]; then
            while IFS= read -r path; do
                path=$(echo "$path" | tr -d '"' | sed 's/\\/\//g')
                if [[ -d "$path/steamapps" ]]; then
                    libs+=("$path")
                fi
            done < <(grep -oP '"path"\s+"[^"]+"' "$vdf" 2>/dev/null | cut -d'"' -f4)
        fi
    done
    
    for search in "${search_paths[@]}"; do
        if [[ -d "$search/steamapps" ]]; then
            libs+=("$search")
        fi
    done
    
    # Deduplicate
    printf '%s\n' "${libs[@]}" | sort -u
}

find_oo2core_dll() {
    local search_dirs=("$@")
    
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir/steamapps" ]]; then
            # Search for Elden Ring specifically
            local er_dirs=$(find "$dir/steamapps/common" -maxdepth 2 -name "ELDEN RING" -type d 2>/dev/null)
            for er_dir in $er_dirs; do
                local dll="$er_dir/Game/oo2core_6_win64.dll"
                if [[ -f "$dll" ]]; then
                    echo "$dll"
                    return 0
                fi
            done
            
            # Also check for Dark Souls III, Sekiro, Bloodborne
            for game in "DARK SOULS III" "SEKIRO" "Bloodborne"; do
                local game_dirs=$(find "$dir/steamapps/common" -maxdepth 2 -iname "$game" -type d 2>/dev/null)
                for game_dir in $game_dirs; do
                    local dll=$(find "$game_dir" -name "oo2core_6_win64.dll" -type f 2>/dev/null | head -1)
                    if [[ -n "$dll" ]]; then
                        echo "$dll"
                        return 0
                    fi
                done
            done
        fi
    done
    
    return 1
}

find_linoodle_wrapper() {
    local search_paths=(
        "/tmp/linoodle-src/build/liblinoodle.so"
        "$HOME/.local/lib/linoodle/liboo2corelinux64.so.6"
        "./liboo2corelinux64.so.6"
        "./linoodle/liboo2corelinux64.so.6"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

find_smithbox_dir() {
    local search_paths=(
        "$HOME/.local/share/smithbox"
        "$HOME/.local/bin/smithbox"
        "/opt/smithbox"
        "/usr/local/bin/smithbox"
        "./linux-x64"
        "$HOME/smithbox-linux"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path/smithbox" ]] || [[ -f "$path/Smithbox" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

prompt_user() {
    local prompt="$1"
    local default="$2"
    local result=""
    
    read -p "$(echo -e "${YELLOW}$prompt${NC} [$default]: ")" result
    echo "${result:-$default}"
}

check_existing_install() {
    local smithbox_dir="$1"
    
    if [[ -f "$smithbox_dir/liboo2corelinux64.so.6" ]]; then
        log_warn "linoodle wrapper already exists in $smithbox_dir"
        read -p "$(echo -e "${YELLOW}Overwrite? (y/N):${NC} ")" overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            log_info "Keeping existing wrapper"
            return 1
        fi
    fi
    
    if [[ -f "$smithbox_dir/oo2core_6_win64.dll" ]]; then
        log_warn "oo2core_6_win64.dll already exists in $smithbox_dir"
        read -p "$(echo -e "${YELLOW}Overwrite? (y/N):${NC} ")" overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            log_info "Keeping existing DLL"
            return 1
        fi
    fi
    
    return 0
}

deploy_files() {
    local smithbox_dir="$1"
    local linoodle_so="$2"
    local oo2core_dll="$3"
    
    log_info "Deploying linoodle wrapper..."
    
    # Copy wrapper
    cp "$linoodle_so" "$smithbox_dir/liboo2corelinux64.so.6"
    chmod 644 "$smithbox_dir/liboo2corelinux64.so.6"
    log_success "Copied liboo2corelinux64.so.6"
    
    # Copy DLL
    cp "$oo2core_dll" "$smithbox_dir/oo2core_6_win64.dll"
    chmod 644 "$smithbox_dir/oo2core_6_win64.dll"
    log_success "Copied oo2core_6_win64.dll"
    
    # Verify
    echo ""
    log_info "Verifying installation:"
    ls -lh "$smithbox_dir/liboo2corelinux64.so.6" "$smithbox_dir/oo2core_6_win64.dll"
    
    echo ""
    log_success "linoodle setup complete!"
    echo ""
    echo "Both files are now in: $smithbox_dir"
    echo ""
    echo "To use:"
    echo "  1. Launch Smithbox: $smithbox_dir/smithbox"
    echo "  2. Open a project for DS3/ER/SDT/BB"
    echo "  3. Oodle textures should now load correctly"
}

main() {
    local smithbox_dir=""
    local linoodle_so=""
    local oo2core_dll=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--smithbox-dir) smithbox_dir="$2"; shift 2 ;;
            -l|--linoodle) linoodle_so="$2"; shift 2 ;;
            -d|--dll) oo2core_dll="$2"; shift 2 ;;
            -t|--timeout) TIMEOUT="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
    
    echo -e "${BLUE}=== linoodle Setup for Smithbox ===${NC}"
    echo ""
    
    # Find Smithbox directory
    if [[ -z "$smithbox_dir" ]]; then
        log_info "Searching for Smithbox installation..."
        smithbox_dir=$(find_smithbox_dir) || true
        
        if [[ -z "$smithbox_dir" ]]; then
            smithbox_dir=$(prompt_user "Enter Smithbox directory path" "$HOME/.local/share/smithbox")
            if [[ ! -d "$smithbox_dir" ]]; then
                log_error "Directory does not exist: $smithbox_dir"
                exit 1
            fi
        else
            log_success "Found Smithbox at: $smithbox_dir"
        fi
    fi
    
    # Check existing installation
    if ! check_existing_install "$smithbox_dir"; then
        exit 0
    fi
    
    # Find linoodle wrapper
    if [[ -z "$linoodle_so" ]]; then
        log_info "Searching for linoodle wrapper..."
        linoodle_so=$(find_linoodle_wrapper) || true
        
        if [[ -z "$linoodle_so" ]]; then
            echo ""
            log_warn "linoodle wrapper not found"
            echo "Build it first:"
            echo "  git clone https://github.com/McSimp/linoodle.git /tmp/linoodle-src"
            echo "  cd /tmp/linoodle-src && git submodule update --init --recursive"
            echo "  # Apply modifications from LINOODLE_CHANGES.md"
            echo "  mkdir build && cd build"
            echo "  cmake .. -DCMAKE_BUILD_TYPE=Release"
            echo "  make -j\$(nproc)"
            echo ""
            linoodle_so=$(prompt_user "Enter path to liboo2corelinux64.so.6" "/tmp/linoodle-src/build/liblinoodle.so")
            if [[ ! -f "$linoodle_so" ]]; then
                log_error "File not found: $linoodle_so"
                exit 1
            fi
        else
            log_success "Found linoodle wrapper: $linoodle_so"
        fi
    fi
    
    # Find oo2core_6_win64.dll
    if [[ -z "$oo2core_dll" ]]; then
        log_info "Searching for oo2core_6_win64.dll in Steam libraries..."
        log_info "(This may take a moment...)"
        
        # Set timeout for search
        oo2core_dll=$(timeout "$TIMEOUT" bash -c "$(declare -f find_steam_libraries); $(declare -f find_oo2core_dll); find_oo2core_dll \$(find_steam_libraries)") || true
        
        if [[ -z "$oo2core_dll" ]]; then
            echo ""
            log_warn "oo2core_6_win64.dll not found automatically"
            echo "It should be in your game install directory:"
            echo "  - ELDER RING/Game/oo2core_6_win64.dll"
            echo "  - DARK SOULS III/Game/oo2core_6_win64.dll"
            echo "  - SEKIRO/Game/oo2core_6_win64.dll"
            echo ""
            oo2core_dll=$(prompt_user "Enter path to oo2core_6_win64.dll" "$HOME/.local/share/Steam/steamapps/common/ELDEN RING/Game/oo2core_6_win64.dll")
            if [[ ! -f "$oo2core_dll" ]]; then
                log_error "File not found: $oo2core_dll"
                exit 1
            fi
        else
            log_success "Found oo2core_6_win64.dll: $oo2core_dll"
        fi
    fi
    
    echo ""
    log_info "Ready to deploy:"
    echo "  Smithbox:  $smithbox_dir"
    echo "  Wrapper:   $linoodle_so"
    echo "  DLL:       $oo2core_dll"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Proceed with installation? (Y/n):${NC} ")" confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    deploy_files "$smithbox_dir" "$linoodle_so" "$oo2core_dll"
}

main "$@"
