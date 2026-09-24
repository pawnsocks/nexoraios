#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
release_version="${NEXORA_VERSION:-1.0.0}"
build_number="${NEXORA_BUILD:-1}"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid version'; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo 'Invalid build'; exit 1; }
sips -s format png -z 1024 1024 Nexora/Assets.xcassets/Brand.imageset/brand.png --out Nexora/Assets.xcassets/AppIcon.appiconset/AppIcon.png >/dev/null
xcodegen generate
xcodebuild -project Nexora.xcodeproj -scheme Nexora -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO MARKETING_VERSION="$release_version" CURRENT_PROJECT_VERSION="$build_number" build
mkdir -p build/package/Payload
cp -R build/Build/Products/Release-iphoneos/Nexora.app build/package/Payload/Nexora.app
(cd build/package && /usr/bin/zip -qr ../Nexora-unsigned.ipa Payload)
echo 'Built build/Nexora-unsigned.ipa. Sign with your own authorized sideloading setup.'
