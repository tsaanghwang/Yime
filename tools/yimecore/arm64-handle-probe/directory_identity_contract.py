"""Compare a probe-created directory with a separate Win32 handle observation.

The comparison is pure Python so mismatch cases can run without the native probe.
Only reopen_directory_identity performs a Windows file open, in the disposable VM.
"""

import ctypes
import ntpath
import re
from pathlib import Path


FILE_CREATED = 2
FILE_ATTRIBUTE_DIRECTORY = 0x10
FILE_ATTRIBUTE_REPARSE_POINT = 0x400
FILE_READ_ATTRIBUTES = 0x80
FILE_TRAVERSE = 0x20
FILE_SHARE_READ = 1
OPEN_EXISTING = 3
FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000
FILE_ATTRIBUTE_TAG_INFO_CLASS = 9
FILE_ID_INFO_CLASS = 18


def _require(condition, reason):
    if not condition:
        raise ValueError(reason)


def _local_path(value):
    _require(isinstance(value, str) and value, "missing final path")
    if value.startswith("\\\\?\\"):
        value = value[4:]
    _require(re.fullmatch(r"[A-Za-z]:\\.+", value) is not None, "final path is not local DOS path")
    _require(all(part not in ("", ".", "..") and not part.endswith((" ", "."))
                 for part in value[3:].split("\\")), "final path contains abnormal component")
    return ntpath.normcase(value)


def _identity_fields(value, label):
    _require(isinstance(value, dict), f"{label} identity missing")
    volume, file_id = value.get("volume"), value.get("file_id")
    _require(isinstance(volume, str) and re.fullmatch(r"[0-9a-fA-F]{16}", volume),
             f"{label} volume invalid")
    _require(isinstance(file_id, str) and re.fullmatch(r"[0-9a-fA-F]{32}", file_id),
             f"{label} 128-bit file ID invalid")
    _require(int(volume, 16) != 0 and int(file_id, 16) != 0, f"{label} zero identity")
    attributes, tag = value.get("attributes"), value.get("reparse_tag")
    _require(type(attributes) is int and attributes >= 0, f"{label} attributes invalid")
    _require(type(tag) is int and tag >= 0, f"{label} reparse tag invalid")
    _require(attributes & FILE_ATTRIBUTE_DIRECTORY, f"{label} is not a directory")
    _require(not attributes & FILE_ATTRIBUTE_REPARSE_POINT and tag == 0,
             f"{label} is a reparse point")
    return volume.lower(), file_id.lower(), _local_path(value.get("final_path"))


def validate_directory_contract(recorded, observed, expected_path, creation_event):
    """Fail closed on malformed evidence or an object/path mismatch."""
    _require(isinstance(creation_event, dict) and creation_event.get("event") == "directory-create",
             "directory-create event missing")
    _require(type(creation_event.get("create_information")) is int and
             creation_event["create_information"] == FILE_CREATED, "FILE_CREATED not observed")
    _require(isinstance(recorded, dict) and recorded.get("event") == "output-directory",
             "output-directory event missing")
    _require(recorded.get("sha256") == "", "directory hash must be empty")
    saved = _identity_fields(recorded, "created handle")
    reopened = _identity_fields(observed, "independent handle")
    _require(saved[:2] == reopened[:2], "volume or full 128-bit file ID mismatch")
    _require(saved[2] == reopened[2], "final paths differ between handles")
    _require(saved[2] == _local_path(str(expected_path)), "final path differs from expected directory")


def reopen_directory_identity(path: Path):
    """Read identity, attributes and final path from one independent directory handle."""
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateFileW.argtypes = (ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                                     ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p)
    kernel32.CreateFileW.restype = ctypes.c_void_p
    kernel32.GetFileInformationByHandleEx.argtypes = (ctypes.c_void_p, ctypes.c_int,
                                                       ctypes.c_void_p, ctypes.c_uint32)
    kernel32.GetFileInformationByHandleEx.restype = ctypes.c_int
    kernel32.GetFinalPathNameByHandleW.argtypes = (ctypes.c_void_p, ctypes.c_wchar_p,
                                                   ctypes.c_uint32, ctypes.c_uint32)
    kernel32.GetFinalPathNameByHandleW.restype = ctypes.c_uint32
    kernel32.CloseHandle.argtypes = (ctypes.c_void_p,)

    class FileIdInfo(ctypes.Structure):
        _fields_ = (("volume", ctypes.c_uint64), ("file_id", ctypes.c_ubyte * 16))

    class AttributeTagInfo(ctypes.Structure):
        _fields_ = (("attributes", ctypes.c_uint32), ("reparse_tag", ctypes.c_uint32))

    handle = kernel32.CreateFileW(str(path), FILE_READ_ATTRIBUTES | FILE_TRAVERSE,
                                  FILE_SHARE_READ, None, OPEN_EXISTING,
                                  FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, None)
    _require(handle not in (None, ctypes.c_void_p(-1).value),
             f"independent CreateFileW failed: Win32={ctypes.get_last_error()}")
    try:
        identity, tag = FileIdInfo(), AttributeTagInfo()
        for kind, target in ((FILE_ID_INFO_CLASS, identity), (FILE_ATTRIBUTE_TAG_INFO_CLASS, tag)):
            if not kernel32.GetFileInformationByHandleEx(handle, kind, ctypes.byref(target), ctypes.sizeof(target)):
                raise ValueError(f"independent GetFileInformationByHandleEx failed: Win32={ctypes.get_last_error()}")
        length = kernel32.GetFinalPathNameByHandleW(handle, None, 0, 0)
        _require(length > 0, f"independent GetFinalPathNameByHandleW length failed: Win32={ctypes.get_last_error()}")
        buffer = ctypes.create_unicode_buffer(length + 1)
        used = kernel32.GetFinalPathNameByHandleW(handle, buffer, len(buffer), 0)
        _require(0 < used < len(buffer), f"independent GetFinalPathNameByHandleW failed: Win32={ctypes.get_last_error()}")
        return {"volume": identity.volume.to_bytes(8, "little").hex(),
                "file_id": bytes(identity.file_id).hex(), "final_path": buffer.value,
                "attributes": tag.attributes, "reparse_tag": tag.reparse_tag}
    finally:
        kernel32.CloseHandle(handle)
