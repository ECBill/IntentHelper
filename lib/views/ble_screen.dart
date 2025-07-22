import 'dart:async';
import 'package:app/services/ble_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BLEScreen extends StatefulWidget {
  @override
  _BLEScreenState createState() => _BLEScreenState();
}

class _BLEScreenState extends State<BLEScreen> {
  List<ScanResult> _devices = [];
  bool _isScanning = false;
  String _statusMessage = '';
  StreamSubscription<ScanResult>? _subscription;

  @override
  void initState() {
    super.initState();
    startScanning();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void startScanning() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning...';
      _devices.clear();
    });

    final stream = scanDevices();

    _subscription = stream.listen((result) {
      setState(() {
        _devices.add(result);
      });
    }, onDone: () {
      setState(() {
        _isScanning = false;
        _statusMessage = _devices.isEmpty ? 'No devices found' : 'Scan completed!';
      });
    }, onError: (error) {
      setState(() {
        _isScanning = false;
        _statusMessage = 'Scan failed: $error';
      });
    });
  }

  Future<void> startConnecting(ScanResult result) async {
    setState(() {
      _statusMessage = 'Connecting to ${result.advertisementData.advName}...';
    });

    final success = await connectToDevice(result);

    setState(() {
      if (success) {
        _statusMessage = 'Connected to ${result.advertisementData.advName}!';
        _isScanning = false;
      } else {
        _statusMessage = 'Failed to connect to ${result.advertisementData.advName}';
        _isScanning = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Scan for Devices'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_statusMessage),
          SizedBox(height: 16),
          if (_isScanning)
            CircularProgressIndicator(),
          if (!_isScanning && _devices.isEmpty)
            Text('No devices found'),
          if (_devices.isNotEmpty)
            SingleChildScrollView(
              child: Column(
                children: _devices.map((device) {
                  return ListTile(
                    title: Text(device.advertisementData.advName ?? 'Unknown Device'),
                    subtitle: Text(device.device.remoteId.toString()),
                    onTap: () async {
                      await startConnecting(device);
                    },
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

Stream<ScanResult> scanDevices({Duration timeout = const Duration(seconds: 10)}) async* {
  await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

  final Set<String> foundDeviceIds = {};

  final StreamController<ScanResult> controller = StreamController<ScanResult>();

  final subscription = FlutterBluePlus.scanResults.listen((results) {
    for (final result in results) {
      final deviceId = result.device.remoteId.toString();

      if (!foundDeviceIds.contains(deviceId)) {
        foundDeviceIds.add(deviceId);
        controller.add(result);
      }
    }
  });

  try {
    await FlutterBluePlus.startScan(withKeywords: ["Bud"]);
    await Future.delayed(Duration(milliseconds: 500));
    yield* controller.stream;
    await Future.delayed(timeout - Duration(milliseconds: 500));
  } finally {
    await FlutterBluePlus.stopScan();
    await subscription.cancel();
    await controller.close();
  }
}

Future<bool> connectToDevice(ScanResult selectedResult) async {
  try {
    await FlutterForegroundTask.saveData(key: 'deviceRemoteId', value: selectedResult.device.remoteId.toString());
    FlutterForegroundTask.sendDataToTask('device');
    return true;
  } catch (e) {
    return false;
  }
}