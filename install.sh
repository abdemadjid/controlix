#!/bin/sh
# Controlix AI - installer for the server (public bootstrap).
#
#   curl -fsSL https://SITE/install.sh | sudo sh -s -- install --host YOUR_SERVER_IP
#   curl -fsSL https://SITE/install.sh | sudo sh -s -- update
#
# --host is the address that your browsers and your agents will use to reach this server
# (its IP address or DNS name). The TLS certificate is issued for exactly this address.
#
# Other options are passed to the installer: --dir DIR  --light  --demo  --yes
#   --admin-user NAME --admin-email MAIL   --registry-user NAME (private image registry,
#   token in the CONTROLIX_REGISTRY_TOKEN variable)   --version X.Y.Z (default: latest)
set -eu

REPO="${CONTROLIX_REPO:-abdemadjid/controlix}"
STATUS_URL="${CONTROLIX_STATUS_URL:-https://abdemadjid.github.io/controlix/status.json}"
DIR=/opt/controlix; HOST=""; VERSION=latest; CMD="${1:-}"
case "$CMD" in install|update) shift ;; "") CMD=install ;; -*) CMD=install ;; *) printf 'usage: install.sh install|update --host IP\n' >&2; exit 2 ;; esac

# The publisher can pause new installs and updates from GitHub by editing status.json on the public site
# ({"active": false, "message": "..."}). Servers that already run Controlix are not touched by this check.
check_status() {
  S="$(curl -fsSL --max-time 10 "$STATUS_URL" 2>/dev/null || true)"
  if printf '%s' "$S" | grep -Eq '"active"[[:space:]]*:[[:space:]]*false'; then
    M="$(printf '%s' "$S" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    die "installation and updates are currently paused by the publisher${M:+: $M}"
  fi
}

have_tty() { ( : </dev/tty ) 2>/dev/null; }
say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root: curl -fsSL URL | sudo sh -s -- $CMD ..."
[ "$(uname -s)" = Linux ] || die "Linux is required"
for c in curl tar sha256sum; do command -v "$c" >/dev/null 2>&1 || die "$c is required (install it with your package manager)"; done

# Read the options that matter here; every option is passed on to the installer unchanged.
ARGS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --host) HOST="$2" ;;
    --dir) DIR="$2"; shift 2; continue ;;
    --version) VERSION="$2"; shift 2; continue ;;
  esac
  ARGS="$ARGS '$1'"; shift
done

if [ "$CMD" = install ] && [ -z "$HOST" ]; then
  GUESS="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if have_tty; then
    printf 'Address of this server, as your browsers and agents will reach it (IP or DNS name)%s: ' "${GUESS:+ [$GUESS]}" >/dev/tty
    read -r HOST </dev/tty || true
    HOST="${HOST:-$GUESS}"
    ARGS="$ARGS '--host' '$HOST'"
  fi
  [ -n "$HOST" ] || die "--host is required: give the IP address or DNS name of this server (for example --host 203.0.113.10)"
fi

check_status

BASE="${CONTROLIX_RELEASE_URL:-https://github.com/$REPO/releases}"
if [ "$VERSION" = latest ]; then URL="$BASE/latest/download"; else URL="$BASE/download/v${VERSION#v}"; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say "Downloading Controlix AI ($VERSION)"
curl -fsSL --retry 3 --retry-delay 2 -o "$TMP/bundle.tgz" "$URL/controlix-bundle.tar.gz" || die "download failed: $URL/controlix-bundle.tar.gz (check the internet access of this server)"
curl -fsSL --retry 3 -o "$TMP/bundle.sha256" "$URL/controlix-bundle.tar.gz.sha256" || die "checksum file not found"
(cd "$TMP" && echo "$(cut -d' ' -f1 bundle.sha256)  bundle.tgz" | sha256sum -c - >/dev/null) || die "the downloaded file does not match its checksum: nothing was installed"

say "Unpacking into $DIR (your .env, data and backups are never overwritten)"
mkdir -p "$DIR"
tar xzf "$TMP/bundle.tgz" -C "$DIR" --strip-components=1
chmod +x "$DIR/install.sh" "$DIR"/scripts/*.sh

# The installer asks for the administrator password: give it the terminal back when the script was piped.
if have_tty; then
  eval "exec sh '$DIR/install.sh' '$CMD' --dir '$DIR' $ARGS </dev/tty"
fi
eval "exec sh '$DIR/install.sh' '$CMD' --dir '$DIR' $ARGS"
