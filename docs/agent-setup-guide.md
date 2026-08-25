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

The role ARNs (production and development) are **outputs** of step 2 — you do not ask for them upfront. You will get them after creating the roles.

**Any value can be skipped.** If the user does not have a value yet (e.g., the S3 buckets do not exist yet, or they have not decided on a naming convention), accept "skip" as an answer. Keep the `<YOUR_...>` placeholder for that value in the generated files and tell the user which placeholders remain at the end. They can fill them in later when they are ready.

Only values the user actually provides get substituted. Never invent a value on their behalf.

### Values you can infer (confirm before using)

- **Repository path:** run `git remote get-url origin` and parse the `owner/repo` segment. Show it to the user and ask them to confirm.
- **AWS account ID:** run `aws sts get-caller-identity --query Account --output text`. Show it to the user and ask them to confirm.
- **Region:** run `aws configure get region`. Show it and confirm.

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

**2b. Create the development role:**

Write the trust policy, substituting the account ID and repository from step 1:

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
          "token.actions.githubusercontent.com:sub": "repo:<REPOSITORY>:*"
        }
      }
    }
  ]
}
EOF
```

Show the user the trust policy content and ask for confirmation before running:

```bash
aws iam create-role \
  --role-name terraform-github-development \
  --assume-role-policy-document file:///tmp/trust-policy-development.json
```

Record the role ARN from the output. This is `<YOUR_DEVELOPMENT_ROLE_ARN>`.

**2c. Create the production role:**

Same as above, but with role name `terraform-github-production`:

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
          "token.actions.githubusercontent.com:sub": "repo:<REPOSITORY>:*"
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

**2d. Attach permissions to the roles:**

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

3. Tell the user what was created:
   - Identity provider: `token.actions.githubusercontent.com`
   - Roles: `terraform-github-development`, `terraform-github-production`
   - Buckets: (the names from step 1)
   - GitHub environments: `development`, `development-plan`, `production`, `production-plan`
   - Secrets set: `AWS_OIDC_ROLE` in all four environments
   - Variable set: `AWS_REGION` at repository level

4. Suggest they open a pull request to trigger the first `terraform plan`. Do not push or open it yourself unless the user asks.

