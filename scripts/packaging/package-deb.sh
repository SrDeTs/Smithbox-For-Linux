#!/usr/bin/env bash
# Build a .deb package from the published linux-x64 tree.
set -euo pipefail
PUBLISH_CONFIGURATION="${PUBLISH_CONFIGURATION:-Release-linux}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-artifacts/package}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

require_cmd dpkg-deb

copy_payload
install_icon
install_desktop_entry
install_bin_symlink

DEB_ROOT="${STAGING_ROOT}/DEBIAN"
mkdir -p "${DEB_ROOT}"
INSTALLED_SIZE="$(du -sk "${PAYLOAD_ROOT}" | cut -f1)"
DEPS="libc6, libstdc++6, libssl3 | libssl1.1, libgl1, libegl1, libx11-6, libxext6, libxrandr2, libxinerama1, libxcursor1, libxi6, libasound2 | libasound2t64"
cat > "${DEB_ROOT}/control" <<EOF
Package: ${PKG_ID}
Version: ${VERSION}
Architecture: amd64
Maintainer: ${MAINTAINER}
Installed-Size: ${INSTALLED_SIZE}
Depends: ${DEPS}
Section: games
Priority: optional
Homepage: ${APP_URL}
Description: ${APP_DESC}
 Smithbox is a mod editor for FromSoftware games (Elden Ring, Dark Souls 3,
 Armored Core VI, etc.). This is a Linux-only build.
EOF

OUT_DIR="${ARTIFACT_ROOT}/deb"
mkdir -p "${OUT_DIR}"
DEB_FILE="${OUT_DIR}/${APP_NAME}_${VERSION}_amd64.deb"

# Fix ownership inside the staging tree so dpkg-deb is happy.
if [ "$(id -u)" -eq 0 ]; then
    chown -R root:root "${STAGING_ROOT}"
else
    fakeroot dpkg-deb --build "${STAGING_ROOT}" "${DEB_FILE}" 2>/dev/null \
        && { log "built ${DEB_FILE}"; exit 0; } || true
    # Fallback: build without fakeroot (may warn about ownership)
    dpkg-deb --build "${STAGING_ROOT}" "${DEB_FILE}"
fi
if [ ! -f "${DEB_FILE}" ]; then
    dpkg-deb --build "${STAGING_ROOT}" "${DEB_FILE}"
fi
log "built ${DEB_FILE}"
