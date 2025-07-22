import 'package:app/extension/context_extension.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class MembersDialog extends StatefulWidget {
  const MembersDialog({super.key});

  @override
  State<MembersDialog> createState() => _MembersDialogState();

  static show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return const MembersDialog();
      },
    );
  }
}

class _MembersDialogState extends State<MembersDialog> {
  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          color: context.isLightMode ? Colors.white : Colors.black,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(8).r,
            topRight: const Radius.circular(8).r,
          ),
        ),
        child:Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(width: 10.w),
                BudIcon(icon: 'icon_members_close.png',size: 18.r,),
                SizedBox(width: 10.w + 18.r),
              ],
            )
          ],
        )
    );
  }
}