# Development Rules for Claude Code Sessions

## Critical Rule: Never Revert Without Saving

**NEVER revert code changes during investigation without first saving them.**

When debugging issues:
1. ✅ Commit working code before making experimental changes
2. ✅ Save changed files to backups if not ready to commit
3. ✅ Use `git stash` to temporarily save changes
4. ❌ **NEVER** use `git checkout` to revert files during investigation
5. ❌ **NEVER** delete files without backing them up first

If code needs to be reverted:
- First: `git add <files> && git stash` or `cp <files> <files>.backup`
- Then: investigate the actual issue instead of giving up
- Only revert as a last resort after thorough investigation
