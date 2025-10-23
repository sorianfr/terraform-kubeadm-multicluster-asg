# Kubeadm cluster module

# Obtener última AMI de Packer
data "aws_ami" "k8s_base" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["k8s-base-*"]
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Private Subnet
resource "aws_subnet" "k8s_private_subnet" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidr_block
  map_public_ip_on_launch = false
  availability_zone       = var.availability_zone

  tags = {
    Name = "${var.name}_private_subnet"
  }
}


# Associate Private Subnet with Private Route Table
resource "aws_route_table_association" "private_rta" {
  subnet_id      = aws_subnet.k8s_private_subnet.id
  route_table_id = var.private_route_table_id
}

locals {
      sg_name = "k8s_sg_${var.name}"
}

# Security Group
resource "aws_security_group" "k8s_sg" {
  name        = local.sg_name
  vpc_id = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [var.public_sg_id] # Allow SSH from the bastion
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block] # Kubernetes API access within VPC
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block] # NodePort range within VPC
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block] # # Kubelet communication within VPC
  }

  ingress {
    from_port   = 5473
    to_port     = 5473
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block] # Service communication within VPC
  }

  # BGP for Calico
  ingress {
    from_port   = 179
    to_port     = 179
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block] # Ensure this matches the pod network CIDR
  }

  # Allow VXLAN for Calico (UDP 4789)
  ingress {
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr_block] # Allow from entire VPC
  }

  # Allow pod-to-pod communication within the cluster
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.pod_cidr] # Pod network CIDR
  }

  # Allow IP-in-IP (used by Calico)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "4" # Protocol 4 is for IP-in-IP
    cidr_blocks = [var.pod_cidr] # Pod network CIDR
  }

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "4" # Protocol 4 is for IP-in-IP
    cidr_blocks = [var.vpc_cidr_block] # Pod network CIDR
  }

  # etcd Communication (Control Plane Only)
  ingress {
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["${var.controlplane_private_ip}/32"] # Restrict to control plane's private IP
  }

  # kube-scheduler and kube-controller-manager
  ingress {
    from_port   = 10259
    to_port     = 10259
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    from_port   = 10257
    to_port     = 10257
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" 
    cidr_blocks = [var.pod_cidr] # Pod network CIDR
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" 
    cidr_blocks = [var.vpc_cidr_block] # Pod network CIDR
  }   

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s_sg"
  }
}

resource "aws_security_group_rule" "ssh_within_group" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.k8s_sg.id
  source_security_group_id = aws_security_group.k8s_sg.id
  description              = "Allow SSH within the security group"
}





# Control-plane IAM role
resource "aws_iam_role" "cp_role" {
  name               = "${var.name}-cp-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "cp_profile" {
  name = "${var.name}-cp-profile"
  role = aws_iam_role.cp_role.name
}

resource "aws_iam_role_policy" "cp_secrets" {
  role = aws_iam_role.cp_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:ListSecrets"
      ],
      Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name}/comando-unir*"
    }]
  })
}

# Worker IAM role
resource "aws_iam_role" "worker_role" {
  name               = "${var.name}-worker-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_instance_profile" "worker_profile" {
  name = "${var.name}-worker-profile"
  role = aws_iam_role.worker_role.name
}

resource "aws_iam_role_policy" "worker_secrets" {
  role = aws_iam_role.worker_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.name}/comando-unir*"
    }]
  })
}

# Attach the AmazonSSMManagedInstanceCore policy for SSM connectivity
resource "aws_iam_role_policy_attachment" "worker_ssm_core" {
  role       = aws_iam_role.worker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_secretsmanager_secret" "join_command" {
  name        = "${var.name}/comando-unir"
  description = "Join command for Kubernetes workers in ${var.name}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "join_command_placeholder" {
  secret_id     = aws_secretsmanager_secret.join_command.id
  secret_string = "waiting-for-controlplane"
}



# Control plane instance
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.k8s_base.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.k8s_private_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.cp_profile.name
  key_name               = var.key_name
  private_ip             = var.controlplane_private_ip

  user_data = templatefile("${path.module}/templates/control_plane_userdata.sh.tpl", {
    cluster_name = var.name
    pod_cidr     = var.pod_cidr
    service_cidr = var.service_cidr
    controlplane_private_ip = var.controlplane_private_ip
    region                  = var.region

  })

  source_dest_check = false # Disable Source/Destination Check

  tags = { Name = "${var.name}-control-plane" }
}

output "control_plane_userdata" {
  value = templatefile("${path.module}/templates/control_plane_userdata.sh.tpl", {
    cluster_name            = var.name
    pod_cidr                = var.pod_cidr
    service_cidr            = var.service_cidr
    controlplane_private_ip = var.controlplane_private_ip
    region                  = var.region
  })
}

# Worker launch template
resource "aws_launch_template" "worker_lt" {
  name_prefix   = "${var.name}-worker-"
  image_id = data.aws_ami.k8s_base.id
  instance_type = var.instance_type

  iam_instance_profile { name = aws_iam_instance_profile.worker_profile.name }

  user_data = base64encode(templatefile("${path.module}/templates/worker_userdata.sh.tpl", {
    cluster_name = var.name
    region = var.region
    controlplane_private_ip = var.controlplane_private_ip

  }))

  depends_on = [
    aws_instance.control_plane,  # ensure the control plane is provisioned
    aws_iam_role.worker_role,    # ensure IAM ready
    aws_iam_instance_profile.worker_profile,
    aws_iam_role_policy.worker_secrets
  ]
}

# Worker ASG
resource "aws_autoscaling_group" "workers" {
  name                = "${var.name}-workers"
  desired_capacity    = var.worker_desired
  min_size            = var.worker_min
  max_size            = var.worker_max
  vpc_zone_identifier = [aws_subnet.k8s_private_subnet.id]
  health_check_type         = "EC2"
  health_check_grace_period = 300
  wait_for_capacity_timeout = "10m"



  launch_template {
    id      = aws_launch_template.worker_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-worker"
    propagate_at_launch = true
  }
  tag {
    key                 = "Cluster"
    value               = var.name
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "worker"
    propagate_at_launch = true
  }

}
