# Shadow

Manage untracked files across git branches using a separate git-backed storage system.

Shadow solves the problem of environment-specific files (like `.env`, config files) that shouldn't be committed to the main repo but need to persist per-branch.

## Installation

```bash
# Clone the repository
git clone https://github.com/gelleson/shadow.git

# Add to PATH or create an alias
alias shadow="/path/to/shadow/shadow.sh"
```

## Quick Start

```bash
# Initialize shadow for your project
shadow init

# Track your .env file
shadow add .env

# Save tracked files (auto-commits to shadow storage)
shadow save

# Switch branches and restore your branch-specific files
git checkout feature-branch
shadow restore
```

## Commands

### Setup

| Command | Description |
|---------|-------------|
| `shadow init` | Initialize shadow for current repo |
| `shadow install-hooks` | Auto save/restore on branch switch |
| `shadow uninstall-hooks` | Remove git hooks |

### Core

| Command | Description |
|---------|-------------|
| `shadow add <file>` | Track a file |
| `shadow remove <file>` | Untrack a file |
| `shadow save [message]` | Save tracked files |
| `shadow restore` | Restore tracked files |
| `shadow status` | Show file status |

### Branch Operations

| Command | Description |
|---------|-------------|
| `shadow ls` | List tracked files |
| `shadow ls --branches` | List shadow branches |
| `shadow diff` | Show local vs shadow differences |
| `shadow diff <b1> <b2>` | Show differences between branches |
| `shadow sync [branch]` | Sync files from branch (default: main) |

### History

| Command | Description |
|---------|-------------|
| `shadow log [file]` | Show commit history |
| `shadow checkout <ref> [file]` | Restore specific version |

### Remote

| Command | Description |
|---------|-------------|
| `shadow remote add <name> <url>` | Add remote |
| `shadow remote remove <name>` | Remove remote |
| `shadow remote list` | List remotes |
| `shadow push [remote]` | Push to remote |
| `shadow pull [remote]` | Pull from remote |

### Maintenance

| Command | Description |
|---------|-------------|
| `shadow gc` | Garbage collect |

## How It Works

```
Your Project                     Shadow Storage (~/.git-shadow/{repo_id}/)
├── .git/                        ├── .git/
├── src/                         ├── .shadowconfig
├── .env         ←── save ───→   ├── .env
└── config.yml   ←── restore ──→ └── config.yml
                                     └── branches: main, feature-x, ...
```

- Each project gets an isolated shadow repo at `~/.git-shadow/{repo_id}/`
- Repo ID is derived from git origin URL (SHA256 hash)
- Shadow branches mirror your main repo branches
- `.shadowconfig` lists tracked files (supports `#` comments)

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SHADOW_DIR` | `~/.git-shadow` | Shadow storage location |

## Examples

### Per-branch environment files

```bash
# On main branch
echo "DATABASE_URL=prod-db" > .env
shadow add .env
shadow save

# On feature branch
git checkout -b feature
echo "DATABASE_URL=dev-db" > .env
shadow save

# Switch back - your prod config is restored
git checkout main
shadow restore
```

### Auto-sync on branch switch

```bash
shadow install-hooks
# Now shadow automatically saves before and restores after branch switches
```

### Team sharing via remote

```bash
# Set up shared shadow storage
shadow remote add team git@github.com:team/shadow-configs.git
shadow push team

# Team member pulls configs
shadow pull team
```

### Restore previous version

```bash
shadow log .env
# abc123 update .env
# def456 add .env

shadow checkout abc123 .env
```

## Testing

```bash
./test_shadow.sh
```

## License

MIT
