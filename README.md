# Smithbox for Linux

This is a Linux-only build of [Smithbox](https://github.com/vawser/Smithbox),
a modding tool for Elden Ring and other FromSoftware games.

All Windows- and macOS-specific code paths, native binaries and build
configurations have been removed. Only Linux (`linux-x64`) is supported.

## Requirements

- **.NET 10 SDK** (`dotnet --version` should print 10.x)
- Vulkan-capable GPU + drivers (an OpenGL fallback is also available)
- For packaging: `dpkg-deb`, `rpmbuild`, `makepkg`, and/or `appimagetool`
  depending on which package formats you want to build.

## Building from source

```bash
# restore + build the full solution
make build            # = dotnet build Smithbox.sln -c Release-linux

# or a debug build
make build-debug      # = Debug-linux

# publish a self-contained app to ./linux-x64
make publish

# run directly from source
make run
```

Then launch the published app:

```bash
cd linux-x64
./smithbox
```

## Oodle textures (DS3 / ER / AC6 / NR)

To open projects that use Oodle-compressed textures, copy the matching
`liboo2corelinux64.so.*` from your game install into the `linux-x64/` directory
(or the Smithbox program directory). Smithbox will pick it up automatically:

- DS3 / ER  → `liboo2corelinux64.so.6`
- AC6       → `liboo2corelinux64.so.8`
- NR        → `liboo2corelinux64.so.9`

## Packaging

```bash
make package          # build deb + rpm + pacman + AppImage
make package-deb      # only the .deb
make package-rpm      # only the .rpm
make package-pacman   # only the pacman (Arch) package
make package-appimage # only the AppImage

make release          # gather all artifacts into artifacts/package/release/
```

Artifacts land under `artifacts/package/<format>/`.

## Running the unit tests

```bash
make test
```

## Platform notes

- **Live param reload / ItemGib** (injecting param changes into a running game
  process) is a Win32-only feature and is **disabled** on Linux. All other
  editor functionality works.
- **Soapstone** (gRPC interop with DSMapStudio) is not yet available on Linux.
- The **Tracy profiler** integration is optional. To enable it, build
  `libTracyClient.so` from [Tracy](https://github.com/wolfpld/tracy) with
  `BUILD_SHARED_LIBS=ON TRACY_FIBERS=ON TRACY_MANUAL_LIFETIME=ON
  TRACY_DELAYED_INIT=ON`, drop it next to `smithbox`, and set
  `SMITHBOX_PROFILER=1`.

## Issues

For any issues or errors, please report to the official repository:
https://github.com/vawser/Smithbox?tab=contributing-ov-file

## Credits (Smithbox)
* Vawser
* ivi
* nex3
* gixxpunk
* Strackeror
* FireWolf700
* GoogleBen
* LordExelot
* Pear0533
* Metito
* WarpZehpyr
* twistedgwazi
* FeeeeK
* colaaaaaa123
* alson041
* gracenotes

## Credits (DSMapStudio)
* Katalash
* philiquaz
* george
* thefifthmatt
* TKGP
* Nordgaren
* [Pav](https://github.com/JohrnaJohrna)
* [Meowmaritus](https://github.com/meowmaritus)
* [PredatorCZ](https://github.com/PredatorCZ)
* [Horkrux](https://github.com/horkrux)
* Shadowth117
