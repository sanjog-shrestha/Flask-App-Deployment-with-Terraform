# Variable for selecting the EC2 instance type. Default is t3.micro (cost-efficient, current-gen).
variable "instance_type" {
    default = "t3.micro"
}

# Variable for specifying the AMI ID for Ubuntu. Default points to a specific Ubuntu AMI.
variable "ami_id" {
    default = "ami-018ff7ece22bf96db"
}