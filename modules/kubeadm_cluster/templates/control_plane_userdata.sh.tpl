#!/bin/bash
set -xe

# Initialize control plane
sudo kubeadm reset -f || true
sudo systemctl stop kubelet || true

# --- Kubeadm Init ---
%{ if enable_aws_ccm }
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
PROVIDER_ID="aws:///$${AVAILABILITY_ZONE}/$${INSTANCE_ID}"

sudo mkdir -p /etc/systemd/system/kubelet.service.d
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/20-cloud-provider.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external --provider-id=$${PROVIDER_ID}"
EOF
sudo systemctl daemon-reload

cat <<EOF | sudo tee /tmp/kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: stable-1.31
networking:
  podSubnet: ${pod_cidr}
  serviceSubnet: ${service_cidr}
controllerManager:
  extraArgs:
    cloud-provider: external
    configure-cloud-routes: "false"
    cluster-name: ${cluster_name}
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${controlplane_private_ip}
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
    provider-id: $${PROVIDER_ID}
EOF

sudo kubeadm init --config /tmp/kubeadm-config.yaml
%{ else }
sudo kubeadm init \
  --pod-network-cidr=${pod_cidr} \
  --service-cidr=${service_cidr} \
  --apiserver-advertise-address=${controlplane_private_ip} \
  --kubernetes-version stable-1.31
%{ endif }

# ==========
# Configure kubeconfig for ubuntu user
# ==========
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config


# --- Store join command in Secrets Manager ---
# Properly quote the join command so AWS CLI receives it as a single argument
JOIN_CMD="$(kubeadm token create --ttl 0 --print-join-command || echo 'failed')"
JOIN_CMD="$JOIN_CMD --cri-socket unix:///var/run/containerd/containerd.sock"

# Update existing secret (created by Terraform)
echo "Updating join command in Secrets Manager..."
aws secretsmanager put-secret-value \
  --region "${region}" \
  --secret-id "${cluster_name}/comando-unir" \
  --secret-string "$JOIN_CMD" || true
  
# --- Marker file ---
echo "User data completed successfully at $(date)" | sudo tee /var/log/user_data_done.log
