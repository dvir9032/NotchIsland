#!/bin/zsh
# Builds a Developer ID–signed, Apple-notarized, stapled NotchIsland.app and zips it into dist/.
# Needs: Xcode signed in to the team's Apple account (Settings → Accounts). Xcode creates the
# Developer ID certificate and uploads to the notary service itself; no stored password.
set -euo pipefail
cd "${0:A:h}/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
ARCHIVE=dist/NotchIsland.xcarchive
rm -rf $ARCHIVE dist/export dist/notarized
mkdir -p dist

xcodegen generate -q
xcodebuild archive -project NotchIsland.xcodeproj -scheme NotchIsland -configuration Release \
  -archivePath $ARCHIVE -allowProvisioningUpdates -quiet
echo "→ uploading $VERSION for notarization"
xcodebuild -exportArchive -archivePath $ARCHIVE -exportOptionsPlist scripts/ExportDeveloperID.plist \
  -exportPath dist/export -allowProvisioningUpdates -quiet

echo "→ waiting for Apple's notary service"
for i in {1..60}; do
  if xcodebuild -exportNotarizedApp -archivePath $ARCHIVE -exportPath dist/notarized -quiet 2>/dev/null; then
    break
  fi
  sleep 20
done
APP=dist/notarized/NotchIsland.app
[[ -d $APP ]] || { echo "notarization didn't finish in 20 minutes"; exit 1; }

xcrun stapler validate $APP
spctl --assess --type execute --verbose $APP
ditto -c -k --keepParent $APP dist/NotchIsland-$VERSION.zip
echo "✓ dist/NotchIsland-$VERSION.zip"
