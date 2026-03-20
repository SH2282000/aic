#!/bin/bash
# 04_auto_collect_massive_dataset.sh
# This script wraps EVERYTHING into one automated loop.
# It randomly varies the task board position slightly, starts the headless environment,
# runs the policy, collects the data, and then tears down the environment to start the next episode.

NUM_EPISODES=50

echo "Starting massive automated data collection for $NUM_EPISODES episodes..."

for i in $(seq 1 $NUM_EPISODES); do
    echo "========================================"
    echo " starting episode $i / $NUM_EPISODES"
    echo "========================================"

    # 1. Generate slight random variations for domain randomization
    # Random offset between -0.05 and 0.05 meters
    RAND_X=$(awk -v min=-0.05 -v max=0.05 'BEGIN{srand(); print min+rand()*(max-min)}')
    RAND_Y=$(awk -v min=-0.05 -v max=0.05 'BEGIN{srand(); print min+rand()*(max-min)}')
    
    BASE_TB_X=0.15
    BASE_TB_Y=-0.2
    
    NEW_TB_X=$(echo "$BASE_TB_X + $RAND_X" | bc -l)
    NEW_TB_Y=$(echo "$BASE_TB_Y + $RAND_Y" | bc -l)

    echo "Spawn parameters randomized -> task_board_x: $NEW_TB_X, task_board_y: $NEW_TB_Y"

    # 2. Start the headless evaluation container IN THE BACKGROUND
    # Notice we pass the random parameters to the launch script via entrypoint
    export DBX_CONTAINER_MANAGER=docker
    distrobox create -r --nvidia -i ghcr.io/intrinsic-dev/aic/aic_eval:latest aic_eval > /dev/null
    
    distrobox enter -r aic_eval -- /entrypoint.sh \
        ground_truth:=true \
        start_aic_engine:=true \
        gazebo_gui:=false \
        launch_rviz:=false \
        task_board_x:=$NEW_TB_X \
        task_board_y:=$NEW_TB_Y &
    
    ENV_PID=$!

    # 3. Wait for the simulator and engine to fully boot up
    echo "Waiting 20 seconds for simulation to initialize..."
    sleep 20

    # 4. Run the data collection wrapper (this blocks until the policy finishes)
    # The policy automatically executes the 3 trials defined in the default sample_config.yaml
    echo "Launching CheatCode policy and recording..."
    pixi run python 03_collect_successful_data.py

    # 5. Tear down the environment completely to prepare for the next randomized episode
    echo "Tearing down environment..."
    kill -s SIGINT $ENV_PID
    wait $ENV_PID 2>/dev/null
    
    # Optional: Aggressive cleanup to ensure no zombie gzserver / ros2 processes
    distrobox enter -r aic_eval -- pkill -f gzserver
    distrobox enter -r aic_eval -- pkill -f ros2

    echo "Episode $i complete!"
    sleep 3
done

echo "Massive data collection finished!"
