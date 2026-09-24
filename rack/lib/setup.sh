# setup — is everything this desktop depends on actually installed?
#
# Checks every dependency listed in quickshell/main/DEPENDENCIES.md plus the
# tools rack itself needs. Reports found/missing; installs nothing.
#
# Ported from bin/orbit-setup. One entry left with orbit: stow. rack links
# through rig's link module, so the stow dependency is gone rather than
# renamed.

rig::load log check
rack::load features

RACK_MODULE_SUMMARY[setup]="check that every dependency is installed"
RACK_MODULE_ACTIONS[setup]="check json"
RACK_MODULE_STATUS[setup]="ready"
RACK_MODULE_TIER[setup]="general"

# name:binary pairs. The binary is what we actually probe for — several names
# differ from the command that provides them (quickshell -> qs, NetworkManager
# -> nmcli, WirePlumber -> wpctl, etc).

# Core shell won't function without these — DEPENDENCIES.md "Required", minus
# the coreutils shell tools (sh/cat/test/awk/sed/grep) which every target this
# repo cares about already ships.
declare -ga RACK_SETUP_REQUIRED=(
    "quickshell:qs"
    "Hyprland:hyprctl"
    "systemd:systemctl"
    "NetworkManager:nmcli"
    "iproute2:ip"
    "PipeWire:pipewire"
    "WirePlumber:wpctl"
    "UPower:upower"
    "BlueZ:bluetoothctl"
    "sudo:sudo"
    "pacman:pacman"
    "flatpak:flatpak"
    "wl-clipboard:wl-copy"
    "cliphist:cliphist"
    "brightnessctl:brightnessctl"
    "lua:lua"
    "zsh:zsh"
)

# Required by the config's *default* values — DEPENDENCIES.md says these are
# swappable (Theme.qml, etc), so a missing one here is a config change
# away from being fine, not a real blocker. No terminal is named: any of the
# terminal role's candidates will do, and `relay default list` is the check
# for which one resolves.
declare -ga RACK_SETUP_DEFAULT_CONFIG=(
    "awww:awww"
)

# Config degrades gracefully without these. The three hypr* daemons are the
# ones autostart.lua launches and hypridle.conf/hyprlock.conf configure, so a
# gap here is a feature that quietly never runs rather than a shell that fails
# to start — which is exactly the kind of thing this check exists to surface.
# yay is here, not a default-config value: flatpak (required) is the install
# source that has to work, and without yay the AUR is simply absent — its
# installer results, Apps › Update › Yay and rack update's AUR stage all skip it.
declare -ga RACK_SETUP_OPTIONAL=(
    "yay:yay"
    "hypridle:hypridle"
    "hyprlock:hyprlock"
    "hyprsunset:hyprsunset"
    "matugen:matugen"
    "grim:grim"
    "slurp:slurp"
    "hyprpicker:hyprpicker"
    "wf-recorder:wf-recorder"
    "procps-ng:pkill"
    "util-linux:rfkill"
    "psmisc:fuser"
    "voxtype-bin:voxtype"
    "wtype:wtype"
    "fzf:fzf"
    "zoxide:zoxide"
    "bat:bat"
    "playerctl:playerctl"
    "uwsm:uwsm"
    "gcc:cc"
    "npm:npm"
)

# What rack and relay need themselves, distinct from anything quickshell shells
# out to. flock is rig's lock module; stow is deliberately absent.
declare -ga RACK_SETUP_OWN=(
    "git:git"
    "jq:jq"
    "flock:flock"
)

: "${RACK_SETUP_NERD_FONT:=JetBrainsMono Nerd Font}"

rack::setup::__font_found() {
    # grep -q exits on the first match, which leaves fc-list writing into a
    # closed pipe: it dies of SIGPIPE with status 141, and under `set -o
    # pipefail` that 141 is the pipeline's status. The font then read as
    # missing on every machine that actually had it. Letting grep drain
    # fc-list costs a few milliseconds and keeps the status honest.
    rig::check::has fc-list && fc-list | grep -i -- "$RACK_SETUP_NERD_FONT" >/dev/null
}

# Prints one line per entry and reports (via return status) whether every entry
# in the group was found — never stops early, so a run always shows the full
# picture, not just the first gap.
rack::setup::__check_group() {
    local -n group=$1
    local entry name bin feature problems=0
    for entry in "${group[@]}"; do
        name=${entry%%:*}
        bin=${entry#*:}
        if rig::check::has "$bin"; then
            printf '  %-16s found (%s)\n' "$name" "$bin"
        elif feature=$(rack::features::off_owner "$bin"); then
            # Turned off with `rack features`, so its absence is a choice.
            printf '  %-16s not wanted (%s is off)\n' "$name" "$feature"
        else
            printf '  %-16s missing (%s not on PATH)\n' "$name" "$bin"
            problems=1
        fi
    done
    return $problems
}

rack::setup::json() {
    local -a groups=(
        RACK_SETUP_REQUIRED:required
        RACK_SETUP_DEFAULT_CONFIG:default_config
        RACK_SETUP_OPTIONAL:optional
        RACK_SETUP_OWN:rack_own
    )
    local g arrname category entry name bin found first=1
    printf '['
    for g in "${groups[@]}"; do
        arrname=${g%%:*}
        category=${g#*:}
        local -n arr=$arrname
        for entry in "${arr[@]}"; do
            name=${entry%%:*}
            bin=${entry#*:}
            rig::check::has "$bin" && found=true || found=false
            ((first)) || printf ','
            first=0
            printf '{"name":"%s","bin":"%s","category":"%s","found":%s}' "$name" "$bin" "$category" "$found"
        done
    done
    rack::setup::__font_found && found=true || found=false
    ((first)) || printf ','
    printf '{"name":"%s","bin":null,"category":"font","found":%s}' "$RACK_SETUP_NERD_FONT" "$found"
    printf ']\n'
}

rack::setup::check() {
    local problems=0

    printf 'required:\n'
    rack::setup::__check_group RACK_SETUP_REQUIRED || problems=1

    printf '\nrequired by default config values (swap the setting if missing):\n'
    rack::setup::__check_group RACK_SETUP_DEFAULT_CONFIG || true

    printf '\noptional (config degrades gracefully without these):\n'
    rack::setup::__check_group RACK_SETUP_OPTIONAL || true

    printf '\nrack and relay themselves:\n'
    rack::setup::__check_group RACK_SETUP_OWN || problems=1

    printf '\nfonts:\n'
    if rack::setup::__font_found; then
        printf '  %-16s found\n' "$RACK_SETUP_NERD_FONT"
    else
        printf '  %-16s missing\n' "$RACK_SETUP_NERD_FONT"
        problems=1
    fi

    return $problems
}

rack::setup::__default() {
    case ${1-} in
        '' | check) rack::setup::check ;;
        --json | json) rack::setup::json ;;
        *)
            rig::log::error "unknown argument '$1' (see: rack help setup)"
            return "$RIG_EX_USAGE"
            ;;
    esac
}

rack::setup::__usage() {
    cat <<'EOF'
  rack setup            report which dependencies are present
  rack setup --json     machine-readable

Checks every dependency listed in quickshell/main/DEPENDENCIES.md plus the
tools rack and relay need themselves. Reports found/missing; installs
nothing.

Exit status is non-zero if anything in the "required" or "rack and relay
themselves" groups is missing. Defaults and optional extras are only
reported, never fail the check.
EOF
}
