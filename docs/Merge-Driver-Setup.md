# Merge driver setup (one-time after clone)

This repo uses a **custom merge driver** so that `.uasset` (and other binary) files are never merged—when both branches change the same file, Git keeps the **incoming branch’s version** (the LFS pointer) instead of creating a merge conflict. After the merge, **`git lfs pull`** must run so those pointers are replaced with real binary files; the setup script adds this to your post-merge hook.

`.gitattributes` is already in the repo, but the driver and hook are **local** (not pushed). Every clone needs a one-time setup.

## Run after cloning

From the repo root:

**Windows (cmd):**
```cmd
scripts\setup-merge-driver.bat
```

**PowerShell / Git Bash:**
```bash
git config merge.theirs.driver "scripts/merge-theirs.bat"
# Optional: ensure post-merge runs LFS pull (or append "git lfs pull" to .git/hooks/post-merge)
```

This does three things:
1. **Merge driver** – When both branches change the same `.uasset`, Git keeps the incoming branch’s version (the pointer) with no conflict.
2. **Post-merge hook** – After every merge, the hook runs `git lfs pull` so pointer files are replaced with real binaries. (If you still see `version` / `oid` / `size` text in `.uasset` files, run `git lfs pull` once.)
3. **Pre-push hook** – Before every push to a remote, the hook runs `git lfs push <remote> --all` so LFS objects are always uploaded (avoids “push succeeded but LFS didn’t upload”).

## Making it visible in Azure DevOps

You can’t run this on the server (merge drivers only run in local Git). To make sure the team runs it:

1. **Repo description** – In Azure DevOps: **Project** → **Repos** → **Files** → set the repo description to mention “After clone, run `scripts\setup-merge-driver.bat` (see `docs/Merge-Driver-Setup.md`).”
2. **Wiki / README** – Add a “Getting started” or “First-time setup” section that links to or copies the instructions above.
3. **Branch policy / PR description template** – Optionally add a reminder like “Ensure you’ve run the merge driver setup (see docs) if you work with .uasset files.”
