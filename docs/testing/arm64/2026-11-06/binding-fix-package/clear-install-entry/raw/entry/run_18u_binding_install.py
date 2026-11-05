"""Local handoff for the frozen .5 package; never stops or unloads a host.

--check verifies the complete delivery and runs native Check only. It deliberately
does not sample installed state or call Restart Manager. Normal invocation checks
the three pinned entry files, native Check, then queries the installed TIP DLL.
Only the standard maintenance helper can install. Its safeguards remain in force.
"""
from __future__ import annotations

import argparse
import ctypes
from ctypes import wintypes as w
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import uuid

ROOT = Path("C:/dev/Yime-deliveries/18u-binding-636cef68-20261106")
PACKAGE = ROOT / "package"
SOURCE = "636cef681ee995a21a9c45fd750f8cb4b0acb4a1"
VERSION = "0.2.0-18u-arm64.5"
ARCHIVE = "yime-yimecore-18u-windows-arm64-636cef681ee9.zip"
IDENTITY = "yime-yimecore-18u-windows-arm64-636cef681ee9.identity.json"
ARCHIVE_SHA = "e482200ea81a8241a4780feaa07b01a53bb8b177ec62b5c2496e158a7b00b36c"
IDENTITY_SHA = "d94ac9817f5e4c6b2090ec64bad6ff79a124efe9d71c086876c348207287ceb1"
PINS = {
    "YimeMaintenance.exe": "36d655beca9f5bcca485ee9d143ce9a7c2d8c9fb79218a4506f516000832b2b9",
    "maintenance-plan.json": "60f1ea319de814858086dd1383a521389bb1cc7aa57870005f0f37ccd6b55180",
    "payload/installed-18u-product.json": "d536a76448ab755f5995a01370f541e7bbb76fca7b9b3bfd23186e0eb9dc61be",
}
INSTALLED_DLL = Path("C:/Program Files/YimeCore 18u Touch/arm64/YimeTextService18u.dll")
ATTEMPT = ROOT / "18u-standard-install-attempt.json"


def now():
    return datetime.now(timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def plain_path(path):
    for member in (path, *path.parents):
        require(not member.is_symlink() and not member.is_junction(),
                "路径存在链接或跳转，已停止：" + str(member))
    return path


def digest(path):
    with plain_path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_pins():
    require(Path(__file__).absolute().parent == ROOT, "请从固定交付目录启动此入口。")
    for name, expected in PINS.items():
        require(digest(PACKAGE / name) == expected, "固定包文件不匹配：" + name)
    plan = json.loads((PACKAGE / "maintenance-plan.json").read_text(encoding="utf-8"))
    require(plan["sourceCommit"] == SOURCE and plan["product"] == "yimecore-18u"
            and plan["target"] == "windows-arm64", "固定维护计划不匹配。")


def verify_archive(emit):
    require(digest(ROOT / ARCHIVE) == ARCHIVE_SHA, "完整 ZIP 哈希不匹配。")
    require(digest(ROOT / IDENTITY) == IDENTITY_SHA, "完整包身份文件不匹配。")
    identity = json.loads((ROOT / IDENTITY).read_text(encoding="utf-8"))
    require(identity["source"]["commit"] == SOURCE and identity["source"]["clean"] is True,
            "完整包源码身份不匹配。")
    require(identity["fileCount"] == len(identity["files"]) == 1156, "完整包文件数不匹配。")
    for index, (name, row) in enumerate(identity["files"].items(), 1):
        relative = PurePosixPath(name)
        require(not relative.is_absolute() and ".." not in relative.parts
                and ":" not in name and "\\" not in name, "完整包路径不合法。")
        path = plain_path(PACKAGE / name)
        require(path.stat().st_size == row["bytes"] and digest(path) == row["sha256"],
                "完整包文件不匹配：" + name)
        if index % 250 == 0:
            emit(f"完整包校验：{index}/1156")
    emit("完整 ZIP、身份文件和 1156 个展开文件全部匹配。")


def require_ordinary_token():
    kernel = ctypes.WinDLL("kernel32.dll", use_last_error=True, winmode=0x00000800)
    security = ctypes.WinDLL("advapi32.dll", use_last_error=True, winmode=0x00000800)
    kernel.GetCurrentProcess.restype = w.HANDLE
    kernel.CloseHandle.argtypes = [w.HANDLE]
    security.OpenProcessToken.argtypes = [w.HANDLE, w.DWORD, ctypes.POINTER(w.HANDLE)]
    security.OpenProcessToken.restype = w.BOOL
    security.GetTokenInformation.argtypes = [w.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                           w.DWORD, ctypes.POINTER(w.DWORD)]
    security.GetTokenInformation.restype = w.BOOL
    token = w.HANDLE()
    require(security.OpenProcessToken(kernel.GetCurrentProcess(), 0x0008, ctypes.byref(token)),
            "无法确认入口的普通用户身份；安装未启动。")
    try:
        elevation, returned = w.DWORD(), w.DWORD()
        require(security.GetTokenInformation(token, 20, ctypes.byref(elevation),
                                            ctypes.sizeof(elevation), ctypes.byref(returned)),
                "无法读取入口提升状态；安装未启动。")
        require(elevation.value == 0, "请普通双击本入口，不要使用“以管理员身份运行”；标准安装器会显示正常 Windows 提示。")
    finally:
        kernel.CloseHandle(token)


class UniqueProcess(ctypes.Structure):
    _fields_ = [("pid", w.DWORD), ("started", w.FILETIME)]


class ProcessInfo(ctypes.Structure):
    _fields_ = [("process", UniqueProcess), ("application", w.WCHAR * 256),
                ("service", w.WCHAR * 64), ("kind", ctypes.c_int),
                ("status", w.ULONG), ("session", w.DWORD), ("restartable", w.BOOL)]


def query_dll_users():
    """Read-only Restart Manager query, matching Product.psm1's API contract."""
    require(plain_path(INSTALLED_DLL).is_file(), "未找到预期的已安装 18u DLL；请保留日志核对。")
    require(ctypes.sizeof(UniqueProcess) == 12 and ctypes.sizeof(ProcessInfo) == 668,
            "Restart Manager 结构大小不匹配。")
    rm = ctypes.WinDLL("rstrtmgr.dll", winmode=0x00000800)
    rm.RmStartSession.argtypes = [ctypes.POINTER(w.DWORD), w.DWORD, w.LPWSTR]
    rm.RmRegisterResources.argtypes = [w.DWORD, w.UINT, ctypes.POINTER(w.LPCWSTR),
                                      w.UINT, ctypes.c_void_p, w.UINT, ctypes.c_void_p]
    rm.RmGetList.argtypes = [w.DWORD, ctypes.POINTER(w.UINT), ctypes.POINTER(w.UINT),
                            ctypes.POINTER(ProcessInfo), ctypes.POINTER(w.DWORD)]
    rm.RmEndSession.argtypes = [w.DWORD]
    for name in ("RmStartSession", "RmRegisterResources", "RmGetList", "RmEndSession"):
        getattr(rm, name).restype = w.DWORD
    session = w.DWORD()
    code = rm.RmStartSession(ctypes.byref(session), 0, ctypes.create_unicode_buffer(33))
    require(code == 0, f"Restart Manager 启动查询失败：{code}")
    try:
        names = (w.LPCWSTR * 1)(str(INSTALLED_DLL))
        code = rm.RmRegisterResources(session, 1, names, 0, None, 0, None)
        require(code == 0, f"Restart Manager 登记查询文件失败：{code}")
        needed, count, reasons = w.UINT(), w.UINT(), w.DWORD()
        rows = None
        for _ in range(3):
            code = rm.RmGetList(session, ctypes.byref(needed), ctypes.byref(count),
                                rows, ctypes.byref(reasons))
            if code == 0:
                return [{"pid": row.process.pid,
                         "creationTicks": (row.process.started.dwHighDateTime << 32)
                                           | row.process.started.dwLowDateTime,
                         "application": row.application, "service": row.service,
                         "session": row.session} for row in (rows or [])[:count.value]]
            require(code == 234, f"Restart Manager 读取占用者失败：{code}")
            rows = (ProcessInfo * needed.value)()
            count.value = needed.value
        raise RuntimeError("占用列表持续变化，未启动安装；请保留日志核对。")
    finally:
        rm.RmEndSession(session)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只校验完整包；不采样已安装状态、不安装")
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    prefix = ROOT / ("18u-check-" if args.check else "18u-start-")
    log_path = Path(str(prefix) + run_id + ".log")
    report_path = log_path.with_suffix(".json")
    # The first operation records that this runner actually started. No old log is replaced.
    with plain_path(log_path).open("x", encoding="utf-8", buffering=1) as log:
        def emit(message):
            line = f"[{now()}] {message}"
            print(line, flush=True)
            log.write(line + "\n")
            log.flush()

        record = {"schema": "18u-binding-local-entry-v1", "startedUTC": now(),
                  "version": VERSION, "sourceCommit": SOURCE, "checkOnly": args.check,
                  "log": str(log_path), "restartManagerQueried": False,
                  "installLaunched": False, "status": "started"}
        result = 1
        try:
            emit("18u 修复版安装入口已经启动。" if not args.check else "只读包校验已经启动；本次不会安装或采样宿主。")
            emit("日志位置：" + str(log_path))
            if not args.check and ATTEMPT.exists():
                raise RuntimeError("已有一次标准安装尝试记录，不会再次安装。请保留日志并回到 Codex 核对。")
            if not args.check:
                require_ordinary_token()
                record["ordinaryUserEntry"] = True
            emit("第 1 步：核对固定 .5 包入口。")
            verify_pins()
            if args.check:
                emit("开发校验：正在核对完整档案，期间不会解压或修改包。")
                verify_archive(emit)
            emit("第 2 步：运行标准包检查 Check；此步不会安装或停止后台。")
            check_log = log_path.with_name(log_path.stem + "-native-check.log")
            with check_log.open("xb") as output:
                check = subprocess.run([str(PACKAGE / "YimeMaintenance.exe"), "-action", "Check"],
                                       cwd=PACKAGE, stdout=output, stderr=subprocess.STDOUT)
            record["nativeCheckExitCode"] = check.returncode
            record["nativeCheckLog"] = str(check_log)
            require(check.returncode == 0, "标准 Check 未通过；安装未启动。详情：" + str(check_log))
            emit("标准包检查通过。")
            if args.check:
                record["status"] = "check-passed-no-installed-sampling-no-install"
                result = 0
            else:
                emit("第 3 步：只读检查旧 18u 输入组件的占用；不会关闭任何应用。")
                record["restartManagerQueried"] = True
                users = query_dll_users()
                record["dll"] = str(INSTALLED_DLL)
                record["dllUsers"] = users
                if users:
                    for user in users:
                        emit(f"仍在占用：{user['application']}（PID {user['pid']}）")
                    emit("安装未启动，18u 后台未停止。请先保存文档并正常退出相应应用。")
                    emit("若资源管理器仍占用，可正常重启后先运行本入口；不要结束 Explorer/System 或强制替换文件。")
                    record["status"] = "blocked-by-dll-users-install-not-started"
                    result = 3
                else:
                    emit("未发现该 DLL 的占用者；标准安装器仍会检查全部文件，检查失败会停止。")
                    # Atomic marker: only one invocation can launch Install, even after failure.
                    with plain_path(ATTEMPT).open("x", encoding="utf-8") as marker:
                        json.dump({"createdUTC": now(), "sourceCommit": SOURCE,
                                   "log": str(log_path), "report": str(report_path),
                                   "note": "standard Install launch reserved; preserve after success or failure"},
                                  marker, ensure_ascii=False, indent=2)
                        marker.flush()
                        os.fsync(marker.fileno())
                    emit("第 4 步：现在启动标准安装；请按 Windows 正常提示继续。不会自动重试。")
                    install_log = log_path.with_name(log_path.stem + "-native-install.log")
                    record["nativeInstallLog"] = str(install_log)
                    with install_log.open("xb") as output:
                        with subprocess.Popen([str(PACKAGE / "YimeMaintenance.exe"), "-action", "Install"],
                                              cwd=PACKAGE, stdout=output, stderr=subprocess.STDOUT) as installed:
                            record["installLaunched"] = True
                            result = installed.wait()
                    record["nativeInstallExitCode"] = result
                    record["status"] = "standard-install-returned-success-awaiting-verification" if result == 0 else "standard-install-failed-no-retry"
                    emit(f"标准安装器返回：{result}。详细输出：{install_log}")
                    emit("请回到 Codex 核对版本、载荷和真实记事本输入；此返回值不代表输入验收通过。")
        except Exception as exc:
            record["status"] = "error-no-automatic-retry"
            record["error"] = str(exc)
            emit("已停止：" + str(exc))
            result = 1
        finally:
            record["finishedUTC"] = now()
            record["exitCode"] = result
            with report_path.open("x", encoding="utf-8") as report:
                json.dump(record, report, ensure_ascii=False, indent=2)
                report.write("\n")
            emit("本次记录已保存：" + str(report_path))
        return result


if __name__ == "__main__":
    raise SystemExit(main())
