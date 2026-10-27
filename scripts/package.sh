#!/usr/bin/env bash
# Packs a release of turboapps into release/, from the apps in apps/:
#
#   turboapps-VERSION-source.tar.gz and .zip        the source, as git has it
#   <app>.ztl, turboapps-VERSION-ztl.zip            the bundles any tlua runs
#   turboapps-VERSION-linux-amd64.tar.gz            native programs: each app
#   turboapps-VERSION-linux-arm64.tar.gz            fused onto the tlua of that
#   turboapps-VERSION-darwin-arm64.tar.gz           platform (tlua fuse --base),
#   turboapps-VERSION-windows-amd64.zip             so it can be done anywhere
#   SHA256SUMS
#
#   scripts/package.sh 0.1.0            VERSION; tlua is the one in .tlua-version
#   scripts/package.sh 0.1.0 0.9.6      or another release of tlua
#
# It needs a tlua on PATH (or TLUA=/path) to bundle with, curl, tar, zip,
# and git for the source. The other platforms' tlua come from tlua's own
# releases, checked against their SHA256SUMS.
set -euo pipefail

version=${1:?usage: scripts/package.sh VERSION [TLUA_VERSION]}
tlua_version=${2:-$(tr -d '[:space:]' < .tlua-version)}
tlua=${TLUA:-tlua}
repo=${TLUA_REPO:-gh0st42/tlua}
# The platforms to build for, as tlua names its archives; windows may fail
# without stopping the others (ONLY=... picks some: ONLY="linux-amd64").
targets=${ONLY:-"linux-amd64 linux-arm64 darwin-arm64 windows-amd64"}

out=release
rm -rf "$out" bases
mkdir -p "$out" bases

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# The apps: every folder of apps/ with a main.lua.
apps=()
for main in apps/*/main.lua; do
  d=$(dirname "$main")
  apps+=("$(basename "$d")")
done
echo "apps: ${apps[*]}"

# Bundles.
mkdir -p dist
for a in "${apps[@]}"; do
  "$tlua" bundle -o "dist/$a.ztl" "apps/$a"
  cp "dist/$a.ztl" "$out/$a.ztl"
done
(cd dist && zip -q -j "../$out/turboapps-$version-ztl.zip" "${apps[@]/%/.ztl}")

# Source.
if git rev-parse --git-dir >/dev/null 2>&1; then
  ref=${SOURCE_REF:-HEAD}
  git archive --format=tar.gz --prefix="turboapps-$version/" -o "$out/turboapps-$version-source.tar.gz" "$ref"
  git archive --format=zip --prefix="turboapps-$version/" -o "$out/turboapps-$version-source.zip" "$ref"
fi

# The tlua of each platform, to build on.
base_url="https://github.com/$repo/releases/download/v$tlua_version"
curl -fsSL -o bases/SHA256SUMS "$base_url/SHA256SUMS"
failed=()
for t in $targets; do
  (
    set -e
    case "$t" in
      windows-*) asset="tlua-$tlua_version-$t.zip" exe=tlua.exe ;;
      *) asset="tlua-$tlua_version-$t.tar.gz" exe=tlua ;;
    esac
    curl -fsSL -o "bases/$asset" "$base_url/$asset"
    want=$(awk -v a="$asset" '$2 == a || $2 == "*" a { print $1 }' bases/SHA256SUMS)
    got=$(sha256 "bases/$asset" | awk '{ print $1 }')
    if [ -z "$want" ] || [ "$want" != "$got" ]; then
      echo "the checksum of $asset is not the one tlua published" >&2
      exit 1
    fi
    mkdir -p "bases/$t"
    case "$asset" in
      *.zip) unzip -q -o "bases/$asset" -d "bases/$t" ;;
      *) tar xzf "bases/$asset" -C "bases/$t" ;;
    esac
    base=$(find "bases/$t" -name "$exe" -type f | head -n 1)
    [ -n "$base" ] || { echo "no $exe in $asset" >&2; exit 1; }
    chmod +x "$base"

    pkg="turboapps-$version-$t"
    mkdir -p "$out/$pkg"
    ext=""
    [ "$exe" = tlua.exe ] && ext=".exe"
    for a in "${apps[@]}"; do
      "$tlua" fuse -o "$out/$pkg/$a$ext" --base "$base" "dist/$a.ztl"
    done
    cp README.md "$out/$pkg/"
    cat > "$out/$pkg/NOTES.txt" <<NOTES
turboapps $version, built on tlua $tlua_version for $t.
Each program here is one file: run it. They are the apps of
https://github.com/gh0st42/turboapps, and need what tlua needs on this system
(on Linux the X11 or Wayland libraries; see tlua's README).
NOTES
    case "$t" in
      darwin-*) cat >> "$out/$pkg/NOTES.txt" <<NOTES

macOS: these are not signed. If it refuses to open a program downloaded from
the web, remove the quarantine mark once: xattr -dr com.apple.quarantine .
NOTES
      ;;
    esac
    case "$t" in
      windows-*) (cd "$out" && zip -q -r "$pkg.zip" "$pkg") ;;
      *) tar czf "$out/$pkg.tar.gz" -C "$out" "$pkg" ;;
    esac
    rm -rf "${out:?}/$pkg"
  ) || failed+=("$t")
done

(cd "$out" && sha256 -- * > SHA256SUMS)
echo "packed:"
ls -l "$out"
if [ ${#failed[@]} -gt 0 ]; then
  echo "not built: ${failed[*]}" >&2
  # windows is best effort: the others are not.
  for t in "${failed[@]}"; do
    case "$t" in windows-*) ;; *) exit 1 ;; esac
  done
fi
