import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:app/utils/toast.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:http/http.dart' as http;
import 'package:app/config/api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../controllers/auth_controller.dart';

class LoginModel {
  ApiService apiService = ApiService();
  String responseData = '';
  String verificationId = '';
  String lastLogin = '';
  FirebaseAuth auth = FirebaseAuth.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  Future<String?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      return googleAuth.idToken;
    } catch (error) {
      print("Google Sign-In Error: $error");
      return null;
    }
  }

  Future<bool> googleHandleAccountLinking() async {
    String? llmToken =
        await FlutterForegroundTask.getData<String>(key: 'llmToken');
    String? googleIdToken = await signInWithGoogle();
    if (googleIdToken == null) {
      print("Google Sign-In failed");
      showMessage("Google Sign-In failed");
      return false;
    } else {
      bool success =
          await linkAnonymousAccount(llmToken as String, googleIdToken);
      if (success) {
        print("Account successfully linked!");
      } else {
        print("Failed to link account.");
      }
      FlutterForegroundTask.saveData(key: 'lastLogin', value: 'Google');
      return true;
    }
  }

  ///绑定谷歌匿名账户
  Future<bool> linkAnonymousAccount(
      String llmToken, String googleIdToken) async {
    final authController = Get.find<MyAuthController>();
    final authToken =
        await authController.userCredential.value?.user?.getIdToken();
    final response = await http.post(
      Uri.parse('https://token.one-api.bud.inc/'),
      headers: {'Authorization': 'Bearer $authToken'},
      body: jsonEncode({
        'anonymousToken': llmToken,
        'googleIdToken': googleIdToken,
      }),
    );
    if (response.statusCode == 200) {
      return true;
    } else {
      print("Failed to link account: ${response.body}");
      return false;
    }
  }

  Future<void> signInWithApple() async {
    try {
      final AuthorizationCredentialAppleID appleIDCredential =
          await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthCredential credential =
          OAuthProvider('inc.bud.app').credential(
        idToken: appleIDCredential.identityToken,
        accessToken: appleIDCredential.authorizationCode,
      );
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCredential.user;
      if (user != null) {
        FlutterForegroundTask.saveData(key: 'lastLogin', value: 'Apple');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLogin', true);
        print("User is signed in: ${user.displayName}, ${user.email}");
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLogin', false);
      print("Error during Apple sign-in: $e");
    }
  }


  Future<void> signInWithOTP(String smsCode) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      
      final user = auth.currentUser;
      if (user == null || !user.isAnonymous) {
        throw FirebaseAuthException(
          code: 'invalid-user',
          message: 'Only anonymous users can link phone',
        );
      }

      await user.linkWithCredential(credential);
      
      FlutterForegroundTask.saveData(key: 'lastLogin', value: 'Phone');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasLinkedPhone', true);
      print("✅ Phone number linked successfully");
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        print("该手机号已绑定其他账号");
        throw e;
      }
      rethrow;
    }
  }

  void sendOTP(String phoneNumber) async {
    await auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      // Set OTP timeout duration
      verificationCompleted: (PhoneAuthCredential credential) async {
      final user = auth.currentUser;
        log("Verification completed: ${user?.uid}");
        if (user != null && user.isAnonymous) {
          await user.linkWithCredential(credential);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        this.verificationId = verificationId;
        print("❌ Verification failed: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        print("📩 OTP has been sent");
        // codeSentCallback(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        print("⏳ OTP retrieval timed out");
      },
    );
  }

  Future<void> unlinkPhone() async {
    final user = auth.currentUser;
    if (user != null) {
      await user.unlink('phone');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLogin', true);
      await prefs.remove('hasLinkedPhone');
    }
  }
}
