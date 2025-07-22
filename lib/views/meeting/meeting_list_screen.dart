import 'dart:convert';
import 'package:app/models/summary_entity.dart';
import 'package:app/services/objectbox_service.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/meeting/components/meeting_list_view.dart';
import 'package:app/views/ui/bud_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';

import 'model/meeting_model.dart';

class MeetingListScreen extends StatefulWidget {
  const MeetingListScreen({super.key});

  @override
  State<MeetingListScreen> createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends State<MeetingListScreen> {
  List<MeetingModel> _list = [];
  bool _isMultiSelectMode = false;
  final Set<int> _selectedIndexes = {};

  /// search
  final TextEditingController _searchController = TextEditingController();
  bool _onSearch = false;
  final List<MeetingModel> _searchResultList = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      _isMultiSelectMode = _selectedIndexes.isNotEmpty;
    });
  }

  void _deleteSelectedItems() {
    List<int> selectedIds = [];
    setState(() {
      _selectedIndexes.toList()
        ..sort((a, b) => b.compareTo(a))
        ..forEach((index) {
          if (_onSearch) {
            selectedIds.add(_searchResultList[index].id);
            _searchResultList.removeAt(index);
          } else {
            selectedIds.add(_list[index].id);
            _list.removeAt(index);
          }
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

  void _initList() {
    setState(() {
      final results = ObjectBoxService().getMeetingSummaries();
      _list = results?.map<MeetingModel>((SummaryEntity record) {
        MeetingModel model = MeetingModel(
          id: record.id,
          content: jsonDecode(record.content!)['abstract'],
          startTime: record.startTime,
          endTime: record.endTime,
          createdAt: record.createdAt,
          fullContent: record.content!,
          title: record.title,
          audioPath: record.audioPath,
        );
        return model;
      }).toList() ??
          [];
    });
  }

  void _onSearchSubmitted(String query) {
    setState(() {
      if (query.isNotEmpty) {
        _onSearch = true;

        /// TODO: search
      } else {
        _onSearch = false;
        _searchResultList.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardDismisser(
      child: Scaffold(
        body: AppBackground(
          child: ListView(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: 16.sp,
                  left: 16.sp,
                  right: 16.sp,
                ),
                child: BudSearchBar(
                  controller: _searchController,
                  onTapLeading: () => {
                    _onSearch
                        ? setState(() {
                            _onSearch = !_onSearch;
                            _searchController.clear();
                          })
                        : context.pop()
                  },
                  leadingIcon: AssetsUtil.icon_arrow_back,
                  trailingIcon: AssetsUtil.icon_search,
                  hintText: 'Search meetings',
                  onSubmitted: _onSearchSubmitted,
                ),
              ),
              MeetingListView(
                shrinkWrap: true,
                list: _onSearch ? _searchResultList : _list,
                onSelect: _selectItem,
                isMultiSelectMode: _isMultiSelectMode,
                selectedIndexes: _selectedIndexes,
                onRefresh: () {
                  setState(() {
                    _initList();
                  });
                },
              )
            ],
          ),
        ),
        bottomNavigationBar: _isMultiSelectMode
            ? BottomAppBar(
                color: Colors.white,
                child: SizedBox(
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
      ),
    );
  }
}
