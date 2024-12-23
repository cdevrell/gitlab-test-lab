# provider "aws" {
#   access_key = "mock_access_key"
#   secret_key = "mock_secret_key"
#   region     = "eu-west-2"
# }

module "s3" {
  source  = "git::http://gitlab.test.lab/dev/terraform-modules/s3.git"
}
