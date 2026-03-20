# Remote NVIDIA GPU Guide for AIC Isaac Lab

If you are running on a remote Ubuntu machine with an NVIDIA GPU (where you likely do not have a physical monitor attached), follow this streamlined guide to install and utilize the vectorized `aic_isaaclab` environment for massively parallel Reinforcement Learning or data generation.

## 1. Prerequisites (Host Machine)

Since you are running remotely, Isaac Lab will run via Docker with GPU passthrough. You must configure the NVIDIA Container Toolkit.

```bash
# Ensure Docker is installed, then install NVIDIA Container Toolkit
# (Instructions for Ubuntu)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit

# Configure Docker to use the NVIDIA runtime natively
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

## 2. Repository Setup

Clone both the Isaac Lab repository and the AIC challenge repository. The AIC repo *must* be cloned inside the IsaacLab folder.

```bash
cd ~
# Clone Isaac Lab (tested on version 2.3.2)
git clone git@github.com:isaac-sim/IsaacLab.git

# Clone the AIC toolkit into the Isaac Lab directory
cd ~/IsaacLab
git clone git@github.com:intrinsic-dev/aic.git
```

## 3. Install the Secret NVIDIA Assets

Because Isaac Sim relies on raw Universal Scene Description (`.usd`) files, the NVIDIA team provides pre-compiled assets for the challenge that are not in the raw GitHub repo.

1. **Download the pack:** [Intrinsic_assets.zip](https://developer.nvidia.com/downloads/Omniverse/learning/Events/Hackathons/Intrinsic_assets.zip) 
2. **Extract it** directly into the Isaac lab environment folder:
   ```bash
   # Target directory:
   ~/IsaacLab/aic/aic_utils/aic_isaac/aic_isaaclab/source/aic_task/aic_task/tasks/manager_based/aic_task/
   ```
   *(Ensure the `Intrinsic_assets/` folder sits exactly inside `/manager_based/aic_task/`)*

## 4. Build and Enter the Isaac Lab Container

Isaac Lab handles its own Docker networking and build system using a `container.py` script.

```bash
cd ~/IsaacLab

# Build the foundational Isaac Lab image
./docker/container.py build base

# Start the container in the background
./docker/container.py start base

# Enter the container interactively
./docker/container.py enter base
```

## 5. Install the AIC Task (Inside the Container)

Once your prompt changes to indicate you are inside the Isaac Lab container, install the challenge extension in editable mode:

```bash
python -m pip install -e aic/aic_utils/aic_isaac/aic_isaaclab/source/aic_task
```

---

## 6. Remote Usage & Headless Execution

Because you are on a remote server, **running GUI scripts (like keyboard teleoperation) will crash if you do not attach a headless flag or configure an Omniverse stream.**

For massive continuous data generation or RL training, append the `--headless` flag.

### Reinforcement Learning (Headless)
To train a massively parallel PPO agent using `rsl-rl`:

```bash
isaaclab -p aic/aic_utils/aic_isaac/aic_isaaclab/scripts/rsl_rl/train.py \
    --task AIC-Task-v0  \
    --num_envs 2048 \
    --enable_cameras \
    --headless
```
*(This commands Isaac Sim to simulate 2,048 robot arms simultaneously without rendering a GUI output to a monitor, strictly utilizing the GPU compute).*

### Data Collection (Headless Sandbox)
If you just want to generate standard datasets passively:
```bash
isaaclab -p aic/aic_utils/aic_isaac/aic_isaaclab/scripts/record_demos.py \
    --task AIC-Task-v0 \
    --dataset_file ./datasets/dataset.hdf5 \
    --num_demos 1000 \
    --headless
```

### Viewing the Simulation Remotely (WebRTC / Livestream)
If you *must* view the teleoperation or the training rendering from your local laptop while the simulation runs on the remote GPU, Isaac Sim supports streaming. You can typically enable this using flags built into IsaacLab (e.g. `--enable_webrtc` or `--livestream 1`) which allows you to view the Isaac Sim GUI in your browser at `http://<remote-ip>:8211`.
