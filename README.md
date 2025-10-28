# terraform-kubeadm-multicluster

This Terraform project provisions multiple self-managed Kubernetes clusters on AWS using kubeadm and Auto Scaling Groups (ASGs).
Each cluster has:
- 1 control-plane node
- Worker Auto Scaling Group
- Pod CIDR and Service CIDR configurable per cluster
- Permanent kubeadm join command stored securely in AWS Secrets Manager
- Optional AWS Cloud Controller Manager (CCM) configuration that enables the external AWS cloud provider integration when `enable_aws_ccm = true`

See `terraform.tfvars` for cluster definitions.


#PACKER
packer init .
packer build ami.pkr.hcl

#copia key a .ssh para poder hacer remote connect
cp ./k8s-key.pem /mnt/c/Users/soria/.ssh/k8s-key.pem


#ANSIBLE
ansible-playbook -i inventory/hosts.yml playbooks/setup_kubeconfigs.yml
kubectl config get-contexts

To deploy the AWS CCM on clusters that enable it, run `ansible-playbook playbooks/5_install_aws_ccm.yml` from the bastion or your local machine after provisioning. The playbook installs the controller only on clusters with `enable_aws_ccm` enabled.
