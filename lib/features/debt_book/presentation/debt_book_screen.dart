import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/printer_service.dart';
import '../../../core/hardware/whatsapp_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_connectivity_service.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../pos/bloc/pos_cubit.dart';
import '../../../core/network/repositories/backoffice_repository.dart';

part 'debt_book_parity_modals.dart';

part 'debt_book_screen_part1.dart';
part 'debt_book_screen_part2.dart';
part 'debt_book_screen_widgets3.dart';

/// MODUL BUKU BON UMKM (PIUTANG PELANGGAN + 1-KLIK TAGIH WA) & BIAYA OPERASIONAL (`PRD-07`)
class DebtBookScreen extends StatefulWidget {
  final int initialTab;

  const DebtBookScreen({super.key, this.initialTab = 0});

  @override
  State<DebtBookScreen> createState() => _DebtBookScreenState();
}
