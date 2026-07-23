using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

namespace SoapstoneLib
{
    /// <summary>
    /// Connection info used by both locally running servers and by local clients, so they can find each other.
    /// 
    /// Currently, this only supports localhost connections.
    /// </summary>
    public sealed class KnownServer
    {
        /// <summary>
        /// Standard server info for DSMapStudio and DSMapStudio fork Smithbox.
        /// </summary>
        public static readonly KnownServer DSMapStudio = new KnownServer(22720, "DSMapStudio", "Smithbox");

        /// <summary>
        /// Alternate name for DSMapstudio/Smithbox server info.
        /// </summary>
        public static readonly KnownServer Smithbox = DSMapStudio;

        /// <summary>
        /// An expected local process name of this server. This usually matches the exe name.
        /// </summary>
        public string ProcessName => ProcessNames.FirstOrDefault();

        /// <summary>
        /// All expected local process names of this server. This usually matches the exe name.
        /// </summary>
        public IReadOnlyList<string> ProcessNames { get; }

        /// <summary>
        /// Standard port for this server to run at. A different one may be selected if it's busy.
        /// </summary>
        public ushort PortHint { get; }

        /// <summary>
        /// Construct an address for local server connections.
        /// 
        /// The server's process must match the process name, if provided here.
        /// Otherwise, the port is used directly, if non-zero. The port is also preferred
        /// if there are multiple ports associated with the given process name.
        /// </summary>
        public KnownServer(ushort portHint, params string[] processNames)
        {
            if (portHint == 0 && processNames.Length == 0)
            {
                throw new ArgumentException($"One of process or port must be provided in KnownServer");
            }
            PortHint = portHint;
            ProcessNames = processNames.ToList().AsReadOnly();
        }

        /// <inheritdoc />
        public override string ToString() => $"KnownServer[PortHint={PortHint},ProcessNames={string.Join(",", ProcessNames)}]";

        /// <summary>
        /// Try to find a running server using heuristic info.
        /// 
        /// This does a lookup of system TCP state and will throw an exception if that fails.
        /// </summary>
        internal bool FindServer(out int realPort)
        {
            realPort = 0;

            // Make sure the server is at least running. This may throw an exception.
            List<TcpRow> rows = GetAllTcpConnections();

            // If process is given, always try to use it, and fail if not present
            if (ProcessNames.Count > 0)
            {
                List<Process> processes = new();
                foreach (string name in ProcessNames)
                {
                    processes.AddRange(Process.GetProcessesByName(name));
                }
                if (processes.Count == 0)
                {
                    return false;
                }
                HashSet<int> processIds = new HashSet<int>(processes.Select(p => p.Id));
                List<int> matchingPorts = new List<int>();
                foreach (TcpRow row in rows)
                {
                    if (processIds.Contains(row.OwningPid) && row.State == TcpState.Listen)
                    {
                        matchingPorts.Add(row.LocalPort);
                    }
                }
                if (matchingPorts.Count > 0)
                {
                    // Prefer PortHint if given
                    realPort = PortHint > 0 && matchingPorts.Contains(PortHint) ? PortHint : matchingPorts[0];
                    return true;
                }
                return false;
            }

            // Use port if process is not given. This will fail later on if there's not a gRPC service there.
            foreach (TcpRow row in rows)
            {
                if (row.LocalPort == PortHint && row.State == TcpState.Listen)
                {
                    realPort = PortHint;
                    return true;
                }
            }
            return false;
        }

        /// <summary>
        /// Checks if the hinted port is in use by a server, as a heuristic for choosing a different port if it is.
        /// </summary>
        internal bool IsPortInUse()
        {
            if (PortHint == 0)
            {
                return false;
            }
            List<TcpRow> rows = GetAllTcpConnections();
            return rows.Any(row => PortHint == row.LocalPort && row.State == TcpState.Listen);
        }

        // ---- Cross-platform TCP table reading ----

        private enum TcpState
        {
            Closed = 1,
            Listen = 2,
            SynSent = 3,
            SynRcvd = 4,
            Established = 5,
            FinWait1 = 6,
            FinWait2 = 7,
            CloseWait = 8,
            Closing = 9,
            LastAck = 10,
            TimeWait = 11,
            DeleteTcb = 12,
        }

        private readonly struct TcpRow
        {
            public readonly int LocalPort;
            public readonly int OwningPid;
            public readonly TcpState State;

            public TcpRow(int localPort, int owningPid, TcpState state)
            {
                LocalPort = localPort;
                OwningPid = owningPid;
                State = state;
            }
        }

        private static List<TcpRow> GetAllTcpConnections()
        {
            if (OperatingSystem.IsWindows())
            {
                return GetAllTcpConnectionsWindows();
            }
            if (OperatingSystem.IsLinux())
            {
                return GetAllTcpConnectionsLinux();
            }
            // macOS and others: return empty so the caller falls back to PortHint.
            return new List<TcpRow>();
        }

        // ---- Linux: /proc/net/tcp and /proc/net/tcp6 ----
        // Format (space-separated):
        //   sl local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode
        // local_address = "0100007F:5860" (hex IP:hex port)
        // st = hex state (0A = LISTEN)
        // There is no owning PID column; pid is inferred via /proc/*/fd/socket inode.
        private static List<TcpRow> GetAllTcpConnectionsLinux()
        {
            var rows = new List<TcpRow>();
            // Build inode -> pid map by scanning /proc/*/fd symlinks.
            var inodeToPid = new Dictionary<ulong, int>();
            try
            {
                foreach (var procDir in Directory.EnumerateDirectories("/proc"))
                {
                    var fdDir = Path.Combine(procDir, "fd");
                    if (!Directory.Exists(fdDir))
                        continue;
                    var pidName = Path.GetFileName(procDir);
                    if (!int.TryParse(pidName, out int pid))
                        continue;
                    try
                    {
                        foreach (var fd in Directory.EnumerateFileSystemEntries(fdDir))
                        {
                            string target = ReadLink(fd);
                            if (target == null)
                                continue;
                            // target looks like: socket:[12345]
                            if (!target.StartsWith("socket:[", StringComparison.Ordinal))
                                continue;
                            var numPart = target.Substring("socket:[".Length).TrimEnd(']');
                            if (ulong.TryParse(numPart, out ulong inode))
                            {
                                inodeToPid[inode] = pid;
                            }
                        }
                    }
                    catch { /* permission denied on some procs */ }
                }
            }
            catch { /* /proc not available */ }

            ParseProcTcpFile("/proc/net/tcp", rows, inodeToPid);
            ParseProcTcpFile("/proc/net/tcp6", rows, inodeToPid);
            return rows;
        }

        private static void ParseProcTcpFile(string path, List<TcpRow> rows, Dictionary<ulong, int> inodeToPid)
        {
            string[] lines;
            try { lines = File.ReadAllLines(path); }
            catch { return; }
            // Skip header
            for (int i = 1; i < lines.Length; i++)
            {
                var parts = lines[i].Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                if (parts.Length < 10)
                    continue;
                // parts[1] = local_address, parts[2] = rem_address, parts[3] = st, parts[9] = inode
                var localAddr = parts[1].Split(':');
                if (localAddr.Length != 2)
                    continue;
                if (!int.TryParse(localAddr[1], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int localPort))
                    continue;
                if (!int.TryParse(parts[3], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int stateInt))
                    continue;
                if (!ulong.TryParse(parts[9], out ulong inode))
                    continue;
                int pid = inodeToPid.TryGetValue(inode, out var p) ? p : 0;
                rows.Add(new TcpRow(localPort, pid, (TcpState)stateInt));
            }
        }

        // ---- Windows: iphlpapi.dll ----
        // https://docs.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable
        // C# marshalling example code
        // http://www.pinvoke.net/default.aspx/iphlpapi/GetExtendedTcpTable.html
        // https://stackoverflow.com/questions/577433/which-pid-listens-on-a-given-port-in-c-sharp

        private static ushort ConvertPort(ushort port) => (ushort)(port >> 8 | ((port & 0xFF) << 8));

        private enum MIB_TCP_STATE : int
        {
            MIB_TCP_STATE_CLOSED = 1,
            MIB_TCP_STATE_LISTEN = 2,
            MIB_TCP_STATE_SYN_SENT = 3,
            MIB_TCP_STATE_SYN_RCVD = 4,
            MIB_TCP_STATE_ESTAB = 5,
            MIB_TCP_STATE_FIN_WAIT1 = 6,
            MIB_TCP_STATE_FIN_WAIT2 = 7,
            MIB_TCP_STATE_CLOSE_WAIT = 8,
            MIB_TCP_STATE_CLOSING = 9,
            MIB_TCP_STATE_LAST_ACK = 10,
            MIB_TCP_STATE_TIME_WAIT = 11,
            MIB_TCP_STATE_DELETE_TCB = 12,
        }

        private enum TCP_TABLE_CLASS : int
        {
            TCP_TABLE_BASIC_LISTENER,
            TCP_TABLE_BASIC_CONNECTIONS,
            TCP_TABLE_BASIC_ALL,
            TCP_TABLE_OWNER_PID_LISTENER,
            TCP_TABLE_OWNER_PID_CONNECTIONS,
            TCP_TABLE_OWNER_PID_ALL,
            TCP_TABLE_OWNER_MODULE_LISTENER,
            TCP_TABLE_OWNER_MODULE_CONNECTIONS,
            TCP_TABLE_OWNER_MODULE_ALL
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MIB_TCPROW_OWNER_PID
        {
            public MIB_TCP_STATE state;
            public uint localAddr;
            // Uses network byte order, but only within two bytes. Use ConvertPort to convert.
            public ushort localPort;
            public uint remoteAddr;
            public ushort remotePort;
            public int owningPid;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MIB_TCP6ROW_OWNER_PID
        {
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
            public byte[] localAddr;
            public uint localScopeId;
            public ushort localPort;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
            public byte[] remoteAddr;
            public uint remoteScopeId;
            public ushort remotePort;
            public MIB_TCP_STATE state;
            public int owningPid;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct COMMON_MIB_TCPTABLE_OWNER_PID
        {
            public uint numEntries;
            // This is followed by a variable length array of either row type.
            // It's easiest to walk through it manually in code.
        }

        [DllImport("iphlpapi.dll", SetLastError = true)]
        static extern uint GetExtendedTcpTable(
            IntPtr tcpTable,
            ref int tcpTableLength,
            bool sort,
            int ipVersion,
            TCP_TABLE_CLASS tcpTableType,
            int reserved = 0);

        // Linux readlink for resolving /proc/*/fd/* socket symlinks.
        [DllImport("libc", SetLastError = true)]
        private static extern IntPtr readlink(string path, byte[] buffer, IntPtr bufferSize);

        private static string ReadLink(string path)
        {
            const int MaxLen = 4096;
            var buf = new byte[MaxLen];
            IntPtr n = readlink(path, buf, (IntPtr)MaxLen);
            if ((long)n <= 0)
                return null;
            return System.Text.Encoding.UTF8.GetString(buf, 0, (int)n);
        }

        private static List<TcpRow> GetAllTcpConnectionsWindows()
        {
            var rows = new List<TcpRow>();
            foreach (var entry in GetWindowsTcpRows<MIB_TCPROW_OWNER_PID>(ipVersion: 2))
            {
                rows.Add(new TcpRow(ConvertPort(entry.localPort), entry.owningPid, (TcpState)entry.state));
            }
            foreach (var entry in GetWindowsTcpRows<MIB_TCP6ROW_OWNER_PID>(ipVersion: 23))
            {
                rows.Add(new TcpRow(ConvertPort(entry.localPort), entry.owningPid, (TcpState)entry.state));
            }
            return rows;
        }

        private static TRow[] GetWindowsTcpRows<TRow>(int ipVersion)
        {
            TRow[] rows;
            int buffSize = 0;

            uint ret = GetExtendedTcpTable(
                IntPtr.Zero,
                ref buffSize,
                true,
                ipVersion,
                TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL);
            // 122 is "insufficient buffer", expected
            if (ret != 0 && ret != 122)
            {
                throw new Exception("GetExtendedTcpTable in iphlpapi.dll failed with error code " + ret);
            }

            // Race conditions may be possible, if this changes between allocation and re-allocation
            IntPtr buffTable = Marshal.AllocHGlobal(buffSize);
            try
            {
                ret = GetExtendedTcpTable(
                    buffTable,
                    ref buffSize,
                    true,
                    ipVersion,
                    TCP_TABLE_CLASS.TCP_TABLE_OWNER_PID_ALL);
                if (ret != 0)
                {
                    throw new Exception("GetExtendedTcpTable in iphlpapi.dll failed with error code " + ret);
                }

                // Get the total size and copy all row structs individually
                // This is pointing to memory we've allocated, so unboxing it should be safe.
#pragma warning disable CS8605
                COMMON_MIB_TCPTABLE_OWNER_PID tab =
                    (COMMON_MIB_TCPTABLE_OWNER_PID)Marshal.PtrToStructure(buffTable, typeof(COMMON_MIB_TCPTABLE_OWNER_PID));
                IntPtr rowPtr = (IntPtr)((long)buffTable + Marshal.SizeOf<int>());

                rows = new TRow[tab.numEntries];
                for (int i = 0; i < tab.numEntries; i++)
                {
                    rows[i] = (TRow)Marshal.PtrToStructure(rowPtr, typeof(TRow));
                    rowPtr = (IntPtr)((long)rowPtr + Marshal.SizeOf<TRow>());
                }
#pragma warning restore CS8605
            }
            finally
            {
                Marshal.FreeHGlobal(buffTable);
            }
            return rows;
        }
    }
}
