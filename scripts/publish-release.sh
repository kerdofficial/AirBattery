#!/bin/bash
# Signs the built zip for Sparkle, adds the appcast.xml item and creates the GitHub release.
# Usage: scripts/publish-release.sh <version> [--dry-run]  (run scripts/build-release.sh first)
# Needs release-notes/<version>.md, gh and the Sparkle key in the login keychain (account kerdofficial-AirBattery).
# --dry-run runs every check and the signing, prints the appcast diff, then restores appcast.xml.
set -euo pipefail

VERSION="${1:?usage: publish-release.sh <version> [--dry-run]}"
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ZIP="$BUILD/AirBattery-$VERSION.zip"
APP="$BUILD/AirBattery.app"
NOTES="$ROOT/release-notes/$VERSION.md"
APPCAST="$ROOT/appcast.xml"
REPO="kerdofficial/AirBattery"
SIGN_UPDATE="$BUILD/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

die() { echo "error: $*" >&2; exit 1; }

[ -f "$ZIP" ] || die "missing $ZIP, run scripts/build-release.sh first"
[ -f "$NOTES" ] || die "missing release notes $NOTES"
[ -x "$SIGN_UPDATE" ] || die "missing Sparkle sign_update at $SIGN_UPDATE (build the app once to fetch the Sparkle package)"

APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$APP_VERSION" = "$VERSION" ] || die "$APP is version $APP_VERSION, expected $VERSION"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")

xcrun stapler validate "$APP" || die "app is not stapled"
spctl --assess --type execute "$APP" || die "Gatekeeper rejects the app"

COMMIT=$(git -C "$ROOT" rev-parse HEAD)
git -C "$ROOT" fetch -q origin
if [ -z "$(git -C "$ROOT" branch -r --contains "$COMMIT")" ]; then
    [ "$DRY_RUN" = 1 ] && echo "warning: $COMMIT is not pushed yet; a real run stops here" >&2 || die "push $COMMIT first, the release tag points at it"
fi

if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    die "release v$VERSION already exists on GitHub"
fi

grep -q "sparkle:version>$BUILD_NUMBER<" "$APPCAST" && die "appcast.xml already has build $BUILD_NUMBER"
LATEST=$({ grep -o 'sparkle:version>[0-9]*<' "$APPCAST" || true; } | tr -dc '0-9\n' | sort -n | tail -1)
[ -z "$LATEST" ] || [ "$BUILD_NUMBER" -gt "$LATEST" ] || die "build $BUILD_NUMBER must be greater than $LATEST already in appcast.xml"

SIGNATURE_LINE=$("$SIGN_UPDATE" --account kerdofficial-AirBattery "$ZIP")
ED_SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNATURE_LINE")
LENGTH=$(sed -n 's/.*length="\([^"]*\)".*/\1/p' <<<"$SIGNATURE_LINE")
[ -n "$ED_SIGNATURE" ] && [ -n "$LENGTH" ] || die "could not parse sign_update output"

NOTES_HTML=$(mktemp)
python3 - "$NOTES" > "$NOTES_HTML" <<'PY'
import html, re, sys

def inline(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)
    return re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', text)

out, para, in_list = [], [], False

def flush():
    global para, in_list
    if para:
        out.append("<p>" + inline(" ".join(para)) + "</p>")
        para = []
    if in_list:
        out.append("</ul>")
        in_list = False

for line in open(sys.argv[1], encoding="utf-8").read().splitlines():
    heading = re.match(r"(#{1,3}) (.*)", line)
    bullet = re.match(r"- (.*)", line)
    if heading:
        flush()
        level = len(heading.group(1))
        out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
    elif bullet:
        if para:
            flush()
        if not in_list:
            out.append("<ul>")
            in_list = True
        out.append(f"<li>{inline(bullet.group(1))}</li>")
    elif line.strip():
        if in_list:
            flush()
        para.append(line.strip())
    else:
        flush()
flush()
print("\n".join(out))
PY

BACKUP=$(mktemp)
cp "$APPCAST" "$BACKUP"
RELEASED=0
cleanup() {
    # Nothing half-done: unless the release was created, appcast.xml goes back to its original content.
    [ "$RELEASED" = 1 ] || cp "$BACKUP" "$APPCAST"
    rm -f "$BACKUP" "$NOTES_HTML"
}
trap cleanup EXIT

python3 - "$APPCAST" "$VERSION" "$BUILD_NUMBER" "$ED_SIGNATURE" "$LENGTH" "$NOTES_HTML" <<'PY'
import sys
from email.utils import formatdate

path, version, build, signature, length, notes_path = sys.argv[1:]
notes = open(notes_path, encoding="utf-8").read().rstrip("\n")
url = "https://github.com/kerdofficial/AirBattery/releases"
item = f"""        <item>
            <title>Version {version}</title>
            <pubDate>{formatdate(localtime=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>{url}/tag/v{version}</sparkle:fullReleaseNotesLink>
            <description><![CDATA[
{notes}
            ]]></description>
            <enclosure url="{url}/download/v{version}/AirBattery-{version}.zip" sparkle:edSignature="{signature}" length="{length}" type="application/octet-stream"/>
        </item>
"""
text = open(path, encoding="utf-8").read()
marker = "</title>\n"
index = text.index(marker, text.index("<channel>")) + len(marker)
open(path, "w", encoding="utf-8").write(text[:index] + item + text[index:])
PY

if [ "$DRY_RUN" = 1 ]; then
    diff -u "$BACKUP" "$APPCAST" || true
    echo "Dry run: appcast.xml restored, no release created."
    exit 0
fi

# The asset must exist before the feed points at it. appcast.xml is only edited locally here and goes live
# when the commit containing it reaches main, so merge that commit after this release is created.
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "AirBattery $VERSION" \
    --notes-file "$NOTES" --target "$COMMIT"
RELEASED=1
echo "Released v$VERSION. Commit appcast.xml and merge it to main to publish the update."
