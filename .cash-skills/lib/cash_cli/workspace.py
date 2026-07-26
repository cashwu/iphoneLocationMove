from __future__ import annotations

import base64
import errno
import json
import os
import re
import shutil
import stat
import subprocess
import uuid
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterator

from .config import ConfigError, parse_cash_config, parse_openspec_config
from .errors import CashError


_CHANGE_NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
_ARCHIVE_NAME = re.compile(r"\d{4}-\d{2}-\d{2}-")


@dataclass(slots=True)
class Workspace:
    root: Path

    @classmethod
    def discover(
        cls,
        start: str | os.PathLike[str] | None = None,
        *,
        launcher_root: str | os.PathLike[str] | None = None,
    ) -> "Workspace":
        cwd = Path(start or os.getcwd()).resolve()
        try:
            result = subprocess.run(
                ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
                check=True,
                capture_output=True,
                text=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise CashError("workspace_not_found", "Unable to resolve Git root.", 1) from error
        root = Path(result.stdout.strip()).resolve()
        if launcher_root is not None and root != Path(launcher_root).resolve():
            raise CashError(
                "workspace_root_mismatch",
                "Launcher root and discovered Git root differ.",
                1,
                str(root),
            )
        workspace = cls(root)
        workspace._require_regular(".cash.yaml")
        workspace._require_regular("openspec/config.yaml")
        workspace._require_lock()
        workspace.load_config()
        return workspace

    @property
    def changes(self) -> Path:
        return self.root / "openspec" / "changes"

    @property
    def parked(self) -> Path:
        return self.changes / ".parked"

    @property
    def archive(self) -> Path:
        return self.changes / "archive"

    @property
    def specs(self) -> Path:
        return self.root / "openspec" / "specs"

    @property
    def state(self) -> Path:
        return self.root / ".cash-skills" / "state"

    @property
    def transactions(self) -> Path:
        return self.state / "transactions"

    def load_config(self) -> tuple[dict[str, object], dict[str, object]]:
        try:
            cash = parse_cash_config(
                self.read_text(".cash.yaml"),
                path=".cash.yaml",
            )
            openspec = parse_openspec_config(
                self.read_text("openspec/config.yaml"),
                path="openspec/config.yaml",
            )
        except ConfigError as error:
            raise CashError(
                "config_invalid",
                str(error),
                2,
                error.path,
            ) from error
        return cash, openspec

    def change_path(self, name: str, *, parked: bool = False) -> Path:
        if (
            _CHANGE_NAME.fullmatch(name) is None
            or _ARCHIVE_NAME.match(name) is not None
        ):
            raise CashError("unsafe_change_name", f"Unsafe change name: {name}")
        base = self.parked if parked else self.changes
        return base / name

    def relative(self, path: Path) -> str:
        try:
            return path.relative_to(self.root).as_posix()
        except ValueError as error:
            raise CashError("unsafe_path", "Path escapes workspace.", path=str(path)) from error

    def _relative_value(self, value: str | os.PathLike[str]) -> str:
        path = Path(value)
        if path.is_absolute():
            try:
                path = path.relative_to(self.root)
            except ValueError as error:
                raise CashError("unsafe_path", "Path escapes workspace.", path=str(value)) from error
        if not path.parts or path == Path(".") or ".." in path.parts:
            if path == Path("."):
                return ""
            raise CashError("unsafe_path", "Path escapes workspace.", path=str(value))
        return path.as_posix()

    @contextmanager
    def _open_directory(self, relative: str | os.PathLike[str] = "") -> Iterator[int]:
        value = self._relative_value(relative) if str(relative) not in {"", "."} else ""
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(self.root, flags)
        try:
            for part in Path(value).parts:
                try:
                    child = os.open(part, flags, dir_fd=descriptor)
                except FileNotFoundError:
                    raise
                except OSError as error:
                    raise CashError("unsafe_path", str(error), 1, value) from error
                os.close(descriptor)
                descriptor = child
                metadata = os.fstat(descriptor)
                if not stat.S_ISDIR(metadata.st_mode):
                    raise CashError("unsafe_path", "Expected a real directory.", path=value)
            yield descriptor
        finally:
            os.close(descriptor)

    @contextmanager
    def _open_parent(self, relative: str | os.PathLike[str]) -> Iterator[tuple[int, str]]:
        value = self._relative_value(relative)
        path = Path(value)
        with self._open_directory(path.parent.as_posix()) as descriptor:
            yield descriptor, path.name

    def path_kind(self, relative: str | os.PathLike[str]) -> str:
        value = self._relative_value(relative)
        try:
            with self._open_parent(value) as (parent, name):
                metadata = os.stat(name, dir_fd=parent, follow_symlinks=False)
        except FileNotFoundError:
            return "missing"
        except OSError as error:
            raise CashError("unsafe_path", str(error), 1, value) from error
        if stat.S_ISLNK(metadata.st_mode):
            raise CashError("unsafe_path", "Symlink managed paths are not allowed.", path=value)
        if stat.S_ISREG(metadata.st_mode):
            return "file"
        if stat.S_ISDIR(metadata.st_mode):
            return "directory"
        return "other"

    def exists(self, relative: str | os.PathLike[str]) -> bool:
        return self.path_kind(relative) != "missing"

    def is_file(self, relative: str | os.PathLike[str]) -> bool:
        return self.path_kind(relative) == "file"

    def is_dir(self, relative: str | os.PathLike[str]) -> bool:
        return self.path_kind(relative) == "directory"

    def stat(self, relative: str | os.PathLike[str]) -> os.stat_result:
        value = self._relative_value(relative)
        try:
            with self._open_parent(value) as (parent, name):
                metadata = os.stat(name, dir_fd=parent, follow_symlinks=False)
        except OSError as error:
            raise CashError("unsafe_path", str(error), 1, value) from error
        if stat.S_ISLNK(metadata.st_mode):
            raise CashError("unsafe_path", "Symlink managed paths are not allowed.", path=value)
        return metadata

    def list_directory(self, relative: str | os.PathLike[str]) -> list[tuple[str, str]]:
        value = self._relative_value(relative)
        try:
            with self._open_directory(value) as descriptor:
                names = os.listdir(descriptor)
                entries: list[tuple[str, str]] = []
                for name in names:
                    metadata = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
                    if stat.S_ISLNK(metadata.st_mode):
                        raise CashError(
                            "unsafe_path",
                            "Symlink managed paths are not allowed.",
                            path=f"{value}/{name}",
                        )
                    if stat.S_ISDIR(metadata.st_mode):
                        kind = "directory"
                    elif stat.S_ISREG(metadata.st_mode):
                        kind = "file"
                    else:
                        kind = "other"
                    entries.append((name, kind))
        except FileNotFoundError:
            return []
        except OSError as error:
            raise CashError("unsafe_path", str(error), 1, value) from error
        return sorted(entries, key=lambda item: item[0].encode("utf-8"))

    def spec_files(self, relative: str | os.PathLike[str]) -> list[str]:
        base = self._relative_value(relative)
        result: list[str] = []
        for capability, kind in self.list_directory(base):
            if kind != "directory":
                continue
            candidate = f"{base}/{capability}/spec.md"
            if self.is_file(candidate):
                result.append(candidate)
        return result

    def walk_text_files(
        self,
        relative: str | os.PathLike[str],
        *,
        exclude_directory: Callable[[tuple[str, ...]], bool] | None = None,
    ) -> list[tuple[str, str]]:
        base = self._relative_value(relative)
        result: list[tuple[str, str]] = []
        flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)

        def visit(descriptor: int, prefix: str) -> None:
            for name in sorted(os.listdir(descriptor), key=lambda value: value.encode("utf-8")):
                metadata = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
                candidate = f"{prefix}/{name}"
                if stat.S_ISLNK(metadata.st_mode):
                    raise CashError(
                        "unsafe_path",
                        "Symlink managed paths are not allowed.",
                        path=candidate,
                    )
                if stat.S_ISDIR(metadata.st_mode):
                    if exclude_directory is not None and exclude_directory(
                        Path(candidate).parts
                    ):
                        continue
                    child = os.open(name, flags, dir_fd=descriptor)
                    try:
                        opened = os.fstat(child)
                        if (opened.st_dev, opened.st_ino) != (
                            metadata.st_dev,
                            metadata.st_ino,
                        ):
                            raise CashError(
                                "unsafe_path",
                                "Directory identity changed during traversal.",
                                path=candidate,
                            )
                        visit(child, candidate)
                    finally:
                        os.close(child)
                elif stat.S_ISREG(metadata.st_mode):
                    descriptor_file = os.open(
                        name,
                        os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
                        dir_fd=descriptor,
                    )
                    try:
                        opened = os.fstat(descriptor_file)
                        if (
                            not stat.S_ISREG(opened.st_mode)
                            or (opened.st_dev, opened.st_ino)
                            != (metadata.st_dev, metadata.st_ino)
                        ):
                            raise CashError(
                                "unsafe_path",
                                "File identity changed during traversal.",
                                path=candidate,
                            )
                        chunks: list[bytes] = []
                        while chunk := os.read(descriptor_file, 131072):
                            chunks.append(chunk)
                    finally:
                        os.close(descriptor_file)
                    try:
                        text = b"".join(chunks).decode("utf-8")
                    except UnicodeDecodeError as error:
                        raise CashError(
                            "invalid_encoding",
                            "Expected UTF-8.",
                            1,
                            candidate,
                        ) from error
                    result.append((candidate, text))

        with self._open_directory(base) as descriptor:
            visit(descriptor, base)
        return result

    def safe_path(self, relative: str | os.PathLike[str], *, allow_missing: bool = False) -> Path:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise CashError("unsafe_path", "Path escapes workspace.", path=str(relative))
        candidate = self.root.joinpath(path)
        current = self.root
        for part in path.parts:
            current = current / part
            try:
                metadata = os.lstat(current)
            except FileNotFoundError:
                if allow_missing:
                    return candidate
                raise CashError("missing_path", "Managed path does not exist.", path=str(relative))
            if stat.S_ISLNK(metadata.st_mode):
                raise CashError("unsafe_path", "Symlink managed paths are not allowed.", path=str(relative))
        return candidate

    def read_bytes(self, relative: str | os.PathLike[str]) -> bytes:
        value = self._relative_value(relative)
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
        try:
            with self._open_parent(value) as (parent, name):
                descriptor = os.open(name, flags, dir_fd=parent)
                named = os.stat(name, dir_fd=parent, follow_symlinks=False)
        except OSError as error:
            if error.errno == errno.ELOOP:
                raise CashError(
                    "unsafe_path",
                    "Symlink managed paths are not allowed.",
                    1,
                    value,
                ) from error
            raise CashError("read_failed", str(error), 1, value) from error
        try:
            metadata = os.fstat(descriptor)
            if (
                not stat.S_ISREG(metadata.st_mode)
                or (metadata.st_dev, metadata.st_ino)
                != (named.st_dev, named.st_ino)
            ):
                raise CashError("unsafe_path", "Managed read identity changed.", path=value)
            chunks: list[bytes] = []
            while chunk := os.read(descriptor, 131072):
                chunks.append(chunk)
            return b"".join(chunks)
        finally:
            os.close(descriptor)

    def read_text(self, relative: str | os.PathLike[str]) -> str:
        try:
            return self.read_bytes(relative).decode("utf-8")
        except UnicodeDecodeError as error:
            raise CashError("invalid_encoding", "Expected UTF-8.", 1, str(relative)) from error

    def assert_readable(self) -> None:
        if not self.exists(".cash-skills/state/transactions"):
            return
        for token, kind in self.list_directory(".cash-skills/state/transactions"):
            if kind == "directory" and self.is_file(
                f".cash-skills/state/transactions/{token}/journal.json"
            ):
                raise CashError(
                    "recovery_required",
                    "An unfinished transaction requires recovery.",
                    1,
                    f".cash-skills/state/transactions/{token}/journal.json",
                )

    def recover(self) -> None:
        if not self.exists(".cash-skills/state/transactions"):
            return
        for token, kind in self.list_directory(".cash-skills/state/transactions"):
            relative = f".cash-skills/state/transactions/{token}/journal.json"
            if kind == "directory" and self.is_file(relative):
                _recover_journal(self, self.root / relative)

    def transaction(self) -> "Transaction":
        return Transaction(self)

    def ensure_directory(self, relative: str, *, mode: int = 0o755) -> Path:
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts:
            raise CashError("unsafe_path", "Directory escapes workspace.", path=relative)
        current = self.root
        for part in path.parts:
            current = current / part
            try:
                metadata = os.lstat(current)
            except FileNotFoundError:
                os.mkdir(current, mode)
                metadata = os.lstat(current)
            if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
                raise CashError("unsafe_path", "Expected a real directory.", path=relative)
        return current

    def _require_regular(self, relative: str) -> os.stat_result:
        path = self.safe_path(relative)
        metadata = os.lstat(path)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise CashError("unsafe_path", "Expected a single-link regular file.", path=relative)
        return metadata

    def _require_lock(self) -> None:
        try:
            metadata = self._require_regular(".cash-workspace.lock")
        except CashError as error:
            raise CashError(
                "workspace_lock_invalid",
                "Workspace lock is missing or unsafe.",
                1,
                ".cash-workspace.lock",
            ) from error
        if stat.S_IMODE(metadata.st_mode) != 0o644 or metadata.st_size != 0:
            raise CashError(
                "workspace_lock_invalid",
                "Workspace lock must be an empty 0644 regular file.",
                1,
                ".cash-workspace.lock",
            )


@dataclass(slots=True)
class Transaction:
    workspace: Workspace
    operations: list[dict[str, object]] = field(default_factory=list)

    def write(self, relative: str, content: bytes, *, mode: int = 0o644) -> None:
        path = self.workspace.safe_path(relative, allow_missing=True)
        self.operations.append(
            {
                "kind": "write",
                "path": relative,
                "content": base64.b64encode(content).decode("ascii"),
                "mode": mode,
                "temporary": f".cash-tmp-{uuid.uuid4().hex}",
                "published_identity": None,
                "before": _relative_snapshot(self.workspace, relative),
                "parent": _directory_identity(
                    self.workspace,
                    Path(relative).parent.as_posix(),
                ),
            }
        )

    def move(self, source: str, destination: str) -> None:
        self.workspace.safe_path(source)
        self.workspace.safe_path(destination, allow_missing=True)
        if self.workspace.exists(destination):
            raise CashError("destination_collision", "Destination already exists.", path=destination)
        self.operations.append(
            {
                "kind": "move",
                "source": source,
                "destination": destination,
                "source_identity": _relative_identity(self.workspace, source),
                "source_parent": _directory_identity(
                    self.workspace,
                    Path(source).parent.as_posix(),
                ),
                "destination_parent": _directory_identity(
                    self.workspace,
                    Path(destination).parent.as_posix(),
                ),
            }
        )

    def delete(self, relative: str) -> None:
        self.workspace.safe_path(relative)
        self.operations.append(
            {
                "kind": "delete",
                "path": relative,
                "before": _relative_snapshot(self.workspace, relative),
                "parent": _directory_identity(
                    self.workspace,
                    Path(relative).parent.as_posix(),
                ),
            }
        )

    def commit(self) -> None:
        if not self.operations:
            return
        self.workspace.recover()
        for operation in self.operations:
            _validate_operation_snapshot(self.workspace, operation)
        token = uuid.uuid4().hex
        directory = self.workspace.transactions / token
        directory.mkdir(parents=True, mode=0o700)
        journal = directory / "journal.json"
        document = {"version": 1, "published": 0, "operations": self.operations}
        _write_journal(journal, document)
        published = 0
        completed = 0
        try:
            for operation in self.operations:
                if operation["kind"] == "write":
                    operation["published_identity"] = _stage_write(
                        self.workspace,
                        operation,
                    )
                published += 1
                document["published"] = published
                _write_journal(journal, document)
                _publish(self.workspace, operation)
                completed = published
                if os.environ.get("CASH_WORKSPACE_CRASH_AFTER_PUBLISH") == str(published):
                    os._exit(97)
        except Exception:
            try:
                rollback_count = completed
                if (
                    published > completed
                    and _operation_matches_published(
                        self.workspace,
                        self.operations[published - 1],
                    )
                ):
                    rollback_count = published
                _rollback(self.workspace, self.operations[:rollback_count])
                _cleanup_temporaries(self.workspace, self.operations)
                shutil.rmtree(directory)
                _remove_empty_parents(self.workspace)
            except Exception as rollback_error:
                raise CashError(
                    "rollback_failed",
                    f"Transaction rollback failed: {rollback_error}",
                    1,
                    self.workspace.relative(journal),
                ) from rollback_error
            raise
        shutil.rmtree(directory)
        _remove_empty_parents(self.workspace)


def _write_journal(journal: Path, document: dict[str, object]) -> None:
    temporary = journal.parent / f".cash-journal-{uuid.uuid4().hex}"
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        content = (
            json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n"
        ).encode("utf-8")
        os.write(descriptor, content)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.replace(temporary, journal)
        directory = os.open(journal.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def _relative_snapshot(
    workspace: Workspace,
    relative: str,
) -> dict[str, object]:
    try:
        with workspace._open_parent(relative) as (parent, name):
            return _snapshot_at(parent, name, relative)
    except FileNotFoundError:
        return {"exists": False}


def _snapshot_at(
    parent: int,
    name: str,
    relative: str,
) -> dict[str, object]:
    try:
        named = os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return {"exists": False}
    if not stat.S_ISREG(named.st_mode) or named.st_nlink != 1:
        raise CashError(
            "unsafe_path",
            "Mutation target must be a single-link regular file.",
            path=relative,
        )
    descriptor = os.open(
        name,
        os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0),
        dir_fd=parent,
    )
    try:
        opened = os.fstat(descriptor)
        if (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
            raise CashError(
                "snapshot_drift",
                "Mutation target identity changed.",
                path=relative,
            )
        chunks: list[bytes] = []
        while chunk := os.read(descriptor, 131072):
            chunks.append(chunk)
    finally:
        os.close(descriptor)
    return {
        "exists": True,
        "device": opened.st_dev,
        "inode": opened.st_ino,
        "mode": stat.S_IMODE(opened.st_mode),
        "content": base64.b64encode(b"".join(chunks)).decode("ascii"),
    }


def _relative_identity(workspace: Workspace, relative: str) -> list[int]:
    with workspace._open_parent(relative) as (parent, name):
        metadata = os.stat(name, dir_fd=parent, follow_symlinks=False)
    if stat.S_ISLNK(metadata.st_mode):
        raise CashError("unsafe_path", "Symlink managed paths are not allowed.", path=relative)
    return [metadata.st_dev, metadata.st_ino]


def _directory_identity(workspace: Workspace, relative: str) -> list[int]:
    with workspace._open_directory(relative) as descriptor:
        metadata = os.fstat(descriptor)
    return [metadata.st_dev, metadata.st_ino]


def _directory_matches(
    workspace: Workspace,
    relative: str,
    expected: list[int],
) -> bool:
    try:
        with workspace._open_directory(relative) as descriptor:
            metadata = os.fstat(descriptor)
    except (CashError, OSError):
        return False
    return [metadata.st_dev, metadata.st_ino] == expected


def _published_write_snapshot(operation: dict[str, object]) -> dict[str, object]:
    content = base64.b64decode(str(operation["content"]))
    identity = operation.get("published_identity")
    if not isinstance(identity, list) or len(identity) != 2:
        raise CashError("recovery_failed", "Published write identity is missing.", 1)
    return {
        "exists": True,
        "device": identity[0],
        "inode": identity[1],
        "mode": int(operation["mode"]),
        "content": base64.b64encode(content).decode("ascii"),
    }


def _operation_matches_published(
    workspace: Workspace,
    operation: dict[str, object],
) -> bool:
    if operation["kind"] == "write":
        return (
            _relative_snapshot(workspace, str(operation["path"]))
            == _published_write_snapshot(operation)
        )
    if operation["kind"] == "delete":
        return workspace.path_kind(str(operation["path"])) == "missing"
    source = str(operation["source"])
    destination = str(operation["destination"])
    try:
        source_identity = _relative_identity(workspace, source)
    except (CashError, OSError):
        source_identity = None
    try:
        destination_identity = _relative_identity(workspace, destination)
    except (CashError, OSError):
        destination_identity = None
    return source_identity is None and destination_identity == operation["source_identity"]


def _stage_write(
    workspace: Workspace,
    operation: dict[str, object],
) -> list[int]:
    relative = str(operation["path"])
    with workspace._open_parent(relative) as (parent, _):
        parent_metadata = os.fstat(parent)
        if [parent_metadata.st_dev, parent_metadata.st_ino] != operation["parent"]:
            raise CashError(
                "snapshot_drift",
                "Staged publication parent changed.",
                path=relative,
            )
        temporary = str(operation["temporary"])
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            int(operation["mode"]),
            dir_fd=parent,
        )
        try:
            content = base64.b64decode(str(operation["content"]))
            os.write(descriptor, content)
            os.fchmod(descriptor, int(operation["mode"]))
            os.fsync(descriptor)
            metadata = os.fstat(descriptor)
        finally:
            os.close(descriptor)
    return [metadata.st_dev, metadata.st_ino]


def _cleanup_temporaries(
    workspace: Workspace,
    operations: list[dict[str, object]],
) -> None:
    for operation in operations:
        if operation["kind"] != "write":
            continue
        relative = str(operation["path"])
        with workspace._open_parent(relative) as (parent, _):
            parent_metadata = os.fstat(parent)
            if [parent_metadata.st_dev, parent_metadata.st_ino] != operation["parent"]:
                raise CashError(
                    "snapshot_drift",
                    "Transaction temporary parent changed.",
                    path=relative,
                )
            temporary = str(operation["temporary"])
            try:
                metadata = os.stat(
                    temporary,
                    dir_fd=parent,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                continue
            identity = operation.get("published_identity")
            if (
                stat.S_ISLNK(metadata.st_mode)
                or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_nlink != 1
                or (identity is not None and not isinstance(identity, list))
                or (
                    isinstance(identity, list)
                    and [metadata.st_dev, metadata.st_ino] != identity
                )
            ):
                raise CashError(
                    "snapshot_drift",
                    "Transaction temporary identity changed.",
                    path=relative,
                )
            os.unlink(temporary, dir_fd=parent)


def _restore_at(
    parent: int,
    name: str,
    content: bytes,
    mode: int,
) -> None:
    temporary = f".cash-rollback-{uuid.uuid4().hex}"
    descriptor = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL,
        mode,
        dir_fd=parent,
    )
    try:
        os.write(descriptor, content)
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    try:
        os.rename(temporary, name, src_dir_fd=parent, dst_dir_fd=parent)
    finally:
        try:
            os.unlink(temporary, dir_fd=parent)
        except FileNotFoundError:
            pass


def _named_identity(parent: int, name: str) -> list[int] | None:
    try:
        metadata = os.stat(name, dir_fd=parent, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(metadata.st_mode):
        raise CashError("unsafe_path", "Symlink managed paths are not allowed.", path=name)
    return [metadata.st_dev, metadata.st_ino]


def _validate_operation_snapshot(
    workspace: Workspace,
    operation: dict[str, object],
) -> None:
    kind = operation["kind"]
    if kind in {"write", "delete"}:
        relative = str(operation["path"])
        if (
            not _directory_matches(
                workspace,
                Path(relative).parent.as_posix(),
                operation["parent"],
            )
            or _relative_snapshot(workspace, relative) != operation["before"]
        ):
            raise CashError(
                "snapshot_drift",
                "Mutation target changed after preflight.",
                path=relative,
            )
        return
    source = str(operation["source"])
    destination = str(operation["destination"])
    try:
        source_identity = _relative_identity(workspace, source)
    except (CashError, OSError):
        source_identity = None
    if (
        not _directory_matches(
            workspace,
            Path(source).parent.as_posix(),
            operation["source_parent"],
        )
        or not _directory_matches(
            workspace,
            Path(destination).parent.as_posix(),
            operation["destination_parent"],
        )
        or source_identity != operation["source_identity"]
        or workspace.path_kind(destination) != "missing"
    ):
        raise CashError("snapshot_drift", "Move target changed after preflight.")


def _publish(workspace: Workspace, operation: dict[str, object]) -> None:
    kind = operation["kind"]
    if kind == "write":
        relative = str(operation["path"])
        before = operation["before"]
        with workspace._open_parent(relative) as (parent, name):
            parent_metadata = os.fstat(parent)
            if [parent_metadata.st_dev, parent_metadata.st_ino] != operation["parent"]:
                raise CashError("snapshot_drift", "Parent identity changed.", path=relative)
            if _snapshot_at(parent, name, relative) != before:
                raise CashError(
                    "snapshot_drift",
                    "Destination changed after preflight.",
                    path=relative,
                )
            temporary = str(operation["temporary"])
            staged = os.stat(
                temporary,
                dir_fd=parent,
                follow_symlinks=False,
            )
            if [staged.st_dev, staged.st_ino] != operation["published_identity"]:
                raise CashError(
                    "snapshot_drift",
                    "Staged publication identity changed.",
                    path=relative,
                )
            try:
                os.replace(
                    temporary,
                    name,
                    src_dir_fd=parent,
                    dst_dir_fd=parent,
                )
            finally:
                try:
                    os.unlink(temporary, dir_fd=parent)
                except FileNotFoundError:
                    pass
        return
    if kind == "delete":
        relative = str(operation["path"])
        before = operation["before"]
        with workspace._open_parent(relative) as (parent, name):
            parent_metadata = os.fstat(parent)
            if (
                not before["exists"]
                or [parent_metadata.st_dev, parent_metadata.st_ino]
                != operation["parent"]
                or _snapshot_at(parent, name, relative) != before
            ):
                raise CashError("snapshot_drift", "Delete identity changed.", path=relative)
            os.unlink(name, dir_fd=parent)
        return
    source = str(operation["source"])
    destination = str(operation["destination"])
    source_parent = Path(source).parent.as_posix()
    destination_parent = Path(destination).parent.as_posix()
    with workspace._open_directory(source_parent) as source_fd:
        with workspace._open_directory(destination_parent) as destination_fd:
            source_parent_metadata = os.fstat(source_fd)
            destination_parent_metadata = os.fstat(destination_fd)
            source_metadata = os.stat(
                Path(source).name,
                dir_fd=source_fd,
                follow_symlinks=False,
            )
            if (
                [
                    source_parent_metadata.st_dev,
                    source_parent_metadata.st_ino,
                ]
                != operation["source_parent"]
                or [
                    destination_parent_metadata.st_dev,
                    destination_parent_metadata.st_ino,
                ]
                != operation["destination_parent"]
                or [source_metadata.st_dev, source_metadata.st_ino]
                != operation["source_identity"]
            ):
                raise CashError("snapshot_drift", "Move identity changed.")
            try:
                os.stat(
                    Path(destination).name,
                    dir_fd=destination_fd,
                    follow_symlinks=False,
                )
            except FileNotFoundError:
                pass
            else:
                raise CashError("snapshot_drift", "Move destination appeared.")
            os.rename(
                Path(source).name,
                Path(destination).name,
                src_dir_fd=source_fd,
                dst_dir_fd=destination_fd,
            )


def _rollback(workspace: Workspace, operations: list[dict[str, object]]) -> None:
    for operation in reversed(operations):
        if operation["kind"] == "move":
            source = str(operation["source"])
            destination = str(operation["destination"])
            source_parent = Path(source).parent.as_posix()
            destination_parent = Path(destination).parent.as_posix()
            with workspace._open_directory(source_parent) as source_fd:
                with workspace._open_directory(destination_parent) as destination_fd:
                    source_parent_metadata = os.fstat(source_fd)
                    destination_parent_metadata = os.fstat(destination_fd)
                    if (
                        [
                            source_parent_metadata.st_dev,
                            source_parent_metadata.st_ino,
                        ]
                        != operation["source_parent"]
                        or [
                            destination_parent_metadata.st_dev,
                            destination_parent_metadata.st_ino,
                        ]
                        != operation["destination_parent"]
                    ):
                        raise CashError("snapshot_drift", "Rollback parent identity changed.")
                    source_identity = _named_identity(source_fd, Path(source).name)
                    destination_identity = _named_identity(
                        destination_fd,
                        Path(destination).name,
                    )
                    if (
                        source_identity == operation["source_identity"]
                        and destination_identity is None
                    ):
                        continue
                    if (
                        source_identity is None
                        and destination_identity == operation["source_identity"]
                    ):
                        os.rename(
                            Path(destination).name,
                            Path(source).name,
                            src_dir_fd=destination_fd,
                            dst_dir_fd=source_fd,
                        )
                        continue
                    raise CashError("snapshot_drift", "Rollback move state is ambiguous.")
        relative = str(operation["path"])
        with workspace._open_parent(relative) as (parent, name):
            parent_metadata = os.fstat(parent)
            if [parent_metadata.st_dev, parent_metadata.st_ino] != operation["parent"]:
                raise CashError(
                    "snapshot_drift",
                    "Rollback parent identity changed.",
                    path=relative,
                )
            current = _snapshot_at(parent, name, relative)
            before = operation["before"]
            if current == before:
                continue
            if operation["kind"] == "delete":
                if current["exists"]:
                    raise CashError(
                        "snapshot_drift",
                        "Rollback delete target changed.",
                        path=relative,
                    )
                _restore_at(
                    parent,
                    name,
                    base64.b64decode(str(before["content"])),
                    int(before["mode"]),
                )
                continue
            if current != _published_write_snapshot(operation):
                raise CashError(
                    "snapshot_drift",
                    "Rollback write target changed.",
                    path=relative,
                )
            if not before["exists"]:
                os.unlink(name, dir_fd=parent)
                continue
            _restore_at(
                parent,
                name,
                base64.b64decode(str(before["content"])),
                int(before["mode"]),
            )


def _recover_journal(workspace: Workspace, journal: Path) -> None:
    try:
        relative = workspace.relative(journal)
        document = json.loads(workspace.read_text(relative))
        if set(document) != {"version", "published", "operations"} or document["version"] != 1:
            raise ValueError("invalid journal schema")
        operations = document["operations"]
        published = int(document.get("published", 0))
        _rollback(workspace, operations[:published])
        _cleanup_temporaries(workspace, operations)
        shutil.rmtree(journal.parent)
        _remove_empty_parents(workspace)
    except Exception as error:
        raise CashError(
            "recovery_failed",
            f"Unable to recover transaction: {error}",
            1,
            workspace.relative(journal),
        ) from error


def _remove_empty_parents(workspace: Workspace) -> None:
    for directory in (workspace.transactions, workspace.state):
        try:
            directory.rmdir()
        except OSError:
            pass
