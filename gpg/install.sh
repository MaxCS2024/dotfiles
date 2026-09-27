#!/usr/bin/env bash
#
# A GPG key for this user, made once so nobody has to learn gpg's prompts:
# ed25519 to sign and certify, with a cv25519 subkey to encrypt (gpg's
# future-default). Nothing else is set up with it; git, mail and pass can be
# pointed at it later.
#
# It is a quick start, not the last key anyone needs. Someone who wants more
# (a passphrase, an offline primary key, subkeys on a YubiKey) makes a new
# key whenever they like. gpg signs with the first secret key in the keyring
# unless told otherwise, so that key then goes in ~/.gnupg/gpg.conf as
# `default-key <fingerprint>`, or this one is deleted.
#
# It has no passphrase and never expires, so it is there without a dialog at
# every use or a renewal to remember. Anyone who gets a copy of ~/.gnupg can
# sign as you with it. gpg --change-passphrase <fingerprint> adds a
# passphrase later, and gpg --quick-set-expire <fingerprint> 2y an expiry.
#
# The name and email come from git config (user.name, user.email). When git
# has none, the terminal the Conf menu opens asks. With no terminal to ask in
# it exits 75, which rack reads as "not finished" (rack/lib/features.sh).
#
# A user who already has a secret key keeps it, and nothing is made. gnupg
# itself is always there: pacman depends on it. rack/features.json runs this
# as setup and refuses to remove the feature, because a deleted secret key
# can't be brought back.

set -euo pipefail

PENDING=75
ALGO=future-default
EXPIRE=never

die() {
    printf 'gpg: %s\n' "$*" >&2
    exit 1
}

# The first secret key's fingerprint, if there is one. Captured whole rather
# than piped into grep -q (see fingerprint/install.sh's listing).
secret_key() {
    local keys
    keys=$(gpg --batch --list-secret-keys --with-colons 2>/dev/null) || true
    awk -F: '$1 == "sec" { sec = 1; next } sec && $1 == "fpr" { print $10; exit }' <<<"$keys"
}

# The account's full name from /etc/passwd, or the login name without one.
account_name() {
    local gecos
    gecos=$(getent passwd "$(id -un)" | cut -d: -f5)
    gecos=${gecos%%,*}
    printf '%s\n' "${gecos:-$(id -un)}"
}

# Sets USER_ID, rather than printing it, so its prompts reach the terminal.
identity() {
    local name email answer
    name=$(git config --global user.name 2>/dev/null) || true
    email=$(git config --global user.email 2>/dev/null) || true
    if [[ -z $name || -z $email ]]; then
        if ! [[ -t 0 && -t 1 ]]; then
            printf 'gpg: needs a name and email for the key. Set git config --global user.name and\n' >&2
            printf 'user.email, or run rack features on gpg in a terminal to be asked.\n' >&2
            exit "$PENDING"
        fi
        printf 'The key carries a name and an email, shown to whoever checks what it signed.\n'
        name=${name:-$(account_name)}
        read -r -p "Name [$name]: " answer
        name=${answer:-$name}
        read -r -p "Email${email:+ [$email]} (empty for none): " answer
        email=${answer:-$email}
    fi
    [[ -n $name ]] || die "the key needs a name"
    [[ $name$email != *[\<\>]* ]] || die "the name and email can't contain < or >"
    USER_ID="$name${email:+ <$email>}"
}

main() {
    local fpr
    command -v gpg >/dev/null || die "gnupg is not installed"
    fpr=$(secret_key)
    if [[ -n $fpr ]]; then
        printf 'you already have a secret key (%s); making no other\n' "$fpr"
        return 0
    fi

    identity
    printf 'making a key for %s\n' "$USER_ID"
    gpg --batch --yes --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "$USER_ID" "$ALGO" default "$EXPIRE"

    fpr=$(secret_key)
    [[ -n $fpr ]] || die "gpg made no key"
    gpg --list-secret-keys "$fpr"
    printf 'gpg --armor --export %s prints the public key to hand out.\n' "$fpr"
    printf 'The revocation certificate is %s/openpgp-revocs.d/%s.rev: keep a copy off this machine.\n' \
        "${GNUPGHOME:-$HOME/.gnupg}" "$fpr"
}

main "$@"
