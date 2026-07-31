#!/usr/bin/env bash
# Shared helpers for Smithbox Linux packaging scripts.
# Expects these env vars to be set by the caller:
#   PUBLISH_CONFIGURATION  (e.g. Release-linux)
#   ARTIFACT_ROOT          (e.g. artifacts/package)
set -euo pipefail

SMITHBOX_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PUBLISH_DIR="${SMITHBOX_ROOT}/linux-x64"
VERSION="$(grep -oP '(?<=<Version>)\d+\.\d+\.\d+' "${SMITHBOX_ROOT}/src/Smithbox/Smithbox.csproj" | head -n1 || true)"
[ -z "${VERSION}" ] && VERSION="0.0.0"
APP_NAME="smithbox"
APP_TITLE="Smithbox"
APP_DESC="A mod editor for FromSoftware games."
APP_URL="https://github.com/vawser/Smithbox"
APP_LICENSE="MIT"
VENDOR="Smithbox"
MAINTAINER="Smithbox For Linux <smithbox-for-linux@example.com>"

# Output layout:
#   $ARTIFACT_ROOT/<distro>/         -> per-distro build artifacts
#   $ARTIFACT_ROOT/staging/          -> shared payload staging tree
STAGING_ROOT="${ARTIFACT_ROOT}/staging"
PAYLOAD_ROOT="${STAGING_ROOT}/opt/${APP_NAME}"
PKG_ID="${APP_NAME}"

log()  { printf '[pack] %s\n' "$*" >&2; }
die()  { printf '[pack][error] %s\n' "$*" >&2; exit 1; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        local pkg_hint=""
        case "$1" in
            dpkg-deb)    pkg_hint="dpkg-deb (Arch: yay -S dpkg-deb | Debian/Ubuntu: apt install dpkg-dev)" ;;
            rpmbuild)    pkg_hint="rpmbuild (Arch: pacman -S rpm-tools | Fedora: dnf install rpm-build)" ;;
            makepkg)     pkg_hint="makepkg (Arch: pacman -S pacman)" ;;
            appimagetool) pkg_hint="appimagetool (Arch: yay -S appimagetool-git)" ;;
            flatpak)      pkg_hint="flatpak (Arch: pacman -S flatpak)" ;;
            flatpak-builder) pkg_hint="flatpak-builder (Arch: pacman -S flatpak-builder)" ;;
            wget)        pkg_hint="wget (Arch: pacman -S wget | Debian: apt install wget)" ;;
            magick|convert) pkg_hint="ImageMagick (Arch: pacman -S imagemagick | Debian: apt install imagemagick)" ;;
            *)           pkg_hint="install '$1' via your package manager" ;;
        esac
        die "required command not found: $1
Install: $pkg_hint"
    fi
}

ensure_publish() {
    [ -d "${PUBLISH_DIR}" ] || die "publish dir not found: ${PUBLISH_DIR}
Run 'make publish' (PUBLISH_CONFIGURATION=${PUBLISH_CONFIGURATION:-Release-linux}) before packaging."
    [ -x "${PUBLISH_DIR}/smithbox" ] || die "smithbox executable not found in ${PUBLISH_DIR}"
}

reset_staging() {
    rm -rf "${STAGING_ROOT}"
    mkdir -p "${PAYLOAD_ROOT}"
}

copy_payload() {
    ensure_publish
    reset_staging
    log "copying payload from ${PUBLISH_DIR} -> ${PAYLOAD_ROOT}"
    cp -a "${PUBLISH_DIR}/." "${PAYLOAD_ROOT}/"
    # Make sure the main binary is executable
    chmod 0755 "${PAYLOAD_ROOT}/smithbox" 2>/dev/null || true
    # Write version marker
    printf '%s\n' "${VERSION}" > "${PAYLOAD_ROOT}/VERSION"
}

install_icon() {
    local icon_src="${SMITHBOX_ROOT}/src/Smithbox/icon.ico"
    local icon_dir="${STAGING_ROOT}/usr/share/icons/hicolor/256x256/apps"
    mkdir -p "${icon_dir}"
    if [ -f "${icon_src}" ]; then
        if command -v magick >/dev/null 2>&1; then
            magick "${icon_src}[0]" -resize 256x256 "${icon_dir}/${APP_NAME}.png"
        elif command -v convert >/dev/null 2>&1; then
            convert "${icon_src}[0]" -resize 256x256 "${icon_dir}/${APP_NAME}.png"
        else
            cp "${icon_src}" "${icon_dir}/${APP_NAME}.ico"
        fi
    fi
}

install_desktop_entry() {
    local apps_dir="${STAGING_ROOT}/usr/share/applications"
    mkdir -p "${apps_dir}"
    cat > "${apps_dir}/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_TITLE}
GenericName=FromSoftware Mod Editor
Comment=${APP_DESC}
Exec=/opt/${APP_NAME}/${APP_NAME} %f
Icon=${APP_NAME}
Terminal=false
Categories=Game;Utility;
StartupWMClass=${APP_TITLE}
EOF
}

install_bin_symlink() {
    local bin_dir="${STAGING_ROOT}/usr/local/bin"
    mkdir -p "${bin_dir}"
    ln -sf "/opt/${APP_NAME}/${APP_NAME}" "${bin_dir}/${APP_NAME}"
}
