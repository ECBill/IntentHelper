import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../main.dart';
import '../../models/login/login_model.dart';
import '../../utils/toast.dart';

class PhoneRegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<PhoneRegisterPage> {
  LoginModel loginModel = LoginModel();
  TextEditingController _phoneController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;

  @override
  void initState() {
    super.initState();

    // 监听输入框内容变化
    _phoneController.addListener(_validateInput);
    _passwordController.addListener(_validateInput);
  }

  // 输入框内容变化时校验
  void _validateInput() {
    setState(() {
      _isEmailValid = _isValidPhone(_phoneController.text);
      _isPasswordValid = _passwordController.text.length > 6;
    });
  }

  // 校验手机格式
  bool _isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^\+\d{10,15}$');
    return phoneRegex.hasMatch(phone);
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
                child: Icon(Icons.supervisor_account_sharp, size: 30)),
            SizedBox(height: 30.h),
            Row(
              children: [
                SizedBox(width: 10),
                Text('Account Registration', style: TextStyle(fontSize: 24)),
              ],
            ),
            SizedBox(height: 20.h),
            // 邮箱输入框
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _phoneController,
                decoration: InputDecoration(
                  hintText: 'Phone number',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 15.w,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  suffixIcon: _phoneController.text.isNotEmpty
                      ? IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () {
                      _phoneController.clear();
                    },
                  )
                      : null,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            if (!_isEmailValid && _phoneController.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please enter a valid phone number',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            SizedBox(height: 20),
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
                  hintText: 'Password',
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
                  'Password must be longer than 6 characters',
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
                  ? () async {
    // loginModel.verifyPhoneNumber(_phoneController.text);
                // User? user = await loginModel.verifyPhoneNumber(
                //     _phonelController.text);
                // if (user != null) {
                //   showMessage("注册成功");
                //   print("注册成功: ${user.email}");
                //   Navigator.pushReplacement(
                //     context,
                //     MaterialPageRoute(builder: (context) => MyHomePage()),
                //   );
                // }
                // else {
                //   print("注册失败");
                //   showMessage("注册失败");
                // }
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
              child: Text('Register', style: TextStyle(color: Colors.white)),
            ),
            // 用户协议和隐私政策
            Container(
              margin: EdgeInsets.only(top: 10.h),
              child: Text(
                'By continuing, you agree to',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11.sp,
                ),
              ),
            ),
            // 可点击的《用户协议》和《隐私政策》
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    print('User Agreement Clicked');
                  },
                  child: Text(
                    'User Agreement',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11.sp,
                    ),
                  ),
                ),
                Text(
                  ' and ',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    print('Privacy Policy Clicked');
                  },
                  child: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
