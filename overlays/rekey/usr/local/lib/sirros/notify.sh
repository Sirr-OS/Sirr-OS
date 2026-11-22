#!/bin/sh
# SirrOS: desktop notification helpers (meant to be sourced, not executed).
#
# Sends notifications to the logged-in user's Phosh session from a root service,
# using the freedesktop Notifications D-Bus API through gdbus (already shipped
# with GNOME, no extra package). One notification is created and then UPDATED in
# place (same id), so the user sees a single entry with a running timer.
#
# Everything is best effort: a failure here must never affect the caller.
# Set SIRROS_NOTIFY_DEBUG=1 to see what gdbus answers; after a failed
# sirros_notify, SIRROS_NOTIFY_ERR says why.
#
# Optional inputs (set by sirros-rekey-after-login):
#   SIRROS_SESSION_UID / SIRROS_SESSION_NAME  session user already detected,
#                                             skips the loginctl lookup
#   SIRROS_PROGRESS_FILE                      log with cryptsetup "Progress:"
#                                             lines; the % is shown in the title
#
# NOTE: texts passed in must not contain single quotes (GVariant string syntax).

# Where the id of the notification is remembered between updates. /run is only
# writable by root; a normal user (e.g. when trying this by hand) gets its own
# runtime dir, otherwise every update would create a NEW notification.
if [ -z "${SIRROS_NOTIFY_IDFILE:-}" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        SIRROS_NOTIFY_IDFILE=/run/sirros-notify.id
    else
        SIRROS_NOTIFY_IDFILE="${XDG_RUNTIME_DIR:-/tmp}/sirros-notify.id"
    fi
fi
SIRROS_NOTIFY_ICON="${SIRROS_NOTIFY_ICON:-drive-harddisk-symbolic}"
SIRROS_EXPLAIN="${SIRROS_EXPLAIN:-Keep the phone on the charger while the new encryption key is created.}"

# Prints "UID NAME" of the active user session; prints nothing if there is none.
sirros_session_user() {
    if [ -n "${SIRROS_SESSION_UID:-}" ] && [ -n "${SIRROS_SESSION_NAME:-}" ]; then
        echo "$SIRROS_SESSION_UID $SIRROS_SESSION_NAME"
        return 0
    fi
    if [ "$(id -u)" -ne 0 ]; then
        echo "$(id -u) $(id -un)"
        return 0
    fi
    loginctl list-sessions --no-legend 2>/dev/null | while read -r id _; do
        [ "$(loginctl show-session "$id" -p Class --value 2>/dev/null)" = "user" ] || continue
        st=$(loginctl show-session "$id" -p State --value 2>/dev/null)
        if [ "$st" = "active" ] || [ "$st" = "online" ]; then
            echo "$(loginctl show-session "$id" -p User --value) $(loginctl show-session "$id" -p Name --value)"
            break
        fi
    done
}

# H:MM:SS from a number of seconds.
sirros_fmt_elapsed() {
    printf '%d:%02d:%02d' $(($1 / 3600)) $((($1 % 3600) / 60)) $(($1 % 60))
}

# Current re-encryption percentage ("34.5%"), or nothing if unknown.
# 1. last "Progress:" line in SIRROS_PROGRESS_FILE (written by sirros-rekey);
# 2. otherwise (root only) the live device-mapper tables. During an online
#    re-encryption cryptsetup maps "root" linearly onto "root-overlay", whose
#    table follows the LUKS2 segments (forward direction): first the part
#    already under the new key, then (only while a chunk is being written) a
#    linear hotzone, then the rest still under the old key.
sirros_progress_pct() {
    p=""
    if [ -r "${SIRROS_PROGRESS_FILE:-}" ]; then
        p=$(tail -n 50 "$SIRROS_PROGRESS_FILE" 2>/dev/null \
            | sed -n 's/.*Progress:[[:space:]]*\([0-9][0-9.]*%\).*/\1/p' | tail -n 1)
    fi
    if [ -z "$p" ] && [ "$(id -u)" -eq 0 ] && command -v dmsetup >/dev/null 2>&1; then
        p=$(dmsetup table "${SIRROS_DM_NAME:-root}-overlay" 2>/dev/null | sirros_dm_pct)
    fi
    printf '%s' "$p"
}

# Reads a dm table on stdin, prints the % already re-encrypted (see above).
# One single target means nothing to measure (not running, or finished).
sirros_dm_pct() {
    awk '{t += $2} NR == 1 {d = ($3 == "crypt") ? $2 : 0}
         END {if (NR > 1 && t > 0) printf "%.1f%%", d * 100 / t}'
}

# Run one org.freedesktop.Notifications method as the session user.
# Needs SIRROS__NAME and SIRROS__BUS (set by sirros_notify).
sirros__call() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$SIRROS__NAME" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$SIRROS__BUS" \
            gdbus call --session --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications --method "$@"
    else
        env DBUS_SESSION_BUS_ADDRESS="unix:path=$SIRROS__BUS" \
            gdbus call --session --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications --method "$@"
    fi
}

# sirros_notify SUMMARY BODY [URGENCY] [PERCENT]
#   urgency: 0 low, 1 normal, 2 critical
#   PERCENT (0-100) is sent as the standard "value" hint, which notification
#   servers that support it draw as a progress bar.
# Creates the notification the first time and replaces it on later calls.
sirros_notify() {
    SIRROS_NOTIFY_ERR=""
    info=$(sirros_session_user)
    [ -n "$info" ] || { SIRROS_NOTIFY_ERR="no active user session"; return 1; }
    uid=${info%% *}
    SIRROS__NAME=${info#* }
    SIRROS__BUS="${SIRROS_RUNDIR:-/run}/user/$uid/bus"
    [ -S "$SIRROS__BUS" ] || { SIRROS_NOTIFY_ERR="no session bus at $SIRROS__BUS"; return 1; }

    rid=0
    [ -r "$SIRROS_NOTIFY_IDFILE" ] && rid=$(cat "$SIRROS_NOTIFY_IDFILE" 2>/dev/null)
    case "$rid" in ''|*[!0-9]*) rid=0 ;; esac

    # stderr is kept so a failure can be explained (SIRROS_NOTIFY_ERR).
    out=$(sirros__call org.freedesktop.Notifications.Notify \
        "SirrOS" "$rid" "$SIRROS_NOTIFY_ICON" "'$1'" "'$2'" "[]" \
        "{'urgency': <byte ${3:-1}>, 'resident': <true>${4:+, 'value': <int32 $4>}}" 0 2>&1)
    rc=$?
    # shellcheck disable=SC2034  # read by the caller
    [ "$rc" -eq 0 ] || SIRROS_NOTIFY_ERR="as $SIRROS__NAME via $SIRROS__BUS: $(printf '%s' "$out" | tr '\n' ' ')"
    [ -n "${SIRROS_NOTIFY_DEBUG:-}" ] && echo "notify: rc=$rc out=$out" >&2

    # Answer looks like: (uint32 7,)
    nid=$(printf '%s' "$out" | sed -n 's/^(uint32 \([0-9][0-9]*\),).*/\1/p')
    if [ -n "$nid" ]; then
        # The server answered with a different id: the previous notification
        # was not replaced in place. Close it so only one entry stays visible.
        if [ "$rid" -ne 0 ] && [ "$nid" != "$rid" ]; then
            sirros__call org.freedesktop.Notifications.CloseNotification "$rid" \
                >/dev/null 2>&1
        fi
        echo "$nid" > "$SIRROS_NOTIFY_IDFILE" 2>/dev/null
    fi
    return "$rc"
}

# sirros_notify_progress PID [INTERVAL_SECONDS]
# While PID is alive, keep one notification updated with the elapsed time (and
# the cryptsetup percentage when known). The first banner is normal urgency;
# updates use SIRROS_UPDATE_URGENCY (default 0 = low) to avoid popping a new
# banner every minute.
sirros_notify_progress() {
    pid=$1
    interval=${2:-60}
    start=$(date +%s)
    first=1
    while kill -0 "$pid" 2>/dev/null; do
        el=$(($(date +%s) - start))
        if [ "$first" = 1 ]; then urg=1; else urg=${SIRROS_UPDATE_URGENCY:-0}; fi
        pct=$(sirros_progress_pct)
        ipct=${pct%%[.%]*}
        case "$ipct" in ''|*[!0-9]*) ipct="" ;; esac
        if [ -n "$ipct" ]; then
            title="Securing your disk $ipct%"
            body="$(sirros_bar "$ipct") $ipct% ($(sirros_fmt_elapsed "$el"))\\n$SIRROS_EXPLAIN"
        else
            title="Securing your disk"
            body="Starting... ($(sirros_fmt_elapsed "$el"))\\n$SIRROS_EXPLAIN"
        fi
        sirros_notify "$title" "$body" "$urg" "$ipct"
        first=0
        sleep "$interval"
    done
}

# Text progress bar, 12 cells, for servers that ignore the "value" hint.
sirros_bar() {
    n=$(($1 * 12 / 100)); b=""; i=0
    while [ "$i" -lt 12 ]; do
        if [ "$i" -lt "$n" ]; then b="$b▰"; else b="$b▱"; fi
        i=$((i + 1))
    done
    printf '%s' "$b"
}

# Forget the notification id so the next run starts a fresh notification.
sirros_notify_reset() { rm -f "$SIRROS_NOTIFY_IDFILE"; }
