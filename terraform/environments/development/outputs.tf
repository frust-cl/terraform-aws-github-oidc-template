output "cloudfront_domain" {
  description = "CloudFront distribution domain name for the Frustie static site."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID, used by the pipeline to invalidate the cache after deploy."
  value       = aws_cloudfront_distribution.site.id
}

output "site_bucket_name" {
  description = "S3 bucket name where site content is stored."
  value       = aws_s3_bucket.site.id
}
