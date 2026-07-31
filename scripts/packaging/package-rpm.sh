#!/usr/bin/env bash
# Build an .rpm package from the published linux-x64 tree.
set -euo pipefail
PUBLISH_CONFIGURATION="${PUBLISH_CONFIGURATION:-Release-linux}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-artifacts/package}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "${SCRIPT_DIR}/common.sh"

require_cmd rpmbuild

copy_payload
install_icon
install_desktop_entry
install_bin_symlink

RPMTOP="${ARTIFACT_ROOT}/rpm/_topdir"
rm -rf "${RPMTOP}"
mkdir -p "${RPMTOP}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# RPM changelog date MUST be in English (e.g. "Thu Jul 23 2026").
# Force C locale so date outputs English day/month names.
CHANGELOG_DATE="$(LC_ALL=C date '+%a %b %d %Y')"

SPEC="${RPMTOP}/SPECS/${PKG_ID}.spec"
STAGING_ABS="$(cd "${STAGING_ROOT}" && pwd)"
RPMTOP_ABS="$(cd "${RPMTOP}" && pwd)"
BUILDROOT_ABS="${RPMTOP_ABS}/BUILDROOT/${PKG_ID}-${VERSION}-1"

cat > "${SPEC}" <<EOF
Name:           ${PKG_ID}
Version:        ${VERSION}
Release:        1
Summary:        ${APP_DESC}
License:        ${APP_LICENSE}
URL:            ${APP_URL}
AutoReqProv:    no
Requires:       glibc, libstdc++, openssl, mesa-libGL, libX11, libXext, libXrandr, libXinerama, libXcursor, libXi, alsa-lib

%description
${APP_DESC}
Smithbox is a mod editor for FromSoftware games. This is a Linux-only build.

%prep
# Payload is pre-built; nothing to extract.

%build
# Nothing to build.

%install
cp -a "${STAGING_ABS}/opt" "%{buildroot}/"
cp -a "${STAGING_ABS}/usr" "%{buildroot}/"
mkdir -p "%{buildroot}/usr/local/bin"
ln -sf /opt/${APP_NAME}/${APP_NAME} "%{buildroot}/usr/local/bin/${APP_NAME}"

%files
/opt/${APP_NAME}
/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.*
/usr/share/applications/${APP_NAME}.desktop
/usr/local/bin/${APP_NAME}

%changelog
* ${CHANGELOG_DATE} ${MAINTAINER} - ${VERSION}-1
- Packaged Smithbox ${VERSION} for Linux
EOF

OUT_DIR="${ARTIFACT_ROOT}/rpm"
mkdir -p "${OUT_DIR}"

# Pre-create the BUILDROOT that rpm will use for %files processing.
# rpmbuild on Arch uses %{_builddir}/%{name}-%{version}-%{release}-build/BUILDROOT
RPM_BUILDROOT="${RPMTOP_ABS}/BUILD/${PKG_ID}-${VERSION}-1-build/BUILDROOT"
rm -rf "${RPM_BUILDROOT}"
mkdir -p "${RPM_BUILDROOT}"
cp -a "${STAGING_ABS}/opt" "${RPM_BUILDROOT}/"
cp -a "${STAGING_ABS}/usr" "${RPM_BUILDROOT}/"
mkdir -p "${RPM_BUILDROOT}/usr/local/bin"
ln -sf "/opt/${APP_NAME}/${APP_NAME}" "${RPM_BUILDROOT}/usr/local/bin/${APP_NAME}"

# Build with explicit topdir.
rpmbuild -bb \
    --define "_topdir ${RPMTOP_ABS}" \
    --define "_builddir ${RPMTOP_ABS}/BUILD" \
    --define "_buildrootdir ${RPMTOP_ABS}/BUILDROOT" \
    --define "_buildroot ${RPM_BUILDROOT}" \
    --define "_rpmdir ${RPMTOP_ABS}/RPMS" \
    --define "_srcrpmdir ${RPMTOP_ABS}/SRPMS" \
    --define "_sourcedir ${RPMTOP_ABS}/SOURCES" \
    --define "_specdir ${RPMTOP_ABS}/SPECS" \
    --define "_rpmfilename %%{ARCH}/%%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
    --target x86_64 \
    "${SPEC}" 2>&1 || die "rpmbuild failed"

# Move resulting rpm(s) into the output dir
find "${RPMTOP}/RPMS" -name '*.rpm' -exec cp -f {} "${OUT_DIR}/" \;
log "built rpm(s) in ${OUT_DIR}"
ls -1 "${OUT_DIR}"
