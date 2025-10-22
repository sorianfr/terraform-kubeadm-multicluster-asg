#!/bin/bash
set -xe

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

echo "Waiting for join command secret:..."
RETRIES=60
DELAY=10

for ((i=1; i<=RETRIES; i++)); do
  if aws secretsmanager describe-secret --region "${region}" --secret-id "${cluster_name}/comando-unir" >/dev/null 2>&1; then
    echo "Secret found after $i attempts."
    break
  fi
  echo "Secret not yet available. Retrying in $DELAY seconds... ($i/$RETRIES)"
  sleep $DELAY
done

# If still not found after all retries, log and exit
if ! aws secretsmanager describe-secret --region "${region}" --secret-id "${cluster_name}/comando-unir" >/dev/null 2>&1; then
  echo "ERROR: Secret not found after $((RETRIES * DELAY)) seconds." >&2
  exit 1
fi

# ==========
# Fetch and execute join command
# ==========

JOIN_CMD=$(aws secretsmanager get-secret-value \
  --region "${region}" \
  --secret-id "${cluster_name}/comando-unir" \
  --query SecretString \
  --output text)

echo "Running join command..."
$JOIN_CMD

# ==========
# Done
# ==========

echo "Worker joined the cluster successfully" | sudo tee /var/log/worker_join_done.log


# Enable kubelet
systemctl enable --now kubelet