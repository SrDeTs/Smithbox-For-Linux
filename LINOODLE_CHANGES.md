# linoodle Modifications for Smithbox

These changes are required to build linoodle with Oodle 2.6 support for Smithbox on Linux.

## Changes

### 1. `linoodle.cpp`

Change the Oodle DLL name from version 8 to version 6:

```diff
-const wchar_t* kOodleDllName = L"oo2core_8_win64.dll";
+const wchar_t* kOodleDllName = L"oo2core_6_win64.dll";
```

Add missing function wrappers (Oodle 2.6 exports these but linoodle didn't have them):

```cpp
// Add these after the existing function wrappers
extern "C" {
    size_t OodleLZ_GetDecodeBufferSize(size_t rawSize, int corruptionPossible) {
        return 0; // Stub - not used by Smithbox
    }
    size_t OodleLZ_GetCompressedBufferSizeNeeded(size_t rawSize) {
        return 0; // Stub - not used by Smithbox
    }
    void* OodleLZ_CompressOptions_GetDefault() {
        return nullptr; // Stub - not used by Smithbox
    }
}
```

### 2. `CMakeLists.txt`

Add `-Wno-error` to avoid build failures with strict compiler flags:

```diff
- add_compile_options(-Wall -Wextra)
+ add_compile_options(-Wall -Wextra -Wno-error)
```

Change from executable to shared library:

```diff
- add_executable(linoodle ...)
+ add_library(linoodle SHARED ...)
```

### 3. `pe-parse/cmake/compilation_flags.cmake`

Remove `-Werror` flag to allow warnings without build failure:

```diff
- set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Werror")
+ set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
```

### 4. `windows_library.cpp`

Add missing include for `std::exchange`:

```diff
+ #include <utility>
```

## Building

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/usr/bin/gcc-15 \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++-15
make -j$(nproc)
```

The output `liblinoodle.so` should be renamed to `liboo2corelinux64.so.6` and placed next to the Smithbox binary.
