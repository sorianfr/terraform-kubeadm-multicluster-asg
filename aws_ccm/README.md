# AWS CCM Fork

This directory captures the high-level adjustments required to deploy the Terraform + Ansible automation with the external AWS Cloud Controller Manager (CCM).

## Highlights

- Sets `enable_aws_ccm = true` for all clusters so the Terraform module renders kubeadm cloud-provider settings, IAM policies, subnet tags, and other prerequisites for the external CCM.
- Documents the post-provisioning Ansible workflow to install the AWS CCM components on the cluster.

## Usage

1. Copy the root `terraform.tfvars.example` into this directory and adjust it so every cluster block sets `enable_aws_ccm = true`. Provide `aws_ccm_image` if you need a custom controller image.
2. Run Terraform from the repository root as usual (the module automatically reads the per-cluster flag).
3. After Terraform finishes, connect to the bastion host and execute:

   ```bash
   cd ~/ansible
   ansible-playbook playbooks/5_install_aws_ccm.yml
   ```

4. Verify that the `aws-cloud-controller-manager` deployment in `kube-system` becomes ready and that Service or LoadBalancer resources reconcile correctly.

Refer to the repository `README.md` and `ansible/README.md` for the full provisioning workflow.
