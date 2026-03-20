
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
