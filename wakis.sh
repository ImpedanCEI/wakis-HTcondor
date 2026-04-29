#!/bin/bash
source /afs/cern.ch/work/e/edelafue/miniconda3/etc/profile.d/conda.sh
conda activate wakis-env

export UCX_TLS=rc,tcp,cuda_copy,cuda_ipc
export HDF5_USE_FILE_LOCKING=FALSE

# Working directory (the folder you want to serve)
WORKDIR=/afs/cern.ch/work/e/edelafue/wakis
cd "$WORKDIR"

# Pick a port in a safe range to avoid collisions
PORT=$((8800 + RANDOM % 200))
HOSTNAME=$(hostname -f)

echo "============================================"
echo "  Worker node : $HOSTNAME"
echo "  Jupyter port: $PORT"
echo "  Working dir : $WORKDIR"
echo "============================================"

nvidia-smi

# Find which specific lxplus node we land on (lxplus is load-balanced)
LXPLUS_NODE=$(ssh -o StrictHostKeyChecking=no \
                  -o BatchMode=yes \
                  -o ConnectTimeout=10 \
                  lxplus.cern.ch hostname -f 2>/dev/null)

if [[ -z "$LXPLUS_NODE" ]]; then
    echo "ERROR: Could not reach lxplus. Check SSH key setup (see readme)."
    exit 1
fi

echo "============================================"
echo "  lxplus node : ${LXPLUS_NODE}"
echo "============================================"
echo "Tunnel from your laptop:"
echo "  ssh -L ${PORT}:localhost:${PORT} ${LXPLUS_NODE} -N"
echo "Then open: http://localhost:${PORT}"
echo "============================================"

# Open a reverse tunnel to that exact lxplus node
ssh -f -N -R ${PORT}:localhost:${PORT} ${LXPLUS_NODE} \
    -o StrictHostKeyChecking=no \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3

jupyter lab \
    --no-browser \
    --port="$PORT" \
    --ip=localhost \
    --notebook-dir="$WORKDIR" \
    --IdentityProvider.token='' \
    --ServerApp.password=''

