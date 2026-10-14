#!/usr/bin/env bash
# Builds a signed apt repository from a directory of .deb files, laid out
# for static hosting (GitHub Pages; see .github/workflows/publish.yml).
#
# Requires apt-ftparchive (apt-utils) and gpg, with the signing key's
# secret key already imported.
#
# Usage:
#   GPG_KEY_ID=<fingerprint> ./apt-repo.sh <deb-dir> <out-dir>
#
# <out-dir> is wiped and recreated. Users add the result with:
#   deb [signed-by=/usr/share/keyrings/rpajarola.gpg] <url> stable main
set -euo pipefail

if [ $# -ne 2 ] || [ -z "${GPG_KEY_ID:-}" ]; then
  echo "usage: GPG_KEY_ID=<fingerprint> $0 <deb-dir> <out-dir>" >&2
  exit 2
fi
DEB_DIR="$(cd "$1" && pwd)"
OUT="$2"
SOURCES="$(cd "$(dirname "$0")" && pwd)/sources.txt"

NAME=rpajarola
SUITE=stable
COMPONENT=main
ARCHES="amd64 arm64"
url="${REPO_URL:-https://rpajarola.github.io/apt}"

shopt -s nullglob
debs=("$DEB_DIR"/*.deb)
if [ ${#debs[@]} -eq 0 ]; then
  echo "apt-repo.sh: no .deb files in $DEB_DIR" >&2
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT/pool/$COMPONENT"
cp "${debs[@]}" "$OUT/pool/$COMPONENT/"
cd "$OUT"

for arch in $ARCHES; do
  dir="dists/$SUITE/$COMPONENT/binary-$arch"
  mkdir -p "$dir"
  apt-ftparchive --arch "$arch" packages "pool/$COMPONENT" > "$dir/Packages"
  gzip -9nk "$dir/Packages"
done

# Written to a temp file first: apt-ftparchive would otherwise checksum
# the half-written Release file it is generating.
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="$NAME" \
  -o APT::FTPArchive::Release::Label="$NAME" \
  -o APT::FTPArchive::Release::Suite="$SUITE" \
  -o APT::FTPArchive::Release::Codename="$SUITE" \
  -o APT::FTPArchive::Release::Architectures="$ARCHES" \
  -o APT::FTPArchive::Release::Components="$COMPONENT" \
  release "dists/$SUITE" > Release.tmp
mv Release.tmp "dists/$SUITE/Release"

gpg --batch --yes --local-user "$GPG_KEY_ID" --armor --detach-sign \
  --output "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
gpg --batch --yes --local-user "$GPG_KEY_ID" --clearsign \
  --output "dists/$SUITE/InRelease" "dists/$SUITE/Release"

# Public key, binary (for /usr/share/keyrings) and armored.
gpg --batch --export "$GPG_KEY_ID" > "$NAME.gpg"
gpg --batch --armor --export "$GPG_KEY_ID" > "$NAME.asc"

# The newest version of each package, for the index page.
packages=$(for arch in $ARCHES; do
  awk '/^Package:/ {p=$2} /^Version:/ {print p, $2}' "dists/$SUITE/$COMPONENT/binary-$arch/Packages"
done | sort -u -k1,1 -k2,2V | awk '{v[$1]=$2} END {for (p in v) print p, v[p]}' | sort)

# Each package links to the repository that builds it, from sources.txt.
{
  cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$NAME apt repository</title>
<style>
  :root { --bg: #f6f3ec; --fg: #1f1d1a; --muted: #6b665d; --card: #fffdf8; --line: #e2dccf; --accent: #b5530f; --code-bg: #efe9dc; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #12110f; --fg: #ece6da; --muted: #9a9284; --card: #1b1a17; --line: #2e2b26; --accent: #f0a04b; --code-bg: #0c0b0a; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 40px 16px; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .home { font-size: 14px; }
  h1 { font-size: 32px; line-height: 1.15; margin: 16px 0 8px; letter-spacing: -.01em; }
  h2 { font-size: 13px; font-weight: 600; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); margin: 32px 0 12px; }
  p { margin: 0 0 12px; }
  .muted { color: var(--muted); }
  table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
  td { padding: 10px 14px; border-top: 1px solid var(--line); }
  tr:first-child td { border-top: 0; }
  td.v { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 14px; color: var(--muted); }
  td.r { text-align: right; white-space: nowrap; }
  pre { background: var(--code-bg); border: 1px solid var(--line); border-radius: 6px; padding: 12px 14px; font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; overflow-x: auto; }
  footer { margin-top: 32px; padding-top: 16px; border-top: 1px solid var(--line); font-size: 14px; color: var(--muted); }
</style>
</head>
<body>
<main>
<a class="home" href="https://rpajarola.github.io/">&larr; rpajarola.github.io</a>
<h1>$NAME apt repository</h1>
<p class="muted">Signed Debian and Ubuntu packages, for amd64 and arm64.</p>
<h2>Packages</h2>
<table>
HTML
  while read -r p v; do
    repo=$(awk -v p="$p" '!/^#/ && $2 == p {print $1; exit}' "$SOURCES")
    repo=${repo:-rpajarola/$p}
    echo "<tr><td><a href=\"https://github.com/$repo\">$p</a></td><td class=\"v\">$v</td><td class=\"r\"><a href=\"https://github.com/$repo/releases\">releases</a></td></tr>"
  done <<< "$packages"
  cat <<HTML
</table>
<h2>Use</h2>
<pre>
sudo curl -fsSLo /usr/share/keyrings/$NAME.gpg $url/$NAME.gpg
echo "deb [signed-by=/usr/share/keyrings/$NAME.gpg] $url $SUITE $COMPONENT" \\
  | sudo tee /etc/apt/sources.list.d/$NAME.list
sudo apt update
sudo apt install $(echo "$packages" | awk '{print $1}' | paste -sd' ' -)
</pre>
<p>The public key is also available <a href="$NAME.asc">armored</a>. On macOS, use the
<a href="https://github.com/rpajarola/homebrew-tap">Homebrew tap</a>.</p>
<footer>Source: <a href="https://github.com/rpajarola/apt">github.com/rpajarola/apt</a></footer>
</main>
</body>
</html>
HTML
} > index.html

echo "apt-repo.sh: built $SUITE/$COMPONENT with ${#debs[@]} package file(s) in $OUT"
