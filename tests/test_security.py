import json
import tempfile
import unittest
from pathlib import Path
from scripts.setup_anki import AnkiSetup, ANKICONNECT_ADDON_ID


class SecurityConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.setup = AnkiSetup(self.directory.name, ankiconnect_config={
            "apiKey": "a" * 64,
            "webCorsOriginList": ["https://reader.example.com"],
        })
        self.addon = self.setup.addons_dir / str(ANKICONNECT_ADDON_ID)
        self.addon.mkdir(parents=True)

    def test_existing_profile_and_saved_override_receive_rotated_credentials(self):
        self.setup.prefs_db.touch()
        (self.addon / "config.json").write_text('{"apiKey": null, "webCorsOriginList": ["*"]}')
        (self.addon / "meta.json").write_text(json.dumps({
            "name": "AnkiConnect",
            "config": {"apiKey": "old-key", "webCorsOriginList": ["*"], "webCorsOrigin": "http://localhost"},
        }))
        self.assertTrue(self.setup.setup_all())
        config = json.loads((self.addon / "config.json").read_text())
        meta = json.loads((self.addon / "meta.json").read_text())
        self.assertEqual(config["apiKey"], "a" * 64)
        self.assertEqual(meta["config"]["apiKey"], config["apiKey"])
        self.assertEqual(meta["config"]["webCorsOriginList"], ["https://reader.example.com"])
        self.assertIsNone(meta["config"]["webCorsOrigin"])
        self.assertEqual(meta["name"], "AnkiConnect")
        for filename in ["config.json", "meta.json"]:
            self.assertEqual((self.addon / filename).stat().st_mode & 0o777, 0o600)

    def test_missing_key_does_not_replace_existing_configuration(self):
        path = self.addon / "config.json"
        path.write_text('{"apiKey":"existing"}')
        self.setup.ankiconnect_config.pop("apiKey")
        self.assertFalse(self.setup.configure_addon())
        self.assertEqual(json.loads(path.read_text()), {"apiKey": "existing"})

    def test_wildcard_and_non_origin_cors_values_fail_closed(self):
        for origins in [["*"], ["https://*.example.com"], ["https://reader.example.com/path"], "https://reader.example.com"]:
            with self.subTest(origins=origins):
                self.setup.ankiconnect_config["webCorsOriginList"] = origins
                self.assertFalse(self.setup.configure_addon())
                self.assertFalse((self.addon / "config.json").exists())


if __name__ == "__main__":
    unittest.main()
