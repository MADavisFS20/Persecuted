#!/usr/bin/env bash
# export_commit_files_to_folders.sh
#
# Exports the files changed in each commit on the current branch into
# per-commit folders at the repository root.
#
# Folder naming rules:
#   1. Take the commit subject (first line of commit message).
#   2. Lowercase it.
#   3. Replace any character not in [a-z0-9] with '-'.
#   4. Collapse multiple consecutive '-' into one.
#   5. Trim leading/trailing '-'.
#   6. If the result is empty, use "commit-<shortSHA>".
#   7. If the sanitized name collides with another commit's folder name,
#      append "-<shortSHA>" to disambiguate.
#
# Files placed in each folder reflect the content at that commit.
# Deleted files are NOT included; only added, modified, or renamed files.
#
# Usage:
#   bash export_commit_files_to_folders.sh
#
# Run from the repository root on a clean working tree.
# The script is idempotent: re-running it overwrites existing output folders.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Collect all commits in chronological order (oldest first).
mapfile -t COMMITS < <(git log --reverse --format="%H" HEAD)

# ── Pass 1: compute sanitized folder names and detect collisions ────────────
declare -A FOLDER_FOR_SHA   # sha -> folder name
declare -A SEEN_NAMES        # sanitized name -> first sha that claimed it

sanitize() {
    local title="$1"
    local result
    result=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//')
    echo "$result"
}

for sha in "${COMMITS[@]}"; do
    subject=$(git log -1 --format="%s" "$sha")
    short="${sha:0:7}"
    name=$(sanitize "$subject")
    [ -z "$name" ] && name="commit-${short}"

    if [[ -v SEEN_NAMES["$name"] ]]; then
        # Collision: suffix the earlier entry and this one with their short SHAs.
        prior_sha="${SEEN_NAMES[$name]}"
        if [[ "${FOLDER_FOR_SHA[$prior_sha]}" == "$name" ]]; then
            FOLDER_FOR_SHA["$prior_sha"]="${name}-${prior_sha:0:7}"
        fi
        name="${name}-${short}"
    else
        SEEN_NAMES["$name"]="$sha"
    fi

    FOLDER_FOR_SHA["$sha"]="$name"
done

# ── Pass 2: extract files for each commit ──────────────────────────────────
for sha in "${COMMITS[@]}"; do
    folder="${FOLDER_FOR_SHA[$sha]}"
    short="${sha:0:7}"

    echo "Processing commit $short: '$folder'"

    # Remove existing folder so the run is idempotent.
    rm -rf "$REPO_ROOT/$folder"

    # Get the list of added/modified/renamed files for this commit.
    # Use --root when the commit has no parent OR its parent is unavailable
    # (e.g. a grafted/shallow clone where the parent object is missing).
    parent_sha=$(git log -1 --format="%P" "$sha")
    if [[ -z "$parent_sha" ]] || ! git cat-file -e "$parent_sha" 2>/dev/null; then
        mapfile -t FILE_LINES < <(git diff-tree --name-status -r --root "$sha" 2>/dev/null | tail -n +2)
    else
        mapfile -t FILE_LINES < <(git diff-tree --name-status -r "$sha" 2>/dev/null)
    fi

    has_files=false
    for line in "${FILE_LINES[@]}"; do
        status="${line:0:1}"
        filepath="${line#?$'\t'}"   # strip status char and tab
        # Also handle rename lines: "R100\told_path\tnew_path"
        if [[ "$status" == "R" ]]; then
            filepath=$(echo "$line" | cut -f3)
        fi
        # Skip deletions
        [[ "$status" == "D" ]] && continue

        dest="$REPO_ROOT/$folder/$filepath"
        mkdir -p "$(dirname "$dest")"
        # Checkout file content as of this commit.
        git show "${sha}:${filepath}" > "$dest"
        has_files=true
    done

    if [[ "$has_files" == false ]]; then
        echo "  (no changed files — skipping folder)"
        continue
    fi
done

echo ""
echo "Done. Per-commit folders created at repo root:"
for sha in "${COMMITS[@]}"; do
    echo "  ${FOLDER_FOR_SHA[$sha]}/"
done
