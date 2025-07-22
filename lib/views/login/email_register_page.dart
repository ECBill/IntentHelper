import 'package:app/controllers/auth_controller.dart';
import 'package:app/views/entry/loading_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../main.dart';
import '../../models/login/login_model.dart';
import '../../utils/toast.dart';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final authController = Get.find<MyAuthController>();
  LoginModel loginModel = LoginModel();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;

  @override
  void initState() {
    super.initState();

    _emailController.addListener(_validateInput);
    _passwordController.addListener(_validateInput);
  }

  void _validateInput() {
    setState(() {
      _isEmailValid = _isValidEmail(_emailController.text);
      _isPasswordValid = _passwordController.text.length > 6;
    });
  }

  bool _isValidEmail(String email) {
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
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
                Text('Register', style: TextStyle(fontSize: 24)),
              ],
            ),
            SizedBox(height: 20.h),
            Container(
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

            SizedBox(height: 80.h),
            ElevatedButton(
              onPressed: (_isEmailValid && _isPasswordValid)
                  ? () async {
                      String? mas = await authController.linkWithEmailPassword(
                          _emailController.text, _passwordController.text);
                      if (mas != null) {
                        showMessage("Registration successful");
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoadingScreen()),
                        );
                      } else {
                        showMessage(mas??'Registration failed');
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: (_isEmailValid && _isPasswordValid)
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
                  return (_isEmailValid && _isPasswordValid)
                      ? Colors.black
                      : Colors.grey.shade500;
                }),
              ),
              child: Text('Register', style: TextStyle(color: Colors.white)),
            ),
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
