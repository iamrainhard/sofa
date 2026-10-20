"""Release guards must reject mismatched, preview and unpublished update packages."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('update_feed', Path(__file__).resolve().parents[1] / 'scripts/update-feed.py')
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


class UpdateFeedChecks(unittest.TestCase):
    def setUp(self):
        self.config = dict(SUPublicEDKey='public-test-key', SUFeedURL='https://example.com/appcast.xml',
                           SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)
        self.info = dict(self.config, CFBundleIdentifier='com.rain.luma-remote', CFBundleVersion='15', CFBundleShortVersionString='0.6.0-beta.1')
        self.tag, self.name, self.digest = 'v0.6.0-beta.1-build15', 'Sofa-0.6.0-beta.1-build15-arm64-notarized.zip', 'a' * 64
        self.url = f'https://github.com/iamrainhard/sofa/releases/download/{self.tag}/{self.name}'
        self.asset = dict(name=self.name, browser_download_url=self.url, size=42, digest='sha256:' + self.digest)
        self.release = dict(draft=False, tag_name=self.tag, assets=[self.asset])

    def check_release(self):
        return feed.validate_release(self.release, self.name, 42, self.digest, self.tag)

    def test_valid_published_asset(self):
        self.assertEqual(self.check_release(), self.url)
        self.assertEqual(feed.validate_app(self.info, self.config), ('15', '0.6.0-beta.1'))

    def test_preview_rejected(self):
        self.info['SofaPreviewState'] = 'remote'
        with self.assertRaises(ValueError): feed.validate_app(self.info, self.config)

    def test_changed_identity_key_or_feed_rejected(self):
        for field in ('CFBundleIdentifier', 'SUPublicEDKey', 'SUFeedURL', 'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction'):
            with self.subTest(field=field), self.assertRaises(ValueError):
                feed.validate_app(dict(self.info, **{field: 'wrong'}), self.config)

    def test_invalid_build_rejected(self):
        for build in ('14', 'abc', ''):
            with self.subTest(build=build), self.assertRaises(ValueError):
                feed.validate_app(dict(self.info, CFBundleVersion=build), self.config)

    def test_draft_or_wrong_tag_rejected(self):
        for change in ({'draft': True}, {'tag_name': 'wrong'}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                feed.validate_release(dict(self.release, **change), self.name, 42, self.digest, self.tag)

    def test_missing_asset_rejected(self):
        self.release['assets'] = []
        with self.assertRaises(ValueError): self.check_release()

    def test_remote_bytes_or_url_mismatch_rejected(self):
        for field, value in (('size', 43), ('digest', None), ('digest', 'sha256:' + 'b' * 64), ('browser_download_url', 'https://example.com/app.zip')):
            with self.subTest(field=field), self.assertRaises(ValueError):
                feed.validate_release(dict(self.release, assets=[dict(self.asset, **{field: value})]), self.name, 42, self.digest, self.tag)


if __name__ == '__main__':
    unittest.main()
