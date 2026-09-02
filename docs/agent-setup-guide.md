# Agent Setup Guide: GitHub Actions + AWS

This file is written for an AI coding agent. If you are a human reading this directly, use `docs/prerequisites.md` instead.

**Two usage modes exist for this scaffold:**

1. **CLI mode (non-agentic).** The user runs the scaffold CLI directly. Placeholders stay in the generated files. The user replaces them manually using `docs/prerequisites.md` as a reference. No agent involvement. This is the default path and needs no change to work.

2. **Agentic mode (you are here).** An agent reads this file and guides the user through setup interactively. The agent collects every required value from the user, offers to create cloud resources, and substitutes the values into the generated files. This is what the rest of this document describes.

---

## Step 1: Collect every required value from the user

Before you run any command or edit any file, ask the user for each value in this table. Present them one at a time or as a group — adapt to the conversation — but do not proceed to step 2 until you have asked about each one.

| # | Value to collect | Example | Used in |
|---|---|---|---|
| 1 | AWS account ID | `123456789012` | Trust policy, identity provider ARN |
| 2 | AWS region | `us-east-1` | Backend, provider config, GitHub variable |
| 3 | GitHub repository path | `my-org/my-repo` | Trust policy `sub` condition |
| 4 | S3 bucket name for **production** state | `my-org-terraform-prod` | Production backend.tf |
| 5 | S3 bucket name for **development** state | `my-org-terraform-dev` | Development backend.tf |
| 6 | GitHub organisation ID | `121528376` | Trust policy `sub` condition (immutable format) |
| 7 | GitHub repository ID | `1346315965` | Trust policy `sub` condition (immutable format) |

Values 6 and 7 are numeric IDs. GitHub uses them in the immutable subject claim format. Step 2 explains why the trust policy needs them.

The role ARNs (production and development) are **outputs** of step 2 — you do not ask for them upfront. You will get them after creating the roles.

**Any value can be skipped.** If the user does not have a value yet (e.g., the S3 buckets do not exist yet, or they have not decided on a naming convention), accept "skip" as an answer. Keep the `<YOUR_...>` placeholder for that value in the generated files and tell the user which placeholders remain at the end. They can fill them in later when they are ready.

Only values the user actually provides get substituted. Never invent a value on their behalf.

### Values you can infer (confirm before using)

- **Repository path:** run `git remote get-url origin` and parse the `owner/repo` segment. Show it to the user and ask them to confirm.
- **AWS account ID:** run `aws sts get-caller-identity --query Account --output text`. Show it to the user and ask them to confirm.
- **Region:** run `aws configure get region`. Show it and confirm.
- **Organisation ID and repository ID:** run `gh api repos/<REPOSITORY> --jq '{owner_id: .owner.id, repo_id: .id}'`. These IDs are facts, not preferences, so you may use them after you show them.

Never silently use an inferred value. Always show it and get a yes or no.

## Step 2: Create the OIDC identity provider and IAM roles

Ask the user:

> I can create the AWS OIDC identity provider and two IAM roles (one for production, one for development) for you. This requires your current AWS session to have IAM permissions (iam:CreateOpenIDConnectProvider, iam:CreateRole, iam:AttachRolePolicy). Would you like me to do this, or would you prefer to create them manually using the steps in `docs/prerequisites.md`?

### If the user says YES (automatic):

**2a. Check for an existing identity provider:**

```bash
aws iam list-open-id-connect-providers
```

If one already matches `token.actions.githubusercontent.com`, tell the user it exists and skip creation. Otherwise:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

Omit `--thumbprint-list`. AWS verifies GitHub's certificate against its own trusted root CAs.

**2b. Confirm the subject claim format:**

The trust policy matches the `sub` claim of the OIDC token. GitHub produces that claim in one of two formats. Read the current format before you write any policy:

```bash
gh api repos/<REPOSITORY>/actions/oidc/customization/sub
```

The response looks like this:

```json
{
  "use_default": true,
  "use_immutable_subject": false,
  "sub_claim_prefix": "repo:frust-cl@121528376/terraform-aws-github-oidc-template@1346315965"
}
```

| Field value | Format the tokens carry | Prefix to use in the trust policy |
|---|---|---|
| `use_immutable_subject: false` | Legacy, name based | `repo:<ORGANISATION>/<REPOSITORY_NAME>` |
| `use_immutable_subject: true` | Immutable, ID based | The `sub_claim_prefix` value |

Use the immutable format. The legacy format holds only mutable names. GitHub releases an organisation name after an organisation deletion, so another account can register that name, create a repository with the same name, and produce the same `sub` value. That account can then assume the IAM role. The immutable format adds the numeric organisation ID and the numeric repository ID, and no other account can reproduce them.

GitHub applies the immutable format by default to repositories created after 15 July 2026. Older repositories keep the legacy format until the owner opts in. GitHub Enterprise Server does not support the immutable format.

**Tell the user the migration order.** A single-step change breaks a pipeline that already runs:

1. Write the trust policy with both `sub` values. An IAM condition accepts an array, and either value matches.
2. Opt in to the immutable format.
3. Run the pipeline once and confirm the role assumption.
4. Remove the legacy `sub` value.

Ask the user before you run the opt-in command. The command changes the token format on the next workflow run:

```bash
gh api --method PUT repos/<REPOSITORY>/actions/oidc/customization/sub \
  -F use_default=true -F use_immutable_subject=true
```

Reference: [Immutable subject claims](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)

**2c. Create the development role:**

Write the trust policy. Substitute the account ID from step 1. Substitute the organisation name, the organisation ID, the repository name, and the repository ID from step 1:

```bash
cat > /tmp/trust-policy-development.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<ORGANISATION>@<ORGANISATION_ID>/<REPOSITORY_NAME>@<REPOSITORY_ID>:*",
            "repo:<ORGANISATION>/<REPOSITORY_NAME>:*"
          ]
        }
      }
    }
  ]
}
EOF
```

The first value uses the immutable format. The second value uses the legacy format, and it keeps a running pipeline alive during the migration in step 2b. Remove the second value after the migration completes.

> **Warning: the `:*` wildcard trusts every ref in the repository.**
>
> The wildcard matches every subject the repository can produce. It matches `ref:refs/heads/<any-branch>`, every tag, the `pull_request` subject, and every GitHub environment. Any branch in the repository can therefore assume this IAM role. A developer who pushes a branch reaches the same AWS permissions as `main`.
>
> This guide accepts that trade-off, because one policy then serves every branch and the setup stays short. Accept it only when the repository restricts who can push.
>
> Pin the branch instead when you need isolation between environments. Replace `:*` with `:ref:refs/heads/develop` for the development role, and with `:ref:refs/heads/main` for the production role. `docs/prerequisites.md` shows the pinned form. Change `StringLike` to `StringEquals` once no wildcard remains.
>
> Tell the user which form you used. Never choose the wildcard silently.

Show the user the trust policy content and ask for confirmation before running:

```bash
aws iam create-role \
  --role-name terraform-github-development \
  --assume-role-policy-document file:///tmp/trust-policy-development.json
```

Record the role ARN from the output. This is `<YOUR_DEVELOPMENT_ROLE_ARN>`.

**2d. Create the production role:**

Same as above, but with role name `terraform-github-production`. The same wildcard warning applies. A wildcard on the production role lets every branch reach production, so state that consequence to the user before you run the command:

```bash
cat > /tmp/trust-policy-production.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<ORGANISATION>@<ORGANISATION_ID>/<REPOSITORY_NAME>@<REPOSITORY_ID>:*",
            "repo:<ORGANISATION>/<REPOSITORY_NAME>:*"
          ]
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name terraform-github-production \
  --assume-role-policy-document file:///tmp/trust-policy-production.json
```

Record the role ARN. This is `<YOUR_PRODUCTION_ROLE_ARN>`.

**2e. Attach permissions to the roles:**

Ask the user which IAM policy to attach. Do NOT guess. Suggest they start with a narrow custom policy. If they are unsure, tell them the minimum the pipeline needs is:

- `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on the state bucket
- Whatever their Terraform resources require

```bash
aws iam attach-role-policy \
  --role-name terraform-github-development \
  --policy-arn <POLICY_ARN_FROM_USER>

aws iam attach-role-policy \
  --role-name terraform-github-production \
  --policy-arn <POLICY_ARN_FROM_USER>
```

### If the user says NO (manual):

Point them to `docs/prerequisites.md` sections 1, 2, and 3. Ask them to come back with the two role ARNs once they finish. Then continue from step 3 below.

## Step 3: Create the S3 state buckets

Ask the user:

> Do you want me to create the two S3 buckets for Terraform state, or have you already created them?

If they want you to create them, use the bucket names from step 1:

```bash
aws s3api create-bucket \
  --bucket <STATE_BUCKET_DEVELOPMENT> \
  --region <REGION> \
  --create-bucket-configuration LocationConstraint=<REGION>

aws s3api put-bucket-versioning \
  --bucket <STATE_BUCKET_DEVELOPMENT> \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket <STATE_BUCKET_DEVELOPMENT> \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket <STATE_BUCKET_DEVELOPMENT> \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Repeat for the production bucket. Skip `LocationConstraint` if the region is `us-east-1` (AWS requires omitting it for that region).

## Step 4: Store secrets in GitHub environments

Check that `gh` is authenticated:

```bash
gh auth status
```

Create the four environments:

```bash
gh api --method PUT repos/<REPOSITORY>/environments/development-plan
gh api --method PUT repos/<REPOSITORY>/environments/development
gh api --method PUT repos/<REPOSITORY>/environments/production-plan
gh api --method PUT repos/<REPOSITORY>/environments/production
```

Set the OIDC role secret in each environment (use the ARNs from step 2):

```bash
gh secret set AWS_OIDC_ROLE --env development-plan --body "<DEVELOPMENT_ROLE_ARN>"
gh secret set AWS_OIDC_ROLE --env development --body "<DEVELOPMENT_ROLE_ARN>"
gh secret set AWS_OIDC_ROLE --env production-plan --body "<PRODUCTION_ROLE_ARN>"
gh secret set AWS_OIDC_ROLE --env production --body "<PRODUCTION_ROLE_ARN>"
```

Set the region as a repository variable (not a secret, not per-environment):

```bash
gh variable set AWS_REGION --body "<REGION>"
```

Ask the user if they want a required reviewer on `production`. If yes:

```bash
REVIEWER_ID=$(gh api users/<USERNAME> --jq .id)
gh api --method PUT repos/<REPOSITORY>/environments/production \
  -F "reviewers[][type]=User" -F "reviewers[][id]=$REVIEWER_ID"
```

The reviewer needs read access to the repository at minimum.

**Plan limitation.** A required reviewer is a deployment protection rule. On the GitHub Free, Pro, and Team plans, protection rules work only in public repositories. The command above returns HTTP 422 on a private repository under those plans, with a message about the billing plan. Two options remain: make the repository public, or move to GitHub Enterprise. A deployment branch policy carries no such limit, and it works on every plan.

Do not add a required reviewer to `production-plan` or `development-plan` by default. Those environments exist so the plan job can run and produce output for the reviewer to read. A reviewer on a plan environment blocks every pull request before the plan starts. Add one only when the plan environment shares an identity with the apply environment.

Reference: [Managing environments for deployment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)

## Step 5: Substitute values into the generated Terraform files

Now re-run the scaffold CLI with the collected values to produce files with real values instead of placeholders:

```bash
npx oidc-scaffold \
  --git-provider github \
  --cloud-provider aws \
  --repository "<REPOSITORY>" \
  --region "<REGION>" \
  --state-bucket-production "<STATE_BUCKET_PRODUCTION>" \
  --state-bucket-development "<STATE_BUCKET_DEVELOPMENT>" \
  --output-dir .
```

Or, if the scaffold is already committed, edit the backend files directly using the values from step 1. Do this with a file edit tool, not a shell substitution.

## Step 6: Verify and hand off

1. Confirm no `<YOUR_...>` placeholder remains in any `.tf` file:
   ```bash
   grep -r '<YOUR_' terraform/
   ```
   If anything remains, the user skipped a value in step 1. Tell them which file and which value.

2. Confirm the pipeline file contains no role ARN, account ID, or region literal — only secret and variable references.

3. Confirm the trust policy matches the live subject format. Read both values and compare the prefix:

   ```bash
   gh api repos/<REPOSITORY>/actions/oidc/customization/sub
   aws iam get-role --role-name terraform-github-production \
     --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output json
   ```

   A mismatch between the two prefixes blocks every role assumption. Report a mismatch to the user and name the exact string that differs.

4. Tell the user what was created:
   - Identity provider: `token.actions.githubusercontent.com`
   - Roles: `terraform-github-development`, `terraform-github-production`
   - Subject claim format in each trust policy, and whether the repository opted in to immutable claims
   - Whether each role uses the `:*` wildcard or a pinned branch
   - Buckets: (the names from step 1)
   - GitHub environments: `development`, `development-plan`, `production`, `production-plan`
   - Secrets set: `AWS_OIDC_ROLE` in all four environments
   - Variable set: `AWS_REGION` at repository level

4. Suggest they open a pull request to trigger the first `terraform plan`. Do not push or open it yourself unless the user asks.

