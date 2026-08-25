# Prerequisites: AWS OIDC with GitHub Actions

This document describes the manual steps required to configure AWS IAM and GitHub for OIDC authentication. Complete these steps before the pipeline can authenticate.

**Agent reading this file:** read `docs/agent-setup-guide.md` first. It tells you whether to walk the human through the console steps below or run the CLI commands directly, and it never runs a mutating command without asking first.

## 1. Create the IAM OIDC Identity Provider

Create an OIDC identity provider in your AWS account that trusts GitHub Actions.

1. Open the [IAM console](https://console.aws.amazon.com/iam/).
2. Navigate to **Identity providers** > **Add provider**.
3. Select **OpenID Connect**.
4. Set the **Provider URL** to:
   ```
   https://token.actions.githubusercontent.com
   ```
5. Set the **Audience** to:
   ```
   sts.amazonaws.com
   ```
6. Click **Add provider**.

> Reference: [Use IAM roles to connect GitHub Actions to actions in AWS](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)

## 2. Create IAM Roles with Trust Policies

Create one IAM role per environment. The pipeline reads the role ARN from a single secret named `AWS_OIDC_ROLE`, and GitHub resolves that name to a different value depending on which of the four environments the job runs under (see step 5). Each role trusts only a specific branch of your repository.

### Production Role

Create a role with the following trust policy. This role allows GitHub Actions to assume it only from the `main` branch of your repository.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:revi-cl/terraform-aws-github-oidc-template:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

The resulting role ARN replaces `<YOUR_PRODUCTION_ROLE_ARN>` in the pipeline configuration.

### Development Role

Create a role with the following trust policy. This role allows GitHub Actions to assume it only from the `develop` branch of your repository.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:revi-cl/terraform-aws-github-oidc-template:ref:refs/heads/develop"
        }
      }
    }
  ]
}
```

The resulting role ARN replaces `<YOUR_DEVELOPMENT_ROLE_ARN>` in the pipeline configuration.

## 3. Attach IAM Permissions to the Roles

Attach policies to each role that grant only the permissions Terraform requires.

**Recommendations:**

- Use the principle of least privilege. Grant only the permissions that Terraform needs to manage your resources.
- Do NOT use wildcard (`*`) permissions in production roles.
- Consider using a custom policy that restricts to specific resource types and ARNs.
- For state management, the role needs at minimum:
  - `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on the state bucket.

> **Warning:** Do not use `AdministratorAccess` or `PowerUserAccess` policies for OIDC roles. Scope permissions to the resources Terraform manages.

## 4. Create S3 Buckets for Terraform State

Create one S3 bucket per environment to store Terraform state files.

### Production State Bucket

1. Create an S3 bucket named: `terraform-aws-github-oidc-s3-bucket-example-prod`
2. Region: `us-east-1`
3. Enable **versioning** on the bucket.
4. Enable **server-side encryption** (SSE-S3 or SSE-KMS).
5. Block all public access.

### Development State Bucket

1. Create an S3 bucket named: `terraform-aws-github-oidc-s3-bucket-example-dev`
2. Region: `us-east-1`
3. Enable **versioning** on the bucket.
4. Enable **server-side encryption** (SSE-S3 or SSE-KMS).
5. Block all public access.

> **Note:** Terraform 1.10+ supports S3 native state locking via `use_lockfile = true`. A DynamoDB table is not required.

## 5. Store the Role ARNs

You now have two role ARNs: one for production, one for development. Neither goes into a pipeline file or a Terraform file. Both go into GitHub environment secrets, both named `AWS_OIDC_ROLE`.

- The production role ARN goes into the `production` **and** `production-plan` environments.
- The development role ARN goes into the `development` **and** `development-plan` environments.

The "Pipeline Secrets" section below explains why four environments exist and lists the exact steps to create them. `docs/agent-setup-guide.md` gives the equivalent `gh` commands, if you would rather run them than click through the console.

## 6. Verify the Configuration

After you complete the steps above:

1. Replace all `<YOUR_...>` placeholders in the backend files with your real bucket names and region.
2. Push a branch and open a pull request to trigger a `terraform plan`.
3. Verify that the GitHub Actions workflow authenticates and runs successfully.
4. Merge to `develop` or `main` and approve the apply job in the matching environment.

## Placeholder Reference

| Placeholder | Description |
|---|---|
| `<YOUR_AWS_ACCOUNT_ID>` | AWS account ID. Both environments live in the same account by default |
| `<YOUR_PRODUCTION_ROLE_ARN>` | IAM role ARN for production. Store this as the `AWS_OIDC_ROLE` secret on the `production` and `production-plan` environments |
| `<YOUR_DEVELOPMENT_ROLE_ARN>` | IAM role ARN for development. Store this as the `AWS_OIDC_ROLE` secret on the `development` and `development-plan` environments |
| `<YOUR_STATE_BUCKET_PRODUCTION>` | S3 bucket for production state |
| `<YOUR_STATE_BUCKET_DEVELOPMENT>` | S3 bucket for development state |
| `<YOUR_AWS_REGION>` | AWS region. Both environments deploy to the same region by default |
| `revi-cl/terraform-aws-github-oidc-template` | GitHub repository (e.g., `org/repo`) |

## References

- [Use IAM roles to connect GitHub Actions to actions in AWS](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)
- [Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [S3 Native State Locking in Terraform](https://developer.hashicorp.com/terraform/language/backend/s3)

## Pipeline Secrets

The pipeline never contains a role ARN, a client ID, or an account identifier. It
reads each value from a secret that the CI/CD platform scopes to an environment.
The name stays the same for production and development. Only the stored value
changes.

| Secret name | Value to store |
|---|---|
| `AWS_OIDC_ROLE` | IAM role ARN the pipeline assumes through OIDC |

The pipeline also reads these values. They are not identities, so they are plain
variables rather than secrets.

| Variable name | Value to store |
|---|---|
| `AWS_REGION` | AWS region the pipeline authenticates and deploys into |

Add these as repository or organisation variables under **Settings > Secrets and variables > Actions > Variables**. They are not secrets, so they need no masking.

### Create the GitHub environments

GitHub Actions releases an environment secret to a job only when the job declares
`environment:`. A required reviewer on an environment blocks the job before it
starts. A plan job bound to `production` would therefore wait for approval, and
the reviewer would never see the plan.

Four environments solve this. Create all four:

| Environment | Required reviewers | Identity to store | Used by |
|---|---|---|---|
| `production-plan` | none | Read-only identity | The plan job on `main` |
| `development-plan` | none | Read-only identity | The plan job on `develop` |
| `production` | yes | Apply identity | The apply job on `main` |
| `development` | optional | Apply identity | The apply job on `develop` |

Add every secret from the table above to all four environments.

The plan job runs first. The apply job declares `needs: plan`, so it never starts
before the plan succeeds. The reviewer reads the plan, then approves the apply.

**Fork limitation:** a pull request from a fork receives no secrets and no
`id-token: write` permission. The plan job cannot run for fork pull requests.
This applies to every OIDC pipeline, not only this one.

**Runner requirement:** the pinned action versions run on Node.js 24. They need an
Actions runner of 2.327.1 or later. GitHub-hosted runners already meet this. Check
any self-hosted runner before you merge.

## Official Documentation

- **Git provider pipeline syntax:** [GitHub Actions workflow syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions)
- **Git provider OIDC:** [GitHub Actions OIDC in cloud providers](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-cloud-providers)
- **Cloud provider OIDC:** [AWS IAM OIDC federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_oidc.html)
- **Terraform state backend:** [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
