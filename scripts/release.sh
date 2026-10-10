#!/bin/bash
# Builds Takku in Release, signs it with the self-signed "Takku" certificate, zips it,
# publishes it as a GitHub Release tagged v<MARKETING_VERSION> (from Config/Base.xcconfig) and
# points the Homebrew cask in the tap (a clone of mameli/homebrew-takku, ../homebrew-takku or
# $TAKKU_TAP) to it. A published version is never replaced: Homebrew checks the zip's SHA-256.
# The Release also carries a copy named Takku.zip, so releases/latest/download/Takku.zip (the
# download button on takku.app) always gives the latest version.
#
#   scripts/release.sh            build, sign and zip into build/release/, then ask before publishing
#   scripts/release.sh --dry-run  build, sign and zip only
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig)
tag="v$version"
app=build/release/DerivedData/Build/Products/Release/Takku.app
zip="build/release/Takku-$version.zip"
latest=build/release/Takku.zip
tap=${TAKKU_TAP:-../homebrew-takku}
cask="$tap/Casks/takku.rb"

if [[ -n $(git status --porcelain) ]]; then
    echo "Commit or stash your changes first: the Release must match a commit." >&2
    exit 1
fi
if gh release view "$tag" >/dev/null 2>&1; then
    echo "Release $tag already exists: raise MARKETING_VERSION in Config/Base.xcconfig." >&2
    exit 1
fi
if [[ ! -f $cask || -n $(git -C "$tap" status --porcelain) ]]; then
    echo "The Homebrew tap must be a clean clone of mameli/homebrew-takku in $tap (or set TAKKU_TAP)." >&2
    exit 1
fi

rm -rf build/release
# No get-task-allow entitlement: it is only for debugging.
xcodebuild -project Takku.xcodeproj -scheme Takku -configuration Release \
    -derivedDataPath build/release/DerivedData \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=Takku DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    clean build | grep -E "error: |BUILD"

codesign --verify --strict "$app"
[[ $(codesign -dvv "$app" 2>&1) == *"Authority=Takku"* ]] || { echo "Not signed with the Takku certificate." >&2; exit 1; }
ditto -c -k --keepParent "$app" "$zip"
cp "$zip" "$latest"
echo "Ready: $zip"

[[ ${1:-} == --dry-run ]] && exit 0
read -r -p "Publish $tag on GitHub? [y/N] " answer
[[ $answer == y ]] || exit 0

if [[ $(git rev-parse HEAD) != $(gh api "repos/{owner}/{repo}/commits/main" --jq .sha) ]]; then
    echo "Push main first: the tag is created on the commit GitHub has." >&2
    exit 1
fi
gh release create "$tag" "$zip" "$latest" --target main --title "Takku $version" --notes-file - <<NOTES
Apple Silicon Mac, macOS 15 or later.

With Homebrew: \`brew install --cask mameli/takku/takku\` (or \`brew upgrade --cask takku\`), then steps 2 and 3. Otherwise:

1. Download \`Takku-$version.zip\` (\`Takku.zip\` is the same file), open it and move **Takku** to **Applications**.
2. Open Takku. macOS says it cannot verify the app, because Takku is not notarized by Apple: press **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down and press **Open Anyway** next to Takku, then confirm with your password.

Alternatively, run \`xattr -dr com.apple.quarantine /Applications/Takku.app\` in Terminal before opening it.

See [takku.app/setup](https://takku.app/setup) for the first setup.
NOTES

# The cask points to this version's zip. Pushed through gh, like the Release.
sha=$(shasum -a 256 "$zip" | cut -d ' ' -f 1)
git -C "$tap" pull --ff-only -q
sed -i '' -e "s/^  version \".*\"/  version \"$version\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask"
git -C "$tap" commit -q -am "Takku $version"
git -C "$tap" -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -q origin main
echo "Homebrew cask updated to $version."
