# Persecuted
Documents of my persecution by Pasco County Florida

## Per-Commit File Export

Each commit's changed files are exported into a folder at the repository root named after the commit title (lowercased, non-alphanumeric characters replaced with `-`). Commits with no file changes are skipped.

| Folder | Commit |
|--------|--------|
| `evidence/` | *Evidence* (`74d913b`) |

### Regenerating the folders

Run from the repository root on a clean working tree:

```bash
bash export_commit_files_to_folders.sh
```

The script is idempotent — re-running it overwrites existing output folders.
