#!/bin/bash
echo "Starting Data Collection Pipeline..."

# Terminal 1: Start the Eval Container with Ground Truth
gnome-terminal -- bash -c "export DBX_CONTAINER_MANAGER=docker; distrobox enter -r aic_eval -- /entrypoint.sh ground_truth:=true start_aic_engine:=true; exec bash"

sleep 15 # Give Gazebo and the engine time to spin up

# Terminal 2: Run the CheatCode Policy to solve the task
gnome-terminal -- bash -c "cd ~/ws_aic/src/aic && pixi run ros2 run aic_model aic_model --ros-args -p use_sim_time:=true -p policy:=aic_example_policies.ros.CheatCode; exec bash"

# Terminal 3: Run LeRobot Data Recorder (You will need to check lerobot_robot_aic docs for exact args)
gnome-terminal -- bash -c "cd ~/ws_aic/src/aic && pixi run lerobot-record --dataset_id my_aic_dataset; exec bash"
