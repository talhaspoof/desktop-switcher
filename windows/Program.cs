using System;
using System.Diagnostics;
using System.Drawing;
using System.Net;
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
        private int currentDesktop = 1;

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private const int KEYEVENTF_EXTENDEDKEY = 0x0001;
        private const int KEYEVENTF_KEYUP = 0x0002;
        private const byte VK_LWIN = 0x5B;
        private const byte VK_CONTROL = 0x11;
        private const byte VK_LEFT = 0x25;
        private const byte VK_RIGHT = 0x27;
        private const byte VK_TAB = 0x09;
        private const byte VK_D = 0x44;

        public TrayApplicationContext()
        {
            EnsureFirewallRule();
            string localIp = GetLocalIpAddress();

            trayIcon = new NotifyIcon()
            {
                Icon = SystemIcons.Application,
                ContextMenuStrip = new ContextMenuStrip(),
                Visible = true,
                Text = $"Desktop Switcher (IP: {localIp})"
            };

            trayIcon.ContextMenuStrip.Items.Add($"Laptop IP: {localIp}").Enabled = false;
            trayIcon.ContextMenuStrip.Items.Add($"Port: {PORT} (Active)").Enabled = false;
            trayIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
            trayIcon.ContextMenuStrip.Items.Add("Reset to Desktop 1", null, (s, e) => JumpToDesktop(1));
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
            catch { return "127.0.0.1"; }
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
                            byte[] response = Encoding.UTF8.GetBytes($"SERVER_HERE:{pcName}:{currentDesktop}");
                            udpServer.Send(response, response.Length, remoteEP);
                        }
                        else if (message.StartsWith("GOTO:"))
                        {
                            if (int.TryParse(message.Split(':')[1], out int targetDesktop))
                            {
                                JumpToDesktop(targetDesktop);
                            }
                        }
                        else if (message == "SWITCH_LEFT")
                        {
                            SendDesktopShortcut(VK_LEFT);
                            if (currentDesktop > 1) currentDesktop--;
                        }
                        else if (message == "SWITCH_RIGHT")
                        {
                            SendDesktopShortcut(VK_RIGHT);
                            currentDesktop++;
                        }
                        else if (message == "NEW_DESKTOP")
                        {
                            SendNewDesktopShortcut();
                            currentDesktop++;
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

        private void JumpToDesktop(int target)
        {
            if (target < 1) target = 1;

            if (target == 1 && currentDesktop == 1)
            {
                // Force sync to Desktop 1 just in case user switched manually on keyboard
                for (int i = 0; i < 8; i++)
                {
                    SendDesktopShortcut(VK_LEFT);
                    Thread.Sleep(25);
                }
                currentDesktop = 1;
                return;
            }

            int diff = target - currentDesktop;
            if (diff > 0)
            {
                for (int i = 0; i < diff; i++)
                {
                    SendDesktopShortcut(VK_RIGHT);
                    Thread.Sleep(35);
                }
            }
            else if (diff < 0)
            {
                for (int i = 0; i < Math.Abs(diff); i++)
                {
                    SendDesktopShortcut(VK_LEFT);
                    Thread.Sleep(35);
                }
            }
            currentDesktop = target;
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

        private void SendNewDesktopShortcut()
        {
            // Ctrl + Win + D creates a new virtual desktop on Windows
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event(VK_LWIN, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
            keybd_event(VK_D, 0, 0, UIntPtr.Zero);

            keybd_event(VK_D, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
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
