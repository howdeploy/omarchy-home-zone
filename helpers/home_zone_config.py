#!/usr/bin/python3

"""Confined settings I/O for Home Zone.

The QML plugin delegates its only persistent file boundary to this helper. The
command-line interface never accepts a path: it resolves the current account's
home directory from the effective UID and only operates on
``.config/omarchy/home-zone.json`` below that directory.
"""

from __future__ import annotations

import errno
import json
import os
import pathlib
import pwd
import secrets
import stat
import sys
from contextlib import contextmanager
from typing import Iterator


CONFIG_DIRECTORY_PARTS = (".config", "omarchy")
CONFIG_NAME = "home-zone.json"
MAX_CONFIG_BYTES = 64 * 1024
EXIT_ERROR = 2
EXIT_MISSING = 3

_DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
_READ_FLAGS = os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW | os.O_CLOEXEC


class ConfigError(Exception):
    """Base class for a rejected or unavailable settings operation."""


class ConfigMissing(ConfigError):
    """The settings directory or file does not exist yet."""


class ConfigSecurityError(ConfigError):
    """The settings path failed an ownership, type, or mode check."""


def _mode(value: int) -> str:
    return f"{stat.S_IMODE(value):04o}"


def _validate_directory(
    descriptor: int,
    *,
    effective_uid: int,
    require_user_owner: bool,
    label: str,
) -> None:
    metadata = os.fstat(descriptor)
    if not stat.S_ISDIR(metadata.st_mode):
        raise ConfigSecurityError(f"{label} is not a directory")

    allowed_owners = {effective_uid} if require_user_owner else {0, effective_uid}
    if metadata.st_uid not in allowed_owners:
        raise ConfigSecurityError(f"{label} has an unexpected owner")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        raise ConfigSecurityError(
            f"{label} has unsafe permissions {_mode(metadata.st_mode)}"
        )


def _open_directory_at(
    parent_descriptor: int,
    name: str,
    *,
    effective_uid: int,
    require_user_owner: bool,
    create: bool,
    label: str,
) -> int:
    try:
        descriptor = os.open(name, _DIRECTORY_FLAGS, dir_fd=parent_descriptor)
    except FileNotFoundError:
        if not create:
            raise ConfigMissing(f"{label} does not exist") from None
        try:
            os.mkdir(name, 0o700, dir_fd=parent_descriptor)
        except FileExistsError:
            pass
        descriptor = os.open(name, _DIRECTORY_FLAGS, dir_fd=parent_descriptor)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.ENOTDIR):
            raise ConfigSecurityError(f"{label} is not a real directory") from None
        raise

    try:
        _validate_directory(
            descriptor,
            effective_uid=effective_uid,
            require_user_owner=require_user_owner,
            label=label,
        )
    except Exception:
        os.close(descriptor)
        raise
    return descriptor


def _open_home_directory(home: pathlib.Path, effective_uid: int) -> int:
    if not home.is_absolute() or home == pathlib.Path("/"):
        raise ConfigSecurityError("the account home directory is invalid")

    current = os.open("/", _DIRECTORY_FLAGS)
    try:
        _validate_directory(
            current,
            effective_uid=effective_uid,
            require_user_owner=False,
            label="filesystem root",
        )
        components = home.parts[1:]
        if not components or any(component in ("", ".", "..") for component in components):
            raise ConfigSecurityError("the account home directory is not canonical")
        for index, component in enumerate(components):
            next_descriptor = _open_directory_at(
                current,
                component,
                effective_uid=effective_uid,
                require_user_owner=index == len(components) - 1,
                create=False,
                label=(
                    "account home"
                    if index == len(components) - 1
                    else "home ancestor"
                ),
            )
            os.close(current)
            current = next_descriptor
        return current
    except Exception:
        os.close(current)
        raise


def _open_config_directory_from_home(
    home_descriptor: int, *, effective_uid: int, create: bool
) -> int:
    current = os.dup(home_descriptor)
    try:
        for component in CONFIG_DIRECTORY_PARTS:
            next_descriptor = _open_directory_at(
                current,
                component,
                effective_uid=effective_uid,
                require_user_owner=True,
                create=create,
                label=f"settings directory {component}",
            )
            os.close(current)
            current = next_descriptor
        return current
    except Exception:
        os.close(current)
        raise


@contextmanager
def _config_directory(*, create: bool) -> Iterator[tuple[int, int]]:
    effective_uid = os.geteuid()
    home = pathlib.Path(pwd.getpwuid(effective_uid).pw_dir)
    home_descriptor = _open_home_directory(home, effective_uid)
    try:
        config_descriptor = _open_config_directory_from_home(
            home_descriptor,
            effective_uid=effective_uid,
            create=create,
        )
    finally:
        os.close(home_descriptor)

    try:
        yield config_descriptor, effective_uid
    finally:
        os.close(config_descriptor)


def _target_metadata(directory_descriptor: int) -> os.stat_result:
    try:
        metadata = os.stat(
            CONFIG_NAME,
            dir_fd=directory_descriptor,
            follow_symlinks=False,
        )
    except FileNotFoundError:
        raise ConfigMissing("settings file does not exist") from None

    if not stat.S_ISREG(metadata.st_mode):
        raise ConfigSecurityError("settings target is not a regular file")
    return metadata


def _open_verified_target(directory_descriptor: int, effective_uid: int) -> int:
    before = _target_metadata(directory_descriptor)
    try:
        descriptor = os.open(CONFIG_NAME, _READ_FLAGS, dir_fd=directory_descriptor)
    except OSError as error:
        if error.errno in (errno.ELOOP, errno.ENXIO, errno.ENODEV):
            raise ConfigSecurityError("settings target cannot be opened safely") from None
        raise

    try:
        metadata = os.fstat(descriptor)
        if (metadata.st_dev, metadata.st_ino) != (before.st_dev, before.st_ino):
            raise ConfigSecurityError("settings target changed during validation")
        if not stat.S_ISREG(metadata.st_mode):
            raise ConfigSecurityError("settings target is not a regular file")
        if metadata.st_uid != effective_uid:
            raise ConfigSecurityError("settings target has an unexpected owner")
        if metadata.st_nlink != 1:
            raise ConfigSecurityError("settings target has multiple hard links")

        permissions = stat.S_IMODE(metadata.st_mode)
        if permissions & 0o022:
            raise ConfigSecurityError(
                f"settings target has unsafe permissions {permissions:04o}"
            )
        if permissions & 0o077:
            os.fchmod(descriptor, 0o600)
        return descriptor
    except Exception:
        os.close(descriptor)
        raise


def _read_bounded(descriptor: int) -> bytes:
    metadata = os.fstat(descriptor)
    if metadata.st_size > MAX_CONFIG_BYTES:
        raise ConfigSecurityError("settings file exceeds the 64 KiB read limit")

    chunks: list[bytes] = []
    remaining = MAX_CONFIG_BYTES + 1
    while remaining > 0:
        chunk = os.read(descriptor, min(16 * 1024, remaining))
        if not chunk:
            break
        chunks.append(chunk)
        remaining -= len(chunk)

    payload = b"".join(chunks)
    if len(payload) > MAX_CONFIG_BYTES:
        raise ConfigSecurityError("settings file exceeds the 64 KiB read limit")
    return payload


def read_config_from_directory(directory_descriptor: int, effective_uid: int) -> bytes:
    descriptor = _open_verified_target(directory_descriptor, effective_uid)
    try:
        return _read_bounded(descriptor)
    finally:
        os.close(descriptor)


def _normalized_payload(payload: bytes) -> bytes:
    if len(payload) > MAX_CONFIG_BYTES:
        raise ConfigSecurityError("settings payload exceeds the 64 KiB limit")
    try:
        parsed = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ConfigError(f"settings payload is not valid JSON: {error}") from None
    if not isinstance(parsed, dict):
        raise ConfigError("settings root must be a JSON object")

    normalized = (json.dumps(parsed, ensure_ascii=False, indent=2) + "\n").encode()
    if len(normalized) > MAX_CONFIG_BYTES:
        raise ConfigSecurityError("normalized settings exceed the 64 KiB limit")
    return normalized


def write_config_to_directory(
    directory_descriptor: int, effective_uid: int, payload: bytes
) -> None:
    normalized = _normalized_payload(payload)
    try:
        existing_descriptor = _open_verified_target(directory_descriptor, effective_uid)
    except ConfigMissing:
        existing_descriptor = -1
    if existing_descriptor >= 0:
        os.close(existing_descriptor)

    temporary_name = f".{CONFIG_NAME}.tmp-{os.getpid()}-{secrets.token_hex(12)}"
    temporary_descriptor = -1
    try:
        temporary_descriptor = os.open(
            temporary_name,
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
            | os.O_NOFOLLOW
            | os.O_CLOEXEC,
            0o600,
            dir_fd=directory_descriptor,
        )
        os.fchmod(temporary_descriptor, 0o600)
        view = memoryview(normalized)
        while view:
            written = os.write(temporary_descriptor, view)
            view = view[written:]
        os.fsync(temporary_descriptor)
        os.close(temporary_descriptor)
        temporary_descriptor = -1

        os.replace(
            temporary_name,
            CONFIG_NAME,
            src_dir_fd=directory_descriptor,
            dst_dir_fd=directory_descriptor,
        )
        os.fsync(directory_descriptor)
    finally:
        if temporary_descriptor >= 0:
            os.close(temporary_descriptor)
        try:
            os.unlink(temporary_name, dir_fd=directory_descriptor)
        except FileNotFoundError:
            pass


def read_config() -> bytes:
    with _config_directory(create=False) as (directory_descriptor, effective_uid):
        return read_config_from_directory(directory_descriptor, effective_uid)


def write_config(payload: bytes) -> None:
    old_umask = os.umask(0o077)
    try:
        with _config_directory(create=True) as (directory_descriptor, effective_uid):
            write_config_to_directory(directory_descriptor, effective_uid, payload)
    finally:
        os.umask(old_umask)


def _read_stdin_payload() -> bytes:
    payload = sys.stdin.buffer.readline(MAX_CONFIG_BYTES + 2)
    if len(payload) > MAX_CONFIG_BYTES + 1:
        raise ConfigSecurityError("settings payload exceeds the 64 KiB limit")
    if payload.endswith(b"\n"):
        payload = payload[:-1]
    if payload.endswith(b"\r"):
        payload = payload[:-1]
    return payload


def main(arguments: list[str]) -> int:
    if arguments == ["read"]:
        try:
            sys.stdout.buffer.write(read_config())
        except ConfigMissing:
            return EXIT_MISSING
        except (ConfigError, OSError) as error:
            print(f"Home Zone config helper: {error}", file=sys.stderr)
            return EXIT_ERROR
        return 0

    if arguments == ["write"]:
        try:
            write_config(_read_stdin_payload())
        except (ConfigError, OSError) as error:
            print(f"Home Zone config helper: {error}", file=sys.stderr)
            return EXIT_ERROR
        return 0

    print("usage: home_zone_config.py read|write", file=sys.stderr)
    return EXIT_ERROR


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
