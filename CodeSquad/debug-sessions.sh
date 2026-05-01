#!/bin/bash
# Diagnostic dump: what CodeSquad's scanner sees

echo "=== Claude Processes ==="
echo ""
for pid in $(pgrep -x claude 2>/dev/null); do
    execpath=$(ps -p "$pid" -o command= 2>/dev/null | head -1)
    cwd=$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | grep '^n' | sed 's/^n//')
    if [[ "$execpath" == *"native-binary"* ]]; then
        source="VS Code"
    else
        source="Terminal"
    fi
    dirname=$(basename "$cwd" 2>/dev/null)
    echo "PID $pid"
    echo "  Source:  $source"
    echo "  CWD:     $cwd"
    echo "  Dirname: $dirname"
    echo "  Exec:    $execpath"
    echo ""
done

echo "=== VS Code Windows (AppleScript) ==="
echo ""
osascript -e '
tell application "System Events"
    set apps to every process whose name contains "Code" or name contains "Cursor"
    repeat with a in apps
        set n to name of a
        set p to unix id of a
        log "App: " & n & " (PID " & p & ")"
        try
            repeat with w in (every window of a)
                log "  Window: " & (name of w)
            end repeat
        on error
            log "  (no windows found)"
        end try
    end repeat
end tell
' 2>&1 | grep -v "^$"

echo ""
echo "=== Match Analysis ==="
echo ""

# Collect VS Code window titles (zsh-compatible)
titles=()
while IFS= read -r line; do
    [[ -n "$line" ]] && titles+=("$line")
done < <(osascript -e '
tell application "System Events"
    set apps to every process whose name contains "Code" or name contains "Cursor"
    repeat with a in apps
        try
            repeat with w in (every window of a)
                log (name of w)
            end repeat
        end try
    end repeat
end tell
' 2>&1 | grep -v "^$")

parse_workspace_name() {
    local cleaned="$1"
    # Strip app suffixes
    for suffix in " — Visual Studio Code" " – Visual Studio Code" " — Code - Insiders" " – Code - Insiders" " — Cursor" " – Cursor"; do
        cleaned="${cleaned%$suffix}"
    done
    # Take last segment after em-dash
    if [[ "$cleaned" == *" — "* ]]; then
        cleaned="${cleaned##* — }"
    elif [[ "$cleaned" == *" – "* ]]; then
        cleaned="${cleaned##* – }"
    fi
    cleaned=$(echo "$cleaned" | xargs)
    # Strip parenthetical decorations like " (Workspace)"
    if [[ "$cleaned" == *" ("*")" ]]; then
        cleaned="${cleaned% (*}"
    fi
    # Strip bracket decorations like " [SSH: host]"
    if [[ "$cleaned" == *" ["*"]" ]]; then
        cleaned="${cleaned% \[*}"
    fi
    echo "$cleaned"
}

echo "VS Code workspace names (parsed from titles):"
for title in "${titles[@]}"; do
    wsname=$(parse_workspace_name "$title")
    echo "  '$wsname'  ←  $title"
done

echo ""
echo "Claude → Workspace matching:"
for pid in $(pgrep -x claude 2>/dev/null); do
    execpath=$(ps -p "$pid" -o command= 2>/dev/null | head -1)
    cwd=$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | grep '^n' | sed 's/^n//')
    dirname=$(basename "$cwd" 2>/dev/null)
    if [[ "$execpath" == *"native-binary"* ]]; then
        source="VS Code"
    else
        source="Terminal"
    fi

    matched=""
    for title in "${titles[@]}"; do
        wsname=$(parse_workspace_name "$title")
        lowname=$(echo "$wsname" | tr '[:upper:]' '[:lower:]')
        lowcwd=$(echo "$cwd" | tr '[:upper:]' '[:lower:]')
        if [[ "$lowcwd" == *"/$wsname/"* ]] || [[ "$lowcwd" == *"/$wsname" ]] || [[ "$lowcwd" == *"$lowname"* ]]; then
            matched="$wsname"
            break
        fi
    done

    if [[ -n "$matched" ]]; then
        echo "  PID $pid ($source) → MATCHED '$matched'  (cwd: $cwd)"
    else
        echo "  PID $pid ($source) → UNMATCHED (terminal)  (cwd: $cwd, dirname: $dirname)"
    fi
done
