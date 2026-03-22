#!/bin/bash
# 04_auto_collect_massive_dataset.sh
# This script wraps EVERYTHING into one automated loop.
# It randomly varies the task board position slightly, starts the headless environment,
# runs the policy, collects the data, and then tears down the environment to start the next episode.

# Guard: prevent running from inside a container
if [ -f /run/.containerenv ] || [ -f /.dockerenv ]; then
    echo "ERROR: This script must be run on the HOST, not inside a container."
    echo "Please exit the container and run from the host machine."
    exit 1
fi

tmux kill-session -t aic_evaluator 2>/dev/null
distrobox stop aic_eval --yes 2>/dev/null

NUM_EPISODES=300

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
    export DBX_CONTAINER_MANAGER=docker
    distrobox create -r --nvidia -i ghcr.io/intrinsic-dev/aic/aic_eval:latest aic_eval > /dev/null 2>&1
    
    tmux new-session -d -s aic_evaluator "distrobox enter -r aic_eval -- /entrypoint.sh \
        ground_truth:=true \
        start_aic_engine:=true \
        gazebo_gui:=false \
        launch_rviz:=false \
        task_board_x:=$NEW_TB_X \
        task_board_y:=$NEW_TB_Y"

    # 3. Wait for the simulator to be fully ready before starting aic_model
    echo "Waiting for simulation to initialize (up to 90 seconds)..."
    BOOT_TIMEOUT=90
    BOOT_ELAPSED=0
    SIM_READY=false

    # Give the sim some time to start up
    sleep 30
    BOOT_ELAPSED=30

    # Poll for /joint_states topic to confirm sim is ready
    while [ $BOOT_ELAPSED -lt $BOOT_TIMEOUT ]; do
        if pixi run ros2 topic list 2>/dev/null | grep -q "/joint_states"; then
            echo "Simulation ready! (after ${BOOT_ELAPSED}s)"
            SIM_READY=true
            sleep 5  # Stabilization buffer
            break
        fi
        sleep 10    
        BOOT_ELAPSED=$((BOOT_ELAPSED + 10))
        echo "  Still waiting... (${BOOT_ELAPSED}s elapsed)"
    done

    if [ "$SIM_READY" = false ]; then
        echo "WARNING: Simulation may not be fully ready after ${BOOT_TIMEOUT}s. Proceeding anyway..."
    fi

    # 4. Start aic_model AFTER the simulation is ready
    #    This ensures the engine can properly discover, configure, and activate the model
    #    before sending any goals (avoids the "lifecycle is not in the active state" race).
    #    We source the Zenoh model session config so the host-side aic_model connects
    #    to the Zenoh router running inside the eval container.
    echo "Starting aic_model now that simulation is ready..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../docker/aic_model/zenoh_config_model_session.sh"
    pixi run ros2 run aic_model aic_model \
        --ros-args -p use_sim_time:=true -p policy:=aic_example_policies.ros.CheatCode &
    MODEL_PID=$!
    echo "aic_model started with PID $MODEL_PID"
    sleep 20  # Give the engine time to discover and activate aic_model

    # 5. Run the data collection (bag recording + monitoring only, model already running)
    echo "Launching bag recording and monitoring..."
    pixi run python 03_collect_successful_data.py --skip-policy --policy-pid $MODEL_PID

    # 6. Make sure the model process is cleaned up
    kill $MODEL_PID 2>/dev/null
    wait $MODEL_PID 2>/dev/null

    # 7. Tear down the environment completely to prepare for the next randomized episode
    echo "Tearing down environment..."
    tmux kill-session -t aic_evaluator 2>/dev/null
    distrobox stop aic_eval --yes 2>/dev/null

    echo "Episode $i complete!"
    sleep 3
done

echo "Massive data collection finished!"
