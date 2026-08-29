import importlib.util
import os
import pathlib
import stat
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "helpers" / "home_zone_config.py"
SPEC = importlib.util.spec_from_file_location("home_zone_config", HELPER_PATH)
config_helper = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(config_helper)


class ConfigHelperTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.temporary.name)
        self.home_descriptor = os.open(
            self.home,
            os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC,
        )
        self.config_descriptor = config_helper._open_config_directory_from_home(
            self.home_descriptor,
            effective_uid=os.geteuid(),
            create=True,
        )

    def write_raw(self, payload, mode=0o600):
        descriptor = os.open(
            config_helper.CONFIG_NAME,
            os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_CLOEXEC,
            mode,
            dir_fd=self.config_descriptor,
        )
        try:
            os.write(descriptor, payload)
            os.fchmod(descriptor, mode)
        finally:
            os.close(descriptor)

    def remove_target(self):
        try:
            os.unlink(config_helper.CONFIG_NAME, dir_fd=self.config_descriptor)
        except FileNotFoundError:
            pass

    def target_mode(self):
        metadata = os.stat(
            config_helper.CONFIG_NAME,
            dir_fd=self.config_descriptor,
            follow_symlinks=False,
        )
        return stat.S_IMODE(metadata.st_mode)

    def test_round_trip_is_atomic_and_restrictive(self):
        config_helper.write_config_to_directory(
            self.config_descriptor,
            os.geteuid(),
            b'{"display":{"placement":"right"}}',
        )
        first_inode = os.stat(
            config_helper.CONFIG_NAME,
            dir_fd=self.config_descriptor,
        ).st_ino

        config_helper.write_config_to_directory(
            self.config_descriptor,
            os.geteuid(),
            b'{"display":{"placement":"left"}}',
        )
        second_inode = os.stat(
            config_helper.CONFIG_NAME,
            dir_fd=self.config_descriptor,
        ).st_ino

        self.assertNotEqual(first_inode, second_inode)
        self.assertEqual(self.target_mode(), 0o600)
        payload = config_helper.read_config_from_directory(
            self.config_descriptor, os.geteuid()
        )
        self.assertEqual(
            payload,
            b'{\n  "display": {\n    "placement": "left"\n  }\n}\n',
        )

    def test_legacy_read_only_permissions_are_tightened(self):
        self.write_raw(b"{}\n", 0o644)

        self.assertEqual(
            config_helper.read_config_from_directory(
                self.config_descriptor, os.geteuid()
            ),
            b"{}\n",
        )
        self.assertEqual(self.target_mode(), 0o600)

    def test_symlink_target_is_rejected_without_touching_victim(self):
        victim = self.home / "victim.json"
        victim.write_text('{"untouched":true}\n')
        self.remove_target()
        os.symlink(victim, config_helper.CONFIG_NAME, dir_fd=self.config_descriptor)

        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.read_config_from_directory(
                self.config_descriptor, os.geteuid()
            )
        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.write_config_to_directory(
                self.config_descriptor, os.geteuid(), b"{}"
            )
        self.assertEqual(victim.read_text(), '{"untouched":true}\n')

    def test_non_regular_and_hard_link_targets_are_rejected(self):
        os.mkfifo(config_helper.CONFIG_NAME, 0o600, dir_fd=self.config_descriptor)
        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.read_config_from_directory(
                self.config_descriptor, os.geteuid()
            )
        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.write_config_to_directory(
                self.config_descriptor, os.geteuid(), b"{}"
            )
        self.remove_target()

        victim = self.home / "linked.json"
        victim.write_text("{}\n")
        os.chmod(victim, 0o600)
        os.link(victim, config_helper.CONFIG_NAME, dst_dir_fd=self.config_descriptor)
        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.write_config_to_directory(
                self.config_descriptor, os.geteuid(), b"{}"
            )

    def test_group_writable_target_is_rejected(self):
        self.write_raw(b"{}\n", 0o620)

        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.read_config_from_directory(
                self.config_descriptor, os.geteuid()
            )
        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.write_config_to_directory(
                self.config_descriptor, os.geteuid(), b"{}"
            )

    def test_unexpected_owner_is_rejected(self):
        self.write_raw(b"{}\n")

        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.read_config_from_directory(
                self.config_descriptor, os.geteuid() + 1
            )

    def test_read_size_is_bounded(self):
        self.write_raw(b"x" * (config_helper.MAX_CONFIG_BYTES + 1))

        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper.read_config_from_directory(
                self.config_descriptor, os.geteuid()
            )

    def test_symlinked_config_directory_is_rejected(self):
        os.close(self.config_descriptor)
        self.config_descriptor = -1
        config_root = self.home / ".config"
        for child in config_root.iterdir():
            child.rmdir()
        config_root.rmdir()
        replacement = self.home / "redirected"
        replacement.mkdir()
        config_root.symlink_to(replacement, target_is_directory=True)

        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper._open_config_directory_from_home(
                self.home_descriptor,
                effective_uid=os.geteuid(),
                create=False,
            )

    def test_group_writable_config_directory_is_rejected(self):
        os.close(self.config_descriptor)
        self.config_descriptor = -1
        config_directory = self.home / ".config" / "omarchy"
        os.chmod(config_directory, 0o770)

        with self.assertRaises(config_helper.ConfigSecurityError):
            config_helper._open_config_directory_from_home(
                self.home_descriptor,
                effective_uid=os.geteuid(),
                create=False,
            )

    def tearDown(self):
        if self.config_descriptor >= 0:
            os.close(self.config_descriptor)
        os.close(self.home_descriptor)
        self.temporary.cleanup()


if __name__ == "__main__":
    unittest.main()
