#!/bin/bash
# start_env_headless.sh

# 1. Ensure docker is used as the container manager
export DBX_CONTAINER_MANAGER=docker

# 2. Re-create the distrobox container instance (idempotent if it exists but stopped)
distrobox create -r --nvidia -i ghcr.io/intrinsic-dev/aic/aic_eval:latest aic_eval

# 3. Enter the container and launch the environment without GUI
echo "Starting simulation headlessly..."
distrobox enter -r aic_eval -- /entrypoint.sh \
  ground_truth:=true \
  start_aic_engine:=true \
  gazebo_gui:=false \
  launch_rviz:=false