# GitHub publication

The public repository lives at <https://github.com/pocarles/Aparte>. Its homepage is
<https://pocarles.com/aparte/> and releases are signed, notarized Universal 2 disk images.

Publication settings:

- repository: `pocarles/Aparte`;
- visibility: public;
- default branch: `main`;
- license: MIT;
- release asset: `Aparte.dmg` with `Aparte.dmg.sha256`;
- release workflow: `.github/workflows/release.yml`;
- protected credential environment: `release`.

Verification commands:

```sh
gh repo view pocarles/Aparte --json nameWithOwner,isPrivate,defaultBranchRef,url,visibility
git status -sb
git log --oneline --decorate --max-count=8
```

Tag releases only after `make check`, `make check-app-store`, and `make check-direct` pass on the intended commit.
