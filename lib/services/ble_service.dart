import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:uuid/uuid.dart';

import '../constants/record_constants.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String? deviceName;

  final StreamController<Uint8List> _dataController = StreamController<Uint8List>();
  Stream<Uint8List> get dataStream => _dataController.stream;
  StreamSubscription<List<int>>? _dataSubscription;

  String? get deviceRemoteId => _device?.remoteId.toString();
  BluetoothConnectionState get connectionState => _connectionState;

  Stream<BluetoothConnectionState> get connectionStateStream =>
      _device?.connectionState ?? Stream<BluetoothConnectionState>.empty();

  Timer? _debounceTimer;

  Future<void> init() async {
    var remoteId = await FlutterForegroundTask.getData(key: 'deviceRemoteId');
    if (remoteId != null) {
      _device = BluetoothDevice.fromId(remoteId);
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
      await _device!.connect(autoConnect: true, mtu: null);
      listenToConnectionState();
    }
    if (Platform.isAndroid) {
      PhySupport phySupport = await FlutterBluePlus.getPhySupport();
      print("pwt phy: le2M: ${phySupport.le2M} leCoded: ${phySupport.leCoded}");
    }
  }

  Future<bool> scanAndConnect() async {
    await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
    await FlutterBluePlus.startScan(
      withKeywords: ["Bud"],
      timeout: const Duration(minutes: 1)
    );

    final results = await FlutterBluePlus.scanResults.firstWhere((results) => results.isNotEmpty);

    if (results.isEmpty) return false;

    _device = results.last.device;
    deviceName = results.last.advertisementData.advName;
    await FlutterForegroundTask.saveData(
      key: 'deviceRemoteId', 
      value: _device!.remoteId.toString()
    );

    dev.log('${_device!.remoteId}: ${results.last.advertisementData.advName} found!');
    
    await _device!.connect(autoConnect: true, mtu: null);
    listenToConnectionState();
    return true;
  }

  Future<void> getAndConnect(dynamic remoteId) async {
    if (remoteId != null) {
      _device = BluetoothDevice.fromId(remoteId);
      await _device?.connect(autoConnect: true, mtu: null);
    }
  }

  void listenToConnectionState() {
    String id = Uuid().v4();
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _device?.connectionState.listen((state) async {
      print("Operation ID: $id $state");
      _connectionState = state;

      _debounceTimer?.cancel();
      _debounceTimer = Timer(Duration(milliseconds: 500), () async {
        if (state == BluetoothConnectionState.connected) {
          Future.delayed(Duration(milliseconds: 500));
          FlutterForegroundTask.sendDataToTask(Constants.actionStopMicrophone);
          FlutterForegroundTask.sendDataToMain(
              {
                'connectionState': true,
                'deviceName': _device?.advName,
                'deviceId': _device?.remoteId.toString()
              }
          );
          if (Platform.isAndroid) {
            await _device!.requestMtu(247);
            await _device!.requestConnectionPriority(
              connectionPriorityRequest: ConnectionPriority.high
            );
            await _device!.setPreferredPhy(
              txPhy: Phy.le2m.mask,
              rxPhy: Phy.le2m.mask,
              option: PhyCoding.noPreferred
            );
          } else {
            _device!.mtu.listen((int mtu) {
              debugPrint("BLE MTU: $mtu");
            });
          }

          List<BluetoothService> services = await _device!.discoverServices();

          BluetoothService? service = services.firstWhereOrNull(
                  (service) => service.uuid.toString() == "ae00"
          );
          if (service == null) return;
          dev.log('Service found: ${service.uuid.toString()}');

          var characteristics = service.characteristics;

          BluetoothCharacteristic? chr = characteristics.firstWhereOrNull(
                  (characteristic) => characteristic.uuid.toString() == "ae03"
          );
          if (chr == null) return;

          dev.log('Characteristic found: ${chr.uuid.toString()}');

          await chr.setNotifyValue(true);
          _dataSubscription?.cancel();
          _dataSubscription = chr.onValueReceived.listen((value) {
            _dataController.add(Uint8List.fromList(value));
          });
        } else if (state == BluetoothConnectionState.disconnected) {
          Future.delayed(Duration(milliseconds: 500));
          FlutterForegroundTask.sendDataToTask(Constants.actionStartMicrophone);
          FlutterForegroundTask.sendDataToMain(
              {
                'connectionState': false,
                'deviceName': _device?.advName,
                'deviceId': _device?.remoteId.toString()
              }
          );
          dev.log("${_device!.disconnectReason?.code} ${_device!.disconnectReason?.description}");
        }
      });
    });
  }

  void dispose() {
    _connectionStateSubscription?.cancel();
    _dataController.close();
  }
}
