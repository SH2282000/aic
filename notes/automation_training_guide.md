# Automation and Training Guide

This guide provides automated scripts to run the environment headlessly and record data, along with best practices for training a visual policy using the `CheatCode` expert.

## 1. Automation Scripts

Since you are running remotely on an Ubuntu GPU machine and Guacamole/VNC struggles with Docker GUIs, running headlessly is required. The launch file `aic_gz_bringup.launch.py` supports `gazebo_gui:=false` and `launch_rviz:=false` flags.

### Script 1: `start_env_headless.sh`
This script sets up Distrobox and launches the evaluation container headlessly. It importantly sets `ground_truth:=true` so the exact port coordinates are published for the `CheatCode` policy to use.

Save this as `~/ws_aic/start_env_headless.sh` and run `chmod +x ~/ws_aic/start_env_headless.sh`:

```bash
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
```

### Script 2: `record_cheat_data.sh`
Once Terminal 1 is running and the "aic_engine initialized" log appears, run this script in a second terminal to automatically launch the `CheatCode` policy and record its actions.

Save this as `~/ws_aic/record_cheat_data.sh` and run `chmod +x ~/ws_aic/record_cheat_data.sh`:

```bash
#!/bin/bash
# record_cheat_data.sh

# Navigate to the workspace
cd ~/ws_aic/src/aic

# 1. Start recording the ROS 2 bag in the background
echo "Starting ROS 2 bag recording..."
pixi run ros2 bag record -o cheatcode_data_$(date +%Y%m%d_%H%M%S) \
  /left_camera/image /center_camera/image /right_camera/image \
  /left_camera/camera_info /center_camera/camera_info /right_camera/camera_info \
  /joint_states /gripper_state /fts_broadcaster/wrench \
  /aic_controller/pose_commands /aic_controller/joint_commands \
  /tf /ground_truth_poses &
RECORD_PID=$!

# Wait a moment to ensure recording has started
sleep 2

# 2. Run the CheatCode policy
echo "Running CheatCode policy..."
pixi run ros2 run aic_model aic_model --ros-args -p use_sim_time:=true -p policy:=aic_example_policies.ros.CheatCode

# 3. Once the policy finishes (or you Ctrl+C it), stop the recording gracefully
echo "Policy finished, stopping bag recording..."
kill -s SIGINT $RECORD_PID
wait $RECORD_PID
echo "Dataset saved successfully."
```

---

## 2. Best Practices for Training on the "Cheat" Policy

You are employing **Imitation Learning (IL) / Behavior Cloning (BC)**. The `CheatCode` policy is your "Expert", and you are training a "Student" (like ACT, Diffusion Policy, etc.).

Your student must work when `ground_truth:=false` (during evaluation). To achieve this, you must train the student to **mimic the expert without looking at the expert's cheat sheet**.

### The Core Principle: Asymmetric Information
*   **Expert (Data Generation):** Uses `/tf` (Ground Truth) to calculate perfect motion outputs (`/aic_controller/pose_commands`).
*   **Student (Training phase):** Gets the **Camera Images** and **Joint States** as input. It must predict the Expert's **outputs** (`/aic_controller/pose_commands`). It **MUST NEVER** receive `/tf` or `/ground_truth_poses` as an input feature to its neural network.

### Step-by-Step Best Practices:

1.  **Strict Masking of Inputs:** When parsing your ROS bags to create your training dataset (e.g., converting to HDF5 or LeRobot format), drop `/tf` and `/ground_truth_poses` from the *Observation Space*. The only features fed into your transformer/CNN should be:
    *   3x RGB Images
    *   Joint Positions (from `/joint_states`)
    *   TCP Pose/Velocity (from `/aic_controller/controller_state`)
    *   Force/Torque (optional, but highly recommended for the insertion phase)
2.  **Using Ground Truth as an Auxiliary Loss (Advanced):** While you cannot use the ground truth target pose as an *input*, you can use it as a secondary *target* to help your visual encoder learn faster. 
    *   *How?* Have your neural network predict the robot's action *and* predict the 3D coordinate of the port from the image. By penalizing the network when it guesses the port location incorrectly, you force the visual encoder to learn exactly where the port is, improving action prediction.
3.  **Data Augmentation:** The "cheat" policy relies entirely on math, so it doesn't care if the lighting changes or the cameras have noise. Your student policy *will* care because it relies on vision. 
    *   You must apply heavy data augmentation (color jitter, random cropping, slight noise) to the camera images during training so your model learns robust, generalizing visual features.
4.  **Domain Randomization (If available):** If the toolkit supports spawning the task board or robot at slightly different poses (`robot_x`, `task_board_y`, etc.), randomize these slightly across different episodes when running `record_cheat_data.sh`. This prevents your model from memorizing a single hardcoded trajectory.
