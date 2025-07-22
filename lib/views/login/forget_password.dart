import 'package:app/controllers/auth_controller.dart';
import 'package:app/main.dart';
import 'package:app/views/entry/loading_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../models/login/login_model.dart';
import '../../utils/toast.dart';

class ForgotPasswordPage extends StatefulWidget {
  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;
  FirebaseAuth auth = FirebaseAuth.instance;
  LoginModel loginModel = LoginModel();
  final authController = Get.find<MyAuthController>();

  @override
  void initState() {
    super.initState();

    // 监听输入框内容变化
    _emailController.addListener(_validateInput);
    _passwordController.addListener(_validateInput);
  }

  // 输入框内容变化时校验
  void _validateInput() {
    setState(() {
      _isEmailValid = _isValidEmail(_emailController.text);
      _isPasswordValid = _passwordController.text.length > 6;
    });
  }

  // 校验邮箱格式
  bool _isValidEmail(String email) {
    // 使用正则表达式进行邮箱格式校验
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  //邮箱忘记密码
  void _resetPassword() async {
    try {
      await auth.sendPasswordResetEmail(email: _emailController.text.trim());
      showMessage('Password reset email has been sent. Please check your inbox.');
    } catch (e) {
      showMessage("Error: ${e.toString()}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.lock, size: 30)),
            SizedBox(height: 30.h),
            Row(
              children: [
                SizedBox(width: 10),
                Text('Forgot Password', style: TextStyle(fontSize: 24)),
              ],
            ),
            SizedBox(height: 20.h),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Please enter your email address below',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12.sp,
                ),
              ),
            ),
            // 邮箱输入框
            Row(
              children: [
                Expanded(
                    child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'Email Address',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 15.w,
                      ),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      suffixIcon: _emailController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close),
                              onPressed: () {
                                _emailController.clear();
                              },
                            )
                          : null,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                )),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    _resetPassword();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isEmailValid ? Colors.black87 : Colors.grey,
                    minimumSize: Size(100, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Send',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            if (!_isEmailValid && _emailController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please enter a valid email address',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Enter new password',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12.sp,
                ),
              ),
            ),
            // 密码输入框
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _passwordController,
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                  hintText: 'Enter new password',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15.sp,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                  ),
                ),
                keyboardType: TextInputType.text,
              ),
            ),
            // 显示密码过短提示
            if (!_isPasswordValid && _passwordController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please enter a valid email address',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            // 底部按钮
            Spacer(),
            ElevatedButton(
              onPressed: (_isEmailValid && _isPasswordValid)
                  ? () async{
                      String? msg = await authController.signInWithEmail(
                        _emailController.text,
                        _passwordController.text,
                      );
                      if (msg != null && msg.isNotEmpty) {
                        showMessage(msg);
                      } else {
                        showMessage("Sign-in successful");
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoadingScreen()),
                        );
                      }
                      authController.signInWithEmail(
                          _emailController.text, _passwordController.text);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: (_isEmailValid && _isPasswordValid)
                    ? Colors.black
                    : Colors.grey.shade500,
                minimumSize: Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10), // 设置圆角
                ),
              ).copyWith(
                // 为禁用状态设置背景颜色
                backgroundColor:
                    MaterialStateProperty.resolveWith<Color>((states) {
                  if (states.contains(MaterialState.disabled)) {
                    return Colors.grey.shade500;
                  }
                  return (_isEmailValid && _isPasswordValid)
                      ? Colors.black
                      : Colors.grey.shade500;
                }),
              ),
              child: Text('Setting', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
