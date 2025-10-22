#!/bin/bash
set -xe

# Initialize control plane
sudo kubeadm reset -f || true
sudo systemctl stop kubelet || true

# --- Kubeadm Init ---
sudo kubeadm init \
  --pod-network-cidr=${pod_cidr} \
  --service-cidr=${service_cidr} \
  --apiserver-advertise-address=${controlplane_private_ip} \
  --kubernetes-version stable-1.31

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

if aws secretsmanager describe-secret --region "${region}" --secret-id "${cluster_name}/comando-unir" >/dev/null 2>&1; then
  echo "Updating join secret"
  aws secretsmanager update-secret \
    --region "${region}" \
    --secret-id "${cluster_name}/comando-unir" \
    --secret-string "$JOIN_CMD" || true
else
  echo "Creating join secret"
  aws secretsmanager create-secret \
    --region "${region}" \
    --name "${cluster_name}/comando-unir" \
    --secret-string "$JOIN_CMD" || true
fi

# --- Marker file ---
echo "User data completed successfully at $(date)" | sudo tee /var/log/user_data_done.log
