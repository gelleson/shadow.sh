# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Shadow is a single-file Bash utility that manages untracked files across git branches using a separate git-backed storage system. It solves the problem of environment-specific files (like `.env`, config files) that shouldn't be committed to the main repo but need to persist per-branch.

## Commands

No build process - the script runs directly:

```bash
./shadow.sh <command>
```

Common commands:
- `shadow init` - Initialize shadow for current repo
- `shadow add <file>` - Start tracking a file
- `shadow save [message]` - Save tracked files to shadow storage
- `shadow restore` - Restore tracked files from shadow storage
- `shadow status` - Show file status (new/modified/deleted/missing)
- `shadow ls` - List tracked files
- `shadow ls --branches` - List shadow branches

## Architecture

**Storage Location**: `~/.git-shadow/{repo_id}/` where repo_id is first 16 chars of SHA256(origin URL)

**Key Functions**:
- `sgit()` - Wrapper to run git commands in shadow repo context
- `_ensure_branch()` - Creates shadow branch from main if it doesn't exist
- `repo_id()` / `shadow_path()` - Compute storage location from git origin

**Flow**:
1. Each project gets isolated shadow repo at `~/.git-shadow/{repo_id}/`
2. Shadow repo has branches mirroring main repo branches
3. `.shadowconfig` in shadow repo lists tracked files (supports `#` comments)
4. `save` copies tracked files from working dir to shadow, commits
5. `restore` copies tracked files from shadow back to working dir

**Branch Handling**: Shadow branches are created on-demand from main/master. If current branch has no shadow, restore falls back to main.
