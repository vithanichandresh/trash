import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothDeviceConnector extends StatefulWidget {
  const BluetoothDeviceConnector({super.key});

  @override
  _BluetoothDeviceConnectorState createState() => _BluetoothDeviceConnectorState();
}

class _BluetoothDeviceConnectorState extends State<BluetoothDeviceConnector> {
  BluetoothDevice? _connectedDevice;
  List<BluetoothDevice> _discoveredDevices = [];
  bool _isScanning = false;

  bool isBleOn = false;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBluetoothPermissions();
    });
    super.initState();
  }

  Future<void> _checkBluetoothPermissions() async {
    // Request Bluetooth and location permissions
    try {
      final status = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();
      bool isGranted =
          status[Permission.bluetooth]!.isGranted &&
          status[Permission.bluetoothScan]!.isGranted &&
          status[Permission.bluetoothConnect]!.isGranted &&
          status[Permission.location]!.isGranted;
      if (isGranted) {
        // Check if Bluetooth is available and enabled
        bool isAvailable = await FlutterBluePlus.isAvailable;
        if (isAvailable) {
          isBleOn = await FlutterBluePlus.isOn;
          setState(() {});
        } else {
          _turnOnBluetooth();
        }
      } else {
        // Handle permission denial
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Bluetooth permissions are required to use this feature.')));
      }
    } catch (e) {
      print(e);
    }
  }

  void _turnOnBluetooth() async {
    try {
      // Request to turn on Bluetooth
      await FlutterBluePlus.turnOn();
    } catch (e) {
      print('Failed to turn on Bluetooth: $e');
    }
  }

  void _scanForDevices() async {
    // Ensure Bluetooth is on
    if (!(await FlutterBluePlus.isAvailable)) {
      _turnOnBluetooth();
      return;
    }

    setState(() {
      _isScanning = true;
      _discoveredDevices.clear();
    });

    // Start scanning
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _discoveredDevices = results.map((r) => r.device).toList();
      });
    });

    // Stop scanning after timeout
    await Future.delayed(Duration(seconds: 10));
    await FlutterBluePlus.stopScan();

    setState(() {
      _isScanning = false;
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      // Disconnect any previous connection
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }

      // Connect to new device
      await device.connect();

      setState(() {
        _connectedDevice = device;
      });

      // Discover services after connection
      await device.discoverServices();
    } catch (e) {
      print('Connection failed: $e');
    }
  }

  void _disconnectDevice() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // refresh button
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                onPressed: () {
                  _checkBluetoothPermissions();
                },
                icon: Text('Refresh Status'),
              ),
            ),
            // Bluetooth Toggle
            ListTile(
              title: Text('Bluetooth'),
              onTap: (){
                if (!isBleOn) {
                  _turnOnBluetooth();
                } else {
                  FlutterBluePlus.turnOff();
                }
              },
              trailing: Switch(
                value: isBleOn,
                onChanged: (value) {
                  if (value) {
                    _turnOnBluetooth();
                  } else {
                    FlutterBluePlus.turnOff();
                  }
                },
              ),
            ),

            // Bluetooth Status
            ListTile(
              title: Text('Bluetooth Status'),
              trailing: StreamBuilder<BluetoothAdapterState>(
                stream: FlutterBluePlus.adapterState,
                initialData: BluetoothAdapterState.unknown,
                builder: (c, snapshot) {
                  final state = snapshot.data;
                  return Text(
                    state == BluetoothAdapterState.on ? 'Enabled' : 'Disabled',
                    style: TextStyle(color: state == BluetoothAdapterState.on ? Colors.green : Colors.red),
                  );
                },
              ),
            ),

            // Connected Device
            if (_connectedDevice != null)
              ListTile(
                title: Text('Connected to: ${_connectedDevice!.name}'),
                trailing: ElevatedButton(child: Text('Disconnect'), onPressed: _disconnectDevice),
              ),

            if (_isScanning) ...[
              LinearProgressIndicator(),
            ] else ...[
              ...List.generate(_discoveredDevices.length, (index) {
                final device = _discoveredDevices[index];
                return ListTile(
                  title: Text(device.name ?? 'Unknown Device'),
                  subtitle: Text(device.id.toString()),
                  trailing: ElevatedButton(child: Text('Connect'), onPressed: () => _connectToDevice(device)),
                );
              }),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(child: Icon(Icons.bluetooth), onPressed: _scanForDevices),
    );
  }

  @override
  void dispose() {
    // Disconnect device and stop scanning when widget is disposed
    _disconnectDevice();
    FlutterBluePlus.stopScan();
    super.dispose();
  }
}
