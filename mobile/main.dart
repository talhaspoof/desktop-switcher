import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const DesktopRemoteApp());

class DesktopRemoteApp extends StatelessWidget {
  const DesktopRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desktop Switcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00E5FF),
        ),
      ),
      home: const RemoteScreen(),
    );
  }
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  RawDatagramSocket? _socket;
  InternetAddress? _serverIp;
  String _pcName = "Tap here to set IP or Scan";
  bool _isConnected = false;
  final int _port = 45454;

  int _totalDesktops = 6; // Default 6 square boxes
  int _activeDesktop = 1;

  @override
  void initState() {
    super.initState();
    _initSocketAndDiscover();
  }

  Future<void> _initSocketAndDiscover() async {
    setState(() {
      if (!_isConnected) _pcName = "Scanning... (Tap to enter IP)";
    });

    _socket?.close();
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.broadcastEnabled = true;

    _socket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? dg = _socket!.receive();
        if (dg != null) {
          String message = utf8.decode(dg.data);
          if (message.startsWith("SERVER_HERE:")) {
            List<String> parts = message.split(":");
            setState(() {
              _serverIp = dg.address;
              _pcName = "${parts[1]} (${dg.address.address})";
              if (parts.length > 2) {
                _activeDesktop = int.tryParse(parts[2]) ?? 1;
              }
              _isConnected = true;
            });
          }
        }
      }
    });

    await _broadcastDiscovery();
  }

  Future<void> _broadcastDiscovery() async {
    if (_socket == null) return;
    List<int> data = utf8.encode("DISCOVER_SERVER");

    // 1. Standard Wi-Fi broadcast
    try {
      _socket!.send(data, InternetAddress("255.255.255.255"), _port);
    } catch (_) {}

    // 2. Common Android Hotspot & Windows Hotspot Subnets
    final List<String> commonHotspotBroadcasts = [
      "192.168.43.255",
      "192.168.137.255",
      "192.168.1.255",
      "192.168.0.255",
    ];
    for (String bcast in commonHotspotBroadcasts) {
      try {
        _socket!.send(data, InternetAddress(bcast), _port);
      } catch (_) {}
    }

    // 3. All active phone network interfaces
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          List<String> parts = addr.address.split('.');
          if (parts.length == 4) {
            String subnetBroadcast = "${parts[0]}.${parts[1]}.${parts[2]}.255";
            try {
              _socket!.send(data, InternetAddress(subnetBroadcast), _port);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  void _showManualIpDialog() {
    TextEditingController ipController = TextEditingController(
      text: _serverIp?.address ?? "192.168.",
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Connect to Laptop IP"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Right-click the Desktop Switcher icon in your Windows System Tray (bottom right corner) to see your Laptop IP.",
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ipController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: "Laptop IP Address",
                hintText: "e.g. 192.168.43.105",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              String ip = ipController.text.trim();
              try {
                InternetAddress parsedIp = InternetAddress(ip);
                setState(() {
                  _serverIp = parsedIp;
                  _pcName = "Laptop ($ip)";
                  _isConnected = true;
                });
                _socket?.send(utf8.encode("DISCOVER_SERVER"), parsedIp, _port);
                Navigator.pop(context);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Invalid IP format!")),
                );
              }
            },
            child: const Text("Connect"),
          ),
        ],
      ),
    );
  }

  void _sendCommand(String cmd) {
    if (!_isConnected || _serverIp == null) {
      _broadcastDiscovery();
      _showManualIpDialog();
      return;
    }
    HapticFeedback.mediumImpact();
    _socket!.send(utf8.encode(cmd), _serverIp!, _port);
  }

  void _selectDesktop(int index) {
    setState(() {
      _activeDesktop = index;
    });
    _sendCommand("GOTO:$index");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: GestureDetector(
          onTap: _showManualIpDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isConnected ? Colors.greenAccent.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _isConnected ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _pcName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 14, color: Colors.white54),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Rescan Network",
            onPressed: _initSocketAndDiscover,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header + Add/Remove Desktop Count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "WORKSPACES",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Colors.white60,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.white60),
                      onPressed: () {
                        if (_totalDesktops > 2) {
                          setState(() => _totalDesktops--);
                        }
                      },
                    ),
                    Text("$_totalDesktops", style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00E5FF)),
                      onPressed: () {
                        setState(() => _totalDesktops++);
                        _sendCommand("NEW_DESKTOP");
                      },
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 10),

            // Grid of Square Desktop Boxes
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 2 square boxes per row
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.0, // Perfect Square
                ),
                itemCount: _totalDesktops,
                itemBuilder: (context, idx) {
                  int desktopNum = idx + 1;
                  bool isSelected = _activeDesktop == desktopNum;

                  return GestureDetector(
                    onTapDown: (_) => _selectDesktop(desktopNum),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isSelected
                              ? [const Color(0xFF6C63FF), const Color(0xFF4834DF)]
                              : [const Color(0xFF22222E), const Color(0xFF181822)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00E5FF)
                              : Colors.white.withOpacity(0.08),
                          width: isSelected ? 2.5 : 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.45),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                )
                              ]
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.desktop_windows_rounded,
                            size: 44,
                            color: isSelected ? Colors.white : const Color(0xFF6C63FF),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Desktop $desktopNum",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.white70,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                "ACTIVE",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00E5FF),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            )
                          ]
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            // Bottom Quick-Action Row (Left / Task View / Right)
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1E28),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () {
                        if (_activeDesktop > 1) setState(() => _activeDesktop--);
                        _sendCommand("SWITCH_LEFT");
                      },
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1E28),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
                        ),
                      ),
                      onPressed: () => _sendCommand("TASK_VIEW"),
                      icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF00E5FF)),
                      label: const Text(
                        "TASK VIEW",
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E1E28),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () {
                        if (_activeDesktop < _totalDesktops) setState(() => _activeDesktop++);
                        _sendCommand("SWITCH_RIGHT");
                      },
                      child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
