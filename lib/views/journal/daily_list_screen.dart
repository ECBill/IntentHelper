import 'dart:convert';

import 'package:app/controllers/style_controller.dart';
import 'package:app/extension/datetime_extension.dart';
import 'package:app/extension/duration_extension.dart';
import 'package:app/extension/string_extension.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/utils/route_utils.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:app/views/ui/layout/bud_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../ui/bud_expansion_text.dart';

class DailyModel {
  final String recordDateTime;

  DateTime? get datetime => recordDateTime.toDateTime();

  String? get formatRecordString {
    if (datetime == null) return null;
    return '${datetime!.year}-${datetime!.month}-${datetime!.day} ${datetime!.hour}:${datetime!.minute}';
  }

  final int id;
  final String content;
  final String fullContent;

  DailyModel({
    required this.id,
    required this.recordDateTime,
    required this.content,
    required this.fullContent
  });
}

class DailyListScreen extends StatefulWidget {
  const DailyListScreen({super.key});

  @override
  State<DailyListScreen> createState() => _DailyListScreenState();
}

class _DailyListScreenState extends State<DailyListScreen> {
  List<DailyModel> _list = [];
  bool _isMultiSelectMode = false;
  final Set<int> _selectedIndexes = {};

  @override
  void initState() {
    super.initState();
    _initList();
  }

  void _selectItem(int index, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedIndexes.add(index);
      } else {
        _selectedIndexes.remove(index);
      }

      if (_selectedIndexes.isNotEmpty) {
        _isMultiSelectMode = true;
      } else {
        _isMultiSelectMode = false;
      }
    });
  }

  void _deleteSelectedItems() {
    List<int> selectedIds = [];
    setState(() {
      _selectedIndexes.toList()
        ..sort((a, b) => b.compareTo(a))
        ..forEach((index) {
          selectedIds.add(_list[index].id);
          _list.removeAt(index);
        });

      _selectedIndexes.clear();
      _isMultiSelectMode = false;
    });
    ObjectBoxService().deleteSummaries(selectedIds);
  }

  void _cancelSelection() {
    setState(() {
      _selectedIndexes.clear();
      _isMultiSelectMode = false;
    });
  }

  /// Mock
  void _initList() {
    setState(() {
      final results = ObjectBoxService().getDailySummaries();
      _list = results?.map((record) => DailyModel(
          id: record.id,
          recordDateTime: DateTime.fromMillisecondsSinceEpoch(record.startTime).toDateFormatString() ,
          content: record.content!,
          fullContent: record.content!
      )).toList() ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return BudScaffold(
      title: 'Daily',
      body: DailyListView(
        list: _list,
        draggable: true,
        onSelect: _selectItem,
        isMultiSelectMode: _isMultiSelectMode,
        selectedIndexes: _selectedIndexes,
      ),
      bottomNavigationBar: _isMultiSelectMode
          ? BottomAppBar(
              color: Colors.white,
              child: Container(
                height: 20.sp,
                child: Row(
                  children: [
                    Text(
                      '${_selectedIndexes.length} selected',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelSelection,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                    TextButton(
                      onPressed: _deleteSelectedItems,
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class DailyListView extends StatelessWidget {
  final bool shrinkWrap;
  final List<DailyModel> list;
  final Function(int index, bool isSelected) onSelect;
  final bool isMultiSelectMode;
  final Set<int> selectedIndexes;
  final bool draggable;

  const DailyListView({
    super.key,
    this.shrinkWrap = false,
    required this.list,
    required this.draggable,
    required this.onSelect,
    required this.isMultiSelectMode,
    required this.selectedIndexes,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      padding: EdgeInsets.all(16.sp),
      itemCount: list.length,
      separatorBuilder: (context, index) => SizedBox(height: 12.sp),
      itemBuilder: (context, index) {
        DailyModel model = list[index];
        return DraggableListTile(
          isLightMode: Provider.of<ThemeNotifier>(context).mode == Mode.light,
          isMultiSelectMode: isMultiSelectMode,
          isSelected: selectedIndexes.contains(index),
          onSelect: (isSelected) => onSelect(index, isSelected ?? false),
          model: model,
          draggable: draggable,
        );
      },
    );
  }
}

class DraggableListTile extends StatefulWidget {
  final bool isLightMode;
  final bool isMultiSelectMode;
  final bool isSelected;
  final Function(bool)? onSelect;
  final DailyModel model;
  final bool draggable;

  const DraggableListTile({
    super.key,
    required this.isLightMode,
    required this.draggable,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onSelect,
    required this.model,
  });

  @override
  State<DraggableListTile> createState() => _DraggableListTileState();
}

class _DraggableListTileState extends State<DraggableListTile> {
  double _dragOffset = 0.0;
  final double _maxDragOffset = -20.sp;
  bool _isDragged = false;

  bool _isAll = false;

  void _onClickArrow() {
    setState(() {
      _isAll = !_isAll;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(_maxDragOffset, 0);

      if (_dragOffset <= _maxDragOffset * 0.7) {
        _isDragged = true;
      }
    });
  }

  void _onDragStart(DragStartDetails details) {
    _isDragged = false;
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      if (_isDragged) {
        widget.onSelect?.call(!widget.isSelected);
      }

      setState(() {
        _dragOffset = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: widget.draggable ? Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.sp),
            color: widget.isLightMode ? null : const Color(0x33FFFFFF),
            gradient: widget.isLightMode
                ? const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFEDFEFF),
                Color(0xFFFFFFFF),
              ],
            )
                : null,
            boxShadow: [
              widget.isLightMode
                  ? const BoxShadow(
                color: Color(0x172A9ACA),
                offset: Offset(0, 4),
                blurRadius: 9,
              )
                  : const BoxShadow(
                color: Color(0x1AA2EDF3),
                blurRadius: 20,
              ),
            ],
          ),
          child: ListTile(
            trailing: widget.isMultiSelectMode
                ? Icon(
              widget.isSelected
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              color: widget.isSelected ? Colors.blue : Colors.grey,
            )
                : null,
            onTap: widget.isMultiSelectMode
                ? () => widget.onSelect?.call(!widget.isSelected)
                : null,
            title: Text(
              '${widget.model.formatRecordString ?? ''}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
                color: widget.isLightMode ? Colors.black : Colors.white,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BudExpansionText(
                  expanded: _isAll,
                  text: widget.model.content,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: widget.isLightMode
                        ? const Color(0xFF666666)
                        : const Color(0x99FFFFFF),
                  ),
                ),
                SizedBox(height: 8.sp),
                InkWell(
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onTap: _onClickArrow,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _isAll ? 'retract' : 'ALL',
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                          color: isLightMode ? Colors.black : Colors.white,
                        ),
                      ),
                      SizedBox(width: 3.sp),
                      BudIcon(
                        icon: _isAll ? AssetsUtil.icon_arrow_up : AssetsUtil.icon_arrow_down,
                        size: 8.sp,
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      )
      : Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.sp),
          color: widget.isLightMode ? null : const Color(0x33FFFFFF),
          gradient: widget.isLightMode
              ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEDFEFF),
              Color(0xFFFFFFFF),
            ],
          )
              : null,
          boxShadow: [
            widget.isLightMode
                ? const BoxShadow(
              color: Color(0x172A9ACA),
              offset: Offset(0, 4),
              blurRadius: 9,
            )
                : const BoxShadow(
              color: Color(0x1AA2EDF3),
              blurRadius: 20,
            ),
          ],
        ),
        child: ListTile(
          trailing: widget.isMultiSelectMode
              ? Icon(
            widget.isSelected
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: widget.isSelected ? Colors.blue : Colors.grey,
          )
              : null,
          onTap: widget.isMultiSelectMode
              ? () => widget.onSelect?.call(!widget.isSelected)
              : null,
          title: Text(
            '${widget.model.formatRecordString ?? ''}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16.sp,
              color: widget.isLightMode ? Colors.black : Colors.white,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BudExpansionText(
                expanded: _isAll,
                text: widget.model.content,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: widget.isLightMode
                      ? const Color(0xFF666666)
                      : const Color(0x99FFFFFF),
                ),
              ),
              SizedBox(height: 8.sp),
              InkWell(
                onTap: _onClickArrow,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _isAll ? 'retract' : 'ALL',
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: isLightMode ? Colors.black : Colors.white,
                      ),
                    ),
                    SizedBox(width: 3.sp),
                    BudIcon(
                      icon: _isAll ? AssetsUtil.icon_arrow_up : AssetsUtil.icon_arrow_down,
                      size: 8.sp,
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}