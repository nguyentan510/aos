#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary_path=${1:-"$repository_root/target/debug/aos"}
evidence_root=${2:-"${TMPDIR:-/tmp}/aos-p6-3-linux-$$"}

[ -x "$binary_path" ] || {
  echo "Build the AOS binary before running the installer smoke: $binary_path" >&2
  exit 1
}

mkdir -p "$evidence_root/package" "$evidence_root/project" "$evidence_root/home"
cp "$binary_path" "$evidence_root/package/aos"
chmod 755 "$evidence_root/package/aos"
cp -R "$repository_root/extensions" "$evidence_root/package/extensions"
archive="$evidence_root/aos-x86_64-unknown-linux-gnu.tar.gz"
tar -czf "$archive" -C "$evidence_root/package" aos extensions
checksum=$(sha256sum "$archive" | awk '{print $1}')
checksums="$evidence_root/SHA256SUMS"
printf "%s  %s\n" "$checksum" "aos-x86_64-unknown-linux-gnu.tar.gz" > "$checksums"

HOME="$evidence_root/home" sh "$repository_root/install.sh" \
  --version v0.1.0-rc.4 \
  --project-path "$evidence_root/project" \
  --yes \
  --install-root "$evidence_root/install" \
  --no-path-update \
  --archive-path "$archive" \
  --checksum-path "$checksums"

installed="$evidence_root/home/.local/bin/aos"
"$installed" doctor "$evidence_root/project" --format=json >/dev/null

HOME="$evidence_root/home" sh "$repository_root/install.sh" \
  --version v0.1.0-rc.4 \
  --yes \
  --install-root "$evidence_root/install" \
  --no-path-update \
  --archive-path "$archive" \
  --checksum-path "$checksums" >/dev/null

bad_checksums="$evidence_root/SHA256SUMS.bad"
printf "%064d  %s\n" 0 "aos-x86_64-unknown-linux-gnu.tar.gz" > "$bad_checksums"
if HOME="$evidence_root/home" sh "$repository_root/install.sh" \
  --version v0.1.0-rc.4 \
  --yes \
  --install-root "$evidence_root/tampered-install" \
  --no-path-update \
  --archive-path "$archive" \
  --checksum-path "$bad_checksums" >/dev/null 2>&1; then
  echo "checksum tampering was not rejected" >&2
  exit 1
fi

HOME="$evidence_root/home" sh "$repository_root/install.sh" \
  --uninstall \
  --yes \
  --install-root "$evidence_root/install" \
  --no-path-update

[ ! -e "$installed" ] || { echo "distribution binary remains after uninstall" >&2; exit 1; }
[ -f "$evidence_root/project/.aos/repository.json" ] ||
  { echo "uninstall removed downstream .aos data" >&2; exit 1; }

echo "AOS_P6_3_INSTALL_LINUX_OK"
echo "AOS_P6_3_FRESH_PROJECT_SMOKE_OK"
