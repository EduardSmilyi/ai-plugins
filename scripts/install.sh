#!/usr/bin/env bash
# Downloads claude-local-agent from GitHub and runs its setup on Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/EduardSmilyi/claude-local-agent/main/scripts/install.sh | bash
#
# Options are those of setup.sh, passed after `bash -s --`.
# No clone or git is needed. The download is removed afterwards.

set -eu -o pipefail

# Everything runs from main, so that a truncated download executes nothing.
main() {
    url=https://github.com/EduardSmilyi/claude-local-agent/archive/refs/heads/main.tar.gz
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT

    curl -fsSL "$url" | tar -xz -C "$work" --strip-components=1 || {
        echo 'install: download failed.' >&2
        exit 1
    }

    # With `curl | bash`, stdin is this script. Give setup the terminal so that
    # it can ask its questions.
    if [ ! -t 0 ] && (: </dev/tty) 2>/dev/null; then
        bash "$work/scripts/setup.sh" "$@" </dev/tty
    else
        bash "$work/scripts/setup.sh" "$@"
    fi
}

main "$@"
