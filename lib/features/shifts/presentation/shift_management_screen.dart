import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../../core/network/repositories/backoffice_repository.dart';

part 'shift_management_screen_part1.dart';
part 'shift_management_screen_part2.dart';
part 'shift_management_screen_widgets3.dart';

/// MODUL SHIFT KASIR, STRICT BLIND DROP & REKONSILIASI Z-REPORT (`PRD-07` / Gelombang 5)
/// - Strict Blind Drop: server menyembunyikan `expected_cash` bagi kasir non-supervisor
///   selama shift aktif; perhitungan selisih & Z-Report dilakukan 100% di sisi server.
/// - Inline Modal Error Guard pada seluruh dialog/sheet shift & kas laci.
/// - Shimmer Skeleton Loading + CDO Warm Linen (Light / Dark / Outdoor High-Contrast).
class ShiftManagementScreen extends StatefulWidget {
  const ShiftManagementScreen({super.key});

  @override
  State<ShiftManagementScreen> createState() => _ShiftManagementScreenState();
}
