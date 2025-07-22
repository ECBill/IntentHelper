import 'dart:developer' as dev;
import 'package:app/constants/voice_constants.dart';
import 'package:flutter/material.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../constants/record_constants.dart';
import '../services/objectbox_service.dart';


class SettingScreenController {
  State? _state;

  bool isSwitchEnabled = true;
  final ObjectBoxService _objectBoxService = ObjectBoxService();

  @mustCallSuper
  void detach() {
    _state = null;
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskAction);
  }

  @mustCallSuper
  void dispose() {
    detach();
  }

  Future<void> resetVoiceprint() async {
    _objectBoxService.deleteAllSpeakers();
    FlutterForegroundTask.sendDataToMain({'isRecording': true});
    FlutterForegroundTask.sendDataToTask(voice_constants.voiceprintStart);
  }

  void resetDevice() async {
    FlutterForegroundTask.removeData(key: 'deviceRemoteId');
    FlutterForegroundTask.sendDataToMain({'action': 'deviceReset'});
  }

  void _onReceiveTaskAction(dynamic data) {
    dev.log('Received task data: $data');
    if (data == Constants.actionDone) {
      _state?.setState(() {
        isSwitchEnabled = true;
      });
    }
  }
}
