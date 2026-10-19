"""Bounded, feedback-paced volume steering for TVs with relative keys only."""
import asyncio
import math
import time


class RelativeVolume:
    def __init__(self, send_key, result, unavailable, *, feedback_timeout=1.5, pacing=0.08):
        self.send_key, self.result, self.unavailable = send_key, result, unavailable
        self.feedback_timeout, self.pacing = feedback_timeout, pacing
        self.info = None
        self.target = None
        self.changed = asyncio.Event()
        self.task = None
        self.deadline = 0
        self.steps = 0

    def report(self, info):
        if (info and isinstance(info.get('max'), int) and isinstance(info.get('level'), int)
                and 0 < info['max'] <= 10000 and 0 <= info['level'] <= info['max']):
            self.info = dict(info)
        else:
            self.info = None
        self.changed.set()

    def set_target(self, percent, request):
        if type(percent) is not int or not 0 <= percent <= 100 or type(request) is not int:
            raise ValueError('Invalid volume target')
        # Replacing intent never queues another burst or resets the safety budget.
        self.target = (percent, request)
        if self.task is None or self.task.done():
            self.deadline, self.steps = time.monotonic() + 10, 0
            self.task = asyncio.create_task(self._drive())

    def cancel(self):
        self.target = None
        if self.task:
            self.task.cancel()
            self.task = None

    def _failed(self):
        pending, self.target = self.target, None
        if pending:
            values = dict(request=pending[1])
            if self.info:
                values['value'] = round(self.info['level'] * 100 / self.info['max'])
            self.result(**values)
        self.unavailable()

    async def _drive(self):
        try:
            while self.target:
                if not self.info or time.monotonic() >= self.deadline or self.steps >= 128:
                    self._failed()
                    return
                percent, request = self.target
                maximum, level = self.info['max'], self.info['level']
                goal = math.floor(percent * maximum / 100 + 0.5)
                if goal == level:
                    self.target = None
                    self.result(request=request, value=round(level * 100 / maximum))
                    return
                self.changed.clear()
                self.send_key('VOLUME_UP' if goal > level else 'VOLUME_DOWN')
                self.steps += 1
                # Never send another key just because time elapsed. A changed
                # level must arrive; duplicate/mute-only broadcasts do not count.
                feedback_deadline = time.monotonic() + self.feedback_timeout
                while self.info and self.info['level'] == level and self.info['max'] == maximum:
                    remaining = feedback_deadline - time.monotonic()
                    if remaining <= 0:
                        self._failed()
                        return
                    try:
                        await asyncio.wait_for(self.changed.wait(), remaining)
                    except asyncio.TimeoutError:
                        self._failed()
                        return
                    self.changed.clear()
                await asyncio.sleep(self.pacing)
        except asyncio.CancelledError:
            pass
        except Exception:
            self._failed()
