# ghostbsd-ports-sync

`ghostbsd-ports-sync` is a Ruby-based CLI tool that automates the process of synchronizing the GhostBSD ports tree with the FreeBSD ports tree. It supports automated conflict resolution using `diff3`, integrates with `poudriere` for testing builds, and includes features for reproducible builds.

---

## Features

- Clone and update the GhostBSD ports tree
- Add and merge changes from the FreeBSD ports tree
- Automatically resolve merge conflicts using `diff3`
- Run `poudriere` bulk test in dry-run mode
- Logs all actions to `~/ghostbsd-ports-sync.log`
- Supports reproducible builds (fixed timestamp, locale, etc.)
- Dry-run mode and verbose logging options

---

## Requirements

- Ruby (>= 2.6)
- Git
- diff3 (usually part of base system)
- poudriere

---

## Installation

```sh
chmod +x ghostbsd-ports-sync
sudo mv ghostbsd-ports-sync /usr/local/bin/
```

---

## Usage

```sh
ghostbsd-ports-sync [options]
```

### Options

- `-v`, `--verbose` – Enable detailed logging to stdout
- `-n`, `--dry-run` – Perform all steps except pushing commits
- `-h`, `--help` – Show usage info

---

## Example Workflow

```sh
ghostbsd-ports-sync -v
```

1. Ensures `git` and `diff3` are installed
2. Clones or updates GhostBSD ports
3. Adds FreeBSD ports as a remote
4. Creates a new branch based on the date (e.g., `sync-freebsd-20250406`)
5. Merges a specific commit or latest FreeBSD changes
6. Resolves any merge conflicts with `diff3`
7. Verifies buildability with `poudriere` (dry-run)
8. Pushes changes (unless in dry-run mode)

---

## Reproducibility

The script enforces reproducibility by:

- Setting `SOURCE_DATE_EPOCH`, `TZ`, `LC_ALL`, and `LANG`
- Using a pinned commit hash for FreeBSD (optional)
- Running `poudriere` in a clean, version-controlled jail and ports tree

To pin a FreeBSD commit, edit the script and set:
```ruby
FREEBSD_COMMIT = 'your_commit_hash_here'
```

---

## Log File

All actions are logged to:
```sh
~/ghostbsd-ports-sync.log
```

---

## License

BSD 2-Clause Simplified License
