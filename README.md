# rpajarola apt repository

A signed apt repository for Debian and Ubuntu (amd64, arm64), served from
GitHub Pages at <https://rpajarola.github.io/apt>, with the packages of:

- [gobootd](https://github.com/rpajarola/gobootd/releases): boot server for old and unusual machines
- [tme-rp](https://github.com/rpajarola/tme/releases): The Machine Emulator (Sun-2, Sun-3, Sun-4c, UltraSPARC)
- [gxemul-rp](https://github.com/rpajarola/gxemul/releases): GXemul, with SIMH tapes, TURBOchannel ROMs and L2TPv3

## Use

```
sudo curl -fsSLo /usr/share/keyrings/rpajarola.gpg https://rpajarola.github.io/apt/rpajarola.gpg
echo "deb [signed-by=/usr/share/keyrings/rpajarola.gpg] https://rpajarola.github.io/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/rpajarola.list
sudo apt update
sudo apt install gobootd tme-rp gxemul-rp
```

The packages are built on Ubuntu 24.04.

## How it works

Nothing is stored here but the list of projects ([`sources.txt`](sources.txt))
and the script that builds the repository ([`apt-repo.sh`](apt-repo.sh)).
The [publish workflow](.github/workflows/publish.yml) downloads the `.deb`
assets of every release of every project in the list, builds and signs
the repository, and deploys it to GitHub Pages. It runs:

- when a project publishes a release: the project's release workflow
  builds the `.deb`s, attaches them to the release and sends this
  repository a `repository_dispatch` event;
- once a week, in case a dispatch was missed;
- by hand (Actions → publish → Run workflow), e.g. after changing a
  release's assets.

To add a project, add it and its package name to `sources.txt`, and give
its release workflow the same `apt` job as gobootd's.

## One-time setup

1. A signing key without a passphrase (it only signs this repository).
   Keep a backup: if it is lost, every user has to fetch a new public key.
   ```
   gpg --batch --passphrase '' --quick-gen-key "rpajarola apt repository <rp@servium.ch>" ed25519 sign never
   gpg --armor --export-secret-keys "rpajarola apt repository" > rpajarola-apt-signing-key.asc
   gh secret set APT_SIGNING_KEY -R rpajarola/apt < rpajarola-apt-signing-key.asc
   ```
   An existing key works too, e.g. whereisrico's from its backup.
2. GitHub Pages from Actions:
   `gh api -X POST repos/rpajarola/apt/pages -f build_type=workflow`
3. In each project, a `PACKAGES_TOKEN` secret: a fine-grained personal
   access token with **Contents: read and write** on `rpajarola/apt` and
   `rpajarola/homebrew-tap` only. The projects use it to trigger the
   publish workflow and to update their Homebrew formulas.

Build the repository locally (with `apt-utils` and the key imported):

```
GPG_KEY_ID=<fingerprint> ./apt-repo.sh <dir-with-debs> site
```
