# Catching and Uploading Files That Aren’t on LFS

This repo uses **Git LFS** for large/binary assets. These steps help you find files that *should* be in LFS but were committed as normal Git files, and how to fix or avoid that.

---

## 1. Check what’s already in LFS

From the repo root:

```bash
git lfs ls-files
```

This lists every file Git LFS is currently tracking. If a `.uasset`, `.fbx`, or something under `Content/`, `import/`, or `plugin/` doesn’t appear here but is in the repo, it’s not on LFS.

---

## 2. Find files that should be LFS but aren’t

**Option A – See what would be migrated (dry run)**

```bash
git lfs migrate info --everything
```

This shows which file types and how much data would be moved to LFS. It doesn’t change anything.

**Option B – List likely offenders (e.g. `.uasset` in the index/working tree)**

PowerShell:

```powershell
git ls-files | Where-Object { $_ -match '\.(uasset|umap|fbx)$' -or $_ -match '^(Content|import|plugin)/' } | ForEach-Object {
  $oid = git rev-parse "HEAD:$_" 2>$null
  if ($oid) {
    $type = git cat-file -t $oid 2>$null
    if ($type -eq 'blob') {
      $size = (git cat-file -s $oid 2>$null)
      [PSCustomObject]@{ Path = $_; Size = $size }
    }
  }
}
```

Or with Git Bash / WSL:

```bash
git ls-files | grep -E '\.(uasset|umap|fbx)$|^(Content|import|plugin)/' | while read f; do
  oid=$(git rev-parse "HEAD:$f" 2>/dev/null)
  [ -n "$oid" ] && git cat-file -t "$oid" 2>/dev/null | grep -q blob && echo "$f"
done
```

Those commands list paths that are tracked by Git as normal blobs; if they match our LFS patterns, they’re candidates to put on LFS.

---

## 3. Fix before pushing (best case: only local commits)

If the “wrong” files exist only in **your local commits** (not yet pushed, or only on your branch):

**3.1 Migrate into LFS (rewrites your local history)**

```bash
# Migrate everything that matches .gitattributes (e.g. *.uasset, content/**, etc.)
git lfs migrate import --everything --include="*.uasset,*.fbx,Content/**"
```

Then push (this will be a history rewrite, so force-push your branch):

```bash
git push --force-with-lease
```

**3.2 If you haven’t committed yet**

- Our `.gitattributes` already tells LFS to track `*.uasset`, `*.fbx`, and `content/**`, etc.
- Unstage, then re-add so LFS can take over:

  ```bash
  git reset HEAD -- path/to/file.uasset
  git add path/to/file.uasset
  ```

- Or re-add everything under `Content/`:

  ```bash
  git reset HEAD -- Content/
  git add Content/
  ```

Then commit and push as usual; the files will be stored in LFS.

---

## 4. If the bad commits are already on the shared branch

If large files were already pushed as non-LFS to `main`/`develop`:

- **Don’t** run `git lfs migrate import --everything` and force-push to the main branch without coordinating with the team; it rewrites history and changes commit SHAs.
- Options:
  1. **Coordinate a one-time migration**: One person runs the migrate (e.g. `git lfs migrate import --everything --include="*.uasset,*.fbx,Content/**"`) on a copy of the repo, then the team agrees to reset main to the new history and everyone re-clones or resets their local main. Document the cutover in Slack/email.
  2. **Fix only in new commits**: For *new* or *modified* files, ensure they’re in LFS from now on (step 3.2). Old blobs stay in history until a full migration is done.

---

## 5. Make sure LFS is installed and pulling

```bash
git lfs install
git lfs pull
```

Run `git lfs install` once per machine; run `git lfs pull` when you need to fetch LFS files (e.g. after pull/merge).

---

## 6. If `git push` doesn't upload LFS objects

Sometimes a normal `git push` succeeds but LFS objects never reach the remote (e.g. hooks didn't run, or the push skipped LFS). The remote then has pointers instead of real files, and others get errors or pointer text when they pull.

**Fix: push LFS explicitly**

```bash
git lfs push origin --all
```

Use your branch name instead of `--all` if you only want to push LFS for the current branch:

```bash
git lfs push origin master
```

After that, run a normal `git push` if needed. To make this automatic, run the repo’s one-time setup so the pre-push hook always runs `git lfs push` before each push: see `docs/Merge-Driver-Setup.md`.

---

## Quick reference (this repo’s LFS patterns)

From `.gitattributes`:

- `content/**` → LFS  
- `import/**` → LFS  
- `plugin/**` → LFS  
- `*.fbx` → LFS  
- `*.uasset` → LFS  

Any file matching these that doesn’t show up in `git lfs ls-files` is a candidate to “catch and upload” using the steps above.
