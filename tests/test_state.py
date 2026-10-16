import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "windows"))
from pet_state import PetState

class StateTests(unittest.TestCase):
    def test_toggle_and_idle_return(self):
        s=PetState(now=0)
        s.click(1)
        s.tick(2)
        self.assertEqual(s.mode, "belly")
        self.assertEqual(s.belly_frame, 8)
        s.click(3)
        s.tick(4)
        self.assertEqual(s.belly_frame, 3)
        s.tick(13.01)
        self.assertEqual((s.mode,s.pose), ("cycle",1))
    def test_auto_pulse(self):
        s=PetState(now=0,belly_mode="auto")
        s.click(1)
        s.tick(1.38)
        self.assertEqual(s.belly_frame,8)
        s.tick(1.9)
        self.assertEqual(s.belly_frame,3)
    def test_laugh_pauses_return(self):
        s=PetState(now=0)
        s.click(1)
        s.start_laugh(2,3)
        s.tick(20)
        self.assertEqual(s.mode,"laugh")
        s.tick(47)
        self.assertEqual(s.mode,"belly")
        s.tick(57.1)
        self.assertEqual(s.mode,"cycle")
    def test_four_pose_cycle(self):
        s=PetState(now=0)
        s.tick(10)
        self.assertEqual(s.pose,2)
        s.tick(40)
        self.assertEqual(s.pose,1)

if __name__ == "__main__": unittest.main()
