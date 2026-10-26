import 'package:flutter/material.dart';

/// App-wide navigator key. Used by services that trigger navigation without
/// direct build-context access (e.g. opening the selfie capture page).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();