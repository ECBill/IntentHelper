import 'dart:convert';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


class MyAuthController extends GetxController {
  Rx<UserCredential?> userCredential = Rx<UserCredential?>(null);

  Future<void> signIn() async {
    if (FirebaseAuth.instance.currentUser == null) {
      await signInAnonymously();
    }
  }

  Future<void> signInAnonymously() async {
    userCredential.value = await FirebaseAuth.instance.signInAnonymously();
    try {
      log("Signed in with temporary account: ${userCredential.value?.user?.uid}");
    } on FirebaseAuthException catch (e) {
      log("Unknown error: ${e.code} ${e.message}");
    }
  }

  Future<String?> signInWithEmail(String email, String password) async {
    print("📩 Email: ${email}");
    print("🔑 Password: ${password}");
    try {
      await FirebaseAuth.instance.signOut();
      userCredential.value = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      // User? user = FirebaseAuth.instance.currentUser;
      // if (user != null) {
      //   await linkWithEmailPassword(email, password);
      // }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLogin', true);
      return null;
    } on FirebaseAuthException catch (e) {
      log("Login failed: ${e.code} ${e.message}");
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLogin', false);
      if (e.code == 'user-not-found') {
        return "❌ User not found. Please register first.";
      } else if (e.code == 'wrong-password') {
        return "❌ Incorrect password. Please try again.";
      } else if (e.code == 'invalid-email') {
        return "⚠️ Please enter a valid email address.";
      } else if (e.code == 'user-disabled') {
        return "🚫 This account has been disabled.";
      } else if (e.code == 'too-many-requests') {
        return "⏳ Too many attempts. Please try again later.";
      } else {
        return "❌ Login failed: ${e.message}";
      }
    } catch (e) {
      return "⚠️ Unknown error: $e";
    } 
  }


  Future<String?> linkWithEmailPassword(String email, String password) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.isAnonymous) {
        throw FirebaseAuthException(
          code: 'invalid-user',
          message: 'Only anonymous users can link email',
        );
      }

      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      userCredential.value = await user.linkWithCredential(credential);
      final uid = userCredential.value?.user?.uid;

      FlutterForegroundTask.saveData(key: 'email', value: email);
      FlutterForegroundTask.saveData(key: 'lastLogin', value: 'Email');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLogin', true);

      print("Linking successful. New user ID: $uid");
      return uid;
    } on FirebaseAuthException catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLogin', false);
      if (e.code == 'email-already-in-use') {
        print("Linking failed: $e");
      } else {
        print("Failed to register: ${e.message}");
      }
      return e.message;
    }
  }

  Future<Map<String, dynamic>> fetchLlmToken() async {
    final authToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http.get(
      Uri.parse('https://api.one-api.bud.inc/?action=getToken'),
      headers: {'Authorization': 'Bearer $authToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data.containsKey('token')) {
        log("Retrieved Llm token: ${data['token']}");
        return data['token'];
      }
    }
    throw Exception("Failed to retrieve Llm token.");
  }
}
