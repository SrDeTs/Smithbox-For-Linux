#!/bin/bash
# linoodle-setup.sh — Setup Oodle 2.6 wrapper for Smithbox on Linux
# Run from inside the Smithbox directory (same folder as smithbox binary)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SMITHBOX_DIR="$(pwd)"
STEAM_LIBRARIES=()
OO2CORE_DLL=""
LINOODLE_SO=""
TIMEOUT=10

usage() {
    echo "Usage: cd /path/to/smithbox-linux && $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dll DLL_PATH        Path to oo2core_6_win64.dll"
    echo "  -t, --timeout SECONDS     Steam library search timeout (default: 10)"
    echo "  -h, --help                Show this help"
    echo ""
    echo "Examples:"
    echo "  cd /run/media/hassenhamdi/DATA/smithbox-linux && $0"
    echo "  $0 -d /path/to/oo2core_6_win64.dll"
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_steam() {
    # Check if Steam is installed
    if ! command -v steam &> /dev/null && [[ ! -d "$HOME/.steam/steam" ]]; then
        return 1
    fi
    return 0
}

find_steam_libraries() {
    local libs=()
    
    # Parse libraryfolders.vdf for all Steam libraries
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
    
    # Add common locations
    local search_paths=(
        "$HOME/.steam/steam"
        "$HOME/.steam/debian-installation"
        "$HOME/.local/share/Steam"
        "/run/media"/*/*/SteamLibrary
        "/mnt"/*/SteamLibrary
        "/media"/*/*/SteamLibrary
    )
    
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
            # Search for FromSoftware games
            for game in "ELDEN RING" "DARK SOULS III" "SEKIRO" "Bloodborne"; do
                while IFS= read -r game_dir; do
                    if [[ -d "$game_dir" ]]; then
                        local dll=$(find "$game_dir" -name "oo2core_6_win64.dll" -type f 2>/dev/null | head -1)
                        if [[ -n "$dll" ]]; then
                            echo "$dll"
                            return 0
                        fi
                    fi
                done < <(find "$dir/steamapps/common" -maxdepth 2 -iname "$game" -type d 2>/dev/null)
            done
        fi
    done
    
    return 1
}

check_pip_linoodle() {
    # Check if linoodle is available via pip
    if command -v pip3 &> /dev/null; then
        local pip_linoodle=$(pip3 show linoodle 2>/dev/null | grep -i "location" | cut -d: -f2 | xargs)
        if [[ -n "$pip_linoodle" ]] && [[ -f "$pip_linoodle/linoodle/liboo2corelinux64.so.6" ]]; then
            echo "$pip_linoodle/linoodle/liboo2corelinux64.so.6"
            return 0
        fi
    fi
    
    if command -v pip &> /dev/null; then
        local pip_linoodle=$(pip show linoodle 2>/dev/null | grep -i "location" | cut -d: -f2 | xargs)
        if [[ -n "$pip_linoodle" ]] && [[ -f "$pip_linoodle/linoodle/liboo2corelinux64.so.6" ]]; then
            echo "$pip_linoodle/linoodle/liboo2corelinux64.so.6"
            return 0
        fi
    fi
    
    return 1
}

check_existing_linoodle() {
    local search_paths=(
        "$SMITHBOX_DIR/liboo2corelinux64.so.6"
        "/tmp/linoodle-src/build/liblinoodle.so"
        "$HOME/.local/lib/linoodle/liboo2corelinux64.so.6"
        "./liboo2corelinux64.so.6"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    return 1
}

check_dependencies() {
    local missing=()
    
    for cmd in git cmake make gcc g++; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        
        # Detect distro
        if [[ -f /etc/arch-release ]]; then
            echo "Install with:"
            echo "  sudo pacman -S ${missing[*]}"
        elif [[ -f /etc/debian_version ]]; then
            echo "Install with:"
            echo "  sudo apt install ${missing[*]}"
        elif [[ -f /etc/fedora-release ]]; then
            echo "Install with:"
            echo "  sudo dnf install ${missing[*]}"
        elif [[ -f /etc/SUSE-brand ]]; then
            echo "Install with:"
            echo "  sudo zypper install ${missing[*]}"
        else
            echo "Install these packages using your package manager:"
            for pkg in "${missing[@]}"; do
                echo "  $pkg"
            done
        fi
        echo ""
        return 1
    fi
    
    return 0
}

build_linoodle() {
    local build_dir="/tmp/linoodle-src"
    
    log_info "Cloning linoodle..."
    rm -rf "$build_dir"
    git clone https://github.com/McSimp/linoodle.git "$build_dir"
    
    cd "$build_dir"
    git submodule update --init --recursive
    
    log_info "Applying Smithbox modifications..."
    
    # Fix 1: Change DLL name from 8 to 6
    sed -i 's/oo2core_8_win64\.dll/oo2core_6_win64.dll/g' linoodle.cpp
    
    # Fix 2: Add missing function wrappers
    cat >> linoodle.cpp << 'LINOODLE_EOF'

// Smithbox: Oodle 2.6 function stubs
extern "C" {
    size_t OodleLZ_GetDecodeBufferSize(size_t rawSize, int corruptionPossible) {
        return 0;
    }
    size_t OodleLZ_GetCompressedBufferSizeNeeded(size_t rawSize) {
        return 0;
    }
    void* OodleLZ_CompressOptions_GetDefault() {
        return nullptr;
    }
}
LINOODLE_EOF
    
    # Fix 3: CMakeLists.txt - add -Wno-error and build as SHARED
    sed -i 's/add_compile_options(-Wall -Wextra)/add_compile_options(-Wall -Wextra -Wno-error)/' CMakeLists.txt
    sed -i 's/add_executable(linoodle/add_library(linoodle SHARED/' CMakeLists.txt
    
    # Fix 4: Remove -Werror from pe-parse
    sed -i 's/-Werror//g' pe-parse/cmake/compilation_flags.cmake
    
    # Fix 5: Add missing include
    sed -i '/#include <vector>/a #include <utility>' windows_library.cpp
    
    log_info "Building linoodle..."
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -5
    make -j$(nproc) 2>&1 | tail -5
    
    if [[ -f "liblinoodle.so" ]]; then
        log_success "linoodle built successfully"
        echo "$build_dir/build/liblinoodle.so"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

ensure_linoodle_wrapper() {
    # 1. Check current directory first
    if [[ -f "$SMITHBOX_DIR/liboo2corelinux64.so.6" ]]; then
        echo "$SMITHBOX_DIR/liboo2corelinux64.so.6"
        return 0
    fi
    
    # 2. Check for pip installed linoodle
    local pip_wrapper=$(check_pip_linoodle) || true
    if [[ -n "$pip_wrapper" ]]; then
        echo "$pip_wrapper"
        return 0
    fi
    
    # 3. Check for existing build
    local existing_wrapper=$(check_existing_linoodle) || true
    if [[ -n "$existing_wrapper" ]]; then
        echo "$existing_wrapper"
        return 0
    fi
    
    # 4. Build from source
    log_warn "linoodle not found, building from source..."
    echo ""
    
    # Check dependencies
    if ! check_dependencies; then
        return 1
    fi
    
    # Build
    build_linoodle
}

ensure_oo2core_dll() {
    # Check if DLL already in current directory
    if [[ -f "$SMITHBOX_DIR/oo2core_6_win64.dll" ]]; then
        echo "$SMITHBOX_DIR/oo2core_6_win64.dll"
        return 0
    fi
    
    # Check if Steam is installed
    if ! check_steam; then
        log_warn "Steam not found" >&2
        echo "" >&2
        echo "Manually provide oo2core_6_win64.dll from your game install:" >&2
        echo "  - ELDEN RING/Game/oo2core_6_win64.dll" >&2
        echo "  - DARK SOULS III/Game/oo2core_6_win64.dll" >&2
        echo "  - SEKIRO/Game/oo2core_6_win64.dll" >&2
        echo "" >&2
        return 1
    fi
    
    # Search Steam libraries
    log_info "Searching Steam libraries for oo2core_6_win64.dll..." >&2
    log_info "(This may take a moment...)" >&2
    
    local dll=$(timeout "$TIMEOUT" bash -c "$(declare -f find_steam_libraries); $(declare -f find_oo2core_dll); find_oo2core_dll \$(find_steam_libraries)" 2>/dev/null) || true
    
    if [[ -n "$dll" ]]; then
        echo "$dll"
        return 0
    fi
    
    log_warn "oo2core_6_win64.dll not found automatically" >&2
    echo "" >&2
    echo "Copy it manually from your game install:" >&2
    echo "  cp '/path/to/game/oo2core_6_win64.dll' $SMITHBOX_DIR/" >&2
    echo "" >&2
    return 1
}

deploy_files() {
    local linoodle_so="$1"
    local oo2core_dll="$2"
    
    log_info "Deploying to: $SMITHBOX_DIR"
    echo ""
    
    # Copy wrapper (skip if same file)
    if [[ "$linoodle_so" != "$SMITHBOX_DIR/liboo2corelinux64.so.6" ]]; then
        cp "$linoodle_so" "$SMITHBOX_DIR/liboo2corelinux64.so.6"
        chmod 644 "$SMITHBOX_DIR/liboo2corelinux64.so.6"
        log_success "Copied liboo2corelinux64.so.6"
    else
        log_success "liboo2corelinux64.so.6 already in place"
    fi
    
    # Copy DLL (skip if same file)
    if [[ "$oo2core_dll" != "$SMITHBOX_DIR/oo2core_6_win64.dll" ]]; then
        cp "$oo2core_dll" "$SMITHBOX_DIR/oo2core_6_win64.dll"
        chmod 644 "$SMITHBOX_DIR/oo2core_6_win64.dll"
        log_success "Copied oo2core_6_win64.dll"
    else
        log_success "oo2core_6_win64.dll already in place"
    fi
    
    # Verify
    echo ""
    log_info "Verifying installation:"
    ls -lh "$SMITHBOX_DIR/liboo2corelinux64.so.6" "$SMITHBOX_DIR/oo2core_6_win64.dll"
    
    echo ""
    log_success "linoodle setup complete!"
    echo ""
    echo "Both files are now in: $SMITHBOX_DIR"
    echo ""
    echo "To use:"
    echo "  1. Launch Smithbox: ./smithbox"
    echo "  2. Open a project for DS3/ER/SDT/BB"
    echo "  3. Oodle textures should now load correctly"
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dll) OO2CORE_DLL="$2"; shift 2 ;;
            -t|--timeout) TIMEOUT="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) log_error "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
    
    echo -e "${BLUE}=== linoodle Setup for Smithbox ===${NC}"
    echo ""
    log_info "Working directory: $SMITHBOX_DIR"
    echo ""
    
    # Verify we're in a Smithbox directory
    if [[ ! -f "$SMITHBOX_DIR/smithbox" ]] && [[ ! -f "$SMITHBOX_DIR/Smithbox" ]]; then
        log_warn "No Smithbox binary found in current directory"
        echo ""
        read -p "$(echo -e "${YELLOW}Continue anyway? (y/N):${NC} ")" continue_anyway
        if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
            exit 1
        fi
    fi
    
    # Ensure linoodle wrapper
    local linoodle_so=""
    linoodle_so=$(ensure_linoodle_wrapper) || {
        log_error "Failed to get linoodle wrapper"
        exit 1
    }
    
    # Ensure oo2core DLL
    local oo2core_dll=""
    if [[ -z "$OO2CORE_DLL" ]]; then
        oo2core_dll=$(ensure_oo2core_dll) || {
            log_error "Failed to get oo2core_6_win64.dll"
            exit 1
        }
    else
        if [[ ! -f "$OO2CORE_DLL" ]]; then
            log_error "DLL not found: $OO2CORE_DLL"
            exit 1
        fi
        oo2core_dll="$OO2CORE_DLL"
    fi
    
    echo ""
    log_info "Ready to deploy:"
    echo "  Wrapper:   $linoodle_so"
    echo "  DLL:       $oo2core_dll"
    echo "  Target:    $SMITHBOX_DIR"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Proceed with installation? (Y/n):${NC} ")" confirm
    if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
        log_info "Installation cancelled"
        exit 0
    fi
    
    deploy_files "$linoodle_so" "$oo2core_dll"
}

main "$@"
