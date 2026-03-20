# Recording Data for AI Policy Training

To train your own AI policy using the provided "CheatCode" reference policy, you need to record the mapping between the robot's observations, its actions, and the ground-truth "cheat" data. 

Here are the commands you can use to record this data, along with explanations of why each topic is useful.

## Method 1: Using Standard ROS 2 Bags

This method uses the built-in `ros2 bag` command-line tool to capture the exact high-frequency (20 Hz) topics streaming during the policy's execution.

Run the following command in your terminal (inside your Docker/distrobox environment):

```bash
ros2 bag record -o cheatcode_training_data \
  /left_camera/image \
  /center_camera/image \
  /right_camera/image \
  /left_camera/camera_info \
  /center_camera/camera_info \
  /right_camera/camera_info \
  /joint_states \
  /gripper_state \
  /fts_broadcaster/wrench \
  /aic_controller/pose_commands \
  /aic_controller/joint_commands \
  /tf \
  /ground_truth_poses
```

*(Note: If the Tool Center Point (TCP) current pose and velocity are published on their own dedicated topics rather than just within `/tf`, you should append those topics to the command as well)*

### Breakdown of the Recorded Topics:

**1. The Inputs (What the Robot Senses)**
Your final policy will need to make decisions based solely on its sensors. This data provides that observation space:
*   **Vision (`/*_camera/image` and `/*_camera/camera_info`)**: The RGB image streams and camera calibration information from all three wrist cameras.
*   **Proprioception (`/joint_states`, `/gripper_state`)**: The current physical state of the robot, specifically the joint angles of the arm and the state of the gripper.
*   **Touch (`/fts_broadcaster/wrench`)**: The 3D force and torque measurements from the wrist sensor, which are critical for learning delicate insertion forces.

**2. The Outputs (What the Robot Does)**
*   **Commands (`/aic_controller/pose_commands`, `/aic_controller/joint_commands`)**: The exact motion commands outputted by the CheatCode policy to solve the task. By pairing the sensory inputs with these command outputs, your AI can learn to predict the correct movement for a given visual and tactile situation.

**3. The "Cheat" Data (Ground Truth)**
*   **Hidden State (`/tf`, `/ground_truth_poses`)**: The CheatCode policy bypasses cameras and directly uses the simulator's hidden data to know exactly where the target port is. Recording the exact ground-truth 3D coordinates alongside the camera images provides the perfect mathematical target for your computer vision model to look at an image and accurately predict those coordinates.

---

## Method 2: Using the LeRobot Integration Utility

If you are using LeRobot to train your model, the toolkit includes a dedicated utility specifically designed for this.

```bash
lerobot-record
```
*(Depending on how the utility is set up in your repository, you might need to supply arguments such as a policy name or output directory, e.g., `lerobot-record --policy cheat --output ./dataset`)*

### Why use this?
This command abstracts away the manual specification of ROS 2 topics and is specifically tailored to format and save the recorded sensory and ground truth data into a structured dataset that the LeRobot training pipeline can consume directly natively.

### Collect Successful Data

Run `helper_scripts/03_collect_successful_data.py` anytime (after starting the headless environment in Terminal 1) directly using: `pixi run python 03_collect_successful_data.py`

Success is strictly defined by the /scoring/insertion_event topic (a std_msgs/msg/String message), which the simulator publishes the exact moment the connector properly seats into the port and completes the task.

To automate the collection and filtering of your data, I have written a Python script in your workspace called 03_collect_successful_data.py.

This script will automatically:

Start recording all the necessary topics to a new ROS bag folder using the same commands you need.
Launch the CheatCode policy.
Passively listen to the /scoring/insertion_event topic.
Stop the recording gracefully when the policy finishes tracking its trajectory.
Check if the insertion success event was ever triggered. If it was not, the script will automatically delete the unsuccessful bag folder so your final dataset is 100% clean and contains only successful trajectories.