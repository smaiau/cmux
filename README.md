# cmux — tmux for Claude Code

Worktree lifecycle manager for parallel Claude Code sessions. Each agent gets its own git worktree — no conflicts, one command each.

## Install

```bash
git clone https://github.com/smaiau/cmux.git ~/.cmux-repo
cd ~/.cmux-repo && ./install.sh
```

Or manually:

```bash
mkdir -p ~/.cmux
cp cmux.sh cmux-team.sh VERSION ~/.cmux/

# Add to ~/.zshrc or ~/.bashrc:
source "$HOME/.cmux/cmux.sh"
source "$HOME/.cmux/cmux-team.sh"
```

## cmux — Single agent per worktree

```bash
cmux new feature-login    # New worktree + branch, run setup, launch Claude
cmux start feature-login  # Resume with --continue
cmux cd feature-login     # cd into worktree
cmux ls                   # List worktrees
cmux merge feature-login  # Merge into primary checkout
cmux rm feature-login     # Remove worktree + branch
cmux rm --all             # Remove ALL worktrees
cmux init                 # Generate .cmux/setup hook using Claude
cmux update               # Update to latest version
```

## cmux-team — Multiple agents in parallel

```bash
cmux-team branch1 branch2 branch3   # Launch one Claude per branch
cmux-team --list                     # List active team windows
cmux-team --kill                     # Close all team windows
cmux-team --clean                    # Remove worktrees (safe — refuses uncommitted)
```

### Behavior

- **Inside tmux**: creates new windows (tabs) in your current session. Navigate with `Ctrl+B n`/`p`.
- **Outside tmux**: creates a separate `cmux-team` session. Auto-attaches.
- Re-running `cmux-team` when windows/session already exist auto-reattaches.

### Setup hook

Create `.cmux/setup` in your repo root to auto-run after worktree creation:

```bash
#!/bin/bash
REPO_ROOT="$(git rev-parse --git-common-dir | xargs dirname)"
ln -sf "$REPO_ROOT/.env" .env
yarn install && npx prisma generate
```

Or generate one automatically: `cmux init`

## Requirements

- tmux
- git
- Claude Code CLI (`claude`)
