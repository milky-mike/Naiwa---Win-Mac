"""Pure, cross-platform behavioral model for Naiwa (no GUI dependencies).

All times are monotonic seconds.  These rules are mirrored in mac/Sources/main.swift.
- Default toggle: click expands and HOLDS; next click retracts and HOLDS.
- Optional auto: every click expands then retracts automatically.
- Any single-click resets the 10s idle timeout; returning always starts at pose 1.
- Laugh uses original 30fps frames and pauses the belly inactivity timeout.
"""
from dataclasses import dataclass


@dataclass
class PetState:
    now: float = 0.0
    belly_mode: str = "toggle"
    mode: str = "cycle"
    pose: int = 1
    belly_frame: int = 3
    expanded: bool = False
    last_single_at: float = -1.0
    next_pose_at: float = 10.0
    belly_from: int = 3
    belly_target: int = 3
    belly_transition_at: float = 0.0
    belly_auto_retract_at: float = -1.0
    laugh_started: float = 0.0
    repeat_count: int = 3
    laugh_restore_belly: bool = False

    pose_interval: float = 10.0
    click_inactivity: float = 10.0
    belly_step_interval: float = 0.075
    video_duration: float = 14.767664
    video_frame_rate: int = 30
    video_frame_count: int = 443

    def __post_init__(self):
        if self.belly_mode not in ("toggle", "auto"):
            raise ValueError("belly_mode must be toggle or auto")
        self.next_pose_at = self.now + self.pose_interval

    def set_belly_mode(self, behavior: str, now: float) -> None:
        if behavior not in ("toggle", "auto"):
            raise ValueError("unknown belly click behavior")
        self.belly_mode = behavior
        if self.mode == "belly":
            self.resume(now)

    def resume(self, now: float, advance: bool = False) -> None:
        self.mode = "cycle"
        self.pose = (self.pose % 4) + 1 if advance else 1
        self.next_pose_at = now + self.pose_interval
        self.belly_frame = 3
        self.belly_target = 3
        self.belly_from = 3
        self.belly_auto_retract_at = -1.0
        self.expanded = False
        self.last_single_at = -1.0
        self.laugh_restore_belly = False

    def click(self, now: float) -> None:
        if self.mode == "laugh":
            self.finish_laugh(now)
        if self.mode != "belly":
            self.belly_frame = 3
            self.expanded = False
        else:
            self.tick_belly_frame(now)
        self.mode = "belly"
        self.last_single_at = now
        self.belly_from = self.belly_frame
        self.belly_transition_at = now
        if self.belly_mode == "auto":
            self.expanded = True
            self.belly_target = 8
            # A short hold at full expansion makes the pulse legible.
            self.belly_auto_retract_at = now + (8 - self.belly_from) * self.belly_step_interval + 0.15
        else:
            self.belly_auto_retract_at = -1.0
            self.expanded = not self.expanded
            self.belly_target = 8 if self.expanded else 3

    def tick_belly_frame(self, now: float) -> None:
        if self.mode != "belly":
            return
        if self.belly_mode == "auto" and self.belly_auto_retract_at >= 0 and now >= self.belly_auto_retract_at:
            self.belly_from = 8
            self.belly_target = 3
            self.belly_transition_at = self.belly_auto_retract_at
            self.belly_auto_retract_at = -1.0
        step_count = int(max(0.0, now - self.belly_transition_at) / self.belly_step_interval + 1e-9)
        difference = self.belly_target - self.belly_from
        step = min(abs(difference), step_count)
        self.belly_frame = self.belly_from + (1 if difference >= 0 else -1) * step
        if self.belly_mode == "auto" and self.belly_frame == 3 and self.belly_auto_retract_at < 0:
            self.expanded = False

    def start_laugh(self, now: float, repeat_count: int) -> None:
        if self.mode == "belly":
            self.tick_belly_frame(now)
        self.laugh_restore_belly = self.mode == "belly" or (self.mode == "laugh" and self.laugh_restore_belly)
        self.mode = "laugh"
        self.laugh_started = now
        self.repeat_count = repeat_count

    def finish_laugh(self, now: float) -> None:
        if self.mode != "laugh":
            return
        if self.laugh_restore_belly:
            self.mode = "belly"
            self.last_single_at = now
            if self.belly_mode == "auto":
                self.belly_frame = 3
                self.expanded = False
            self.belly_from = self.belly_frame
            self.belly_target = self.belly_frame
            self.belly_transition_at = now
            self.belly_auto_retract_at = -1.0
        else:
            self.resume(now)

    def tick(self, now: float) -> None:
        if self.mode == "laugh":
            if now - self.laugh_started >= self.video_duration * self.repeat_count:
                self.finish_laugh(now)
            return
        if self.mode == "belly":
            self.tick_belly_frame(now)
            if now - self.last_single_at >= self.click_inactivity:
                self.resume(now)
            return
        if now >= self.next_pose_at:
            increments = max(1, int((now - self.next_pose_at) / self.pose_interval) + 1)
            self.pose = ((self.pose - 1 + increments) % 4) + 1
            self.next_pose_at += increments * self.pose_interval

    def image_key(self, now: float) -> str:
        if self.mode == "laugh":
            local = max(0.0, now - self.laugh_started) % self.video_duration
            idx = max(0, min(self.video_frame_count - 1, int(local * self.video_frame_rate)))
            return f"LaughFrames/frame_{idx:03d}.png"
        if self.mode == "belly":
            return f"Stills/belly_{self.belly_frame:02d}.png"
        return f"Stills/pose_{self.pose}.png"
