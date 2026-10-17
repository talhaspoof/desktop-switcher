using System;
using System.Diagnostics;
using System.Drawing;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace DesktopSwitcherServer
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new TrayApplicationContext());
        }
    }

    public class TrayApplicationContext : ApplicationContext
    {
        private NotifyIcon trayIcon;
        private UdpClient udpServer;
        private Thread listenThread;
        private bool isRunning = true;
        private const int PORT = 45454;

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private const int KEYEVENTF_EXTENDEDKEY = 0x0001;
        private const int KEYEVENTF_KEYUP = 0x0002;
        private const byte VK_LWIN = 0x5B;
        private const byte VK_CONTROL = 0x11;
        private const byte VK_LEFT = 0x25;
        private const byte VK_RIGHT = 0x27;
        private const byte VK_TAB = 0x09;

        public TrayApplicationContext()
        {
            EnsureFirewallRule();
            string localIp = GetLocalIpAddress();

            trayIcon = new NotifyIcon()
            {
                Icon = SystemIcons.Application,
                ContextMenuStrip = new ContextMenuStrip(),
                Visible = true,
                Text = $"Desktop Switcher ({localIp})"
            };

            trayIcon.ContextMenuStrip.Items.Add($"Laptop IP: {localIp}").Enabled = false;
            trayIcon.ContextMenuStrip.Items.Add($"Port: {PORT} (Active)").Enabled = false;
            trayIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
            trayIcon.ContextMenuStrip.Items.Add("Exit", null, OnExit);

            StartUdpServer();
        }

        private void EnsureFirewallRule()
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo("netsh",
                    $"advfirewall firewall add rule name=\"Desktop Switcher UDP\" dir=in action=allow protocol=UDP localport={PORT} profile=any")
                {
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi);
            }
            catch { }
        }

        private string GetLocalIpAddress()
        {
            try
            {
                using (Socket socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0))
                {
                    socket.Connect("8.8.8.8", 65530);
                    IPEndPoint endPoint = socket.LocalEndPoint as IPEndPoint;
                    return endPoint.Address.ToString();
                }
            }
            catch
            {
                return "127.0.0.1";
            }
        }

        private void StartUdpServer()
        {
            listenThread = new Thread(() =>
            {
                udpServer = new UdpClient(PORT);
                udpServer.EnableBroadcast = true;
                IPEndPoint remoteEP = new IPEndPoint(IPAddress.Any, 0);

                while (isRunning)
                {
                    try
                    {
                        byte[] data = udpServer.Receive(ref remoteEP);
                        string message = Encoding.UTF8.GetString(data);

                        if (message == "DISCOVER_SERVER")
                        {
                            string pcName = Environment.MachineName;
                            byte[] response = Encoding.UTF8.GetBytes($"SERVER_HERE:{pcName}");
                            udpServer.Send(response, response.Length, remoteEP);
                        }
                        else if (message == "SWITCH_LEFT")
                        {
                            SendDesktopShortcut(VK_LEFT);
                        }
                        else if (message == "SWITCH_RIGHT")
                        {
                            SendDesktopShortcut(VK_RIGHT);
                        }
                        else if (message == "TASK_VIEW")
                        {
                            SendTaskViewShortcut();
                        }
                    }
                    catch (SocketException) { }
                }
            });
            listenThread.IsBackground = true;
            listenThread.Start();
        }

        private void SendDesktopShortcut(byte directionKey)
        {
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event(VK_LWIN, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
            keybd_event(directionKey, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);

            keybd_event(directionKey, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_LWIN, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        }

        private void SendTaskViewShortcut()
        {
            keybd_event(VK_LWIN, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
            keybd_event(VK_TAB, 0, 0, UIntPtr.Zero);

            keybd_event(VK_TAB, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_LWIN, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
        }

        private void OnExit(object sender, EventArgs e)
        {
            isRunning = false;
            udpServer?.Close();
            trayIcon.Visible = false;
            Application.Exit();
        }
    }
}
