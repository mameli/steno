#!/bin/bash
# Builds Steno in Release, signs it with the self-signed "Steno" certificate, zips it and
# publishes it as a GitHub Release tagged v<MARKETING_VERSION> (from Config/Base.xcconfig).
#
#   scripts/release.sh            build, sign and zip into build/release/, then ask before publishing
#   scripts/release.sh --dry-run  build, sign and zip only
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig)
tag="v$version"
app=build/release/DerivedData/Build/Products/Release/Steno.app
zip="build/release/Steno-$version.zip"

if [[ -n $(git status --porcelain) ]]; then
    echo "Commit or stash your changes first: the Release must match a commit." >&2
    exit 1
fi
if gh release view "$tag" >/dev/null 2>&1; then
    echo "Release $tag already exists: raise MARKETING_VERSION in Config/Base.xcconfig." >&2
    exit 1
fi

rm -rf build/release
# No get-task-allow entitlement: it is only for debugging.
xcodebuild -project Steno.xcodeproj -scheme Steno -configuration Release \
    -derivedDataPath build/release/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=Steno DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build | grep -E "error: |BUILD"

codesign --verify --strict "$app"
[[ $(codesign -dvv "$app" 2>&1) == *"Authority=Steno"* ]] || { echo "Not signed with the Steno certificate." >&2; exit 1; }
ditto -c -k --keepParent "$app" "$zip"
echo "Ready: $zip"

[[ ${1:-} == --dry-run ]] && exit 0
read -r -p "Publish $tag on GitHub? [y/N] " answer
[[ $answer == y ]] || exit 0

if [[ $(git rev-parse HEAD) != $(gh api "repos/{owner}/{repo}/commits/main" --jq .sha) ]]; then
    echo "Push main first: the tag is created on the commit GitHub has." >&2
    exit 1
fi
gh release create "$tag" "$zip" --target main --title "Steno $version" --notes-file - <<NOTES
Apple Silicon Mac, macOS 15 or later.

1. Download \`Steno-$version.zip\`, open it and move **Steno** to **Applications**.
2. Open Steno. macOS says it cannot verify the app, because Steno is not notarized by Apple: press **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down and press **Open Anyway** next to Steno, then confirm with your password.

Alternatively, run \`xattr -dr com.apple.quarantine /Applications/Steno.app\` in Terminal before opening it.

See the [README](https://github.com/mameli/steno#first-setup) for the first setup.
NOTES
