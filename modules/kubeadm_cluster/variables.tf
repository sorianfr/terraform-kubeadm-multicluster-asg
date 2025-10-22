variable "name" {}
variable "region" {}

variable "instance_type" {}


variable "availability_zone" {
  description = "Availability zone for the resources"
  type        = string
}

variable "worker_min" {
  description = "Minimum number of worker nodes in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "worker_max" {
  description = "Maximum number of worker nodes in the Auto Scaling Group"
  type        = number
  default     = 3
}

variable "worker_desired" {
  description = "Desired number of worker nodes in the Auto Scaling Group"
  type        = number
  default     = 1
}

variable "key_name" {
  description = "Name of the SSH key pair to use for instances"
  type        = string
}


variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "private_subnet_cidr_block" {
  description = "CIDR block for the private subnet"
  type        = string
}


variable "controlplane_private_ip" {
  description = "Private IP of the control plane"
  type        = string
}

variable "pod_cidr" {
  description = "CIDR block for the pod network"
  type        = string
}

variable "service_cidr" {
  description = "CIDR block for the Kubernetes Services"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the Kubernetes cluster"
  type        = string
}

variable "private_route_table_id" {
  description = "Route table ID for the private subnet"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile for EC2 instances"
  type        = string
}

variable "public_sg_id" {
  description = "The ID of the public security group"
  type        = string
}

variable "bastion_public_dns" {
  description = "Public DNS of the bastion host"
  type        = string
}

variable "worker_ebs_volumes" {
  description = "Optional list of EBS volumes to attach to each worker node"
  type = list(object({
    device_name = string
    volume_size = number
    volume_type = string
  }))
  default = []
}
