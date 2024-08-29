import 'package:flutter/material.dart';
import 'draw_points_page.dart';
// ignore: unused_import
import 'login.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget
{
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp
    (
        title: "TeamView",
        theme: ThemeData(primarySwatch: Colors.blue, visualDensity: VisualDensity.adaptivePlatformDensity),
        home: Login()
    );
  }
}