#!/bin/bash
set -xe

# Configure kubelet for external cloud provider if required
%{ if enable_aws_ccm }
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
PROVIDER_ID="aws:///$${AVAILABILITY_ZONE}/$${INSTANCE_ID}"

sudo systemctl stop kubelet || true
sudo mkdir -p /etc/systemd/system/kubelet.service.d
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/20-cloud-provider.conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--cloud-provider=external --provider-id=$${PROVIDER_ID}"
EOF
sudo systemctl daemon-reload
%{ endif }

# Wait for the API server to be ready before attempting to join
echo "Waiting for API server at $API_SERVER:$PORT to be ready..."

for i in {1..60}; do
  if nc -z -w3 "${controlplane_private_ip}" 6443; then
    echo "API server is ready!"
    break
  fi
  echo "API server not ready yet... retrying in 10s"
  sleep 10
done
# ==========
# Wait for the join command secret
# ==========

# Wait until secret is updated
echo "Waiting for join command secret..."
until JOIN_CMD=$(aws secretsmanager get-secret-value \
  --region "${region}" \
  --secret-id "${cluster_name}/comando-unir" \
  --query SecretString \
  --output text 2>/dev/null) && [[ "$JOIN_CMD" != "waiting-for-controlplane" ]]; do
  echo "Join command not yet available. Retrying..."
  sleep 10
done

# Execute join command
echo "Running: $JOIN_CMD"
eval $JOIN_CMD
# ==========
# Done
# ==========

echo "Worker joined the cluster successfully" | sudo tee /var/log/worker_join_done.log


# Enable kubelet
systemctl enable --now kubelet
