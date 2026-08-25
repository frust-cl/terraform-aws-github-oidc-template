# template-repo

Starter template for new Frust repos. Generate a new repo from this one ("Use this template" in GitHub, or the `create_repo_from_template` devbot tool) to inherit the standard branch model and git workflow.

## What's included

- `WORKFLOW.md` — branch model (main/develop/feature/release/hotfix), naming conventions, PR rules.
- `.github/workflows/backport.yml` — auto-opens a `main` → `develop` PR after any `hotfix/*` or `release/*` branch merges into `main`.

## After generating a repo from this template

GitHub's "generate from template" only copies files — branch protection is **not** carried over. Branch protection for the standard model (no delete, no force-push, PR-required with enforced merge method on `main`/`develop`) is enforced by 4 **org-level** rulesets in `revi-cl`, scoped to repos with the custom property `branch-model=gitflow`. To bring a new repo under that protection:

1. Create the `develop` branch: `git push origin main:develop`
2. Set the custom property on the new repo:
   ```bash
   gh api orgs/revi-cl/properties/values -X PATCH \
     -f 'repository_names[]=<new-repo-name>' \
     -f 'properties[][property_name]=branch-model' \
     -f 'properties[][value]=gitflow'
   ```
   That's it — the 4 org rulesets apply automatically the moment the property is set. Nothing to configure per-repo.
3. Confirm `.github/workflows/backport.yml` is present and `contents: read` / `pull-requests: write` permissions are enabled for Actions on the new repo (`Settings → Actions → General → Workflow permissions`).
