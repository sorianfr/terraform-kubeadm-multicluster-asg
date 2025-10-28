# terraform-kubeadm-multicluster

This Terraform project provisions multiple self-managed Kubernetes clusters on AWS using kubeadm and Auto Scaling Groups (ASGs).
Each cluster has:
- 1 control-plane node
- Worker Auto Scaling Group
- Pod CIDR and Service CIDR configurable per cluster
- Permanent kubeadm join command stored securely in AWS Secrets Manager

See `terraform.tfvars` for cluster definitions.


#PACKER
packer init .
packer build ami.pkr.hcl

#copia key a .ssh para poder hacer remote connect
cp ./k8s-key.pem /mnt/c/Users/soria/.ssh/k8s-key.pem


#ANSIBLE
ansible-playbook -i inventory/hosts.yml playbooks/setup_kubeconfigs.yml
kubectl config get-contexts