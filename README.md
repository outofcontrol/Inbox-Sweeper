# macOS Directory Cleanup

A zsh script and a launchd agent that keep one folder tidy. Every hour, files and symlinks that have been in the folder for more than 24 hours move to the Trash, and subfolders left empty are removed.

## How it works

1. Age counts from the Finder "Date Added", so a file moved in today stays for 24 hours whatever its modification date.
2. A folder moved in today keeps all of its contents for 24 hours.
3. Each run collects its items into one folder named `Cleanup <date> <time>` and moves that folder to the Trash. The subfolder layout is kept inside it.
4. Symlinks are moved as links. Their targets stay where they are.
5. Hidden files and hidden folders are included.

## Requirements

macOS 15 or later, which provides `/usr/bin/trash`.

## Configure

1. In `local.cleanup-old-files.plist`, replace `/Users/USERNAME/DIRECTORY` with the absolute path of the folder to clean.
2. In the same file, replace `/Users/USERNAME` in the script and log paths with your home folder.
3. To change the age limit, edit `MAX_AGE_HOURS` in `cleanup-old-files.sh`.
4. To change how often it runs, edit `StartInterval` (seconds) in the plist.

## Install

```sh
mkdir -p ~/bin
cp cleanup-old-files.sh ~/bin/
cp local.cleanup-old-files.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.cleanup-old-files.plist
```

The agent runs once on load and then every hour. Activity is logged to `~/Library/Logs/cleanup-old-files.log`.

## Preview

List what a run would move to the Trash:

```sh
DRY_RUN=1 zsh ~/bin/cleanup-old-files.sh /path/to/folder
```

## Uninstall

```sh
launchctl bootout gui/$(id -u)/local.cleanup-old-files
rm ~/Library/LaunchAgents/local.cleanup-old-files.plist ~/bin/cleanup-old-files.sh
```
