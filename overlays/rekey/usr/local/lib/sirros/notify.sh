#!/bin/sh
# SirrOS: desktop notification helpers (meant to be sourced, not executed).
#
# Sends notifications to the logged-in user's Phosh session from a root service,
# using the freedesktop Notifications D-Bus API through gdbus (already shipped
# with GNOME, no extra package). One notification is created and then UPDATED in
# place (same id), so the user sees a single entry with a running timer.
#
# Everything is best effort: a failure here must never affect the caller.
# Set SIRROS_NOTIFY_DEBUG=1 to see what gdbus answers.
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
SIRROS_EXPLAIN="Generating a new unique encryption key for your disk in the background, keep the charger connected."

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

# Last cryptsetup percentage found in SIRROS_PROGRESS_FILE ("12.3%"), or nothing.
sirros_progress_pct() {
    [ -r "${SIRROS_PROGRESS_FILE:-}" ] || return 0
    tail -n 50 "$SIRROS_PROGRESS_FILE" 2>/dev/null \
        | sed -n 's/.*Progress:[[:space:]]*\([0-9][0-9.]*%\).*/\1/p' | tail -n 1
}

# Run one org.freedesktop.Notifications method as the session user.
# Needs SIRROS__NAME and SIRROS__BUS (set by sirros_notify).
sirros__call() {
    if [ "$(id -u)" -eq 0 ]; then
        set -- runuser -u "$SIRROS__NAME" -- "$@"
    fi
    env DBUS_SESSION_BUS_ADDRESS="unix:path=$SIRROS__BUS" \
        gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications --method "$@"
}

# sirros_notify SUMMARY BODY [URGENCY]     urgency: 0 low, 1 normal, 2 critical
# Creates the notification the first time and replaces it on later calls.
sirros_notify() {
    info=$(sirros_session_user)
    [ -n "$info" ] || return 1
    uid=${info%% *}
    SIRROS__NAME=${info#* }
    SIRROS__BUS="${SIRROS_RUNDIR:-/run}/user/$uid/bus"
    [ -S "$SIRROS__BUS" ] || return 1

    rid=0
    [ -r "$SIRROS_NOTIFY_IDFILE" ] && rid=$(cat "$SIRROS_NOTIFY_IDFILE" 2>/dev/null)
    case "$rid" in ''|*[!0-9]*) rid=0 ;; esac

    err=/dev/null
    [ -n "${SIRROS_NOTIFY_DEBUG:-}" ] && err=/dev/stderr

    out=$(sirros__call org.freedesktop.Notifications.Notify \
        "SirrOS" "$rid" "$SIRROS_NOTIFY_ICON" "'$1'" "'$2'" "[]" \
        "{'urgency': <byte ${3:-1}>, 'resident': <true>}" 0 2>"$err")
    rc=$?
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
        title="Securing your disk  $(sirros_fmt_elapsed "$el")"
        [ -n "$pct" ] && title="$title  ($pct)"
        sirros_notify "$title" "$SIRROS_EXPLAIN" "$urg"
        first=0
        sleep "$interval"
    done
}

# Forget the notification id so the next run starts a fresh notification.
sirros_notify_reset() { rm -f "$SIRROS_NOTIFY_IDFILE"; }
