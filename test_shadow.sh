#!/bin/bash
# Tests for shadow.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHADOW="$SCRIPT_DIR/shadow.sh"
TEST_DIR=""
ORIGINAL_HOME="$HOME"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

setup() {
    TEST_DIR=$(mktemp -d)
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"
    export SHADOW_DIR="$HOME/.git-shadow"

    # Create test git repo
    mkdir -p "$TEST_DIR/repo"
    cd "$TEST_DIR/repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial"
}

teardown() {
    cd "$SCRIPT_DIR"
    export HOME="$ORIGINAL_HOME"
    [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo -e "${RED}FAIL${NC}: $msg"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
    return 0
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${RED}FAIL${NC}: $msg"
        echo "  Expected to contain: $needle"
        echo "  Actual: $haystack"
        return 1
    fi
    return 0
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-File should exist: $file}"
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}FAIL${NC}: $msg"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local file="$1"
    local msg="${2:-File should not exist: $file}"
    if [[ -f "$file" ]]; then
        echo -e "${RED}FAIL${NC}: $msg"
        return 1
    fi
    return 0
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))

    setup

    if "$test_name"; then
        echo -e "${GREEN}PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}: $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    teardown
}

# Test: init creates shadow repo
test_init() {
    local output=$("$SHADOW" init)
    assert_contains "$output" "Initialized shadow" "init should show success message" || return 1
    assert_file_exists "$SHADOW_DIR"/*/.git/config "shadow .git should exist" || return 1
    assert_file_exists "$SHADOW_DIR"/*/.shadowconfig ".shadowconfig should exist" || return 1
}

# Test: init is idempotent
test_init_idempotent() {
    "$SHADOW" init
    local output=$("$SHADOW" init)
    assert_contains "$output" "already initialized" "second init should say already initialized" || return 1
}

# Test: add tracks a file
test_add() {
    "$SHADOW" init
    echo "secret=value" > .env
    local output=$("$SHADOW" add .env)
    assert_contains "$output" "Added .env" "add should confirm file added" || return 1

    # Check .shadowconfig contains file
    local config=$(cat "$SHADOW_DIR"/*/.shadowconfig)
    assert_contains "$config" ".env" ".shadowconfig should contain .env" || return 1
}

# Test: add fails for non-existent file
test_add_missing_file() {
    "$SHADOW" init
    if "$SHADOW" add nonexistent.txt 2>&1; then
        echo "add should fail for missing file"
        return 1
    fi
    return 0
}

# Test: remove untracks a file
test_remove() {
    "$SHADOW" init
    echo "secret=value" > .env
    echo "other=value" > other.txt
    "$SHADOW" add .env
    "$SHADOW" add other.txt

    # Verify files are in config before remove
    local config_before=$(cat "$SHADOW_DIR"/*/.shadowconfig)
    assert_contains "$config_before" ".env" ".shadowconfig should contain .env before remove" || return 1
    assert_contains "$config_before" "other.txt" ".shadowconfig should contain other.txt before remove" || return 1

    "$SHADOW" remove .env

    # Check .shadowconfig doesn't contain .env but still has other.txt
    local config_after=$(cat "$SHADOW_DIR"/*/.shadowconfig)
    if [[ "$config_after" == *".env"* ]]; then
        echo ".shadowconfig should not contain .env after remove"
        return 1
    fi
    assert_contains "$config_after" "other.txt" ".shadowconfig should still contain other.txt" || return 1
    return 0
}

# Test: save commits tracked files
test_save() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    echo "v2" > .env
    local output=$("$SHADOW" save "update env")
    assert_contains "$output" "Saved to" "save should confirm" || return 1
}

# Test: save with no changes
test_save_no_changes() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env
    local output=$("$SHADOW" save)
    assert_contains "$output" "No changes" "save with no changes should report" || return 1
}

# Test: restore brings back files
test_restore() {
    "$SHADOW" init
    echo "secret=value" > .env
    "$SHADOW" add .env

    rm .env
    assert_file_not_exists ".env" "file should be deleted" || return 1

    local output=$("$SHADOW" restore)
    assert_contains "$output" "Restored .env" "restore should confirm" || return 1
    assert_file_exists ".env" "file should be restored" || return 1

    local content=$(cat .env)
    assert_eq "secret=value" "$content" "content should match" || return 1
}

# Test: status shows file states
test_status() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    local output=$("$SHADOW" status)
    assert_contains "$output" "unchanged" "status should show unchanged" || return 1

    echo "v2" > .env
    output=$("$SHADOW" status)
    assert_contains "$output" "modified" "status should show modified" || return 1
}

# Test: status shows new files
test_status_new() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    # Manually add to config without copying
    echo "newfile.txt" >> "$SHADOW_DIR"/*/.shadowconfig
    echo "content" > newfile.txt

    local output=$("$SHADOW" status)
    assert_contains "$output" "new" "status should show new file" || return 1
}

# Test: ls lists tracked files
test_ls() {
    "$SHADOW" init
    echo "v1" > .env
    echo "v2" > config.yaml
    "$SHADOW" add .env
    "$SHADOW" add config.yaml

    local output=$("$SHADOW" ls)
    assert_contains "$output" ".env" "ls should list .env" || return 1
    assert_contains "$output" "config.yaml" "ls should list config.yaml" || return 1
}

# Test: ls --branches lists branches
test_ls_branches() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    local output=$("$SHADOW" ls --branches)
    assert_contains "$output" "main" "ls --branches should show main" || return 1
}

# Test: diff shows changes
test_diff() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    echo "v2" > .env
    local output=$("$SHADOW" diff)
    assert_contains "$output" "v1" "diff should show old value" || return 1
    assert_contains "$output" "v2" "diff should show new value" || return 1
}

# Test: branch-specific storage
test_branch_isolation() {
    "$SHADOW" init
    echo "main-value" > .env
    "$SHADOW" add .env

    # Create and switch to feature branch
    git checkout -q -b feature
    echo "feature-value" > .env
    "$SHADOW" save

    # Switch back to main
    git checkout -q main
    "$SHADOW" restore

    local content=$(cat .env)
    assert_eq "main-value" "$content" "main branch should have main-value" || return 1

    # Switch to feature
    git checkout -q feature
    "$SHADOW" restore

    content=$(cat .env)
    assert_eq "feature-value" "$content" "feature branch should have feature-value" || return 1
}

# Test: log shows history
test_log() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    echo "v2" > .env
    "$SHADOW" save "second commit"

    local output=$("$SHADOW" log)
    assert_contains "$output" "second commit" "log should show commit message" || return 1
}

# Test: sync copies from another branch
test_sync() {
    "$SHADOW" init
    echo "main-config" > config.txt
    "$SHADOW" add config.txt

    git checkout -q -b feature
    "$SHADOW" sync main

    local content=$(cat config.txt)
    assert_eq "main-config" "$content" "sync should copy files from main" || return 1
}

# Test: checkout restores specific version
test_checkout_ref() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    echo "v2" > .env
    "$SHADOW" save "v2 commit"

    echo "v3" > .env
    "$SHADOW" save "v3 commit"

    "$SHADOW" checkout HEAD~1 .env
    local content=$(cat .env)
    assert_eq "v2" "$content" "checkout should restore v2" || return 1
}

# Test: gc runs without error
test_gc() {
    "$SHADOW" init
    echo "v1" > .env
    "$SHADOW" add .env

    local output=$("$SHADOW" gc)
    assert_contains "$output" "Garbage collection complete" "gc should complete" || return 1
}

# Test: install-hooks creates hook
test_install_hooks() {
    "$SHADOW" init
    "$SHADOW" install-hooks

    assert_file_exists ".git/hooks/post-checkout" "hook should be installed" || return 1

    local content=$(cat .git/hooks/post-checkout)
    assert_contains "$content" "shadow" "hook should contain shadow commands" || return 1
}

# Test: uninstall-hooks removes hook
test_uninstall_hooks() {
    "$SHADOW" init
    "$SHADOW" install-hooks
    "$SHADOW" uninstall-hooks

    assert_file_not_exists ".git/hooks/post-checkout" "hook should be removed" || return 1
}

# Test: handles nested directories
test_nested_dirs() {
    "$SHADOW" init
    mkdir -p config/env
    echo "nested" > config/env/local.conf
    "$SHADOW" add config/env/local.conf

    rm -rf config
    "$SHADOW" restore

    assert_file_exists "config/env/local.conf" "nested file should be restored" || return 1
    local content=$(cat config/env/local.conf)
    assert_eq "nested" "$content" "content should match" || return 1
}

# Test: shadowconfig supports comments
test_config_comments() {
    "$SHADOW" init
    echo "value" > .env
    "$SHADOW" add .env

    # Add comment to config
    echo "# This is a comment" >> "$SHADOW_DIR"/*/.shadowconfig
    echo "" >> "$SHADOW_DIR"/*/.shadowconfig

    # Should not fail with comments
    local output=$("$SHADOW" status)
    assert_contains "$output" ".env" "status should work with comments in config" || return 1
}

# Test: remote add
test_remote_add() {
    "$SHADOW" init
    local output=$("$SHADOW" remote add backup /tmp/backup.git 2>&1 || true)
    assert_contains "$output" "Added remote backup" "remote add should confirm" || return 1
}

# Test: remote list
test_remote_list() {
    "$SHADOW" init
    "$SHADOW" remote add backup /tmp/backup.git
    local output=$("$SHADOW" remote list)
    assert_contains "$output" "backup" "remote list should show backup" || return 1
}

# Test: help displays usage
test_help() {
    local output=$("$SHADOW" 2>&1 || true)
    assert_contains "$output" "Usage: shadow" "help should show usage" || return 1
    assert_contains "$output" "init" "help should list init command" || return 1
    assert_contains "$output" "save" "help should list save command" || return 1
}

# Run all tests
main() {
    echo "Running shadow.sh tests..."
    echo

    run_test test_init
    run_test test_init_idempotent
    run_test test_add
    run_test test_add_missing_file
    run_test test_remove
    run_test test_save
    run_test test_save_no_changes
    run_test test_restore
    run_test test_status
    run_test test_status_new
    run_test test_ls
    run_test test_ls_branches
    run_test test_diff
    run_test test_branch_isolation
    run_test test_log
    run_test test_sync
    run_test test_checkout_ref
    run_test test_gc
    run_test test_install_hooks
    run_test test_uninstall_hooks
    run_test test_nested_dirs
    run_test test_config_comments
    run_test test_remote_add
    run_test test_remote_list
    run_test test_help

    echo
    echo "================================"
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo "================================"

    [[ $TESTS_FAILED -eq 0 ]]
}

main "$@"
