# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A zsh script and a launchd agent that move files which have sat in one folder for more than 24 hours to the Trash. There is no build step, test suite, or linter config.

## Commands

```sh
# List what would be trashed, without trashing
DRY_RUN=1 zsh inbox-sweeper.sh /path/to/folder

# Run for real
zsh inbox-sweeper.sh /path/to/folder

# Syntax checks
zsh -n inbox-sweeper.sh
plutil -lint local.inbox-sweeper.plist
```

Test changes against a scratch folder with `DRY_RUN=1`. The script moves items to the Trash with `/usr/bin/trash` (macOS 15 and later). Empty folders and their `.DS_Store` are removed outright. The Claude Code sandbox denies Trash moves. Substitute a stub for `/usr/bin/trash` to exercise the success path.

## Deployment layout

The plist hardcodes absolute paths that differ from the repo layout:

- Script: `/Users/USERNAME/bin/inbox-sweeper.sh` (a copy outside this repo, edits here do not reach it until copied)
- Target folder: `/Users/USERNAME/DIRECTORY` (placeholder, also the script default via `$HOME/CHANGE_ME`)
- Log: `~/Library/Logs/inbox-sweeper.log` (stdout and stderr combined)

The agent runs hourly (`StartInterval` 3600) and at load. launchd does not expand `~` or `$HOME` in plist strings. Keep the paths absolute.

## Script behavior

`inbox-sweeper.sh` is zsh specific. It relies on glob qualifiers (`(ND^/)`, `(ND/On)`, `(DN)`), path modifiers (`:A`, `:h`), and associative arrays. Do not port it to bash or run it with `sh`.

Age is measured from when an item entered the folder, not from its modification time:

- `added_ts` reads the Spotlight attribute `kMDItemDateAdded` through `mdls`, falls back to inode change time (`stat -f %c`), and caches results in `_added`. Symlinks skip `mdls` and always use the change time of the link itself.
- `time_in_folder` takes the newest Date Added among the item and every ancestor folder below `TARGET_DIR`. A folder moved in today protects all of its contents until the folder itself ages out.
- Both functions return through `$REPLY`, not stdout, to avoid a subshell per file.

Three steps run in order:

0. Trash staging folders left in `TARGET_DIR/.cleanup-staging` by a run whose Trash move failed.
1. Stage files and symlinks older than `MAX_AGE_HOURS` at any depth. The `(ND^/)` qualifier matches everything except real folders, dotfiles and the contents of hidden folders included. Each item is moved with `mv -n` into `.cleanup-staging/Cleanup <date> <time>/` under its path relative to `TARGET_DIR`, then that folder is trashed with one `trash -s` call (`-s` makes failure exit non-zero). The Trash holds one folder per run with the subfolder layout intact. `mv` moves a symlink itself, never its target, and `**/` does not descend into symlinked folders. Do not add the `-` qualifier or switch to `***/`, both follow symlinks.
2. Remove subfolders, hidden ones included, that are empty (ignoring `.DS_Store`) and older than the cutoff. `.cleanup-staging` is excluded here and in step 1. `On` sorts in reverse name order, which visits children before parents. `TARGET_DIR` is never removed.

`set -uo pipefail` omits `-e` on purpose. A failed `trash` or `mdls` on one file does not stop the run.

All external tools are called by absolute path (`/usr/bin/trash`, `/usr/bin/mdls`, `/bin/date`) because launchd provides a minimal `PATH`.
