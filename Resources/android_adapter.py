"""Google/Android TV adapter using Android TV Remote Service v2, not ADB.

The dependency is pinned. Its TLS context hook is overridden to trust only the
TV certificate approved during setup; upstream's default disables verification.
"""
import asyncio
import hashlib
import os
from pathlib import Path
import queue
import re
import ssl
import tempfile
import threading

from androidtvremote2 import AndroidTVRemote
from androidtvremote2.certificate_generator import generate_selfsigned_cert
from androidtvremote2.exceptions import InvalidAuth
from bridge import host_address
from relative_volume import RelativeVolume

KEYS = {
    'UP': 'DPAD_UP', 'DOWN': 'DPAD_DOWN', 'LEFT': 'DPAD_LEFT', 'RIGHT': 'DPAD_RIGHT',
    'OK': 'DPAD_CENTER', 'RETURNS': 'BACK', 'HOME': 'HOME', 'MENU': 'MENU',
    'POWER': 'POWER', 'VOLUMEUP': 'VOLUME_UP', 'VOLUMEDOWN': 'VOLUME_DOWN',
    'MUTE': 'VOLUME_MUTE', 'PLAY': 'MEDIA_PLAY', 'PAUSE': 'MEDIA_PAUSE',
    'STOP': 'MEDIA_STOP', 'FORWARDS': 'MEDIA_FAST_FORWARD', 'BACK': 'MEDIA_REWIND',
    'CHANNELUP': 'CHANNEL_UP', 'CHANNELDOWN': 'CHANNEL_DOWN', 'SUBTITLE': 'CAPTIONS',
    'RED': 'PROG_RED', 'GREEN': 'PROG_GREEN', 'YELLOW': 'PROG_YELLOW', 'BLUE': 'PROG_BLUE',
    'INPUT': 'TV_INPUT', **{str(i): str(i) for i in range(10)},
}
# Shortcuts, NOT an installed-app catalog. Deep links avoid market:// launch regressions.
SHORTCUTS = (
    {'name': 'YouTube', 'appId': 'com.google.android.youtube.tv', 'link': 'https://www.youtube.com'},
    {'name': 'Netflix', 'appId': 'com.netflix.ninja', 'link': 'netflix://'},
    {'name': 'Prime Video', 'appId': 'com.amazon.amazonvideo.livingroom', 'link': 'https://app.primevideo.com'},
    {'name': 'Disney+', 'appId': 'com.disney.disneyplus', 'link': 'https://www.disneyplus.com'},
)
APP_NAMES = {item['appId']: item['name'] for item in SHORTCUTS}
APP_NAMES.update({'com.google.android.apps.tv.launcherx': 'Google TV Home',
                  'com.google.android.tvlauncher': 'Android TV Home',
                  'com.apple.atve.androidtv.appletv': 'Apple TV'})


def valid_pin(pin):
    return isinstance(pin, str) and re.fullmatch(r'[0-9A-Fa-f]{6}', pin) is not None


def pinned_context(certfile, keyfile, server_pem):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False  # TV certificates do not carry LAN IP SANs.
    context.verify_mode = ssl.CERT_REQUIRED
    context.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
    context.load_verify_locations(cadata=server_pem)
    context.load_cert_chain(certfile, keyfile)
    return context


class PinnedRemote(AndroidTVRemote):
    def __init__(self, *args, pinned_ssl_context, **kwargs):
        super().__init__(*args, **kwargs)
        self.pinned_ssl_context = pinned_ssl_context

    async def _create_ssl_context(self):
        return self.pinned_ssl_context


class AndroidAdapter:
    def __init__(self, emit, remote_factory=PinnedRemote, api_port=6466, pair_port=6467):
        self.emit = emit
        self.remote_factory = remote_factory
        self.api_port, self.pair_port = api_port, pair_port
        self.commands = queue.Queue(maxsize=128)
        self.closed = threading.Event()
        self.loop = None
        self.task = None
        self.remote = None
        self.ready = False
        self.volume_driver = None
        self.latest_volume = None
        self.volume_lock = threading.Lock()
        self.pairing = False
        self.storage = None
        self.certificate = self.private_key = self.server_pem = None
        self.thread = threading.Thread(target=self._worker, daemon=True)
        self.thread.start()

    def event(self, kind, **values):
        if not self.closed.is_set():
            self.emit(dict(event=kind, **values))

    def command(self, command):
        if not self.closed.is_set():
            if command.get('action') == 'volume':
                # Drag updates use a latest-value mailbox instead of filling the
                # transport queue while a TV is slow to acknowledge a key.
                with self.volume_lock:
                    self.latest_volume = command
            else:
                if command.get('action') in ('cancel_volume', 'mute') or (command.get('action') == 'key' and command.get('key') in ('VOLUMEUP', 'VOLUMEDOWN', 'MUTE', 'POWER')):
                    with self.volume_lock:
                        self.latest_volume = None
                self.commands.put_nowait(command)

    def tick(self):
        pass  # asyncio owns Android network I/O; VIDAA keeps its existing tick loop.

    def close(self):
        self.closed.set()
        if self.loop and self.task and not self.loop.is_closed():
            try:
                self.loop.call_soon_threadsafe(self.task.cancel)
            except RuntimeError:
                pass
        if threading.current_thread() is not self.thread:
            self.thread.join(timeout=2)

    def _worker(self):
        asyncio.run(self._run())

    async def _run(self):
        self.loop = asyncio.get_running_loop()
        self.task = asyncio.current_task()
        try:
            while not self.closed.is_set():
                try:
                    command = self.commands.get_nowait()
                except queue.Empty:
                    with self.volume_lock:
                        command, self.latest_volume = self.latest_volume, None
                    if command is None:
                        await asyncio.sleep(0.02)
                        continue
                action = command.get('action')
                try:
                    await asyncio.wait_for(self._command(command), timeout=18)
                except InvalidAuth:
                    if action == 'pin':
                        self.event('error', message='That code did not match. Check all six characters on your TV, or show a new code.')
                        self.event('status', value='pairing')
                    else:
                        self.ready = False
                        self.event('error', message='This TV needs a new pairing code. Choose Show code on TV.')
                        self.event('status', value='pairing')
                except Exception:
                    if action in ('connect', 'pair', 'pin'):
                        self.ready = False
                        self.pairing = False
                        if self.remote:
                            self.remote.disconnect()
                        self.event('error', message='Google TV did not finish connecting. Keep it awake and check Android TV Remote Service, then reconnect.', disconnected=True)
                    else:
                        self.event('error', message='The TV could not accept that command. Reconnect if it is asleep.')
        except asyncio.CancelledError:
            pass
        finally:
            if self.volume_driver:
                self.volume_driver.cancel()
            if self.remote:
                self.remote.disconnect()
            if self.storage:
                self.storage.cleanup()
            self.private_key = None

    async def _prepare(self, command):
        self.host = host_address(command['host'])
        saved = command.get('saved') or {}
        self.storage = tempfile.TemporaryDirectory(prefix='sofa-pair-')
        os.chmod(self.storage.name, 0o700)
        certfile = Path(self.storage.name) / 'client.pem'
        keyfile = Path(self.storage.name) / 'key.pem'
        if saved:
            self.certificate, self.private_key = saved['certificate'], saved['private_key']
        else:
            cert, key = await asyncio.to_thread(generate_selfsigned_cert, 'Sofa')
            self.certificate, self.private_key = cert.decode(), key.decode()
        for path, value in ((certfile, self.certificate), (keyfile, self.private_key)):
            with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as fp:
                fp.write(value)

        # Probe only to obtain a certificate. No pairing secret or remote commands
        # are sent on this unverified connection; all protocol traffic is pinned.
        probe = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        probe.check_hostname = False
        probe.verify_mode = ssl.CERT_NONE
        probe.load_cert_chain(certfile, keyfile)
        _, writer = await asyncio.wait_for(asyncio.open_connection(self.host, self.pair_port, ssl=probe), 5)
        try:
            der = writer.get_extra_info('ssl_object').getpeercert(True)
        finally:
            writer.close()
            try:
                await asyncio.wait_for(writer.wait_closed(), 1)
            except (OSError, asyncio.TimeoutError):
                pass
        fingerprint = hashlib.sha256(der).hexdigest().upper()
        approved = command.get('fingerprint', '')
        if approved != fingerprint:
            keyfile.unlink(missing_ok=True)
            self.event('trust', fingerprint=fingerprint, changed=bool(approved))
            return False
        self.server_pem = ssl.DER_cert_to_PEM_cert(der)
        context = pinned_context(str(certfile), str(keyfile), self.server_pem)
        keyfile.unlink()  # Only the public cert is needed during the PIN exchange.
        self.remote = self.remote_factory('Sofa', str(certfile), str(keyfile), self.host,
                                          pinned_ssl_context=context, api_port=self.api_port, pair_port=self.pair_port,
                                          enable_ime=command.get('enable_ime', True), enable_voice=False)
        self.volume_driver = RelativeVolume(
            self.remote.send_key_command,
            lambda **values: self.event('volume_result', **values),
            lambda: self.event('volume_control_unavailable'))
        self.remote.add_is_on_updated_callback(lambda _: self._state())
        self.remote.add_current_app_updated_callback(lambda _: self._state())
        self.remote.add_volume_info_updated_callback(lambda _: self._volume())
        self.remote.add_is_available_updated_callback(self._available)
        return True

    def _state(self):
        if not self.ready or not self.remote:
            return
        value = {'statetype': 'android_state'}
        if self.remote.is_on is not None:
            value['power'] = self.remote.is_on
        if self.remote.current_app:
            value['appname'] = APP_NAMES.get(self.remote.current_app, self.remote.current_app)
        self.event('state', value=value)

    def _volume(self):
        if not self.ready or not self.remote:
            return
        info = self.remote.volume_info
        if self.volume_driver:
            self.volume_driver.report(info)
        if info and info.get('max', 0) > 0 and 0 <= info['level'] <= info['max']:
            self.event('volume', value=round(info['level'] * 100 / info['max']), muted=info['muted'])

    def _available(self, available):
        self.ready = available
        if not available and self.volume_driver:
            self.volume_driver.cancel()
        self.event('status', value='ready' if available else 'offline')
        if available:
            self._state()
            self._volume()

    def _auth_expired(self):
        self.ready = False
        self.event('status', value='pairing')
        self.event('error', message='Pairing was revoked on the TV. Show a new code to pair again.')

    async def _connected(self):
        await self.remote.async_connect()
        self.ready = True
        self.pairing = False
        self.event('status', value='ready')
        info = self.remote.device_info or {}
        self.event('device', name=info.get('model') or 'Google / Android TV',
                   model=' · '.join(filter(None, [info.get('manufacturer'), info.get('model')])) or 'Google / Android TV')
        self.event('apps', value=[{k: v for k, v in item.items() if k != 'link'} for item in SHORTCUTS])
        self.event('sources', value=[])
        self._state()
        self._volume()
        self.remote.keep_reconnecting(self._auth_expired)

    async def _command(self, command):
        action = command.get('action')
        if action == 'connect':
            self.event('status', value='connecting')
            if not await self._prepare(command):
                return
            if command.get('saved'):
                try:
                    await self._connected()
                    return
                except InvalidAuth:
                    self.remote.disconnect()
            await self._command({'action': 'pair'})
        elif action == 'pair':
            if not self.remote:
                raise ValueError('Connect first')
            self.ready = False
            self.pairing = False
            self.event('status', value='connecting')
            await self.remote.async_start_pairing()
            self.pairing = True
            self.event('status', value='pairing')
        elif action == 'pin':
            pin = command.get('pin', '')
            if not valid_pin(pin) or not self.pairing:
                raise InvalidAuth()
            await self.remote.async_finish_pairing(pin.upper())
            # Save only after the TV confirms the code; never return a PIN in errors.
            self.event('credentials', value={'certificate': self.certificate, 'private_key': self.private_key})
            self.event('status', value='connecting')
            await self._connected()
        else:
            if not self.ready or not self.remote:
                raise ValueError('Pair first')
            if action in ('refresh', 'read_volume'):
                self._state()
                self._volume()
            elif action == 'volume':
                self.volume_driver.set_target(command.get('value'), command.get('request'))
            elif action == 'cancel_volume':
                self.volume_driver.cancel()
            elif action == 'key':
                key = KEYS[command.get('key')]
                if key in ('VOLUME_UP', 'VOLUME_DOWN', 'VOLUME_MUTE', 'POWER'):
                    self.volume_driver.cancel()
                self.remote.send_key_command(key)
                self.event('sent', label=command.get('label', 'Command sent'))
            elif action == 'mute':
                self.volume_driver.cancel()
                self.remote.send_key_command('VOLUME_MUTE')
            elif action == 'app':
                index = command['index']
                if type(index) is not int or not 0 <= index < len(SHORTCUTS):
                    raise ValueError('Invalid shortcut')
                self.remote.send_launch_app_command(SHORTCUTS[index]['link'])
                self.event('sent', label=command.get('label', 'App shortcut sent'))
            else:
                raise ValueError('Unsupported Android TV action')
