#!/usr/bin/env bash
# Build a pacman (Arch) package from the published linux-x64 tree.
set -euo pipefail
PUBLISH_CONFIGURATION="${PUBLISH_CONFIGURATION:-Release-linux}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-artifacts/package}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

require_cmd makepkg

copy_payload
install_icon
install_desktop_entry
install_bin_symlink

PKGDIR="${ARTIFACT_ROOT}/pacman"
mkdir -p "${PKGDIR}"

cat > "${PKGDIR}/PKGBUILD" <<EOF
# Maintainer: ${MAINTAINER}
pkgname=${PKG_ID}
pkgver=${VERSION}
pkgrel=1
pkgdesc="${APP_DESC}"
arch=('x86_64')
url="${APP_URL}"
license=('${APP_LICENSE}')
depends=('glibc' 'gcc-libs' 'openssl' 'mesa' 'libx11' 'libxext' 'libxrandr' 'libxinerama' 'libxcursor' 'libxi' 'alsa-lib')
source=("\${pkgname}-\${pkgver}.tar.gz")
sha256sums=('SKIP')

package() {
    cp -a "\${srcdir}/opt" "\${pkgdir}/"
    cp -a "\${srcdir}/usr" "\${pkgdir}/"
    install -d "\${pkgdir}/usr/local/bin"
    ln -sf "/opt/${APP_NAME}/${APP_NAME}" "\${pkgdir}/usr/local/bin/${APP_NAME}"
}
EOF

# Pack staging into the source tarball the PKGBUILD expects.
tar -C "${STAGING_ROOT}" -czf "${PKGDIR}/${PKG_ID}-${VERSION}.tar.gz" opt usr

# Build the package inside a temp dir (makepkg needs write cwd).
BUILD_DIR="${ARTIFACT_ROOT}/pacman_build"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -a "${PKGDIR}/." "${BUILD_DIR}/"

( cd "${BUILD_DIR}" && makepkg -f --noconfirm --skippgpcheck -d 2>&1 || die "makepkg failed" )

# Move resulting .pkg.tar.* into the output dir
find "${BUILD_DIR}" -maxdepth 1 -name '*.pkg.tar.*' -exec cp -f {} "${PKGDIR}/" \;
rm -rf "${BUILD_DIR}"
log "built pacman package in ${PKGDIR}"
ls -1 "${PKGDIR}"/*.pkg.tar.* 2>/dev/null || true
