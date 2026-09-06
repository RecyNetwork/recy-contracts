# Repository workflow

## End-of-session check-in

- Before ending each session, commit all completed repository work. Do not leave completed changes uncommitted unless the user explicitly requests it.
- Create incremental, feature-based commits. Keep unrelated fixes, features, documentation, and workflow changes in separate commits when they can stand independently.
- Verify each behavioral change with the relevant tests or smoke scenario before committing. Run the full Foundry suite when contract behavior changes; report any failures or checks that could not run.
- Inspect staged changes before each commit. Never commit secrets, credentials, local environment files, generated build output, or temporary verification files.
- Preserve pre-existing user work. Do not discard or silently include unrelated changes; include them only when the user requests checking in everything or otherwise authorizes it.
- Check the final repository status and report the commit hashes, verification results, and any intentionally uncommitted work.
- Committing does not authorize pushing, deploying contracts, or broadcasting transactions. Do those only when requested.
