SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := build

DOTNET ?= dotnet
SOLUTION ?= Smithbox.sln
SMITHBOX_PROJECT ?= src/Smithbox/Smithbox.csproj
TEST_PROJECT ?= src/Smithbox.Tests/Smithbox.Tests.csproj
CONFIG ?= Release-linux
PUBLISH_DIR ?= linux-x64
ARTIFACT_ROOT ?= artifacts/package
PACKAGING_DIR ?= scripts/packaging
RELEASE_SCRIPT ?= ReleasePraGithub.sh

export PUBLISH_CONFIGURATION := $(CONFIG)
export ARTIFACT_ROOT

.PHONY: help restore build build-debug run publish publish-clean test clean clobber \
	package package-deb package-rpm package-pacman package-appimage release

help:
	@printf '%s\n' \
		'Smithbox for Linux — build & packaging' \
		'' \
		'Targets:' \
		'  make build            Build the full solution (default)' \
		'  make restore          Restore NuGet packages' \
		'  make run              Run Smithbox from src/Smithbox/Smithbox.csproj' \
		'  make publish          Publish to ./linux-x64' \
		'  make test             Run the unit tests' \
		'  make package          Build all Linux packages (deb/rpm/pacman/appimage)' \
		'  make package-deb      Build only the .deb package' \
		'  make package-rpm      Build only the .rpm package' \
		'  make package-pacman   Build only the pacman (Arch) package' \
		'  make package-appimage Build only the AppImage' \
		'  make release          Create the GitHub release bundle from packaged artifacts' \
		'  make clean            Clean build outputs' \
		'  make clobber          clean + remove publish/artifacts' \
		'' \
		'Variables:' \
		'  CONFIG=Release-linux  Build configuration (Debug-linux | Release-linux)' \
		'  PUBLISH_DIR=linux-x64  Publish output directory' \
		'  ARTIFACT_ROOT=artifacts/package  Package output root' \
		'' \
		'Note: package/appimage targets require the corresponding tools to be installed' \
		'(dpkg-deb, rpmbuild, makepkg, appimagetool).'

restore:
	$(DOTNET) restore "$(SOLUTION)"

build:
	$(DOTNET) build "$(SOLUTION)" -c "$(CONFIG)"

build-debug:
	$(MAKE) build CONFIG=Debug-linux

run:
	$(DOTNET) run --project "$(SMITHBOX_PROJECT)" -c "$(CONFIG)"

publish:
	rm -rf "$(PUBLISH_DIR)"
	$(DOTNET) publish "$(SMITHBOX_PROJECT)" -c "$(CONFIG)" -o "$(PUBLISH_DIR)"

publish-clean:
	rm -rf "$(PUBLISH_DIR)"

test:
	$(DOTNET) test "$(TEST_PROJECT)" -c "$(CONFIG)"

clean:
	$(DOTNET) clean "$(SOLUTION)" -c "$(CONFIG)"
	@find . \
		\( -path './.git' -o -path './.venv' \) -prune -o \
		-type d \( -name bin -o -name obj \) -print0 | xargs -0r rm -rf
	rm -rf "$(PUBLISH_DIR)" artifacts linux-x64 publish

clobber: clean

package-deb:
	PUBLISH_CONFIGURATION="$(CONFIG)" ARTIFACT_ROOT="$(ARTIFACT_ROOT)" bash "$(PACKAGING_DIR)/package-deb.sh"

package-rpm:
	PUBLISH_CONFIGURATION="$(CONFIG)" ARTIFACT_ROOT="$(ARTIFACT_ROOT)" bash "$(PACKAGING_DIR)/package-rpm.sh"

package-pacman:
	PUBLISH_CONFIGURATION="$(CONFIG)" ARTIFACT_ROOT="$(ARTIFACT_ROOT)" bash "$(PACKAGING_DIR)/package-pacman.sh"

package-appimage:
	PUBLISH_CONFIGURATION="$(CONFIG)" ARTIFACT_ROOT="$(ARTIFACT_ROOT)" bash "$(PACKAGING_DIR)/package-appimage.sh"

package:
	$(MAKE) package-deb
	$(MAKE) package-rpm
	$(MAKE) package-pacman
	$(MAKE) package-appimage

release: package
	bash "$(RELEASE_SCRIPT)"
