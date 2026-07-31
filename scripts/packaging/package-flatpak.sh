#!/usr/bin/env bash
# Build a Flatpak package from the published linux-x64 tree.
set -euo pipefail
PUBLISH_CONFIGURATION="${PUBLISH_CONFIGURATION:-Release-linux}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-artifacts/package}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

require_cmd flatpak
require_cmd flatpak-builder

copy_payload

OUT_DIR="${ARTIFACT_ROOT}/flatpak"
FLATPAK_DIR="${ARTIFACT_ROOT}/flatpak_build"
rm -rf "${OUT_DIR}" "${FLATPAK_DIR}"
mkdir -p "${OUT_DIR}" "${FLATPAK_DIR}"

APP_ID="com.Smithbox.App"

# Ensure the Freedesktop SDK + Sdk extension are installed
SDK_REF="org.freedesktop.Sdk"
SDK_VERSION="24.08"
SDK_REPO="flathub"

log "ensuring freedesktop SDK ${SDK_VERSION} is installed"
flatpak remote-add --if-not-exists --user "${SDK_REPO}" "https://dl.flathub.org/repo/flathub.flatpakrepo" 2>/dev/null || true
flatpak install --user --noninteractive --or-update "${SDK_REPO}" "${SDK_REF}//${SDK_VERSION}" 2>/dev/null || true

# Copy the published payload into the flatpak build source dir
PAYLOAD_SRC="${FLATPAK_DIR}/smithbox-payload"
rm -rf "${PAYLOAD_SRC}"
mkdir -p "${PAYLOAD_SRC}"
cp -a "${PAYLOAD_ROOT}/." "${PAYLOAD_SRC}/"

# Generate desktop entry
cat > "${FLATPAK_DIR}/${APP_ID}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Smithbox
GenericName=FromSoftware Mod Editor
Comment=${APP_DESC}
Exec=smithbox
Icon=${APP_ID}
Terminal=false
Categories=Game;Utility;
StartupWMClass=Smithbox
EOF

# Generate icon (256x256 PNG)
ICON_DIR="${FLATPAK_DIR}/icons/256x256/apps"
mkdir -p "${ICON_DIR}"
ICON_SRC="${SMITHBOX_ROOT}/src/Smithbox/icon.ico"
if [ -f "${ICON_SRC}" ]; then
    if command -v magick >/dev/null 2>&1; then
        magick "${ICON_SRC}[0]" -resize 256x256 "${ICON_DIR}/${APP_ID}.png"
    elif command -v convert >/dev/null 2>&1; then
        convert "${ICON_SRC}[0]" -resize 256x256 "${ICON_DIR}/${APP_ID}.png"
    else
        cp "${ICON_SRC}" "${ICON_DIR}/${APP_ID}.ico"
    fi
fi

# Generate the flatpak manifest
MANIFEST="${FLATPAK_DIR}/${APP_ID}.yaml"
cat > "${MANIFEST}" <<EOF
app-id: ${APP_ID}
runtime: ${SDK_REF}
runtime-version: "${SDK_VERSION}"
sdk: ${SDK_REF}
command: smithbox
finish-args:
  - --share=ipc
  - --socket=wayland
  - --socket=fallback-x11
  - --socket=pulseaudio
  - --device=all
  - --share=network
  - --filesystem=home
  - --filesystem=/run/media
  - --filesystem=/mnt
  - --filesystem=/media
modules:
  - name: smithbox
    buildsystem: simple
    build-commands:
      - mkdir -p /app/bin
      - cp -ra * /app/bin/
      - install -Dm644 ${APP_ID}.desktop /app/share/applications/${APP_ID}.desktop
      - install -Dm644 icons/256x256/apps/${APP_ID}.png /app/share/icons/hicolor/256x256/apps/${APP_ID}.png
    sources:
      - type: dir
        path: smithbox-payload
      - type: file
        path: ${APP_ID}.desktop
        dest: .
      - type: dir
        path: icons
        dest: icons
EOF

# Build the flatpak
log "building flatpak (this may take a while)"
flatpak-builder --user --force-clean --repo="${FLATPAK_DIR}/repo" "${FLATPAK_DIR}/build" "${MANIFEST}" 2>&1 \
    || die "flatpak-builder failed"

# Bundle into a .flatpak file
BUNDLE="${OUT_DIR}/${APP_ID}-${VERSION}.flatpak"
log "bundling flatpak"
flatpak build-bundle "${FLATPAK_DIR}/repo" "${BUNDLE}" "${APP_ID}" 2>&1 \
    || die "flatpak build-bundle failed"

log "built ${BUNDLE}"
ls -lh "${BUNDLE}"
