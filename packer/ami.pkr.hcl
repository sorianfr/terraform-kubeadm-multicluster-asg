packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.0.0"
    }
  }
}

# Fuente: Ubuntu 22.04 base
source "amazon-ebs" "ubuntu" {
  region           = "us-east-1"
  instance_type    = "t3.micro"
  ssh_username     = "ubuntu"
  ami_name         = "k8s-base-{{timestamp}}"
  associate_public_ip_address = true
  ssh_interface           = "public_ip"

  ssh_keypair_name        = "packer_ssh_NVirginia"             # Nombre del keypair en AWS
  ssh_private_key_file    = "packer_ssh_NVirginia.pem"  # Clave privada local
  ssh_timeout = "10m"

  source_ami_filter {
      filters = {
        name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
        root-device-type    = "ebs"
        virtualization-type = "hvm"
      }
      most_recent = true
      owners      = ["099720109477"]
    }

}

build {
  name    = "k8s-base-ami"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      "curl -o /tmp/setup_k8s_ec2.sh https://raw.githubusercontent.com/sorianfr/kubeadm_multinode_cluster_vagrant/master/setup_k8s_ec2.sh",
      "chmod +x /tmp/setup_k8s_ec2.sh",
      "sudo /tmp/setup_k8s_ec2.sh"
    ]
  }
}