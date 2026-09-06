# DP1-J-a fixture-only continuous directory-membership monitor. Definitions only.
#
# This helper deliberately cannot target the installed NSIS tree.  It proves a
# fail-closed notification primitive only inside a fresh repository-local DP1-J
# fixture.  Detection is not physical prevention and is not a full toolchain
# closure claim.  The caller must wait for its guarded process to exit before
# completion; observing the sentinel ADD on this handle is the interval's
# linearization endpoint, and later notification batches are outside it.
$script:RimePimeNsisMembershipMonitorSchemaV1 = 'yime-rime-pime-nsis-membership-monitor-result-v1'
$script:RimePimeNsisMembershipMonitorTypeNameV1 = 'YimePime.NsisMembership.MonitorHostV1'
$script:RimePimeNsisMembershipMonitorImplementationV1 = 'yime-rime-pime-nsis-membership-monitor-native-v1'

function Get-RimePimeNsisMembershipSha256TextV1 {
    param([Parameter(Mandatory)][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Assert-RimePimeNsisMembershipFixtureRootV1 {
    param([Parameter(Mandatory)][string]$Root)
    $repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd([char]92)
    $parent = [IO.Path]::GetFullPath((Join-Path $repo '.tmp\dual-product')).TrimEnd([char]92)
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([char]92)
    if (-not (Test-Path -LiteralPath $full -PathType Container) -or
        -not $full.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'DP1-J membership monitor rejected a non-fixture root.'
    }
    $relative = $full.Substring($parent.Length + 1)
    $segments = @($relative.Split([char]92, [StringSplitOptions]::RemoveEmptyEntries))
    if ($segments.Count -lt 2 -or $segments[0] -cnotmatch '^dp1-j-membership-test-[A-Za-z0-9-]+$') {
        throw 'DP1-J membership monitor requires a descendant of a fresh immediate fixture root.'
    }
    $cursor = $full
    while ($cursor.Length -ge $parent.Length -and
        ($cursor.Equals($parent, [StringComparison]::OrdinalIgnoreCase) -or
         $cursor.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase))) {
        $item = Get-Item -LiteralPath $cursor -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'DP1-J membership monitor rejected a reparse fixture path.'
        }
        if ($cursor.Equals($parent, [StringComparison]::OrdinalIgnoreCase)) { break }
        $next = Split-Path -Parent $cursor
        if (-not $next -or $next -eq $cursor) { break }
        $cursor = $next
    }
    return $full
}

function Initialize-RimePimeNsisMembershipMonitorTypeV1 {
    $existing = $script:RimePimeNsisMembershipMonitorTypeNameV1 -as [type]
    if ($null -ne $existing) {
        $property = $existing.GetProperty('ImplementationId',
            [Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::Static)
        if ($null -eq $property -or
            [string]$property.GetValue($null, $null) -cne $script:RimePimeNsisMembershipMonitorImplementationV1) {
            throw 'DP1-J membership monitor found an untrusted preloaded native type.'
        }
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace YimePime.NsisMembership {
    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeOverlappedV1 {
        internal UIntPtr Internal;
        internal UIntPtr InternalHigh;
        internal UInt32 Offset;
        internal UInt32 OffsetHigh;
        internal IntPtr EventHandle;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeFileTimeV1 {
        internal UInt32 Low;
        internal UInt32 High;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeFileInformationV1 {
        internal UInt32 FileAttributes;
        internal NativeFileTimeV1 CreationTime;
        internal NativeFileTimeV1 LastAccessTime;
        internal NativeFileTimeV1 LastWriteTime;
        internal UInt32 VolumeSerialNumber;
        internal UInt32 FileSizeHigh;
        internal UInt32 FileSizeLow;
        internal UInt32 NumberOfLinks;
        internal UInt32 FileIndexHigh;
        internal UInt32 FileIndexLow;
    }

    public sealed class MonitorResultV1 {
        public bool ArmedBeforeInterval { get; internal set; }
        public bool BarrierObserved { get; internal set; }
        public int NotificationBatchCount { get; internal set; }
        public int NotificationRecordCount { get; internal set; }
        public int UnexpectedEventCount { get; internal set; }
        public string BarrierNameSha256 { get; internal set; }
    }

    public sealed class MonitorHostV1 : IDisposable {
        public static string ImplementationId { get { return "yime-rime-pime-nsis-membership-monitor-native-v1"; } }

        private const uint FILE_LIST_DIRECTORY = 0x00000001;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_ATTRIBUTE_DIRECTORY = 0x00000010;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        private const uint FILE_NOTIFY_CHANGE_FILE_NAME = 0x00000001;
        private const uint FILE_NOTIFY_CHANGE_DIR_NAME = 0x00000002;
        private const uint ERROR_IO_PENDING = 997;
        private const uint ERROR_OPERATION_ABORTED = 995;
        private const uint WAIT_OBJECT_0 = 0;
        private const uint WAIT_TIMEOUT = 258;
        private const uint WAIT_FAILED = 0xffffffff;
        private const uint FILE_ACTION_ADDED = 1;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string path, uint access, uint share,
            IntPtr security, uint creation, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandle(SafeFileHandle file,
            out NativeFileInformationV1 information);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReadDirectoryChangesW(SafeFileHandle directory, IntPtr buffer,
            uint bufferLength, [MarshalAs(UnmanagedType.Bool)] bool watchSubtree, uint filter,
            IntPtr bytesReturned, IntPtr overlapped, IntPtr completionRoutine);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetOverlappedResult(SafeFileHandle file, IntPtr overlapped,
            out uint transferred, [MarshalAs(UnmanagedType.Bool)] bool wait);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CancelIoEx(SafeFileHandle file, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateEventW(IntPtr attributes,
            [MarshalAs(UnmanagedType.Bool)] bool manualReset,
            [MarshalAs(UnmanagedType.Bool)] bool initialState, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ResetEvent(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetShortPathNameW(string longPath, StringBuilder shortPath, uint capacity);

        private readonly string root;
        private readonly int bufferBytes;
        private readonly string barrierName;
        private readonly string barrierPath;
        private readonly string barrierDigest;
        private string barrierShortName;
        private SafeFileHandle directory;
        private IntPtr eventHandle;
        private IntPtr buffer;
        private IntPtr overlapped;
        private bool pending;
        private bool armed;
        private bool completed;
        private bool disposed;
        private bool barrierCreated;
        private int batchCount;
        private int recordCount;
        private int unexpectedCount;
        private uint rootVolumeSerialNumber;
        private uint rootFileIndexHigh;
        private uint rootFileIndexLow;

        public bool IsArmed { get { return armed && !completed && !disposed; } }
        public bool IsCompleted { get { return completed; } }
        public bool IsDisposed { get { return disposed; } }

        public MonitorHostV1(string rootPath, int requestedBufferBytes) {
            if (String.IsNullOrEmpty(rootPath)) throw new ArgumentException("Fixture root is required.");
            if (requestedBufferBytes < 128 || requestedBufferBytes > 65536)
                throw new ArgumentOutOfRangeException("requestedBufferBytes");
            root = Path.GetFullPath(rootPath);
            bufferBytes = requestedBufferBytes;
            barrierName = NewBarrierName();
            barrierPath = Path.Combine(root, barrierName);
            barrierDigest = Sha256(barrierName);
            try {
                directory = CreateFileW(root, FILE_LIST_DIRECTORY,
                    FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING,
                    FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_OVERLAPPED,
                    IntPtr.Zero);
                if (directory == null || directory.IsInvalid)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not open fixture notification root.");
                NativeFileInformationV1 rootInformation = ReadDirectoryInformation(directory);
                rootVolumeSerialNumber = rootInformation.VolumeSerialNumber;
                rootFileIndexHigh = rootInformation.FileIndexHigh;
                rootFileIndexLow = rootInformation.FileIndexLow;
                VerifyCurrentRootIdentity();
                eventHandle = CreateEventW(IntPtr.Zero, true, false, null);
                if (eventHandle == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create notification event.");
                buffer = Marshal.AllocHGlobal(bufferBytes);
                overlapped = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(NativeOverlappedV1)));
                IssueRead();
                armed = true;
            }
            catch (Exception constructionError) {
                try { DisposeResources(true); }
                catch (Exception cleanupError) {
                    throw new AggregateException("Membership monitor construction and cleanup both failed.",
                        constructionError, cleanupError);
                }
                throw;
            }
        }

        private static NativeFileInformationV1 ReadDirectoryInformation(SafeFileHandle handle) {
            NativeFileInformationV1 information;
            if (!GetFileInformationByHandle(handle, out information))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not inspect fixture root identity.");
            if ((information.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 ||
                (information.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                throw new InvalidOperationException("Fixture root identity is not an ordinary directory.");
            return information;
        }

        private void VerifyCurrentRootIdentity() {
            using (SafeFileHandle current = CreateFileW(root, 0,
                FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero)) {
                if (current == null || current.IsInvalid)
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not reopen fixture root for identity verification.");
                NativeFileInformationV1 information = ReadDirectoryInformation(current);
                if (information.VolumeSerialNumber != rootVolumeSerialNumber ||
                    information.FileIndexHigh != rootFileIndexHigh ||
                    information.FileIndexLow != rootFileIndexLow)
                    throw new InvalidOperationException("Fixture root path identity changed during the guarded interval.");
            }
        }

        private static string NewBarrierName() {
            byte[] random = new byte[16];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(random);
            StringBuilder text = new StringBuilder(32);
            for (int i = 0; i < random.Length; ++i) text.Append(random[i].ToString("x2"));
            return "B" + text.ToString() + ".SNT";
        }

        private static string Sha256(string value) {
            using (SHA256 sha = SHA256.Create()) {
                byte[] digest = sha.ComputeHash(new UTF8Encoding(false).GetBytes(value));
                StringBuilder text = new StringBuilder(64);
                for (int i = 0; i < digest.Length; ++i) text.Append(digest[i].ToString("x2"));
                return text.ToString();
            }
        }

        private void IssueRead() {
            if (disposed || completed || pending) throw new InvalidOperationException("Notification state is invalid.");
            if (!ResetEvent(eventHandle))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not reset notification event.");
            NativeOverlappedV1 value = new NativeOverlappedV1();
            value.EventHandle = eventHandle;
            Marshal.StructureToPtr(value, overlapped, false);
            bool accepted = ReadDirectoryChangesW(directory, buffer, (uint)bufferBytes, true,
                FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME,
                IntPtr.Zero, overlapped, IntPtr.Zero);
            if (!accepted) {
                int error = Marshal.GetLastWin32Error();
                if ((uint)error != ERROR_IO_PENDING)
                    throw new Win32Exception(error, "ReadDirectoryChangesW did not arm.");
            }
            pending = true;
        }

        private void CreateBarrier() {
            try {
                FileStream stream = null;
                try {
                    stream = new FileStream(barrierPath, FileMode.CreateNew,
                        FileAccess.Write, FileShare.Read, 1, FileOptions.WriteThrough);
                    barrierCreated = true;
                    stream.WriteByte(0x4a);
                    stream.Flush(true);
                }
                finally {
                    if (stream != null) stream.Dispose();
                }
                StringBuilder shortPath = new StringBuilder(32768);
                uint shortLength = GetShortPathNameW(barrierPath, shortPath, (uint)shortPath.Capacity);
                if (shortLength > 0 && shortLength < (uint)shortPath.Capacity)
                    barrierShortName = Path.GetFileName(shortPath.ToString());
            }
            catch (Exception ex) {
                throw new InvalidOperationException("Could not create the unique completion barrier.", ex);
            }
        }

        private uint AwaitBatch(uint timeoutMilliseconds) {
            uint wait = WaitForSingleObject(eventHandle, timeoutMilliseconds);
            if (wait == WAIT_TIMEOUT) throw new TimeoutException("Membership notification barrier timed out.");
            if (wait == WAIT_FAILED)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Membership notification wait failed.");
            if (wait != WAIT_OBJECT_0) throw new InvalidOperationException("Membership notification wait was indeterminate.");
            uint transferred;
            bool ok = GetOverlappedResult(directory, overlapped, out transferred, false);
            pending = false;
            if (!ok) {
                int error = Marshal.GetLastWin32Error();
                if ((uint)error == ERROR_OPERATION_ABORTED)
                    throw new InvalidOperationException("Membership notification was unexpectedly cancelled.");
                throw new Win32Exception(error, "Membership notification completion failed.");
            }
            if (transferred == 0)
                throw new InvalidOperationException("Membership notification overflow or zero-byte completion occurred.");
            if (transferred > (uint)bufferBytes)
                throw new InvalidOperationException("Membership notification returned an invalid byte count.");
            return transferred;
        }

        private bool ParseBatch(uint transferred) {
            ValidateBatchLayout(buffer, transferred);
            int position = 0;
            bool sawBarrier = false;
            checked { batchCount++; }
            while (true) {
                uint next = (uint)Marshal.ReadInt32(buffer, position);
                uint action = (uint)Marshal.ReadInt32(buffer, position + 4);
                uint nameBytes = (uint)Marshal.ReadInt32(buffer, position + 8);
                string name = Marshal.PtrToStringUni(IntPtr.Add(buffer, position + 12), (int)(nameBytes / 2));
                checked { recordCount++; }
                bool isBarrierName = String.Equals(name, barrierName, StringComparison.OrdinalIgnoreCase) ||
                    (!String.IsNullOrEmpty(barrierShortName) &&
                     String.Equals(name, barrierShortName, StringComparison.OrdinalIgnoreCase));
                if (isBarrierName && action == FILE_ACTION_ADDED) {
                    if (sawBarrier) throw new InvalidOperationException("Completion barrier was duplicated.");
                    sawBarrier = true;
                }
                else {
                    checked { unexpectedCount++; }
                }
                if (next == 0) break;
                position = checked(position + (int)next);
            }
            return sawBarrier;
        }

        private static void ValidateBatchLayout(IntPtr data, uint transferred) {
            int position = 0;
            while (true) {
                if (position < 0 || position + 12 > (int)transferred)
                    throw new InvalidOperationException("Membership notification record framing is invalid.");
                uint next = (uint)Marshal.ReadInt32(data, position);
                uint nameBytes = (uint)Marshal.ReadInt32(data, position + 8);
                if (nameBytes == 0 || (nameBytes & 1) != 0 ||
                    nameBytes > (uint)((int)transferred - position - 12))
                    throw new InvalidOperationException("Membership notification name framing is invalid.");
                string name = Marshal.PtrToStringUni(IntPtr.Add(data, position + 12), (int)(nameBytes / 2));
                if (String.IsNullOrEmpty(name) || name.IndexOf('\0') >= 0)
                    throw new InvalidOperationException("Membership notification name is invalid.");
                if (next == 0) break;
                uint recordBytes = checked(12u + nameBytes);
                uint alignedRecordBytes = checked((recordBytes + 3u) & ~3u);
                if ((next & 3u) != 0 || next < alignedRecordBytes ||
                    next > (uint)((int)transferred - position - 12))
                    throw new InvalidOperationException("Membership notification record offset is invalid.");
                position = checked(position + (int)next);
            }
        }

        internal static void ParseOverlappingBatchForTest() {
            IntPtr data = Marshal.AllocHGlobal(40);
            try {
                for (int offset = 0; offset < 40; offset += 4) Marshal.WriteInt32(data, offset, 0);
                Marshal.WriteInt32(data, 0, 12);
                Marshal.WriteInt32(data, 4, 1);
                Marshal.WriteInt32(data, 8, 8);
                byte[] name = Encoding.Unicode.GetBytes("TEST");
                Marshal.Copy(name, 0, IntPtr.Add(data, 12), name.Length);
                ValidateBatchLayout(data, 40);
            }
            finally { Marshal.FreeHGlobal(data); }
        }

        public MonitorResultV1 Seal(int timeoutMilliseconds) {
            if (!IsArmed || timeoutMilliseconds < 1 || timeoutMilliseconds > 60000)
                throw new InvalidOperationException("Membership monitor is not armed for completion.");
            System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
            bool sawBarrier = false;
            try {
                VerifyCurrentRootIdentity();
                CreateBarrier();
                while (!sawBarrier) {
                    double remaining = timeoutMilliseconds - clock.Elapsed.TotalMilliseconds;
                    if (remaining <= 0) throw new TimeoutException("Membership notification barrier timed out.");
                    uint bytes = AwaitBatch((uint)Math.Max(1, Math.Min(remaining, UInt32.MaxValue)));
                    sawBarrier = ParseBatch(bytes);
                    if (!sawBarrier) IssueRead();
                }
                if (unexpectedCount != 0)
                    throw new InvalidOperationException("Unexpected directory membership activity invalidated the guarded interval.");
                completed = true;
                armed = false;
                MonitorResultV1 result = new MonitorResultV1();
                result.ArmedBeforeInterval = true;
                result.BarrierObserved = true;
                result.NotificationBatchCount = batchCount;
                result.NotificationRecordCount = recordCount;
                result.UnexpectedEventCount = unexpectedCount;
                result.BarrierNameSha256 = barrierDigest;
                DisposeResources(false);
                return result;
            }
            catch (Exception sealError) {
                try { DisposeResources(true); }
                catch (Exception cleanupError) {
                    throw new AggregateException("Membership completion and cleanup both failed.",
                        sealError, cleanupError);
                }
                throw;
            }
        }

        internal void CancelPendingForTest() {
            if (!pending || directory == null || directory.IsInvalid)
                throw new InvalidOperationException("No pending notification exists.");
            if (!CancelIoEx(directory, overlapped))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Test cancellation failed.");
        }

        private void SettlePendingCancellation() {
            if (!pending) return;
            bool cancelled = CancelIoEx(directory, overlapped);
            int cancelError = cancelled ? 0 : Marshal.GetLastWin32Error();
            if (!cancelled && cancelError != 1168)
                throw new Win32Exception(cancelError, "Could not cancel pending membership notification.");
            uint wait = WaitForSingleObject(eventHandle, 5000);
            if (wait == WAIT_TIMEOUT)
                throw new TimeoutException("Pending membership notification did not settle after cancellation.");
            if (wait == WAIT_FAILED)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cancellation settlement wait failed.");
            if (wait != WAIT_OBJECT_0)
                throw new InvalidOperationException("Cancellation settlement was indeterminate.");
            uint transferred;
            bool completedNormally = GetOverlappedResult(directory, overlapped, out transferred, false);
            if (!completedNormally) {
                int completionError = Marshal.GetLastWin32Error();
                if ((uint)completionError != ERROR_OPERATION_ABORTED)
                    throw new Win32Exception(completionError, "Cancellation completion status was invalid.");
            }
            pending = false;
        }

        private void DisposeResources(bool cancelPending) {
            if (disposed) return;
            if (pending && directory != null && !directory.IsInvalid) {
                if (!cancelPending)
                    throw new InvalidOperationException("Pending membership I/O cannot be released without cancellation.");
                SettlePendingCancellation();
            }
            if (directory != null) { directory.Dispose(); directory = null; }
            if (overlapped != IntPtr.Zero) { Marshal.FreeHGlobal(overlapped); overlapped = IntPtr.Zero; }
            if (buffer != IntPtr.Zero) { Marshal.FreeHGlobal(buffer); buffer = IntPtr.Zero; }
            if (eventHandle != IntPtr.Zero) {
                if (!CloseHandle(eventHandle))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not close the notification event.");
                eventHandle = IntPtr.Zero;
            }
            if (barrierCreated) {
                try {
                    File.Delete(barrierPath);
                    if (File.Exists(barrierPath))
                        throw new IOException("Completion barrier remained after deletion.");
                }
                catch (Exception ex) {
                    throw new InvalidOperationException("Could not remove the completion barrier after notification settlement.", ex);
                }
                barrierCreated = false;
            }
            disposed = true;
            armed = false;
        }

        public void Dispose() { DisposeResources(true); }
    }
}
'@
}

function New-RimePimeNsisMembershipMonitorHandleV1 {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][int]$BufferBytes
    )
    $full = Assert-RimePimeNsisMembershipFixtureRootV1 $Root
    Initialize-RimePimeNsisMembershipMonitorTypeV1
    $native = [YimePime.NsisMembership.MonitorHostV1]::new($full, $BufferBytes)
    return [pscustomobject][ordered]@{
        PSTypeName = 'YimePime.NsisMembershipMonitorHandleV1'
        Native = $native
        Closed = $false
    }
}

function Open-RimePimeNsisMembershipMonitorV1 {
    param([Parameter(Mandatory)][string]$Root)
    return New-RimePimeNsisMembershipMonitorHandleV1 -Root $Root -BufferBytes 65536
}

function Assert-RimePimeNsisMembershipMonitorArmedV1 {
    param([Parameter(Mandatory)]$Monitor)
    if ($null -eq $Monitor -or $Monitor.PSObject.TypeNames -notcontains 'YimePime.NsisMembershipMonitorHandleV1' -or
        $null -eq $Monitor.Native -or $Monitor.Closed -or -not $Monitor.Native.IsArmed -or
        $Monitor.Native.IsCompleted -or $Monitor.Native.IsDisposed) {
        throw 'DP1-J membership monitor handle is not armed.'
    }
    return $true
}

function Complete-RimePimeNsisMembershipMonitorV1 {
    param(
        [Parameter(Mandatory)]$Monitor,
        [ValidateRange(1, 60000)][int]$TimeoutMilliseconds = 10000
    )
    $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $Monitor
    try {
        $nativeResult = $Monitor.Native.Seal($TimeoutMilliseconds)
        $Monitor.Closed = [bool]$Monitor.Native.IsDisposed
        if (-not $Monitor.Closed) { throw 'DP1-J native membership monitor did not finish completion cleanup.' }
        return [pscustomobject][ordered]@{
            schema_version = $script:RimePimeNsisMembershipMonitorSchemaV1
            fixture_only = $true
            read_directory_changes_w_overlapped = $true
            armed_before_guarded_interval = [bool]$nativeResult.ArmedBeforeInterval
            unique_completion_barrier_observed = [bool]$nativeResult.BarrierObserved
            notification_batch_count = [int]$nativeResult.NotificationBatchCount
            notification_record_count = [int]$nativeResult.NotificationRecordCount
            unexpected_membership_event_count = [int]$nativeResult.UnexpectedEventCount
            barrier_name_sha256 = [string]$nativeResult.BarrierNameSha256
            completed_cleanly = $true
            physical_membership_prevention_claimed = $false
            makensis_interval_covered = $false
            active_same_sid_transient_tree_membership_interference_excluded = $false
            nsis_non_os_compiler_input_closure = $false
            full_nsis_toolchain_input_closure = $false
        }
    }
    catch {
        $Monitor.Closed = [bool]$Monitor.Native.IsDisposed
        throw
    }
}

function Close-RimePimeNsisMembershipMonitorV1 {
    param([Parameter(Mandatory)]$Monitor)
    if ($null -eq $Monitor -or $Monitor.PSObject.TypeNames -notcontains 'YimePime.NsisMembershipMonitorHandleV1') {
        throw 'DP1-J membership monitor handle is invalid.'
    }
    if (-not $Monitor.Closed -and $null -ne $Monitor.Native) {
        $Monitor.Native.Dispose()
        $Monitor.Closed = [bool]$Monitor.Native.IsDisposed
        if (-not $Monitor.Closed) { throw 'DP1-J native membership monitor did not finish disposal.' }
    }
}

function Open-RimePimeNsisMembershipMonitorCoreV1 {
    param(
        [Parameter(Mandatory)][string]$Root,
        [ValidateRange(128, 65536)][int]$BufferBytes = 65536
    )
    return New-RimePimeNsisMembershipMonitorHandleV1 -Root $Root -BufferBytes $BufferBytes
}

function Invoke-RimePimeNsisMembershipMonitorCancellationForTestV1 {
    param([Parameter(Mandatory)]$Monitor)
    $null = Assert-RimePimeNsisMembershipMonitorArmedV1 $Monitor
    $method = $Monitor.Native.GetType().GetMethod('CancelPendingForTest',
        [Reflection.BindingFlags]::Instance -bor [Reflection.BindingFlags]::NonPublic)
    if ($null -eq $method) { throw 'DP1-J internal cancellation probe is unavailable.' }
    try { $null = $method.Invoke($Monitor.Native, @()) }
    catch { throw $_.Exception.InnerException }
}

function Invoke-RimePimeNsisMembershipParserOverlapForTestV1 {
    Initialize-RimePimeNsisMembershipMonitorTypeV1
    $type = $script:RimePimeNsisMembershipMonitorTypeNameV1 -as [type]
    $method = $type.GetMethod('ParseOverlappingBatchForTest',
        [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::NonPublic)
    if ($null -eq $method) { throw 'DP1-J internal parser probe is unavailable.' }
    try { $null = $method.Invoke($null, @()) }
    catch { throw $_.Exception.InnerException }
}
