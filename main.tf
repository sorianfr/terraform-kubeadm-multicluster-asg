terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Index clusters by name for reuse
locals {
  clusters_by_name = {
    for cluster in var.clusters :
    cluster.name => cluster
  }
}



# Generate a TLS private key
resource "tls_private_key" "k8s_key_pair" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Key Pair
resource "aws_key_pair" "k8s_key_pair" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.k8s_key_pair.public_key_openssh
}

# Save the private key locally
resource "local_file" "save_private_key" {
  filename        = "${path.module}/${var.key_pair_name}.pem"
  content         = tls_private_key.k8s_key_pair.private_key_pem
  file_permission = "0600"

}

# Output the private key (for reference or debugging)
output "k8s_private_key" {
  value     = tls_private_key.k8s_key_pair.private_key_pem
  sensitive = true
}


# VPC for All Clusters
resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main_vpc"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidr_block
  map_public_ip_on_launch = true
  availability_zone       = var.availability_zone

  tags = {
    Name = "public_subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main_igw"
  }
}


# Route Table for Public Subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public_rt"
  }
}

# Associate Public Subnet with Public Route Table
resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Elastic IP for Shared NAT Gateway
resource "aws_eip" "shared_nat_eip" {

  tags = {
    Name = "shared_nat_eip"
  }
}

# Shared NAT Gateway
resource "aws_nat_gateway" "shared_nat_gw" {
  allocation_id = aws_eip.shared_nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "shared_nat_gw"
  }

  depends_on = [aws_eip.shared_nat_eip]
}

# Shared Private Route Table
resource "aws_route_table" "shared_private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.shared_nat_gw.id
  }

  tags = {
    Name = "shared_private_rt"
  }
}

# Shared Bastion Host (uses public subnet)
resource "aws_instance" "bastion" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = aws_key_pair.k8s_key_pair.key_name

  tags = {
    Name = "shared_bastion"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install -y curl wget unzip jq",
      "sudo apt install -y ansible", # Install Ansible
      "curl -LO https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl",
      "chmod +x kubectl",
      "sudo mv kubectl /usr/local/bin/",
      "kubectl version --client" # Verify kubectl installation
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.k8s_key_pair.private_key_pem
    host        = self.public_ip
  }

  depends_on = [local_file.save_private_key]

}

# Shared Bastion Host Security Group
resource "aws_security_group" "bastion_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Adjust for production environments
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "bastion_sg"
  }
}

# IAM Role for EC2 instances to access S3 and other resources
resource "aws_iam_role" "AmazonEBSCSIDriverRole" {
  name = "AmazonEBSCSIDriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.AmazonEBSCSIDriverRole.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
# Create instance profile to be attached to ec2 instances. 
resource "aws_iam_instance_profile" "AmazonEBS_instance_profile" {
  name = "AmazonEBS_instance_profile"
  role = aws_iam_role.AmazonEBSCSIDriverRole.name
}


module "clusters" {
  for_each = { for c in var.clusters : c.name => c }
  source   = "./modules/kubeadm_cluster"

  name            = each.value.name
  region          = var.region
  vpc_id          = aws_vpc.main_vpc.id
  vpc_cidr_block         = var.vpc_cidr_block
  availability_zone = var.availability_zone
  private_route_table_id = aws_route_table.shared_private_rt.id
  controlplane_private_ip  = each.value.controlplane_private_ip
  private_subnet_cidr_block = each.value.private_subnet_cidr_block
  key_name               = aws_key_pair.k8s_key_pair.key_name
  iam_instance_profile   = aws_iam_instance_profile.AmazonEBS_instance_profile.name
  public_sg_id           = aws_security_group.bastion_sg.id
  bastion_public_dns     = aws_instance.bastion.public_dns
  instance_type   = each.value.instance_type
  worker_min      = each.value.worker_min
  worker_max      = each.value.worker_max
  worker_desired  = each.value.worker_desired
  pod_cidr        = each.value.pod_cidr
  service_cidr    = each.value.service_cidr
  enable_aws_ccm  = each.value.enable_aws_ccm

    depends_on = [aws_nat_gateway.shared_nat_gw]
}

resource "null_resource" "copy_files_to_bastion" {
  provisioner "local-exec" {
    command = <<-EOT
      sleep 60
      for file in ${join(" ", var.copy_files_to_bastion)}; do
        echo "Copying $file to bastion"
        scp -i "${var.key_pair_name}.pem" -o StrictHostKeyChecking=no "$file" ubuntu@${aws_instance.bastion.public_dns}:~/
      done
    EOT
  }
}


resource "null_resource" "copy_ansible_to_bastion" {
  depends_on = [aws_instance.bastion, local_file.ansible_inventory]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Copying ansible directory to bastion..."
      # First copy the directory
      scp -i "${path.module}/${var.key_pair_name}.pem" -o StrictHostKeyChecking=no -r ${path.module}/ansible ubuntu@${aws_instance.bastion.public_dns}:~/
      # Then copy the generated inventory file specifically
      scp -i "${path.module}/${var.key_pair_name}.pem" -o StrictHostKeyChecking=no ${path.module}/ansible/inventory/hosts.yml ubuntu@${aws_instance.bastion.public_dns}:~/ansible/inventory/hosts.yml
    EOT
  }
}

#---------------------------------------------
# Generate Ansible inventory from Terraform outputs
#---------------------------------------------

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory/hosts.yml"
  content = templatefile("${path.module}/templates/ansible_inventory.yml.tpl", {
    bastion_public_dns = aws_instance.bastion.public_dns
    clusters = {
      for c in var.clusters : c.name => {
        controlplane_private_ip = c.controlplane_private_ip
        pod_cidr                = c.pod_cidr
        service_cidr            = c.service_cidr
      }
    }
    ssh_key_path = "/home/ubuntu/${var.key_pair_name}.pem"
  })
}

#---------------------------------------------
# Outputs for Ansible inventory generation
#---------------------------------------------

output "bastion_public_dns" {
  description = "Public DNS of the bastion host"
  value       = aws_instance.bastion.public_dns
}

output "clusters" {
  description = "Map of clusters with control plane IP and pod/service CIDRs"
  value = {
    for c in var.clusters : c.name => {
      controlplane_private_ip = try(c.controlplane_private_ip, null)
      pod_cidr                = try(c.pod_cidr, null)
      service_cidr            = try(c.service_cidr, null)
    }
  }
}

output "kubeconfig_locations" {
  description = "Kubeconfig file locations on bastion host"
  value = {
    for c in var.clusters : c.name => "~/ansible/kubeconfigs/${c.name}-kubeconfig.yaml"
  }
}

resource "local_file" "ansible_all_group_vars" {
  filename = "${path.module}/ansible/group_vars/all.yml"
  content = yamlencode({
    bastion_host = aws_instance.bastion.public_dns

    calico_version_default = "v3.27.0"
    encapsulation_default  = "VXLANCrossSubnet"
    bgp_default            = "Enabled"
    nat_outgoing_default   = "Enabled"
    block_size_default     = 26
    aws_region             = var.region
    aws_ccm_image_default  = "registry.k8s.io/provider-aws/cloud-controller-manager:v1.29.0"
    clusters = {
      for cluster in var.clusters : cluster.name => {
        controlplane_ip = cluster.controlplane_private_ip
        pod_cidr        = cluster.pod_cidr
        service_cidr    = cluster.service_cidr
        kubeconfig      = "~/ansible/kubeconfigs/${cluster.name}-kubeconfig.yaml"
        calico_version  = try(cluster.calico_version, null)
        encapsulation   = try(cluster.encapsulation, null)
        bgp             = try(cluster.bgp, null)
        nat_outgoing    = try(cluster.nat_outgoing, null)
        block_size      = try(cluster.block_size, null)
        enable_aws_ccm  = try(cluster.enable_aws_ccm, false)
        aws_ccm_image   = try(cluster.aws_ccm_image, null)
      }
    }
  })
}
resource "local_file" "ansible_cluster_group_vars" {
  for_each = {
    for c in var.clusters : c.name => c
  }

  filename = "${path.module}/ansible/group_vars/${each.key}.yml"

  content = yamlencode({
    controlplane_ip = each.value.controlplane_private_ip
    pod_cidr        = each.value.pod_cidr
    service_cidr    = each.value.service_cidr
    kubeconfig      = "~/ansible/kubeconfigs/${each.key}-kubeconfig.yaml"

    calico_version  = try(each.value.calico_version, null)
    encapsulation   = try(each.value.encapsulation, null)
    bgp             = try(each.value.bgp, null)
    nat_outgoing    = try(each.value.nat_outgoing, null)
    block_size      = try(each.value.block_size, null)
    enable_aws_ccm  = try(each.value.enable_aws_ccm, false)
    aws_ccm_image   = try(each.value.aws_ccm_image, null)
    aws_region      = var.region
  })
}

# ===========================================================
# Copy kubeconfigs from control planes to bastion host
# ===========================================================
resource "null_resource" "copy_kubeconfigs_to_bastion" {
  for_each = module.clusters

  provisioner "remote-exec" {
    inline = [
      "set -euxo pipefail",

      "echo '=== Running kubeconfig copy on bastion for ${each.key} ==='",
      "mkdir -p ~/ansible/kubeconfigs",

      "echo 'Checking SSH connectivity to ${each.value.controlplane_private_ip}'",
      "ssh -i ~/k8s-key.pem -o StrictHostKeyChecking=no ubuntu@${each.value.controlplane_private_ip} 'echo Connected OK'",

      "echo 'Waiting for admin.conf on ${each.key} ...'",
      "until ssh -i ~/k8s-key.pem -o StrictHostKeyChecking=no ubuntu@${each.value.controlplane_private_ip} 'test -f /etc/kubernetes/admin.conf' 2>/dev/null; do echo 'Still waiting...'; sleep 10; done",

      "echo 'Copying kubeconfig for ${each.key} ...'",
      "scp -i ~/k8s-key.pem -o StrictHostKeyChecking=no ubuntu@${each.value.controlplane_private_ip}:/etc/kubernetes/admin.conf ~/ansible/kubeconfigs/${each.key}-kubeconfig.yaml",

      "echo '✅ Copied ~/ansible/kubeconfigs/${each.key}-kubeconfig.yaml successfully'"
    ]

    connection {
      type        = "ssh"
      host        = aws_instance.bastion.public_ip
      user        = "ubuntu"
      private_key = tls_private_key.k8s_key_pair.private_key_pem
    }
  }

 
  depends_on = [
    aws_instance.bastion,
    module.clusters
  ]
}
