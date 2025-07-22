import 'dart:async';
import 'dart:developer';
import 'package:app/views/entry/loading_screen.dart';
import 'package:app/views/login/phone_register_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../main.dart';
import '../../models/login/login_model.dart';
import '../../utils/toast.dart';

class PhoneLoginPage extends StatefulWidget {
  @override
  _PhoneLoginPageState createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  LoginModel loginModel = LoginModel();
  TextEditingController _phoneController = TextEditingController(text: '+1');
  TextEditingController _codeController = TextEditingController();
  bool _isPasswordValid = false;
  bool _isPhoneValid = false;
  int _countdown = 0; // 倒计时秒数
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // 监听输入框内容变化
    _phoneController.addListener(_validateInput);
    _codeController.addListener(_validateInput);
  }

  // 输入框内容变化时校验
  void _validateInput() {
    setState(() {
      // 校验邮箱是否有效
      _isPhoneValid = _isValidPhone(_phoneController.text);
      // 校验密码是否大于6位
      _isPasswordValid = _codeController.text.length > 6;
    });
  }

// 校验手机号格式
  bool _isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^\+\d{10,15}$');
    return phoneRegex.hasMatch(phone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 设置背景颜色为白色
      appBar: AppBar(
        backgroundColor: Colors.white, // 设置AppBar背景颜色为白色
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          '',
          style: TextStyle(color: Colors.black), // 设置标题颜色为黑色
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                padding: EdgeInsets.symmetric(horizontal: 10.h),
                child: const Icon(Icons.perm_phone_msg,
                    size: 30, color: Colors.black)),
            SizedBox(height: 40.h),
            Row(
              children: [
                SizedBox(height: 10.h),
                Text('Phone Login',
                    style: TextStyle(fontSize: 24.sp, color: Colors.black)),
              ],
            ),
            SizedBox(height: 40.h),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  hintText: 'Phone Login/Register',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14.sp,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  suffixIcon: _phoneController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: () {
                            _phoneController.clear();
                            _phoneController.text = '+1';
                            _phoneController.selection = TextSelection.fromPosition(
                              const TextPosition(offset: 2),
                            );
                          },
                        )
                      : null,
                ),
                keyboardType: TextInputType.number,
              ),
            ),
            // 显示邮箱格式错误提示
            if (!_isPhoneValid && _phoneController.text.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8.0.h),
                child: Text(
                  'Please enter a valid phone number',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            SizedBox(height: 20.h),
            // 验证码输入框 + 发送验证码按钮
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _codeController,
                      decoration: InputDecoration(
                        hintText: 'code',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14.sp,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 12.h),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ),
                SizedBox(
                  height: 10.w,
                  width: 10.w,
                ),
                ElevatedButton(
                  onPressed: (_isPhoneValid && _countdown == 0)
                      ? _startCountdown
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _countdown == 0 ? Colors.black : Colors.grey,
                    minimumSize: Size(80.w, 45.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _countdown > 0 ? '$_countdown s' : 'Get code',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            // 显示密码过短提示
            if (!_isPasswordValid && _codeController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Password length must be greater than 6 characters',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            // 底部按钮
            const Spacer(),
            ElevatedButton(
              onPressed: (_isPhoneValid && _isPasswordValid)
                  ? () {
                      String msg =
                          loginModel.signInWithOTP(_codeController.text) as String;
                      if (msg.isNotEmpty) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => LoadingScreen()),
                        );
                      } else {
                        showMessage("Captcha error, please try again");
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: (_isPhoneValid && _isPasswordValid)
                    ? Colors.black
                    : Colors.grey.shade500,
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(
                backgroundColor:
                    MaterialStateProperty.resolveWith<Color>((states) {
                  if (states.contains(MaterialState.disabled)) {
                    return Colors.grey.shade500;
                  }
                  return (_isPhoneValid && _isPasswordValid)
                      ? Colors.black
                      : Colors.grey.shade500;
                }),
              ),
              child: Text('login', style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  void _startCountdown() {
    // setState(() {
    //   _countdown = 60; 
    // });

    // _timer = Timer.periodic(Duration(seconds: 1), (timer) {
    //   setState(() {
    //     if (_countdown > 0) {
    //       _countdown--;
    //     } else {
    //       _timer?.cancel();
    //     }
    //   });
    // });
    log('Phone number: ${_phoneController.text}');
    loginModel.sendOTP(_phoneController.text);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
