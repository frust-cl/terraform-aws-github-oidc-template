# Production remote state: Amazon S3.
#
# State always lives in the cloud this environment deploys to. The pipeline
# reaches this bucket with the same OIDC identity it uses for the resources,
# so no separate credential is required.
#
# Locking uses the S3 native lock file. DynamoDB locking is deprecated.

terraform {
  backend "s3" {
    bucket       = "terraform-aws-github-oidc-s3-bucket-example-prod"
    key          = "terraform/production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
