output "state_bucket_name" { value = aws_s3_bucket.terraform_state.bucket }
output "state_bucket_arn" { value = aws_s3_bucket.terraform_state.arn }
output "dynamodb_table_name" { value = aws_dynamodb_table.terraform_locks.name }
output "app_cache_bucket_name" { value = aws_s3_bucket.app_cache.bucket }
output "app_cache_bucket_arn" { value = aws_s3_bucket.app_cache.arn }
