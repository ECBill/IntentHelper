import 'package:app/extension/context_extension.dart';
import 'package:app/models/login/login_model.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/entry/loading_screen.dart';
import 'package:app/views/login/phone_login_page.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../ui/app_background.dart';
import 'email_login_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  LoginModel loginModel = LoginModel();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: 130.h),
              Image.asset(
                'assets/images/logo.png',
                width: 116.r,
                height: 106.r,
              ),
              SizedBox(height: 17.h),
              Text(
                'B u d d i e',
                style: TextStyle(
                    color: context.isLightMode ? Colors.black : Colors.white,
                    fontSize: 34.sp),
              ),
              const Spacer(),
              _buildLoginButton(
                context,
                'Phone',
                AssetsUtil.icon_login_phone,
                    () {
                  // Navigator.push(
                  //   context,
                  //   MaterialPageRoute(builder: (context) => PhoneLoginPage()),
                  // );
                },
              ),
              SizedBox(height: 8.h),
              _buildLoginButton(
                context,
                'Connect with Google',
                AssetsUtil.icon_login_google,
                    () async {
                  // try {
                  //   await loginModel.signInWithGoogle();
                  //   Navigator.pushReplacement(
                  //     context,
                  //     MaterialPageRoute(builder: (context) => LoadingScreen()),
                  //   );
                  //   print('Google login success');
                  // } catch (e) {
                  //   print('Google login fail: $e');
                  // }
                },
              ),
              SizedBox(height: 8.h),
              _buildLoginButton(
                context,
                'Sign in with Apple',
                AssetsUtil.icon_login_apple,
                    () async {
                  // try {
                  //   await loginModel.signInWithApple();
                  //   Navigator.pushReplacement(
                  //     context,
                  //     MaterialPageRoute(builder: (context) => LoadingScreen()),
                  //   );
                  //   print('Apple login success');
                  // } catch (e) {
                  //   print('Apple login fail: $e');
                  // }
                },
              ),
              SizedBox(height: 8.h),
              _buildLoginButton(
                context,
                'E-Mail',
                AssetsUtil.icon_login_email,
                    () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => EmailLoginPage()),
                  );
                },
              ),
              SizedBox(height: 26.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 22.w),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                        'Continuing to operate means that you have read and agreed to the ',
                        style: TextStyle(
                          color: context.isLightMode
                              ? Colors.black.withAlpha(80)
                              : Colors.white.withAlpha(60),
                        ),
                      ),
                      const TextSpan(
                        text: 'User Agreement',
                        style: TextStyle(
                          color: Color(0xff29BBC6),
                        ),
                      ),
                      TextSpan(
                        text: ' and ',
                        style: TextStyle(
                          color: context.isLightMode
                              ? Colors.black.withAlpha(80)
                              : Colors.white.withAlpha(60),
                        ),
                      ),
                      const TextSpan(
                        text: 'Privacy Policy',
                        style: TextStyle(
                          color: Color(0xff29BBC6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 25.h),
            ],
          ),
        ),
      ),
    );
  }

  bool agree = false;

  Widget _buildLoginButton(
      BuildContext context,
      String text,
      String iconPath,
      VoidCallback onPressed,
      ) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 22.w),
        height: 46.h,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8).r,
            color: Colors.white.withAlpha(context.isLightMode ? 60 : 30),
            border: Border.all(
                color: Colors.white.withAlpha(context.isLightMode ? 100 : 30))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(width: 16.w),
            BudIcon(icon: iconPath, size: 18.r),
            Expanded(
              child: Center(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18.sp,
                    color: context.isLightMode ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
            SizedBox(width: 16.w + 18.r),
          ],
        ),
      ),
    );
  }
}