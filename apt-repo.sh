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

{
  cat <<HTML
<!doctype html>
<meta charset="utf-8">
<title>rpajarola apt repository</title>
<h1>rpajarola apt repository</h1>
<p>Debian and Ubuntu packages (amd64, arm64) for:</p>
<ul>
HTML
  while read -r p v; do
    echo "<li><a href=\"https://github.com/rpajarola/$p\">$p</a> $v</li>"
  done <<< "$packages"
  cat <<HTML
</ul>
<pre>
sudo curl -fsSLo /usr/share/keyrings/$NAME.gpg $url/$NAME.gpg
echo "deb [signed-by=/usr/share/keyrings/$NAME.gpg] $url $SUITE $COMPONENT" \\
  | sudo tee /etc/apt/sources.list.d/$NAME.list
sudo apt update
sudo apt install $(echo "$packages" | awk '{print $1}' | paste -sd' ' -)
</pre>
<p>Source: <a href="https://github.com/rpajarola/apt">github.com/rpajarola/apt</a></p>
HTML
} > index.html

echo "apt-repo.sh: built $SUITE/$COMPONENT with ${#debs[@]} package file(s) in $OUT"
