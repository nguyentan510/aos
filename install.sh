#!/bin/sh
set -eu

repository="nguyentan510/aos"
asset_name="aos-x86_64-unknown-linux-gnu.tar.gz"
version=""
project_path=""
yes=0
uninstall=0
install_root="${XDG_DATA_HOME:-$HOME/.local/share}/aos"
no_path_update=0
archive_path=""
checksum_path=""

usage() {
  echo "usage: install.sh [--version TAG] [--project-path PATH] [--yes] [--uninstall]"
  echo "                  [--install-root PATH] [--no-path-update]"
  echo "                  [--archive-path PATH --checksum-path PATH]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version) version=$2; shift 2 ;;
    --project-path) project_path=$2; shift 2 ;;
    --yes) yes=1; shift ;;
    --uninstall) uninstall=1; shift ;;
    --install-root) install_root=$2; shift 2 ;;
    --no-path-update) no_path_update=1; shift ;;
    --archive-path) archive_path=$2; shift 2 ;;
    --checksum-path) checksum_path=$2; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

confirm() {
  [ "$yes" -eq 1 ] && return 0
  printf "%s [y/N] " "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) ;; *) echo "AOS installation cancelled."; exit 0 ;; esac
}

canonical() {
  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$1"
  else
    case "$1" in /*) printf "%s\n" "$1" ;; *) printf "%s/%s\n" "$PWD" "$1" ;; esac
  fi
}

checksum_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "sha256sum or shasum is required." >&2
    exit 1
  fi
}

install_root=$(canonical "$install_root")
[ "$install_root" != "/" ] || { echo "InstallRoot cannot be a filesystem root." >&2; exit 2; }
manifest_path="$install_root/install.json"
bin_link="$HOME/.local/bin/aos"

case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64) ;;
  *) echo "P6.3 supports Linux x86_64 GNU only." >&2; exit 1 ;;
esac

if [ "$uninstall" -eq 1 ]; then
  confirm "Uninstall the AOS distribution from $install_root?"
  [ -f "$manifest_path" ] || { echo "No installer-owned manifest at $manifest_path." >&2; exit 1; }
  recorded_root=$(sed -n 's/.*"install_root":[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_path")
  recorded_hash=$(sed -n 's/.*"current_binary_sha256":[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_path")
  [ "$(canonical "$recorded_root")" = "$install_root" ] ||
    { echo "Installation ownership does not match the requested root." >&2; exit 1; }
  if [ -L "$bin_link" ]; then
    link_target=$(canonical "$bin_link")
    case "$link_target" in "$install_root"/versions/*/aos) ;; *)
      echo "Refusing uninstall because the current symlink is not installer-owned." >&2; exit 1 ;;
    esac
    actual_hash=$(checksum_file "$link_target")
    [ "$actual_hash" = "$recorded_hash" ] ||
      { echo "Refusing uninstall because the binary was modified." >&2; exit 1; }
    rm "$bin_link"
  elif [ -e "$bin_link" ]; then
    echo "Refusing uninstall because $bin_link is not an installer-owned symlink." >&2
    exit 1
  fi
  sed -n 's/^[[:space:]]*"\([^"]*\/versions\/[^"]*\)"[,]*$/\1/p' "$manifest_path" |
    while IFS= read -r version_directory; do
      case "$version_directory" in "$install_root"/versions/*) rm -rf "$version_directory" ;; esac
    done
  rm "$manifest_path"
  echo "AOS_P6_3_UNINSTALL_LINUX_OK"
  exit 0
fi

[ -n "$archive_path" ] && [ -n "$checksum_path" ] ||
  if [ -n "$archive_path$checksum_path" ]; then
    echo "ArchivePath and ChecksumPath must be provided together." >&2
    exit 2
  fi

if [ -n "$project_path" ]; then
  [ -d "$project_path" ] || { echo "ProjectPath must be an existing directory." >&2; exit 3; }
  confirm "Install AOS and set up project '$project_path'?"
fi

if [ -z "$version" ]; then
  version=$(curl -fsSL -H "User-Agent: aos-installer" \
    "https://api.github.com/repos/$repository/releases/latest" 2>/dev/null |
    sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)
  if [ -z "$version" ]; then
    version=$(curl -fsSL -H "User-Agent: aos-installer" \
      "https://api.github.com/repos/$repository/releases" |
      sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  fi
  [ -n "$version" ] || { echo "No published AOS release is available." >&2; exit 1; }
fi
case "$version" in
  v[0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*.[0-9]*-rc.[0-9]*) ;;
  *) echo "Version must look like v0.1.0 or v0.1.0-rc.4." >&2; exit 2 ;;
esac

temporary=$(mktemp -d "${TMPDIR:-/tmp}/aos-install.XXXXXX")
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
archive="$temporary/$asset_name"
checksums="$temporary/SHA256SUMS"
if [ -n "$archive_path" ]; then
  cp "$(canonical "$archive_path")" "$archive"
  cp "$(canonical "$checksum_path")" "$checksums"
else
  base="https://github.com/$repository/releases/download/$version"
  curl -fsSL "$base/$asset_name" -o "$archive"
  curl -fsSL "$base/SHA256SUMS" -o "$checksums"
fi

expected=$(awk -v name="$asset_name" '$2 == name || $2 == "*" name {print $1}' "$checksums")
[ "$(printf "%s\n" "$expected" | sed '/^$/d' | wc -l)" -eq 1 ] ||
  { echo "SHA256SUMS must contain exactly one entry for $asset_name." >&2; exit 1; }
actual=$(checksum_file "$archive")
[ "$actual" = "$expected" ] || { echo "Checksum mismatch for $asset_name." >&2; exit 1; }

tar -tzf "$archive" | while IFS= read -r entry; do
  case "$entry" in /*|../*|*/../*|*/..) echo "Archive contains unsafe path: $entry" >&2; exit 9 ;; esac
done
if tar -tvzf "$archive" | awk '
  substr($1, 1, 1) == "l" || substr($1, 1, 1) == "h" { unsafe=1 }
  END { exit unsafe ? 1 : 0 }
'; then
  :
else
  echo "Archive contains a symbolic or hard link." >&2
  exit 9
fi
stage="$temporary/stage"
mkdir -p "$stage"
tar -xzf "$archive" -C "$stage"
[ -f "$stage/aos" ] || { echo "Archive does not contain aos at its root." >&2; exit 1; }
chmod 755 "$stage/aos"
"$stage/aos" version --format=json >/dev/null

version_directory="$install_root/versions/$version"
case "$version_directory" in "$install_root"/versions/*) ;; *)
  echo "Refusing to install outside the installation root." >&2; exit 1 ;;
esac
mkdir -p "$install_root/versions" "$HOME/.local/bin"
managed_versions=""
if [ -f "$manifest_path" ]; then
  recorded_root=$(sed -n 's/.*"install_root":[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_path")
  recorded_hash=$(sed -n 's/.*"current_binary_sha256":[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest_path")
  [ "$(canonical "$recorded_root")" = "$install_root" ] ||
    { echo "Existing installation ownership does not match the requested root." >&2; exit 1; }
  if [ -L "$bin_link" ]; then
    current_target=$(canonical "$bin_link")
    [ "$(checksum_file "$current_target")" = "$recorded_hash" ] ||
      { echo "Refusing to replace a modified current binary." >&2; exit 1; }
  elif [ -e "$bin_link" ]; then
    echo "Refusing to replace an unowned current path: $bin_link" >&2
    exit 1
  fi
  managed_versions=$(sed -n 's/^[[:space:]]*"\([^"]*\/versions\/[^"]*\)"[,]*$/\1/p' "$manifest_path")
fi
if [ ! -e "$version_directory" ]; then
  mv "$stage" "$version_directory"
fi
[ -x "$version_directory/aos" ] || { echo "Installed version directory is incomplete." >&2; exit 1; }
pending_link="$HOME/.local/bin/.aos.pending.$$"
ln -s "$version_directory/aos" "$pending_link"
mv -Tf "$pending_link" "$bin_link"
binary_hash=$(checksum_file "$version_directory/aos")

pending_manifest="$install_root/install.json.pending.$$"
managed_versions=$(printf "%s\n%s\n" "$managed_versions" "$version_directory" | sed '/^$/d' | sort -u)
managed_json=$(printf "%s\n" "$managed_versions" | awk '
  BEGIN { first=1 }
  {
    if (!first) printf ",\n";
    printf "    \"%s\"", $0;
    first=0
  }
')
cat > "$pending_manifest" <<EOF
{
  "schema_version": "1",
  "installer": "install.sh",
  "repository": "$repository",
  "version": "$version",
  "install_root": "$install_root",
  "bin_path": "$bin_link",
  "current_binary_sha256": "$binary_hash",
  "archive_name": "$asset_name",
  "archive_sha256": "$actual",
  "managed_version_paths": [
$managed_json
  ]
}
EOF
mv -f "$pending_manifest" "$manifest_path"

echo "Installed AOS $version at $bin_link"
echo "AOS_P6_3_INSTALL_LINUX_OK"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
  [ "$no_path_update" -eq 1 ] || echo "Warning: add $HOME/.local/bin to PATH." >&2 ;;
esac
if [ -n "$project_path" ]; then
  "$version_directory/aos" setup "$(canonical "$project_path")" --yes --format=json
  echo "AOS_P6_3_FRESH_PROJECT_SMOKE_OK"
fi
