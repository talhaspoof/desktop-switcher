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
  String _pcName = "Searching for PC...";
  bool _isConnected = false;
  final int _port = 45454;

  @override
  void initState() {
    super.initState();
    _initSocketAndDiscover();
  }

  Future<void> _initSocketAndDiscover() async {
    setState(() {
      _pcName = "Scanning Wi-Fi for PC...";
      _isConnected = false;
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
            setState(() {
              _serverIp = dg.address;
              _pcName = message.split(":")[1];
              _isConnected = true;
            });
          }
        }
      }
    });

    _broadcastDiscovery();
  }

  void _broadcastDiscovery() {
    if (_socket == null) return;
    List<int> data = utf8.encode("DISCOVER_SERVER");
    _socket!.send(data, InternetAddress("255.255.255.255"), _port);
  }

  void _sendCommand(String cmd) {
    if (!_isConnected || _serverIp == null) {
      _broadcastDiscovery();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not connected! Rescanning...")),
      );
      return;
    }
    HapticFeedback.lightImpact();
    _socket!.send(utf8.encode(cmd), _serverIp!, _port);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(
              Icons.circle,
              size: 12,
              color: _isConnected ? Colors.greenAccent : Colors.orangeAccent,
            ),
            const SizedBox(width: 10),
            Text(_pcName, style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initSocketAndDiscover,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _buildActionButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    label: "PREVIOUS",
                    onTap: () => _sendCommand("SWITCH_LEFT"),
                  ),
                  const SizedBox(width: 20),
                  _buildActionButton(
                    icon: Icons.arrow_forward_ios_rounded,
                    label: "NEXT",
                    onTap: () => _sendCommand("SWITCH_RIGHT"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              flex: 1,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E1E28),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Color(0xFF00E5FF), width: 1.5),
                    ),
                  ),
                  onPressed: () => _sendCommand("TASK_VIEW"),
                  icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF00E5FF)),
                  label: const Text("TASK VIEW", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => onTap(),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF252532), Color(0xFF181820)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.5), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: const Color(0xFF6C63FF)),
              const SizedBox(height: 16),
              Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
