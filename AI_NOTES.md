# SolanaAI – AI Assistant Notes

## Overview
SolanaAI is a Windows Python project using YOLO-based detection plus a HID/vgamepad aimbot, built around a PyQt6 GUI. The original monolithic `main.py` has been refactored into a modular architecture with a backend controller and a separate GUI application.

This file is the primary place where the AI assistant should look to understand past decisions, architecture, and "known good" states.

## High-Level Architecture

- `main.py`
  - Thin entry point.
  - Creates configuration and aimbot controller, launches the Qt GUI.

- `detector.py`
  - Core backend / runtime orchestrator.
  - Responsibilities:
    - High-DPI / package initialization and first-run install via `initialize_packages()`.
    - Configuration layer via `ConfigManager` (JSON config file, callbacks on change).
    - `AimbotController`:
      - Model loading (`YOLO` via `ultralytics`).
      - Screen capture via `StealthCapture` (wrapper around `bettercam`/DXGI).
      - Main loop `run_loop()` that grabs frames, runs detection, and routes results to aiming and triggerbot.
      - Kalman smoothing via `KalmanSmoother`.
      - Movement curves via `MovementCurves`.
      - Anti-recoil via `SmartArduinoAntiRecoil`.
      - Controller support via `ControllerHandler`.
      - Triggerbot via `Triggerbot` and flickbot via `Flickbot`.
      - Overlay and visual debugging control.
      - Stream-proof integration via `StreamProofManager`.
    - Overlay bridge (`OverlayConfigBridge`) and `Overlay` object wiring.

- `gui_app.py`
  - Hosts the `ConfigApp` PyQt6 main window (frameless custom UI).
  - Loads multiple tab modules (`tabs_*.py`) for different configuration pages:
    - General, Target, Display, Performance, Models, Advanced, Anti-recoil, Triggerbot, Flickbot, Controller, Hotkeys, About.
  - Uses helper modules:
    - `widgets.py` – shared widgets/styling.
    - `icons.py` – icon resources.
    - `hotkeys.py` – global hotkey listener thread (F6/F7, and F3 pause).
  - Holds a reference to `AimbotController` and calls its methods for start/stop, pause, status, and applying backend-driven visual changes.

- Other key modules
  - `controller_handler.py` – XInput/vgamepad-based controller input, normalized API for thumbsticks, triggers, and buttons; handles its own polling thread safely.
  - `debug_visuals.py` – `CompactVisuals` OpenCV window for detections.
  - `overlay.py` – Tkinter-based overlay window (FOV / crosshair visualization).
  - `anti_recoil.py`, `triggerbot.py`, `flickbot.py` – feature-specific backends.
  - `stream_proof.py` – stream-proofing via window flags / Win32 APIs.
  - `movement_curves.py`, `kalman_smoother.py` – movement and smoothing helpers.

## Runtime Flow

1. `main.py` creates a `ConfigManager` and `AimbotController`.
2. `ConfigApp` is created with references to the config manager and aimbot controller.
3. The user starts the aimbot from the GUI.
4. `AimbotController.start()` sets up threads and calls `run_loop()`:
   - Initializes `KalmanSmoother`, the YOLO model, and `StealthCapture`.
   - Enters a loop that repeatedly grabs frames, runs YOLO detection every Nth frame, and uses cached results on skipped frames.
   - Applies triggerbot and aiming logic when the keybind or controller activation is pressed.
   - Updates the debug window (`CompactVisuals`) and the overlay as needed.

## Config & Hotkeys

- Config is stored in a JSON file managed by `ConfigManager` in `detector.py`.
- `ConfigManager.register_callback(self.on_config_updated)` in `AimbotController` wires configuration changes to runtime updates.
- Global hotkeys (from `hotkeys.py`):
  - F6 – Toggle stream-proof.
  - F7 – Toggle menu visibility.
  - F3 – Global pause/unpause for aiming & triggerbot.

## Important Decisions / Design Constraints

### 1. Separation of GUI and backend

- All heavy vision/aim logic lives in `AimbotController` (backend).
- The PyQt6 GUI (`ConfigApp` and tabs) should not run capture or heavy loops directly.
- Config changes from the GUI are applied via `ConfigManager.update_config`, which notifies `AimbotController.on_config_updated`.

### 2. Visual reconfiguration & freeze prevention

To avoid GUI freezes when toggling overlay/debug/stream-proof:

- `AimbotController.on_config_updated` is **lightweight**:
  - Reloads feature configs (anti-recoil, triggerbot, flickbot, controller).
  - Reloads core runtime snapshot via `load_current_config()`.
  - Schedules heavy visual work instead of doing it inline.

- Heavy visual work is centralized in `AimbotController.apply_visual_config_changes()`:
  - Uses a lock (`_visual_state_lock`) and last-known visual state to compute diffs.
  - Handles:
    - Overlay start/stop.
    - Debug window start/stop.
    - Overlay FOV changes (restart overlay if needed).
    - Overlay shape changes.
    - Reinitializing components on FOV/mouse method change.

- For thread safety with Qt:
  - If `config_app_reference` is set, `on_config_updated` uses:
    - `QMetaObject.invokeMethod(config_app, "apply_visual_config_from_backend", Qt.QueuedConnection)`
  - `ConfigApp.apply_visual_config_from_backend()` is a `@pyqtSlot()` that calls `aimbot_controller.apply_visual_config_changes()` on the Qt main thread.

- Gating rule:
  - Overlay and debug window shouldnt run concurrently (to reduce conflicts between Tk, OpenCV, and Qt).
  - Current behavior (as of latest edits): **overlay wins**; if both are enabled, debug window is disabled.

### 3. Global F3 pause/unpause

- `AimbotController` has a `self.paused` flag:
  - Initialized in `__init__`.
  - `start()` ensures `paused = False`.
  - `stop()` / `force_stop()` clear it.

- `toggle_pause()` in `AimbotController`:
  - Flips `self.paused` and logs `[+] Aimbot paused/unpaused`.

- `run_loop()` and `process_frame_for_aiming()` respect `self.paused`:
  - When paused, aiming and triggerbot logic are skipped, but capture and UI remain alive.

- `ConfigApp.toggle_aimbot_pause()` (PyQt slot):
  - Invoked by the hotkey thread on F3 press.
  - Updates status label and dot color (Paused vs Running).

- `hotkeys.py`:
  - Background thread reads key state via `win32api.GetAsyncKeyState(0x72)` (VK_F3).
  - On key-down edge, uses `QMetaObject.invokeMethod(config_app, "toggle_aimbot_pause", Qt.QueuedConnection)`.

### 4. Controller support (XInput / vgamepad)

- `ControllerHandler` normalizes XInput state to handle variations (`state.gamepad` vs `state.Gamepad`).
- `physical_controller_connected` and an internal `is_aiming` flag are used.
- `AimbotController.process_frame()` logic:
  - Considers the controller active if:
    - `self.controller.enabled` and `self.controller.physical_controller_connected` and `self.controller.is_aiming`.
  - Aims if either the keybind is active or controller is active.

- Thread-safety fix:
  - `ControllerHandler.stop()` avoids `thread.join()` from within its own thread to prevent `cannot join current thread` errors.

### 5. Aim jitter reduction / deadzone

- `aim_at_target()` uses deadzones on the final integer HID movements (`final_x`, `final_y`):

  - Compute raw movement via `calc_movement()` (mouse FOV, DPI, sensitivity).
  - Optionally pass through Kalman smoother.
  - Clamp to [-127, 127] and round to integers.
  - Apply adaptive thresholds (current behavior):
    - For moving targets: `min_movement_threshold` is 0.50 1.0 based on distance.
    - For stationary: `min_movement_threshold` is 1.00 1.5 based on distance.
  - If both |final_x| and |final_y|  threshold, suppress movement to avoid visible jitter near center.

- Goal: stable lock on stationary targets with minimal micro-jitter, while still aiming responsively when further away.

### 6. Kalman smoothing & alpha stability

- `calc_movement()` uses a pre-smoothing factor `alpha` to blend current vs previous motion.
- `alpha_with_kalman` from config is **clamped** into a safe range [0.05, 1.0] to avoid feedback oscillation or overshoot.

## Known Good Behaviors (Regression Targets)

When things are working as intended, the following should hold:

1. **Startup**
   - `python main.py` opens the GUI without tracebacks.
   - Console shows package checks passed, model and capture initialized.

2. **Aimbot**
   - Pressing Start in GUI runs `AimbotController.start()` and begins detection.
   - Holding the keybind (e.g., `0x02` / right mouse) causes the crosshair to move smoothly toward targets within the FOV.
   - Aim does NOT spin in tiny circles around the target and does NOT jitter 1-count when already centered.

3. **Pause (F3)**
   - Toggling F3 moves between `Running` and `Paused` states in the GUI.
   - While paused, no aiming or triggerbot is applied, but capture and debug visuals can continue.
   - No crashes or process exits occur when spamming F3.

4. **Overlay & Debug Window**
   - Enabling overlay in GUI shows a Tk-based overlay around the FOV.
   - Enabling debug window shows the OpenCV `CompactVisuals` window with detection boxes.
   - Enabling both simultaneously does NOT freeze the GUI:
     - Current behavior: overlay remains, debug window is disabled.

5. **Controller**
   - Plugging/unplugging controller does not crash or spam errors.
   - Configured button combos (e.g. Back+Start) can toggle aimbot/overlay/debug window without deadlocks.

## Anti-cheat Notes (Capture)

- The logging messages about "Anti-cheat safe capture" refer to the use of screen-capture libraries that hook into Windows/DXGI (similar to OBS/ShadowPlay) rather than injecting into the game process or reading its memory.
- This does **not** guarantee safety from anti-cheat detection; any use of automated aiming still carries ban risk.

## How Future AI Sessions Should Use This File

If you are a future AI assistant reading this:

1. Read this file completely before making any architectural changes.
2. Verify that the current code in `detector.py`, `gui_app.py`, and related modules still matches the assumptions here.
3. When implementing new changes or major fixes, append a new section at the bottom (or instruct the user to do so) describing:
   - What was changed.
   - Why.
   - Any new invariants or expectations.
4. Keep this file concise but accurate; it is the primary long-term memory for this project.
