#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p "Aji Pet.app/Contents/MacOS" "Aji Pet.app/Contents/Resources"
cp AjiPet/Info.plist "Aji Pet.app/Contents/Info.plist"
xcrun swiftc AjiPet/Sources/main.swift -o "Aji Pet.app/Contents/MacOS/AjiPet" -target arm64-apple-macos13.0 -framework AppKit -module-cache-path /private/tmp/aji-swift-cache -O
cp AjiPet/Assets/pet-sheet.png "Aji Pet.app/Contents/Resources/pet-sheet.png"
codesign --force --sign - "Aji Pet.app"
