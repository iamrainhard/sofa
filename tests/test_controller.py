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
        self.controller = Controller(self.events.append, factory, factory)

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
