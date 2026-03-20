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

class SuccessMonitor(Node):
    def __init__(self):
        super().__init__('success_monitor')
        self.success = False
        # Subscribe to the standard success completion event topic defined in the challenge
        self.subscription = self.create_subscription(
            String,
            '/scoring/insertion_event',
            self.listener_callback,
            10
        )
        self.get_logger().info('Success monitor started. Waiting for precise insertion event...')

    def listener_callback(self, msg):
        self.get_logger().info(f'Insertion Event Received: {msg.data}')
        self.success = True

def main():
    rclpy.init()
    monitor = SuccessMonitor()

    # Define unique bag name
    bag_name = f"cheatcode_data_{int(time.time())}"

    # 1. Start ROS 2 bag recording
    bag_cmd = [
        "ros2", "bag", "record", "-o", bag_name,
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
    try:
        while policy_process.poll() is None:
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
        print(f"✅ SUCCESS! Operation was successful. Episode saved in directory: {bag_name}")
    else:
        print(f"❌ FAILED! Successful insertion not detected. Deleting corrupted/failed episode data: {bag_name}")
        if os.path.exists(bag_name):
            shutil.rmtree(bag_name)

    monitor.destroy_node()
    rclpy.shutdown()

if __name__ == '__main__':
    main()
