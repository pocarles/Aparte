# GitHub status

The private GitHub repository is live at <https://github.com/pocarles/Aparte>.

Verified August 30, 2026:

- repository: `pocarles/Aparte`;
- visibility: private;
- default branch: `main`;
- local remote: `git@github.com:pocarles/Aparte.git`;
- pushed history: every milestone commit on `main`.

Verification commands:

```sh
gh repo view pocarles/Aparte --json nameWithOwner,isPrivate,defaultBranchRef,url,visibility
git status -sb
git log --oneline --decorate --max-count=8
```

Do not change visibility, enable publication automation, or create a release without a separate release decision.
