import 'dart:convert';
import 'dart:io';

import 'package:app/models/record_entity.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/utils/path_provider_utils.dart';
import 'package:app/utils/share_plus_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';

class ExportDataDialog extends StatefulWidget {
  const ExportDataDialog({super.key});

  @override
  State createState() => _ExportDataDialogState();
}

class _ExportDataDialogState extends State<ExportDataDialog> {
  DateTimeRange? _selectedDateRange;
  final TextEditingController _fileNameController = TextEditingController();
  String _fileName = 'exported_data.csv';

  @override
  void initState() {
    super.initState();
    _fileNameController.text = _fileName;
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }

  Future<void> _exportData() async {
    List<RecordEntity>? results;
    if (_selectedDateRange == null) {
      results = ObjectBoxService().getRecords();
    } else {
      results = ObjectBoxService().getRecordsByTimeRange(
        _selectedDateRange!.start.millisecondsSinceEpoch,
        _selectedDateRange!.end.millisecondsSinceEpoch,
      );
    }

    List<List<dynamic>> rows = [];
    rows.add(['Role', 'Content', 'Timestamp']);
    for (var record in results!) {
      rows.add([record.role, record.content, DateTime.fromMillisecondsSinceEpoch(record.createdAt!).toString()]);
    }
    String csvData = const ListToCsvConverter().convert(rows);
    final String path = await PathProviderUtil.getAppSaveDirectory();
    String filePath = '$path/$_fileName';
    if (!filePath.endsWith('.csv')) {
      filePath = '$filePath.csv';
    }

    try {
      File file = File(filePath);
      // 添加 UTF-8 BOM 来确保中文字符正确显示
      List<int> utf8Bom = [0xEF, 0xBB, 0xBF];
      List<int> utf8Data = utf8.encode(csvData);
      List<int> finalData = utf8Bom + utf8Data;

      await file.writeAsBytes(finalData);
      bool success = await SharePlusUtil.shareFile(path: filePath);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File has been saved to: ${file.path}')),
        );
      }
    } catch (e) {
      debugPrint('Error saving CSV file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Data'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Select Date Range'),
              subtitle: _selectedDateRange == null
                  ? const Text('No date range selected')
                  : Text('From ${_selectedDateRange!.start} to ${_selectedDateRange!.end}'),
              onTap: _pickDateRange,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'File Name'),
              controller: _fileNameController,
              onChanged: (value) {
                setState(() {
                  _fileName = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Confirm'),
          onPressed: () async {
            await _exportData();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class ExportLatencyLog extends StatefulWidget {
  const ExportLatencyLog({super.key});

  @override
  State createState() => _ExportLatencyLogState();
}

class _ExportLatencyLogState extends State<ExportLatencyLog> {
  final TextEditingController _fileNameController = TextEditingController();
  String _fileName = 'latency_log.txt';

  @override
  void initState() {
    super.initState();
    _fileNameController.text = _fileName;
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }

  Future<String?> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    return result;
  }

  Future<void> _exportData() async {
    String? path = await _pickDirectory();

    String results;

    final directory = await getApplicationDocumentsDirectory();
    final logFile = File('${directory.path}/latency_report.txt');

    try {
      results = await logFile.readAsString();
    } catch (e) {
      print("Error reading file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e')),
      );
      return;
    }

    if (path != null) {
      String filePath = '$path/$_fileName';
      if (!filePath.endsWith('.txt')) {
        filePath = '$filePath.txt';
      }
      File(filePath).writeAsBytes(utf8.encode(results)).then((file) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File has been saved to: ${file.path}')),
        );
      }).catchError((e) {
        debugPrint('Error saving TXT file: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: $e')),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Latency Log'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'File Name'),
              controller: _fileNameController,
              onChanged: (value) {
                setState(() {
                  _fileName = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: const Text('Confirm'),
          onPressed: () async {
            await _exportData();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
