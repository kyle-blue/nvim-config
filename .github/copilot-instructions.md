# Neovim Config — Copilot Instructions

## Repo overview
Personal Neovim config for macOS, written in Lua.
- **Plugin manager**: lazy.nvim
- **Theme**: Tokyo Night
- **Key plugins**: nvim-tree, Telescope, lualine, blink.cmp, oil.nvim, render-markdown

## Structure
```
lua/
  core/          # Core config (options, keymaps, autocmds, git_compare_hl)
  plugins/       # One file per plugin config
  git_compare.lua            # Git baseline utilities (origin + accepted commit)
  git_compare_sidebar.lua    # Three-panel sidebar alongside nvim-tree
  git_compare_decorator.lua  # Legacy (unused)
init.lua         # Bootstraps lazy.nvim and loads lua/core/*
```

## Custom git-comparison system
Two highlight tiers (tree backgrounds + buffer line backgrounds):
1. **Origin** — changes since `git merge-base HEAD origin/*` (muted green/orange)
2. **Accepted** — changes since last `:Accept` baseline (vivid green/orange)

`:Accept` snapshots the working tree with `git stash create`.
`:AcceptDiff` opens a CodeDiff against the accepted baseline.

## Coding conventions
- Lua only; follow patterns in existing files
- Minimal comments — only where logic genuinely needs clarification
- No external formatting or linting tools; keep files consistent with neighbours
- `pcall` around any nvim-tree internal API calls (they can change across versions)

## Git workflow
- **Always make progressive, descriptive commits** as work proceeds — small logical units, not one giant commit at the end
- Commit messages: imperative mood, concise, e.g. `feat: add accept baseline command`
- **Never `git push`** — that is the user's responsibility
- **Never include "Co-authored-by" or any agent attribution** in commit messages
