# Terraform provider configuration.
#
# This repo targets AWS (eu-west-2 / London) and uses the AWS provider to create
# the ALB, security groups, EC2 instance, and related networking resources.

# AWS Provider block: Configures the AWS region for resource deployment.
provider "aws" {
  region = "eu-west-2" # Sets AWS region to London (eu-west-2).
}