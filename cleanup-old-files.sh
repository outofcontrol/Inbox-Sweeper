#!/bin/zsh
# Move files and symlinks that have been in TARGET_DIR (including its
# subfolders) for more than MAX_AGE_HOURS to the Trash, then remove subfolders
# left empty. Symlink targets are left alone. Requires macOS 15 (/usr/bin/trash).
#
# Each run gathers its old items into one folder, "Cleanup <date> <time>",
# keeping their subfolder layout, and trashes that folder as a single item.
# The folder is built in TARGET_DIR/.cleanup-staging and exists there only
# during the run. If the Trash move fails it stays, and the next run retries.
#
# "Time in the folder" uses the Finder "Date Added" (kMDItemDateAdded), so a
# file you moved or downloaded today counts from today, even if its
# modification date is years old. If Spotlight has no Date Added for an item,
# the inode change time is used instead. Symlinks always use the inode change
# time of the link itself.
#
# A file inside a subfolder counts from whichever is newest: its own Date
# Added, or the Date Added of any subfolder it sits in. So if you drop an
# existing folder in today, nothing inside it is trashed until tomorrow.
#
# Usage: cleanup-old-files.sh [folder]      (DRY_RUN=1 to only list)

set -uo pipefail

TARGET_DIR="${1:-$HOME/CHANGE_ME}"
MAX_AGE_HOURS=24
DRY_RUN="${DRY_RUN:-0}"

log() { echo "$(/bin/date '+%F %T') $*"; }

if [[ ! -d "$TARGET_DIR" ]]; then
  log "ERROR: folder not found: $TARGET_DIR" >&2
  exit 1
fi
TARGET_DIR=${TARGET_DIR:A}   # absolute path, no trailing slash

cutoff=$(( $(/bin/date +%s) - MAX_AGE_HOURS * 3600 ))

STAGE_ROOT="$TARGET_DIR/.cleanup-staging"
stage="$STAGE_ROOT/Cleanup $(/bin/date '+%F %H%M%S')"
staged=0

# Trash one staging folder, then drop STAGE_ROOT if nothing is left in it.
trash_stage() {
  if /usr/bin/trash -s "$1"; then
    log "trashed: $1"
  else
    log "ERROR: could not trash $1, will retry next run" >&2
  fi
  /bin/rm -f -- "$STAGE_ROOT/.DS_Store"
  /bin/rmdir -- "$STAGE_ROOT" 2>/dev/null
}

# 0. Staging folders left behind by a run whose Trash move failed.
for d in "$STAGE_ROOT"/*(ND/); do
  if [[ "$DRY_RUN" == 1 ]]; then
    log "would trash leftover: $d"
  else
    trash_stage "$d"
  fi
done

# Date Added (epoch seconds) for one path, cached. Result in $REPLY.
typeset -A _added
added_ts() {
  local p=$1 raw ts=""
  if [[ -n "${_added[$p]-}" ]]; then REPLY=${_added[$p]}; return; fi
  # Symlinks skip mdls, which may report on the link's target instead.
  [[ -L "$p" ]] || raw=$(/usr/bin/mdls -raw -name kMDItemDateAdded "$p" 2>/dev/null)
  if [[ -n "${raw-}" && "$raw" != "(null)" ]]; then
    ts=$(/bin/date -j -f '%Y-%m-%d %H:%M:%S %z' "$raw" +%s 2>/dev/null)
  fi
  [[ -z "$ts" ]] && ts=$(/usr/bin/stat -f %c "$p")
  _added[$p]=$ts
  REPLY=$ts
}

# Newest Date Added of the path and every subfolder above it. Result in $REPLY.
time_in_folder() {
  local p=$1 best d
  added_ts "$p"; best=$REPLY
  d=${p:h}
  while [[ "$d" == "$TARGET_DIR"/* ]]; do
    added_ts "$d"; (( REPLY > best )) && best=$REPLY
    d=${d:h}
  done
  REPLY=$best
}

# 1. Old files and symlinks, at any depth. (ND^/) = everything except real
#    folders, dotfiles and hidden folders included, no error if none. A
#    symlink is moved itself; what it points to is never touched, and
#    symlinked folders are not descended into. Items are moved into $stage
#    under their path relative to TARGET_DIR.
for f in "$TARGET_DIR"/**/*(ND^/); do
  [[ "$f" == "$STAGE_ROOT"/* ]] && continue
  time_in_folder "$f"
  if (( REPLY < cutoff )); then
    if [[ "$DRY_RUN" == 1 ]]; then
      log "would trash: $f"
    else
      dest="$stage/${f#$TARGET_DIR/}"
      if /bin/mkdir -p -- "${dest:h}" && /bin/mv -n -- "$f" "$dest"; then
        log "staged: $f"
        (( staged++ ))
      else
        log "ERROR: could not stage $f" >&2
      fi
    fi
  fi
done

(( staged )) && { log "trashing $staged item(s) as: ${stage:t}"; trash_stage "$stage"; }

# 2. Subfolders that are now empty (ignoring .DS_Store) and were added more
#    than MAX_AGE_HOURS ago. Deepest first, so emptied parents go too.
#    The target folder itself is never removed.
for d in "$TARGET_DIR"/**/*(ND/On); do
  [[ "$d" == "$STAGE_ROOT" || "$d" == "$STAGE_ROOT"/* ]] && continue
  contents=( "$d"/*(DN) )
  contents=( ${contents:#$d/.DS_Store} )
  (( ${#contents} )) && continue
  time_in_folder "$d"
  (( REPLY < cutoff )) || continue
  if [[ "$DRY_RUN" == 1 ]]; then
    log "would remove empty folder: $d"
  else
    /bin/rm -f -- "$d/.DS_Store"
    /bin/rmdir -- "$d" 2>/dev/null && log "removed empty folder: $d"
  fi
done
