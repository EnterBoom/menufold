#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

app_path="$PWD/build/折叠菜单栏.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" build/module-cache
clang -fobjc-arc -mmacosx-version-min=14.0 -c Sources/NativeVisibility.m -o build/NativeVisibility.o
swiftc -O -target arm64-apple-macos14.0 -module-cache-path "$PWD/build/module-cache" \
    -import-objc-header Sources/NativeVisibility.h build/NativeVisibility.o \
    -framework AppKit -framework ServiceManagement -framework Carbon \
    Sources/*.swift -o "$app_path/Contents/MacOS/MenuFold"
cp Info.plist "$app_path/Contents/Info.plist"
swift -module-cache-path "$PWD/build/module-cache" scripts/make-icon.swift "$PWD/build"
iconutil -c icns "$PWD/build/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
codesign --verify --strict "$app_path"
printf '已构建 %s\n' "$app_path"

if [[ "${1:-}" == "--install" ]]; then
    installed_path="/Applications/折叠菜单栏.app"
    ditto "$app_path" "$installed_path"
    codesign --verify --strict "$installed_path"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$installed_path"
    printf '已安装 %s\n' "$installed_path"
fi
