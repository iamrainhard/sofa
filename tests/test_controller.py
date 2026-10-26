from pathlib import Path
import sys
import unittest
from unittest.mock import Mock
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Resources'))
from controller import Controller


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.events = []
        self.instances = []
        def factory(emit):
            adapter = Mock()
            adapter.emit = emit
            self.instances.append(adapter)
            return adapter
        self.controller = Controller(self.events.append, factory, factory, factory)

    def test_vidaa_probe_and_original_command_preserved(self):
        command = dict(action='connect', session='v1', platform='vidaa', host='192.168.1.9', saved={'accesstoken': 'fixture'})
        self.controller.command(command)
        calls = self.instances[0].command.call_args_list
        self.assertEqual(calls[0].args[0], dict(action='probe', host='192.168.1.9'))
        self.assertEqual(calls[1].args[0], command)

    def test_switch_platform_drops_old_credentials_and_commands(self):
        self.controller.command(dict(action='connect', session='v1', platform='vidaa', host='192.168.1.9'))
        old = self.instances[0]
        self.controller.command(dict(action='connect', session='a1', platform='androidtv', host='192.168.1.9'))
        old.close.assert_called_once()
        old.emit(dict(event='credentials', value={'accesstoken': 'stale'}))
        old.emit(dict(event='status', value='ready'))
        self.assertEqual(self.events, [])
        new = self.instances[1]
        new.command.reset_mock()
        self.controller.command(dict(action='key', key='POWER', session='v1'))
        new.command.assert_not_called()
        new.emit(dict(event='status', value='ready'))
        self.assertEqual(self.events[-1], dict(event='status', value='ready', session='a1', platform='androidtv'))
        self.controller.close()
        new.emit(dict(event='status', value='ready'))
        self.assertEqual(len(self.events), 1)

    def test_unknown_platform_cannot_fall_back_to_vidaa(self):
        with self.assertRaises(ValueError):
            self.controller.command(dict(action='connect', session='x', platform='roku', host='192.168.1.9'))
        self.assertEqual(self.instances, [])

    def test_three_platforms_keep_commands_and_credentials_isolated(self):
        for platform in ('vidaa', 'androidtv', 'samsung', 'vidaa'):
            previous = self.instances[-1] if self.instances else None
            session = f'{platform}-{len(self.instances)}'
            command = dict(action='connect', session=session, platform=platform, host='192.168.1.9', saved={'fixture': platform})
            self.controller.command(command)
            active = self.instances[-1]
            self.assertEqual(active.command.call_args.args[0], command)
            if previous:
                previous.close.assert_called_once()
                previous.emit(dict(event='credentials', value={'token': 'stale'}))
            self.assertFalse(any(e.get('value') == {'token': 'stale'} for e in self.events))
            active.emit(dict(event='credentials', value={'fixture': platform}))
            self.assertEqual(self.events[-1]['platform'], platform)
            self.assertEqual(self.events[-1]['session'], session)
            active.command.reset_mock()
            self.controller.command(dict(action='key', key='HOME', session=session))
            active.command.assert_called_once()
        self.controller.close()

class DiscoveryRoutingTests(unittest.TestCase):
    def test_cancel_and_new_scan_discard_late_results(self):
        from unittest.mock import patch
        jobs = []
        class Thread:
            def __init__(self, target, args=(), **kwargs): jobs.append((target, args))
            def start(self): pass
        events = []
        controller = Controller(events.append)
        with patch('controller.threading.Thread', Thread), patch('controller.discover') as discover:
            controller.command(dict(action='discover', discovery='old', interfaces=[]))
            oldtarget, oldargs = jobs[-1]
            controller.command(dict(action='discover', discovery='new', interfaces=[]))
            newtarget, newargs = jobs[-1]
            oldargs[1]({'host': '192.168.1.2'})
            self.assertEqual(events, [])
            newargs[1]({'host': '192.168.1.3'})
            self.assertEqual(events[0]['discovery'], 'new')
            controller.command(dict(action='cancel_discovery'))
            newargs[1]({'host': '192.168.1.4'})
            self.assertEqual(len(events), 1)
        controller.inspection_pool.shutdown()

    def test_unrelated_or_duplicate_candidate_is_not_probed(self):
        from unittest.mock import patch
        controller = Controller(lambda value: None)
        controller.discovery_token = 'scan'
        with patch.object(controller.inspection_pool, 'submit') as submit:
            command = dict(action='inspect_device', discovery='old', host='192.168.1.2', platform='androidtv', identity='bonjour:TV')
            controller.command(command); submit.assert_not_called()
            command['discovery'] = 'scan'
            controller.command(command); controller.command(command)
            self.assertEqual(submit.call_count, 1)
        controller.inspection_pool.shutdown()
