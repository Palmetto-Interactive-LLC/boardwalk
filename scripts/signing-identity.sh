#!/bin/zsh
# Prints the code-signing identity to build with, creating a local one if needed.
#
# Why: macOS remembers Bluetooth permission per app *identity*. An ad-hoc signed app
# gets a new identity on every build, so macOS would ask for Bluetooth again after
# each rebuild. A self-signed certificate that stays in your login keychain keeps the
# identity stable, so you're asked once.
#
# Override with SIGN_IDENTITY="Your Identity" (e.g. an Apple Development certificate).
# Prints "-" (ad-hoc) in CI or if a local identity can't be created.
set -uo pipefail

NAME="Boardwalk Local Signing"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then printf "%s\n" "$SIGN_IDENTITY"; exit 0; fi
if [[ -n "${CI:-}" ]]; then printf "%s\n" "-"; exit 0; fi

if security find-certificate -c "$NAME" >/dev/null 2>&1; then printf "%s\n" "$NAME"; exit 0; fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(openssl rand -hex 16)"

{
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -subj "/CN=$NAME" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" &&
  /usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS" &&
  security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASS" -T /usr/bin/codesign
} >/dev/null 2>&1

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Created local signing certificate \"$NAME\" in your login keychain." >&2
  printf "%s\n" "$NAME"
else
  echo "Couldn't create a local signing certificate. Falling back to ad-hoc signing." >&2
  printf "%s\n" "-"
fi
