Wakis simulations on HTCondor
===

HTCondor is CERN's batch system that give us access to very computationally powerfull resources to run simulations non-interactively, submitted via CERN's `lxplus`.

For Wakis simulations, it is very useful to inspect the generated grid and material tensors before submitting the simulation job. Furthermore, it is needed to check this tensor generation on an equally powerful node as the submission node. This motivates connecting to HTCondor nodes interactively.

*And this is exactly what this guide is about!*

## 1. Prepare you Python instalation

The setup assumes that you have a working python installation in your `afs/WORK` folder or CERNBox `eos/` folder. Alternatively, a version that sources a `cvmfs` docker container can be easily implemented from this guide. Everything can be accessed from lxplus:
```
ssh -XY username@lxplus.cern.ch
```

Following the [Wakis installation guide](https://wakis.readthedocs.io/en/latest/installation.html), the most updated setup would be:

 ### Get your miniconda/miniforge:
 In your `/afs/cern.ch/work/e/$USER/`
 ```bash
 cd /afs/cern.ch/work/${USER::1}/$USER/
 # get, install and activate miniforge
wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
bash Miniforge3-$(uname)-$(uname -m).sh
conda activate
 ```

 ### Install Wakis dependencies in a new environment

 ```bash
 # Multithreaded numpy
conda create --name wakis-env python=3.12 numpy scipy mkl mkl-service
pip install sparse_dot_mkl
# Wakis dependencies
pip install wakis['all']
# For CUDA 12.x
pip install cupy-cuda12x
```

### Clone and install Wakis in editable mode
 In your `/afs/cern.ch/work/${USER::1}/$USER/`
```bash
cd /afs/cern.ch/work/${USER::1}/$USER/
https://github.com/ImpedanCEI/Wakis.git
pip uninstall wakis
cd Wakis
pip install -e .
```

## 2. HTcondor submission scripts

To submit jobs to HTcondor, one needs a submission file `.sub` that helps the batch system distribute the nodes according to the user's needs. The following `.sub` file will request 1 GPU from a new generation H100, A100, H200. The `flavour` specifies the length of the simulation and should be adjusted according to [the HTcondor guidelines](https://batchdocs.web.cern.ch/local/submit.html). One can leave `espresso` (20') for quick tests, and change to `workday` (8h) when running interactive simulations. The way to submit the script is:

```
myschedd bump
condor_submit -i wakis.sub
```


* wakis.sub: 
```bash
if !defined FNAME
    FNAME               = jupyter_notebook
endif

ID                      = $(Cluster).$(Process)

output                  = ./logs/$(FNAME).$(ID).out
error                   = ./logs/$(FNAME).$(ID).err
log                     = ./logs/$(FNAME).$(Cluster).log

should_transfer_files   = NO

request_GPUs            = 1
request_CPUs            = 1
request_memory          = 32GB
requirements            = GPUs_Capability >= 8.0
+JobFlavour             = "espresso"
+AccountingGroup        = your_acct_group

executable              = wakis.sh

queue 1
```

The other script we need is the one to execute on the node that has been allocated to us based on the submission script. The following script will spawn a `jupyer notebook` on the node, and reverse tunnel back to `lxplus` so we can forward tunnel it to our local PC and open it in the browser. The working folder can also be set to something different than AFS, and could be in `eos/` for example. 

* wakis.sh

```bash
#!/bin/bash
source /afs/cern.ch/work/${USER::1}/$USER/miniconda3/etc/profile.d/conda.sh
conda activate wakis-env

export UCX_TLS=rc,tcp,cuda_copy,cuda_ipc
export HDF5_USE_FILE_LOCKING=FALSE

# Working directory (the folder you want to serve)
WORKDIR=/afs/cern.ch/work/${USER::1}/$USER/Wakis
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

```

## 3. Tunneling your jupyter notebook back to your local PC. 

The script in `wakis.sh` is setup so it prints the necessary instructions for you to copy paste in your local PC. It will be in the form of (with different port and node number):

```
ssh -L 8889:localhost:8889 lxplus928.cern.ch -N
```

Once this tunnel is running, you will be able to open the jupyter notebook from the browser on (in the case of the previous example): http://localhost:8889

### PyVista plots troubleshooting

If the PyVista interactive plots are not working out-of-the-box, these lines should be added to the imports cell:

```python
pv.global_theme.trame.server_proxy_enabled = True
pv.global_theme.trame.server_proxy_prefix = '/proxy/'
pv.global_theme.window_size = [600, 400] # optional 
```
