#!/usr/bin/env bash
# Builds a page for each project in sources.txt: its README and its manual
# pages, rendered to HTML. apt-repo.sh copies the result into the site
# (PAGES_DIR) and links each package to its page.
#
# Both come from the project's default branch, so they describe what's on
# main, which may be ahead of the packaged version. The README is rendered
# by GitHub's API, the same way github.com shows it (Markdown or plain
# text). Manual pages are the files named <name>.<section> in a directory
# called man, rendered with mandoc.
#
# Requires gh (with a token: GH_TOKEN in CI), mandoc and perl.
#
# Usage:
#   ./project-pages.sh <out-dir>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <out-dir>" >&2
  exit 2
fi
OUT="$1"
SOURCES="$(cd "$(dirname "$0")" && pwd)/sources.txt"
NAME=rpajarola

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# page_head <title> <back-href> <back-label>
page_head() {
  cat <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$1</title>
<link rel="stylesheet" href="../site.css">
</head>
<body>
<main>
<a class="home" href="$2">&larr; $3</a>
HTML
}

foot() {
  cat <<HTML
<footer>Source: <a href="https://github.com/$1">github.com/$1</a></footer>
</main>
</body>
</html>
HTML
}

rm -rf "$OUT"
mkdir -p "$OUT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

grep -v '^#' "$SOURCES" | while read -r repo pkg; do
  [ -n "$repo" ] || continue
  echo "project-pages.sh: $pkg ($repo)"
  dir="$OUT/$pkg"
  mkdir -p "$dir"

  desc=$(gh repo view "$repo" --json description --jq '.description // ""' | esc)
  tag=$(gh release list -R "$repo" --limit 1 --exclude-drafts --exclude-pre-releases --json tagName --jq '.[0].tagName // ""')

  # GitHub returns the README as a fragment. Its relative links and
  # images point into the repository, and its headings' ids carry a
  # user-content- prefix that github.com strips with JavaScript.
  readme=$(gh api "repos/$repo/readme" -H "Accept: application/vnd.github.html+json" 2>/dev/null |
    REPO="$repo" perl -pe '
      s{\b(href|src)="(?![a-z][a-z0-9+.-]*:|#|/)([^"]*)"}{
        $1 . "=\"https://github.com/$ENV{REPO}/" . ($1 eq "src" ? "raw" : "blob") . "/HEAD/$2\""
      }ge;
      s{\bid="user-content-}{id="}g;
    ' || true)

  # Manual pages, rendered in a directory holding all of them under
  # their <name>.<section> names, so mandoc links references between them
  # locally and everything else to manpages.debian.org.
  rm -rf "$work/man" && mkdir -p "$work/man"
  gh api "repos/$repo/git/trees/HEAD?recursive=1" \
    --jq '.tree[] | select(.type == "blob") | .path' |
    { grep -E '(^|/)man/[^/]+\.[1-9][a-z]*$' || true; } |
    while read -r path; do
      gh api "repos/$repo/contents/$path" -H "Accept: application/vnd.github.raw" > "$work/man/${path##*/}"
    done
  mans=()
  for f in "$work"/man/*; do
    [ -e "$f" ] && mans+=("${f##*/}")
  done

  for m in ${mans[@]+"${mans[@]}"}; do
    title="${m%.*}(${m##*.})"
    {
      page_head "$title &mdash; $pkg" "./" "$pkg"
      echo "<div class=\"man\">"
      (cd "$work/man" && mandoc -T html -O "fragment,man=%N.%S.html;https://manpages.debian.org/%N.%S" "$m")
      echo "</div>"
      foot "$repo"
    } > "$dir/$m.html"
  done

  {
    page_head "$pkg" "../" "$NAME apt repository"
    echo "<h1>$pkg</h1>"
    [ -n "$desc" ] && echo "<p class=\"muted\">$desc</p>"
    echo "<p><a href=\"https://github.com/$repo\">GitHub</a> &middot; <a href=\"https://github.com/$repo/releases\">releases</a>${tag:+ (latest: $tag)}</p>"
    cat <<HTML
<h2>Install</h2>
<pre>
sudo apt install $pkg                   # Debian, Ubuntu: <a href="../">set up the repository</a> first
brew install rpajarola/tap/$pkg         # macOS
</pre>
HTML
    if [ ${#mans[@]} -gt 0 ]; then
      echo "<h2>Manual pages</h2>"
      echo "<ul class=\"mans\">"
      for m in "${mans[@]}"; do
        # The one-line description from the NAME section, after the dash.
        nd=$(cd "$work/man" && mandoc -T utf8 -O width=1000 "$m" 2>/dev/null | col -b |
          awk '/^NAME/ {getline; print; exit}' | perl -CS -pe 's/^.*?\s[-\x{2013}\x{2014}]\s+//' | esc)
        echo "<li><a href=\"$m.html\">${m%.*}(${m##*.})</a>${nd:+ <span class=\"muted\">&mdash; $nd</span>}</li>"
      done
      echo "</ul>"
    fi
    if [ -n "$readme" ]; then
      echo "<h2>README</h2>"
      echo "<div class=\"doc\">"
      echo "$readme"
      echo "</div>"
    fi
    foot "$repo"
  } > "$dir/index.html"
done
