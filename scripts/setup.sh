#!/usr/bin/env bash
# Installs claude-local and the local-agent skill on Linux and macOS.
#
#   bash scripts/setup.sh [--configure] [--install-dir DIR]
#
# claude-local is placed in the folder that holds `claude`, the skill in
# ~/.claude/skills/local-agent and the settings in ~/.claude/local-agent.
# Replaced files are kept with a .bak suffix. PATH is never changed.
#
#   --configure        ask for the settings again, even if they are filled in
#   --install-dir DIR  install claude-local into DIR instead

set -eu

die() {
    echo "setup: $*" >&2
    exit 1
}

configure=
install_dir=
while [ $# -gt 0 ]; do
    case $1 in
        --configure) configure=1 ;;
        --install-dir)
            [ $# -ge 2 ] || die '--install-dir needs a folder.'
            install_dir=$2
            shift
            ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

case $(uname -s) in
    MINGW* | MSYS* | CYGWIN*) die 'on Windows run scripts/setup.ps1 from PowerShell.' ;;
esac

repo=$(cd "$(dirname "$0")/.." && pwd)
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
settings=$config_dir/local-agent/settings.json
old_settings=$config_dir/settings-local.json

if command -v jq >/dev/null 2>&1; then
    json=jq
elif command -v node >/dev/null 2>&1; then
    json=node
elif python3 -c '' >/dev/null 2>&1; then
    json=python3
else
    die 'jq, node or python3 is needed. Install one and run setup again.'
fi

if [ -z "$install_dir" ]; then
    claude=$(command -v claude || true)
    case $claude in
        */*) install_dir=$(cd "$(dirname "$claude")" && pwd) ;;
        *) die 'claude was not found on PATH. Install Claude Code, or pass --install-dir.' ;;
    esac
fi

# install_file LABEL SOURCE TARGET
install_file() {
    if [ ! -e "$3" ]; then
        cp "$2" "$3"
        echo "$1: installed at $3"
    elif cmp -s "$2" "$3"; then
        echo "$1: up to date at $3"
    else
        cp "$3" "$3.bak"
        cp "$2" "$3"
        echo "$1: updated $3 (previous copy: $3.bak)"
    fi
}

mkdir -p "$install_dir" 2>/dev/null || true
[ -d "$install_dir" ] && [ -w "$install_dir" ] ||
    die "$install_dir is not writable. Pass --install-dir with a folder on your PATH."
install_file launcher "$repo/scripts/claude-local" "$install_dir/claude-local"
chmod +x "$install_dir/claude-local"
case :$PATH: in
    *:"$install_dir":*) ;;
    *) echo "path: $install_dir is NOT on PATH. Add it, then restart your terminal." ;;
esac

mkdir -p "$config_dir/skills/local-agent"
install_file skill "$repo/skills/local-agent/SKILL.md" "$config_dir/skills/local-agent/SKILL.md"

# The settings hold a token: keep everything written from here private.
umask 077
mkdir -p "$config_dir/local-agent"
if [ ! -e "$settings" ] && [ -f "$old_settings" ]; then
    mv "$old_settings" "$settings"
    chmod 600 "$settings"
    echo "settings: moved $old_settings to $settings"
fi

# Prints the "env" block of a JSON file as NAME=VALUE lines.
read_env() {
    case $json in
        jq) jq -r '(.env // {}) | to_entries[] | "\(.key)=\(.value)"' "$1" ;;
        node) node -e '
            const text = require("fs").readFileSync(process.argv[1], "utf8").replace(/^﻿/, "");
            for (const [k, v] of Object.entries(JSON.parse(text).env || {})) console.log(k + "=" + v);
        ' "$1" ;;
        python3) python3 -c '
import json, sys
for k, v in (json.load(open(sys.argv[1], encoding="utf-8-sig")).get("env") or {}).items():
    print("%s=%s" % (k, v))
' "$1" ;;
    esac 2>/dev/null
}

# Prints file $1 with the NAME=VALUE lines from stdin merged into "env".
# Values arrive on stdin so that the token never shows up in a process list.
merge_env() {
    case $json in
        jq) jq -R -s --slurpfile base "$1" '
            [split("\n")[] | select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.*)$")]
            | from_entries as $new
            | $base[0] | .env = ((.env // {}) + $new)' ;;
        node) node -e '
            const fs = require("fs");
            const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8").replace(/^﻿/, ""));
            data.env = data.env || {};
            for (const line of fs.readFileSync(0, "utf8").split("\n")) {
                const i = line.indexOf("=");
                if (i > 0) data.env[line.slice(0, i)] = line.slice(i + 1);
            }
            console.log(JSON.stringify(data, null, 2));
        ' "$1" ;;
        python3) python3 -c '
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8-sig"))
env = data.setdefault("env", {})
for line in sys.stdin.read().split("\n"):
    k, sep, v = line.partition("=")
    if sep:
        env[k] = v
print(json.dumps(data, indent=2))
' "$1" ;;
    esac
}

base=$repo/settings.template.json
[ -f "$settings" ] && base=$settings
current=$(read_env "$base") || die "$base is not valid JSON. Fix or delete it and run setup again."

# Current value of $1, or nothing if it is missing or still a <placeholder>.
value_of() {
    printf '%s\n' "$current" | sed -n "s/^$1=//p" | sed -n '/^<.*>$/!p'
}

filled=
[ -n "$(value_of ANTHROPIC_BASE_URL)" ] && [ -n "$(value_of ANTHROPIC_MODEL)" ] && filled=1

if [ -z "$configure" ] && [ ! -t 0 ]; then
    if [ ! -f "$settings" ]; then
        cp "$base" "$settings"
        chmod 600 "$settings"
    fi
    if [ -n "$filled" ]; then
        echo "settings: $settings kept"
    else
        echo "settings: $settings is not filled in. Run setup in a terminal to answer the questions."
    fi
    exit 0
fi

if [ -z "$configure" ] && [ -n "$filled" ]; then
    printf 'Settings already exist at %s. Change them? [y/N] ' "$settings"
    read -r reply || reply=
    case $reply in
        [Yy]*) ;;
        *)
            echo "settings: $settings kept"
            exit 0
            ;;
    esac
fi

# ask PROMPT DEFAULT PATTERN -> sets $answer
ask() {
    while :; do
        if [ -n "$2" ]; then printf '%s [%s]: ' "$1" "$2"; else printf '%s: ' "$1"; fi
        read -r answer || die 'input ended; settings were not changed.'
        answer=${answer:-$2}
        [[ $answer =~ $3 ]] && return 0
        echo '  Not a valid value, try again.'
    done
}

echo
echo 'Local model settings (press Enter to keep the value in brackets).'
ask 'Server URL, e.g. http://localhost:1234' "$(value_of ANTHROPIC_BASE_URL)" '^https?://.+'
url=$answer

old_token=$(value_of ANTHROPIC_AUTH_TOKEN)
if [ -n "$old_token" ]; then hint='Enter keeps the current one'; else hint='Enter if the server needs none'; fi
printf 'Server token, input hidden (%s): ' "$hint"
read -r -s token || die 'input ended; settings were not changed.'
echo
token=${token:-${old_token:-local}}

old_model=$(value_of ANTHROPIC_MODEL)
ask 'Model name' "$old_model" '^[^<[:space:]]+$'
model=$answer

context=$(value_of CLAUDE_CODE_MAX_CONTEXT_TOKENS)
ask 'Context window, tokens' "${context:-204800}" '^[1-9][0-9]*$'
context=$answer

output=$(value_of CLAUDE_CODE_MAX_OUTPUT_TOKENS)
ask 'Max output, tokens' "${output:-25600}" '^[1-9][0-9]*$'
output=$answer

new_values() {
    printf '%s=%s\n' \
        ANTHROPIC_BASE_URL "$url" \
        ANTHROPIC_AUTH_TOKEN "$token" \
        ANTHROPIC_MODEL "$model" \
        CLAUDE_CODE_MAX_CONTEXT_TOKENS "$context" \
        CLAUDE_CODE_MAX_OUTPUT_TOKENS "$output"
    for name in ANTHROPIC_SMALL_FAST_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL \
        ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do
        # Keep a hand-set per-tier model unless the main model changed.
        if [ "$model" != "$old_model" ] || [ -z "$(value_of "$name")" ]; then
            printf '%s=%s\n' "$name" "$model"
        fi
    done
}

tmp=$settings.tmp
trap 'rm -f "$tmp"' EXIT
new_values | merge_env "$base" >"$tmp" || die 'could not write the settings.'
mv "$tmp" "$settings"
chmod 600 "$settings"
echo "settings: saved to $settings"
