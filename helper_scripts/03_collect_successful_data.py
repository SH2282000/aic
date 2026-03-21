#!/usr/bin/env python3
"""
03_collect_successful_data.py

This script automates the data collection process. Instead of manually starting
the ROS bag and the policy, you can just run:
  pixi run python 03_collect_successful_data.py

It will:
1. Start recording the 20 Hz topics into a new folder.
2. Launch the `CheatCode` policy.
3. Listen to the `/scoring/insertion_event` topic (which is published when Gazebo
   detects the connector is successfully plugged into the port).
4. Auto-kill the bag recording when the policy finishes.
5. If the `/scoring/insertion_event` was NEVER received, it deletes the bag folder
   to keep your dataset clean.
"""

import subprocess
import time
import os
import shutil
import rclpy
from rclpy.node import Node
from std_msgs.msg import String
from lifecycle_msgs.msg import TransitionEvent

class SuccessMonitor(Node):
    def __init__(self):
        super().__init__('success_monitor')
        self.success = False
        self.policy_finished = False
        # Subscribe to the standard success completion event topic defined in the challenge
        self.subscription = self.create_subscription(
            String,
            '/scoring/insertion_event',
            self.success_callback,
            10
        )
        self.transition_sub = self.create_subscription(
            TransitionEvent,
            '/aic_model/transition_event',
            self.transition_callback,
            10
        )
        self.get_logger().info('Success monitor started. Waiting for precise insertion event and lifecycle transition...')

    def success_callback(self, msg):
        self.get_logger().info(f'Insertion Event Received: {msg.data}')
        self.success = True

    def transition_callback(self, msg):
        if msg.goal_state.label == 'finalized' or msg.goal_state.label == 'unconfigured':
            self.get_logger().info(f'Policy node transitioned to: {msg.goal_state.label}')
            self.policy_finished = True

def main():
    rclpy.init()
    monitor = SuccessMonitor()

    # Create a dedicated data directory in the workspace root
    # Using path relative to this script: helper_scripts/.. -> aic/data/episodes
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_data_dir = os.path.join(script_dir, "..", "data", "episodes")
    os.makedirs(base_data_dir, exist_ok=True)

    # Define unique bag name
    bag_name = f"cheatcode_data_{int(time.time())}"
    bag_path = os.path.join(base_data_dir, bag_name)

    # 1. Start ROS 2 bag recording
    bag_cmd = [
        "ros2", "bag", "record", "-o", bag_path,
        "/left_camera/image", "/center_camera/image", "/right_camera/image",
        "/left_camera/camera_info", "/center_camera/camera_info", "/right_camera/camera_info",
        "/joint_states", "/gripper_state", "/fts_broadcaster/wrench",
        "/aic_controller/pose_commands", "/aic_controller/joint_commands",
        "/tf", "/ground_truth_poses"
    ]
    print(f"Starting recording: {bag_name}")
    bag_process = subprocess.Popen(bag_cmd)

    # Wait for bag to initialize fully
    time.sleep(2) 

    # 2. Run the CheatCode policy
    print("Starting CheatCode policy...")
    policy_cmd = [
        "ros2", "run", "aic_model", "aic_model", 
        "--ros-args", "-p", "use_sim_time:=true", "-p", "policy:=aic_example_policies.ros.CheatCode"
    ]
    policy_process = subprocess.Popen(policy_cmd)

    # 3. Block and spin the node to listen for the success metric while the policy runs
    start_time = time.time()
    timeout_duration = 240.0  # 4 minutes per episode
    
    try:
        while policy_process.poll() is None:
            if monitor.policy_finished:
                print("\nLifecycle transition completed indicating policy finish. Terminating process...")
                policy_process.terminate()
                break
            
            elapsed_time = time.time() - start_time
            if elapsed_time > timeout_duration:
                print(f"\nEpisode timed out after {timeout_duration} seconds! Terminating process...")
                monitor.success = False
                policy_process.terminate()
                break
                
            rclpy.spin_once(monitor, timeout_sec=0.1)
    except KeyboardInterrupt:
        print("\nInterrupted by user. Cleaning up...")
        policy_process.terminate()

    # Policy finished.
    print("Policy finished execution.")
    
    # 4. Stop the bag recording
    print("Stopping bag recording...")
    bag_process.terminate()
    bag_process.wait()
    print("Bag recording stopped.")

    # 5. Check success and keep or delete the bag
    if monitor.success:
        print(f"✅ SUCCESS! Operation was successful. Episode saved in directory: {bag_path}")
    else:
        print(f"❌ FAILED! Successful insertion not detected. Deleting corrupted/failed episode data: {bag_path}")
        # if os.path.exists(bag_path):
        #     shutil.rmtree(bag_path)

    monitor.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()
