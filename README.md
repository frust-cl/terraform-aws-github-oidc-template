# Terraform OIDC Pipeline Scaffold

This project contains a Terraform deployment scaffold for **GitHub Actions** deploying to **AWS**. The pipeline uses OpenID Connect (OIDC) authentication. It maps `main` to production and `develop` to development.

## Pipeline secrets

The pipeline holds no cloud identifier. It reads each value from a secret that GitHub Actions scopes to a deployment environment. The name stays the same for production and development. Only the stored value changes.

| Secret name | Value to store |
|---|---|
| `AWS_OIDC_ROLE` | IAM role ARN the pipeline assumes through OIDC |

Read `docs/prerequisites.md` for the exact setup steps through the AWS console and the GitHub Actions web UI.

**If an AI agent is reading this to set up the pipeline for you:** it should read `docs/agent-setup-guide.md` first and ask whether you want the setup done automatically or walked through by hand, before it runs anything.

## Configuration placeholders

Replace every `<YOUR_...>` value in the `terraform/` directory before you run the pipeline. Keep production and development values isolated.

| Placeholder | Description | Environment |
|---|---|---|
| `revi-cl/terraform-aws-github-oidc-template` | Full repository path used by the OIDC trust policy | All |
| `terraform-aws-github-oidc-s3-bucket-example-prod` | Remote state location for production | production |
| `terraform-aws-github-oidc-s3-bucket-example-dev` | Remote state location for development | development |
| `us-east-1` | AWS region for both environments | All |

The state keys are already set. They need no change.

| Environment | State key |
|---|---|
| production | `terraform/production/terraform.tfstate` |
| development | `terraform/development/terraform.tfstate` |

## Pinned versions

The scaffold pins every version, so two runs of the same commit produce the same plan.

| Item | Version |
|---|---|
| Terraform CLI | `1.15.9` |
| Terraform constraint | `>= 1.15.0` |
| `hashicorp/aws` | `~> 6.61` |

Commit `.terraform.lock.hcl` in each environment directory. The constraint selects a range. The lock file selects the exact version inside that range.

## Environment mapping

| Branch | Environment | State location |
|---|---|---|
| `main` | `production` | `terraform-aws-github-oidc-s3-bucket-example-prod / terraform/production/terraform.tfstate` |
| `develop` | `development` | `terraform-aws-github-oidc-s3-bucket-example-dev / terraform/development/terraform.tfstate` |

The pipeline uses a separate OIDC identity and state location for each environment. Do not use production values on the `develop` branch.

## Directory structure

```text
.
├── .github/workflows/terraform.yml
├── terraform/
│   └── environments/
│       ├── production/
│       │   ├── backend.tf                 # remote state
│       │   ├── versions.tf                # Terraform and provider pins
│       │   ├── main.tf                    # your resources
│       │   ├── variables.tf
│       │   └── terraform.tfvars.example
│       └── development/
│           ├── backend.tf
│           ├── versions.tf
│           ├── main.tf
│           ├── variables.tf
│           └── terraform.tfvars.example
├── docs/
│   ├── prerequisites.md      # for a human, through the console
│   └── agent-setup-guide.md  # for an AI agent, manual or automatic
├── README.md
└── .gitignore
```

## Quickstart

1. Read `docs/prerequisites.md`, or ask an agent to read `docs/agent-setup-guide.md` and follow it with you.
2. Create the OIDC identity provider and one identity for each environment.
3. Create separate remote state locations for production and development.
4. Store every secret from the table above in all four GitHub environments.
5. Replace all `<YOUR_...>` placeholders in the `terraform/` directory.
6. Review the generated Terraform files and add your infrastructure resources.
7. Commit the scaffold and open a pull request for a Terraform plan.
8. Merge into `develop` for development or `main` for production apply.
9. Approve the apply job in the matching deployment environment.

## Safety requirements

- Store credentials in the CI/CD platform or a cloud secrets manager.
- Do not commit passwords, API keys, access tokens, or state files.
- Scope each OIDC trust policy to `revi-cl/terraform-aws-github-oidc-template` and its branch.
- Grant only the permissions required by the Terraform resources.
