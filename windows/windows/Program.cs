using System;
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
            trayIcon = new NotifyIcon()
            {
                Icon = SystemIcons.Application,
                ContextMenuStrip = new ContextMenuStrip(),
                Visible = true,
                Text = "Desktop Switcher Server (Running)"
            };

            trayIcon.ContextMenuStrip.Items.Add($"Status: Active on Port {PORT}").Enabled = false;
            trayIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
            trayIcon.ContextMenuStrip.Items.Add("Exit", null, OnExit);

            StartUdpServer();
        }

        private void StartUdpServer()
        {
            listenThread = new Thread(() =>
            {
                udpServer = new UdpClient(PORT);
                IPEndPoint remoteEP = new IPEndPoint(IPAddress.Any, PORT);

                while (isRunning)
                {
                    try
                    {
                        byte[] data = udpServer.Receive(ref remoteEP);
                        string message = Encoding.UTF8.GetString(data);

                        switch (message)
                        {
                            case "DISCOVER_SERVER":
                                string pcName = Environment.MachineName;
                                byte[] response = Encoding.UTF8.GetBytes($"SERVER_HERE:{pcName}");
                                udpServer.Send(response, response.Length, remoteEP);
                                break;
                            case "SWITCH_LEFT":
                                SendDesktopShortcut(VK_LEFT);
                                break;
                            case "SWITCH_RIGHT":
                                SendDesktopShortcut(VK_RIGHT);
                                break;
                            case "TASK_VIEW":
                                SendTaskViewShortcut();
                                break;
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
