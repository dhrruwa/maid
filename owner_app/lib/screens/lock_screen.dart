import 'package:flutter/material.dart';

import '../core/device.dart';
import '../widgets/pin_pad.dart';

class LockScreen extends StatelessWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PinPad(
          title: 'Enter PIN',
          subtitle: 'Owner',
          onCompleted: (pin) async {
            if (!Device.checkPin(pin)) return false;
            onUnlocked();
            return true;
          },
        ),
      ),
    );
  }
}
