#!/usr/bin/env python3
"""Platform-neutral JSON-lines entry point. VIDAA wire code remains in bridge.py."""
import json
import queue
import signal
import sys
import threading

from bridge import Bridge, discover_devices


class Controller:
    def __init__(self, emit=None, vidaa_factory=Bridge, android_factory=None):
        self.emit = emit or (lambda value: print(json.dumps(value), flush=True))
        self.lock = threading.RLock()
        self.adapter = None
        self.session = None
        self.platform = None
        self.vidaa_factory = vidaa_factory
        self.android_factory = android_factory

    def event(self, value, session):
        with self.lock:
            if self.session == session:
                self.emit(dict(value, session=session, platform=self.platform))

    def close(self):
        with self.lock:
            self.session = None  # Invalidate before cancellation can produce callbacks.
            old, self.adapter = self.adapter, None
        if old:
            old.close()

    def command(self, command):
        action = command.get('action')
        if action == 'discover':
            token = command.get('discovery')
            def discover():
                try:
                    devices = [dict(tv, platform='vidaa') for tv in discover_devices()]
                except OSError:
                    devices = []
                with self.lock:
                    self.emit(dict(event='discovery', discovery=token, devices=devices))
            threading.Thread(target=discover, daemon=True).start()
            return
        if action == 'disconnect':
            self.close()
            return
        if action == 'connect':
            self.close()
            session = command.get('session')
            platform = command.get('platform', 'vidaa')
            if not isinstance(session, str) or not session or platform not in ('vidaa', 'androidtv'):
                raise ValueError('Choose a supported TV platform.')
            self.session, self.platform = session, platform
            emit = lambda value: self.event(value, session)
            if platform == 'vidaa':
                self.adapter = self.vidaa_factory(emit)
                # Keep the original VIDAA probe, certificate check and auth flow.
                try:
                    self.adapter.command(dict(action='probe', host=command['host']))
                except Exception:
                    pass  # A missing volume service must not prevent remote pairing.
            else:
                factory = self.android_factory
                if factory is None:
                    from android_adapter import AndroidAdapter
                    factory = AndroidAdapter
                self.adapter = factory(emit)
        if self.adapter is None or command.get('session') != self.session:
            return
        try:
            self.adapter.command(command)
        except Exception:
            # Never forward third-party exception strings: some contain PINs.
            self.event(dict(event='error', message='The TV command failed. Reconnect and try again.',
                            disconnected=action == 'connect'), self.session)
            if action == 'connect':
                self.close()

    def tick(self):
        if self.adapter:
            try:
                self.adapter.tick()
            except Exception:
                self.event(dict(event='error', message='Connection interrupted. Reconnect when your TV is awake.',
                                disconnected=True), self.session)
                self.close()


def main():
    commands = queue.Queue(maxsize=256)
    def reader():
        for line in sys.stdin:
            try:
                if len(line) > 131072:
                    continue
                value = json.loads(line)
                if isinstance(value, dict):
                    commands.put(value)
            except ValueError:
                pass
        commands.put(None)
    threading.Thread(target=reader, daemon=True).start()
    controller = Controller()
    def stop(_signal, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop)
    try:
        while True:
            try:
                command = commands.get(timeout=0.05)
                if command is None:
                    break
                controller.command(command)
            except queue.Empty:
                pass
            except Exception:
                controller.event(dict(event='error', message='Unable to connect to this TV.', disconnected=True), controller.session)
                controller.close()
            controller.tick()
    finally:
        controller.close()


if __name__ == '__main__':
    main()
