#!/bin/bash
# shadow - manage untracked files across git branches (git-backed storage)

set -e

SHADOW_DIR="${SHADOW_DIR:-$HOME/.git-shadow}"

# Get repo ID from origin URL or path
repo_id() {
    local origin=$(git remote get-url origin 2>/dev/null || pwd)
    echo -n "$origin" | sha256sum | cut -c1-16
}

shadow_path() {
    echo "$SHADOW_DIR/$(repo_id)"
}

current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD
}

# Run git in shadow repo
sgit() {
    git -C "$(shadow_path)" "$@"
}

cmd_init() {
    local sp=$(shadow_path)

    if [[ -d "$sp/.git" ]]; then
        echo "Shadow already initialized at $sp"
        return
    fi

    mkdir -p "$sp"
    git -C "$sp" init -q
    touch "$sp/.shadowconfig"
    git -C "$sp" add .shadowconfig
    git -C "$sp" commit -q -m "init shadow"

    echo "Initialized shadow at $sp"
}

cmd_add() {
    local sp=$(shadow_path)
    local branch=$(current_branch)
    local added_files=()
    local failed=0

    [[ $# -eq 0 ]] && { echo "Usage: shadow add <file|dir>..."; exit 1; }

    # Ensure branch exists
    _ensure_branch "$branch"
    sgit checkout -q "$branch"

    # Process each argument
    for path in "$@"; do
        if [[ -f "$path" ]]; then
            # Single file
            _add_single_file "$path" "$sp"
            added_files+=("$path")
        elif [[ -d "$path" ]]; then
            # Directory - add all files recursively
            while IFS= read -r -d '' file; do
                _add_single_file "$file" "$sp"
                added_files+=("$file")
            done < <(find "$path" -type f -print0)
        else
            echo "File not found: $path" >&2
            failed=1
        fi
    done

    [[ $failed -eq 1 ]] && exit 1

    # Commit all changes
    sgit add -A
    if sgit diff --cached --quiet; then
        echo "No new files to add"
    else
        sgit commit -q -m "add files" || true
        if [[ ${#added_files[@]} -eq 1 ]]; then
            echo "Added ${added_files[0]}"
        else
            echo "Added ${#added_files[@]} file(s)"
        fi
    fi
}

_add_single_file() {
    local file="$1"
    local sp="$2"

    # Add to .shadowconfig if not present
    grep -qxF "$file" "$sp/.shadowconfig" 2>/dev/null || echo "$file" >> "$sp/.shadowconfig"

    # Copy file
    mkdir -p "$sp/$(dirname "$file")"
    cp "$file" "$sp/$file"
}

cmd_remove() {
    local file="$1"
    local sp=$(shadow_path)

    # Remove from .shadowconfig
    grep -vxF "$file" "$sp/.shadowconfig" > "$sp/.shadowconfig.tmp"
    mv "$sp/.shadowconfig.tmp" "$sp/.shadowconfig"

    # Remove file
    rm -f "$sp/$file"

    # Commit
    sgit add -A
    sgit commit -q -m "remove $file" || true

    echo "Removed $file"
}

cmd_save() {
    local sp=$(shadow_path)
    local branch=$(current_branch)
    local msg="${1:-save $branch}"

    _ensure_branch "$branch"
    sgit checkout -q "$branch"

    # Copy tracked files
    while IFS= read -r file; do
        [[ -z "$file" || "$file" == \#* ]] && continue
        if [[ -f "$file" ]]; then
            mkdir -p "$sp/$(dirname "$file")"
            cp "$file" "$sp/$file"
        fi
    done < "$sp/.shadowconfig"

    # Commit if changes
    sgit add -A
    if sgit diff --cached --quiet; then
        echo "No changes"
    else
        sgit commit -q -m "$msg"
        echo "Saved to $branch"
    fi
}

cmd_restore() {
    local sp=$(shadow_path)
    local branch=$(current_branch)

    # Use branch or fall back to main
    if sgit show-ref -q "refs/heads/$branch"; then
        sgit checkout -q "$branch"
    else
        sgit checkout -q main 2>/dev/null || sgit checkout -q master
        echo "No shadow for '$branch', using main"
    fi

    # Copy tracked files back
    while IFS= read -r file; do
        [[ -z "$file" || "$file" == \#* ]] && continue
        if [[ -f "$sp/$file" ]]; then
            mkdir -p "$(dirname "$file")"
            cp "$sp/$file" "$file"
            echo "Restored $file"
        fi
    done < "$sp/.shadowconfig"
}

cmd_status() {
    local sp=$(shadow_path)
    local branch=$(current_branch)

    echo "Branch: $branch"
    echo

    while IFS= read -r file; do
        [[ -z "$file" || "$file" == \#* ]] && continue

        local here=$([[ -f "$file" ]] && echo 1 || echo 0)
        local there=$([[ -f "$sp/$file" ]] && echo 1 || echo 0)

        if [[ $here -eq 0 && $there -eq 0 ]]; then
            printf "  \e[31mmissing\e[0m     %s\n" "$file"
        elif [[ $here -eq 1 && $there -eq 0 ]]; then
            printf "  \e[32mnew\e[0m         %s\n" "$file"
        elif [[ $here -eq 0 && $there -eq 1 ]]; then
            printf "  \e[31mdeleted\e[0m     %s\n" "$file"
        elif diff -q "$file" "$sp/$file" >/dev/null 2>&1; then
            printf "  unchanged   %s\n" "$file"
        else
            printf "  \e[33mmodified\e[0m    %s\n" "$file"
        fi
    done < "$sp/.shadowconfig"
}

cmd_ls() {
    local sp=$(shadow_path)

    if [[ "$1" == "--branches" ]]; then
        sgit branch
    else
        cat "$sp/.shadowconfig" 2>/dev/null | grep -v '^#' | grep -v '^$'
    fi
}

cmd_diff() {
    local sp=$(shadow_path)

    if [[ -n "$1" && -n "$2" ]]; then
        # Between branches
        sgit diff "$1" "$2"
    else
        # Local vs shadow
        while IFS= read -r file; do
            [[ -z "$file" || "$file" == \#* ]] && continue
            [[ -f "$file" && -f "$sp/$file" ]] && diff -u "$sp/$file" "$file" --label "shadow:$file" --label "local:$file" || true
        done < "$sp/.shadowconfig"
    fi
}

cmd_log() {
    local file="$1"
    local count="${2:-10}"

    if [[ -n "$file" ]]; then
        sgit log --oneline -n "$count" -- "$file"
    else
        sgit log --oneline -n "$count"
    fi
}

cmd_sync() {
    local from="${1:-main}"
    local sp=$(shadow_path)
    local branch=$(current_branch)

    _ensure_branch "$branch"
    sgit checkout -q "$branch"

    # Checkout files from source branch
    while IFS= read -r file; do
        [[ -z "$file" || "$file" == \#* ]] && continue
        sgit checkout "$from" -- "$file" 2>/dev/null || true
    done < "$sp/.shadowconfig"

    sgit commit -q -m "sync from $from" || true
    cmd_restore

    echo "Synced from $from"
}

cmd_checkout() {
    local ref="$1"
    local file="$2"
    local sp=$(shadow_path)

    if [[ -n "$file" ]]; then
        # Restore single file from ref
        sgit show "$ref:$file" > "$file"
        echo "Restored $file from $ref"
    else
        # Checkout entire ref
        sgit checkout "$ref"
        cmd_restore
    fi
}

cmd_push() {
    local remote="${1:-origin}"
    sgit push "$remote" --all
    echo "Pushed to $remote"
}

cmd_pull() {
    local remote="${1:-origin}"
    sgit pull "$remote"
    cmd_restore
    echo "Pulled from $remote"
}

cmd_remote() {
    case "$1" in
        add)    sgit remote add "$2" "$3"; echo "Added remote $2" ;;
        remove) sgit remote remove "$2"; echo "Removed remote $2" ;;
        list|"") sgit remote -v ;;
        *)      echo "Usage: shadow remote [add|remove|list]"; exit 1 ;;
    esac
}

cmd_gc() {
    sgit gc --aggressive --prune=now
    echo "Garbage collection complete"
}

cmd_install_hooks() {
    local hook=".git/hooks/post-checkout"

    cat > "$hook" << 'EOF'
#!/bin/bash
if [ "$3" = "1" ]; then
    shadow save 2>/dev/null || true
    shadow restore 2>/dev/null || true
fi
EOF
    chmod +x "$hook"
    echo "Installed post-checkout hook"
}

cmd_uninstall_hooks() {
    rm -f ".git/hooks/post-checkout"
    echo "Removed hooks"
}

# Ensure shadow branch exists (create from main if not)
_ensure_branch() {
    local branch="$1"
    if ! sgit show-ref -q "refs/heads/$branch"; then
        local base=$(sgit symbolic-ref --short HEAD 2>/dev/null || echo main)
        sgit checkout -q -b "$branch" "$base" 2>/dev/null || sgit checkout -q -b "$branch"
    fi
}

# Main
case "${1:-}" in
    init)             cmd_init ;;
    add)              shift; cmd_add "$@" ;;
    remove|rm)        cmd_remove "$2" ;;
    save)             shift; cmd_save "$*" ;;
    restore)          cmd_restore ;;
    status|st)        cmd_status ;;
    ls)               cmd_ls "$2" ;;
    diff)             cmd_diff "$2" "$3" ;;
    log)              cmd_log "$2" "$3" ;;
    sync)             cmd_sync "$2" ;;
    checkout|co)      cmd_checkout "$2" "$3" ;;
    push)             cmd_push "$2" ;;
    pull)             cmd_pull "$2" ;;
    remote)           shift; cmd_remote "$@" ;;
    gc)               cmd_gc ;;
    install-hooks)    cmd_install_hooks ;;
    uninstall-hooks)  cmd_uninstall_hooks ;;
    *)
        cat << 'EOF'
Usage: shadow <command>

Setup:
  init                Initialize shadow for current repo
  install-hooks       Auto save/restore on branch switch
  uninstall-hooks     Remove hooks

Core:
  add <file>          Track a file
  remove <file>       Untrack a file
  save [message]      Save tracked files
  restore             Restore tracked files
  status              Show file status

Branch:
  ls [--branches]     List files or branches
  diff [b1] [b2]      Show differences
  sync [branch]       Sync from branch (default: main)

History:
  log [file]          Show commit history
  checkout <ref> [f]  Restore version

Remote:
  remote add <n> <u>  Add remote
  remote remove <n>   Remove remote
  remote list         List remotes
  push [remote]       Push to remote
  pull [remote]       Pull from remote

Maintenance:
  gc                  Garbage collect
EOF
        exit 1
        ;;
esac
