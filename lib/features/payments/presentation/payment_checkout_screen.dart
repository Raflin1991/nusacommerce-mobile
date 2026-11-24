import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../pos/utils/pos_financial_calculator.dart';

part 'payment_checkout_screen_part1.dart';
part 'payment_checkout_screen_part2.dart';
part 'payment_checkout_screen_part3.dart';
part 'payment_checkout_screen_part4.dart';
part 'payment_checkout_screen_widgets5.dart';

class _MultiTenderLine {
  String methodCode;
  String methodLabel;
  final TextEditingController amountController;
  final TextEditingController referenceController;
  String subType;

  _MultiTenderLine({
    required this.methodCode,
    required this.methodLabel,
    required double initialAmount,
    String initialSubType = '',
  })  : amountController = TextEditingController(
          text: IdrCurrencyFormatter.format(initialAmount),
        ),
        referenceController = TextEditingController(),
        subType = initialSubType;

  double get amount => IdrCurrencyFormatter.parse(amountController.text);

  void dispose() {
    amountController.dispose();
    referenceController.dispose();
  }
}


/// LAYAR 4 — PEMBAYARAN / CHECKOUT SCREEN
/// OXORA Mobile Enterprise Payment Checkout Screen
class PaymentCheckoutScreen extends StatefulWidget {
  final OfflineDatabase offlineDb;

  const PaymentCheckoutScreen({super.key, required this.offlineDb});

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}
