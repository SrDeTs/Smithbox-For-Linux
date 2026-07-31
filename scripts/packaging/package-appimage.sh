#!/usr/bin/env bash
# Build an AppImage from the published linux-x64 tree using appimagetool.
set -euo pipefail
PUBLISH_CONFIGURATION="${PUBLISH_CONFIGURATION:-Release-linux}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-artifacts/package}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

require_cmd wget

OUT_DIR="${ARTIFACT_ROOT}/appimage"
mkdir -p "${OUT_DIR}"

APPDIR="${ARTIFACT_ROOT}/appdir"
rm -rf "${APPDIR}"
copy_payload

# Place payload under AppDir/usr/bin (AppRun convention)
rm -rf "${APPDIR}/usr/bin"
mkdir -p "${APPDIR}/usr"
cp -a "${PAYLOAD_ROOT}" "${APPDIR}/usr/bin"

# Desktop entry
mkdir -p "${APPDIR}"
cat > "${APPDIR}/${APP_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${APP_TITLE}
GenericName=FromSoftware Mod Editor
Comment=${APP_DESC}
Exec=${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Game;Utility;
StartupWMClass=${APP_TITLE}
EOF

# Icon
ICON_SRC="${SMITHBOX_ROOT}/src/Smithbox/icon.ico"
ICON_DIR="${APPDIR}/usr/share/icons/hicolor/256x256/apps"
mkdir -p "${ICON_DIR}"
if [ -f "${ICON_SRC}" ]; then
    if command -v magick >/dev/null 2>&1; then
        magick "${ICON_SRC}[0]" -resize 256x256 "${ICON_DIR}/${APP_NAME}.png"
        cp "${ICON_DIR}/${APP_NAME}.png" "${APPDIR}/${APP_NAME}.png"
    elif command -v convert >/dev/null 2>&1; then
        convert "${ICON_SRC}[0]" -resize 256x256 "${ICON_DIR}/${APP_NAME}.png"
        cp "${ICON_DIR}/${APP_NAME}.png" "${APPDIR}/${APP_NAME}.png"
    else
        cp "${ICON_SRC}" "${APPDIR}/${APP_NAME}.ico"
    fi
fi

# AppRun
cat > "${APPDIR}/AppRun" <<EOF
#!/usr/bin/env bash
HERE="\$(dirname "\$(readlink -f "\${0}")")"
export LD_LIBRARY_PATH="\${HERE}/usr/bin/:\${LD_LIBRARY_PATH}"
exec "\${HERE}/usr/bin/smithbox" "\$@"
EOF
chmod 0755 "${APPDIR}/AppRun"

# Use system appimagetool if available, otherwise download it.
APPIMAGETOOL="${APPIMAGETOOL:-$(command -v appimagetool 2>/dev/null || echo "")}"
if [ -z "${APPIMAGETOOL}" ] || [ ! -x "${APPIMAGETOOL}" ]; then
    APPIMAGETOOL="${OUT_DIR}/appimagetool-x86_64.AppImage"
    if [ ! -x "${APPIMAGETOOL}" ]; then
        log "downloading appimagetool"
require_cmd appimagetool
        wget -q -O "${APPIMAGETOOL}" \
            "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" \
            || die "failed to download appimagetool"
        chmod +x "${APPIMAGETOOL}"
    fi
fi

OUTPUT="${OUT_DIR}/${APP_TITLE}-${VERSION}-x86_64.AppImage"

# If running inside a container/headless, appimagetool may need --appimage-extract-and-run
# If using a downloaded AppImage version, it may need --appimage-extract-and-run.
# The system-installed appimagetool (from appimagetool-git) does not need it.
if [ -f "${APPIMAGETOOL}" ] && file "${APPIMAGETOOL}" | grep -q "AppImage"; then
    ARCH=x86_64 "${APPIMAGETOOL}" --appimage-extract-and-run "${APPDIR}" "${OUTPUT}" 2>&1 \
        || die "appimagetool failed"
else
    ARCH=x86_64 "${APPIMAGETOOL}" "${APPDIR}" "${OUTPUT}" 2>&1 \
        || die "appimagetool failed"
fi
chmod +x "${OUTPUT}"
log "built ${OUTPUT}"
