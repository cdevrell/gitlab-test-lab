terraform {
  required_providers {
    # aws = {
    #   source  = "hashicorp/aws"
    #   version = "~> 5.0"
    # }
    null = {
      source = "hashicorp/null"
      version = ">=3.2.3"
    }
  }
}

resource "null_resource" "mock-bucket-resource" {
  # bucket = "my-bucket"
}

# resource "aws_s3_bucket" "test-bucket" {
#   bucket = "my-bucket"
# }
