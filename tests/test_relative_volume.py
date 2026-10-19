import asyncio
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from relative_volume import RelativeVolume


class RelativeVolumeTests(unittest.IsolatedAsyncioTestCase):
    def make_driver(self, *, maximum=20, level=7, acknowledge=True):
        self.sent, self.results, self.failures = [], [], []
        self.level, self.maximum = level, maximum
        def send(key):
            self.sent.append(key)
            if acknowledge:
                self.level = max(0, min(self.maximum, self.level + (1 if key == 'VOLUME_UP' else -1)))
                asyncio.get_running_loop().call_later(.005, lambda: self.driver.report(
                    dict(level=self.level, max=self.maximum, muted=False)))
        self.driver = RelativeVolume(send, lambda **v: self.results.append(v),
                                     lambda: self.failures.append(True), feedback_timeout=.06, pacing=.001)
        self.driver.report(dict(level=level, max=maximum, muted=False))
        return self.driver

    async def test_quantizes_target_to_native_steps(self):
        driver = self.make_driver()
        driver.set_target(53, 1)
        await driver.task
        self.assertEqual(self.sent, ['VOLUME_UP'] * 4)
        self.assertEqual(self.results, [dict(request=1, value=55)])
        self.assertFalse(self.failures)

    async def test_reverse_drag_replaces_old_target(self):
        driver = self.make_driver()
        driver.set_target(100, 1)
        await asyncio.sleep(.002)  # One key outstanding; its reply has not arrived.
        driver.set_target(10, 2)
        await driver.task
        self.assertEqual(self.sent[0], 'VOLUME_UP')
        self.assertTrue(all(key == 'VOLUME_DOWN' for key in self.sent[1:]))
        self.assertEqual(self.results, [dict(request=2, value=10)])

    async def test_no_feedback_stops_after_one_key_and_falls_back(self):
        driver = self.make_driver(acknowledge=False)
        driver.set_target(100, 1)
        await driver.task
        self.assertEqual(self.sent, ['VOLUME_UP'])
        self.assertEqual(self.results, [dict(request=1, value=35)])
        self.assertEqual(self.failures, [True])

    async def test_duplicate_feedback_does_not_authorize_more_keys(self):
        driver = self.make_driver(acknowledge=False)
        driver.set_target(100, 1)
        for _ in range(5):
            await asyncio.sleep(.01)
            driver.report(dict(level=7, max=20, muted=True))
        await driver.task
        self.assertEqual(len(self.sent), 1)
        self.assertTrue(self.failures)

    async def test_cancel_stops_motion(self):
        driver = self.make_driver()
        driver.set_target(100, 1)
        await asyncio.sleep(.002)
        driver.cancel()
        await asyncio.sleep(.02)
        self.assertEqual(len(self.sent), 1)
        self.assertFalse(self.results or self.failures)

    async def test_missing_feedback_never_sends_a_key(self):
        driver = self.make_driver(maximum=0, level=0)
        driver.set_target(50, 1)
        await driver.task
        self.assertFalse(self.sent)
        self.assertTrue(self.failures)

    async def test_step_budget_limits_incorrect_or_unusually_large_range(self):
        driver = self.make_driver(maximum=10000, level=0)
        driver.set_target(100, 1)
        await driver.task
        self.assertEqual(len(self.sent), 128)
        self.assertTrue(self.failures)
