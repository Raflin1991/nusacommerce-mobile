import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/voice_input_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';

class CopilotMessage {
  final String role; // 'user' | 'model'
  final String text;
  final String? engineMode;
  final String? inputMode;
  final int tokensUsed;
  final bool cacheHit;
  final String avatarState;
  final DateTime timestamp;

  const CopilotMessage({
    required this.role,
    required this.text,
    this.engineMode,
    this.inputMode,
    this.tokensUsed = 0,
    this.cacheHit = false,
    this.avatarState = 'idle',
    required this.timestamp,
  });
}

/// Opens the OXORA Copilot AI Mobile Bottom Sheet (Chat + Voice Input, RBAC-Scoped).
Future<void> showNusaCopilotSheet(
  BuildContext context, {
  MobileWorkspaceRole? workspace,
  NusaVoiceInputService? voiceService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withOpacity(0.42),
    builder: (ctx) => NusaCopilotSheet(
      workspace: workspace,
      voiceService: voiceService,
    ),
  );
}

class NusaCopilotSheet extends StatefulWidget {
  final MobileWorkspaceRole? workspace;
  final NusaVoiceInputService? voiceService;

  const NusaCopilotSheet({
    super.key,
    this.workspace,
    this.voiceService,
  });

  @override
  State<NusaCopilotSheet> createState() => _NusaCopilotSheetState();
}

class _NusaCopilotSheetState extends State<NusaCopilotSheet> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final List<CopilotMessage> _messages = [];

  late final NusaVoiceInputService _voiceService;
  late String _sessionId;
  bool _sending = false;
  bool _listeningVoice = false;
  bool _showVoiceFallbackStrip = false;
  String? _voiceNotice;
  String? _modalError;
  String? _engineNotice;
  String _activeEngineMode = 'gemini_v2';
  String _avatarState = 'greeting';
  String _postSuccessAvatarState = 'idle';
  List<({String label, String prompt})> _followUpChips = const [];

  @override
  void initState() {
    super.initState();
    _voiceService = widget.voiceService ?? NusaVoiceInputService();
    _sessionId = _newSessionId();
  }

  String _newSessionId() => 'mobile-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  MobileWorkspaceRole _resolvedWorkspace(AuthSessionModel session) {
    return MobileWorkspaceResolver.sanitizeActiveWorkspace(session, widget.workspace);
  }

  List<(String label, String prompt)> _quickPrompts(MobileWorkspaceRole ws) {
    switch (ws) {
      case MobileWorkspaceRole.ownerPulse:
        return const [
          ('Ringkas Omzet & Laba', 'Ringkas omzet, laba kotor, dan kondisi cabang hari ini.'),
          ('Omzet Minggu & Bulan Ini', 'Bagaimana omzet minggu ini dan bulan ini dibandingkan periode sebelumnya?'),
          ('Stok Kritis', 'Produk apa saja yang stoknya kritis dan perlu segera di-restock?'),
          ('Approval & Tugas', 'Apakah ada persetujuan Maker-Checker atau tugas prioritas yang menunggu?'),
        ];
      case MobileWorkspaceRole.managerDesk:
        return const [
          ('Ringkas Cabang', 'Ringkas operasional cabang dan penjualan hari ini.'),
          ('Omzet Minggu Ini', 'Berapa omzet dan total transaksi cabang minggu ini?'),
          ('Antrean Approval', 'Apakah ada persetujuan atau tugas terbuka yang perlu ditindaklanjuti?'),
          ('Cek Stok Menipis', 'Produk apa saja yang stoknya di bawah batas reorder?'),
        ];
      case MobileWorkspaceRole.posFastLane:
        return const [
          ('Transaksi Saya', 'Berapa transaksi selesai saya hari ini di cabang ini?'),
          ('Cek Stok Cabang', 'Produk apa yang stoknya mulai menipis hari ini?'),
          ('Tugas Kasir', 'Apa saja tugas operasional yang perlu saya selesaikan hari ini?'),
        ];
      case MobileWorkspaceRole.warehouseWorkbench:
        return const [
          ('Stok Kritis & Reorder', 'Daftar produk stok kritis yang perlu segera di-restock atau opname.'),
          ('Status Inventori', 'Ringkas jumlah produk aktif dan kondisi stok gudang hari ini.'),
          ('Tugas Gudang', 'Apa saja tugas gudang atau transfer yang masih terbuka?'),
        ];
      case MobileWorkspaceRole.employeeEss:
        return const [
          ('Tugas Saya Hari Ini', 'Apa saja tugas operasional prioritas saya hari ini?'),
          ('Ringkas Operasional', 'Ringkas informasi operasional cabang yang relevan untuk saya.'),
        ];
    }
  }

  Future<void> _handleVoiceTap() async {
    if (_sending || _listeningVoice) return;
    setState(() {
      _listeningVoice = true;
      _avatarState = 'thinking';
      _voiceNotice = 'Mendengarkan suara (Bahasa Indonesia)...';
      _modalError = null;
    });

    final result = await _voiceService.listenOnce(locale: 'id-ID');
    if (!mounted) return;

    if (result.transcript != null && result.transcript!.trim().isNotEmpty) {
      setState(() {
        _listeningVoice = false;
        _showVoiceFallbackStrip = false;
        _voiceNotice = null;
        _inputCtrl.text = result.transcript!.trim();
      });
      await _sendMessage(result.transcript!.trim(), inputMode: 'voice');
      return;
    }

    setState(() {
      _listeningVoice = false;
      _avatarState = 'idle';
      _showVoiceFallbackStrip = true;
      _voiceNotice = result.infoMessage ??
          'Pilih perintah suara cepat di bawah atau ketik pertanyaan Anda.';
    });
  }

  Future<void> _sendMessage(String rawText, {String inputMode = 'text'}) async {
    final text = rawText.trim();
    if (text.isEmpty || _sending) return;

    final session = context.read<AuthCubit>().state.session;

    setState(() {
      _sending = true;
      _avatarState = 'thinking';
      _modalError = null;
      _showVoiceFallbackStrip = false;
      _voiceNotice = null;
      _inputCtrl.clear();
      _messages.add(
        CopilotMessage(
          role: 'user',
          text: text,
          inputMode: inputMode,
          timestamp: DateTime.now(),
        ),
      );
    });
    _scrollToBottom();

    if (session.isLocalTrial) {
      final reply = _buildLocalTrialReply(session, text);
      if (!mounted) return;
      setState(() {
        _activeEngineMode = 'local_offline';
        _postSuccessAvatarState = 'idle';
        _avatarState = 'success';
        _engineNotice = 'Mode Toko Mandiri (Offline Lokal) — menggunakan data perangkat ini.';
        _messages.add(
          CopilotMessage(
            role: 'model',
            text: reply,
            engineMode: 'local_offline',
            timestamp: DateTime.now(),
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final api = GetIt.instance<ApiClient>();
      final workspace = _resolvedWorkspace(session);
      final historyPayload = _messages
          .take(_messages.length > 1 ? _messages.length - 1 : 0)
          .toList()
          .reversed
          .take(6)
          .toList()
          .reversed
          .map((m) => {'role': m.role, 'text': m.text})
          .toList();

      final res = await api.dio.post(
        ApiEndpoints.copilotChat,
        data: {
          'message': text,
          'input_mode': inputMode,
          'session_id': _sessionId,
          'workspace': workspace.name,
          if (historyPayload.isNotEmpty) 'history': historyPayload,
        },
      );

      final body = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
      if (body['success'] != true) {
        final msg = (body['message'] ?? 'OXORA Copilot tidak dapat memproses permintaan.').toString();
        if (!mounted) return;
        setState(() {
          _modalError = msg;
          _avatarState = 'guard';
          _sending = false;
        });
        return;
      }

      final data = Map<String, dynamic>.from((body['data'] as Map?) ?? {});
      final reply = (data['reply'] ?? '').toString().trim();
      final engineMode = (data['engine_mode'] ?? data['provider'] ?? 'gemini_v2').toString();
      final notice = data['notice']?.toString();
      final tokensUsed = (data['tokens_used'] as num?)?.toInt() ?? 0;
      final cacheHit = data['cache_hit'] == true ||
          engineMode == 'semantic_cache' ||
          engineMode == 'faq_zero_token';
      final serverAvatarState = (data['avatar_state'] ?? (cacheHit ? 'guiding' : 'idle')).toString();
      final resolvedPostState = serverAvatarState == 'guiding' ? 'guiding' : 'idle';
      final parsedChips = _parseFollowUpChips(data['follow_up_chips'] ?? data['suggestions']);
      final serverSessionId = data['session_id']?.toString().trim();

      if (!mounted) return;
      setState(() {
        if (serverSessionId != null && serverSessionId.isNotEmpty) {
          _sessionId = serverSessionId;
        }
        _activeEngineMode = engineMode;
        _postSuccessAvatarState = resolvedPostState;
        _avatarState = 'success';
        _engineNotice = (notice != null && notice.trim().isNotEmpty) ? notice.trim() : null;
        _followUpChips = parsedChips;
        _messages.add(
          CopilotMessage(
            role: 'model',
            text: reply.isEmpty
                ? 'OXORA Copilot tidak menerima jawaban dari server. Coba ulangi pertanyaan Anda.'
                : reply,
            engineMode: engineMode,
            tokensUsed: tokensUsed,
            cacheHit: cacheHit,
            avatarState: resolvedPostState,
            timestamp: DateTime.now(),
          ),
        );
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      final isOffline = ApiClient.isNetworkOfflineError(e);
      setState(() {
        _modalError = isOffline
            ? 'Koneksi internet terputus. OXORA Copilot Cloud membutuhkan koneksi aktif.'
            : ApiClient.extractErrorMessage(e);
        _avatarState = 'guard';
        _sending = false;
      });
    }
  }

  List<({String label, String prompt})> _parseFollowUpChips(dynamic raw) {
    if (raw is! List) return const [];
    final chips = <({String label, String prompt})>[];
    for (final item in raw) {
      if (item is Map) {
        final label = (item['label'] ?? item['title'] ?? '').toString().trim();
        final prompt = (item['prompt'] ?? item['query'] ?? label).toString().trim();
        if (label.isNotEmpty && prompt.isNotEmpty) {
          chips.add((label: label, prompt: prompt));
        }
      } else if (item is String && item.trim().isNotEmpty) {
        final text = item.trim();
        chips.add((label: text, prompt: text));
      }
      if (chips.length >= 4) break;
    }
    return chips;
  }

  String _buildLocalTrialReply(AuthSessionModel session, String prompt) {
    final db = GetIt.instance.isRegistered<OfflineDatabase>()
        ? GetIt.instance<OfflineDatabase>()
        : null;
    if (db == null) {
      return '**OXORA Copilot Lokal** — Mode Mandiri aktif pada ${session.activeStore.name}.';
    }
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final todayRep = db.computeLocalBusinessReport(startDate: todayStart, endDate: now);
    final weekRep = db.computeLocalBusinessReport(startDate: weekStart, endDate: now);
    final monthRep = db.computeLocalBusinessReport(startDate: monthStart, endDate: now);

    final todayNet = (todayRep['net_sales'] as num?)?.toDouble() ?? 0;
    final todayTx = (todayRep['transactions_count'] as num?)?.toInt() ?? 0;
    final weekNet = (weekRep['net_sales'] as num?)?.toDouble() ?? 0;
    final weekTx = (weekRep['transactions_count'] as num?)?.toInt() ?? 0;
    final monthNet = (monthRep['net_sales'] as num?)?.toDouble() ?? 0;
    final monthTx = (monthRep['transactions_count'] as num?)?.toInt() ?? 0;
    final lowStock = (todayRep['low_stock_count'] as num?)?.toInt() ?? 0;

    return '**OXORA Copilot Lokal — ${session.activeStore.name}**\n'
        '- Omzet Hari Ini: **${IdrCurrencyFormatter.format(todayNet)}** ($todayTx transaksi)\n'
        '- Omzet Minggu Ini (WTD): **${IdrCurrencyFormatter.format(weekNet)}** ($weekTx transaksi)\n'
        '- Omzet Bulan Ini (MTD): **${IdrCurrencyFormatter.format(monthNet)}** ($monthTx transaksi)\n'
        '- Produk Stok Menipis: **$lowStock SKU**\n'
        '*(Hubungkan Akun Cloud untuk penalaran Gemini AI penuh & sinkronisasi multi-cabang)*';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final session = context.watch<AuthCubit>().state.session;
    final workspace = _resolvedWorkspace(session);
    final wsSpec = MobileWorkspaceResolver.specFor(workspace);
    final prompts = _quickPrompts(workspace);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final isCompactHeight = viewportHeight <= 680;
    final double cardTopPadding = isCompactHeight ? 84.0 : 106.0;
    final double baseMascotSize = isCompactHeight ? 104.0 : 126.0;
    final double activeMascotSize =
        _avatarState == 'thinking' ? (baseMascotSize + 18.0) : baseMascotSize;
    final double overlapOnCard = _avatarState == 'thinking' ? 18.0 : 14.0;
    final double mascotTopOffset =
        (cardTopPadding - activeMascotSize + overlapOnCard).clamp(0.0, cardTopPadding);

    final String statusLine = switch (_avatarState) {
      'greeting' => 'Halo! OXORA Buddy siap membantu Anda',
      'thinking' => 'Sedang mengetik & menyiapkan jawaban...',
      'success' => 'Jawaban siap! Ada lagi yang bisa dibantu?',
      _ =>
        '${session.activeStore.name.isEmpty ? 'Cabang Aktif' : session.activeStore.name} • RBAC Aman (${session.userRole.isEmpty ? 'Operator' : session.userRole})',
    };

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: isCompactHeight ? 0.90 : 0.88,
        minChildSize: 0.60,
        maxChildSize: 0.96,
        builder: (ctx, _) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // Rounded Chat Sheet Card (leaves clean transparent sky above for perched 3D OXORA Buddy)
            Padding(
              padding: EdgeInsets.only(top: cardTopPadding),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(tokens.isDark ? 0.45 : 0.14),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Subtle top spacing below perched paws / desk rim
                    SizedBox(height: isCompactHeight ? 14 : 18),
                    // Clean Spacious Header (no cramped avatar circle!)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'OXORA Buddy',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    NusaBadge(
                                      label: wsSpec.shortTitle,
                                      variant: NusaBadgeVariant.primary,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  statusLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _avatarState == 'thinking'
                                        ? tokens.accent
                                        : tokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_messages.isNotEmpty)
                            IconButton(
                              tooltip: 'Bersihkan percakapan',
                              onPressed: _sending
                                  ? null
                                  : () => setState(() {
                                        _messages.clear();
                                        _followUpChips = const [];
                                        _sessionId = _newSessionId();
                                        _modalError = null;
                                        _engineNotice = null;
                                        _avatarState = 'idle';
                                      }),
                              icon: Icon(Icons.delete_sweep_outlined, color: tokens.textSecondary),
                            ),
                          IconButton(
                            tooltip: 'Tutup OXORA Copilot',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(Icons.close_rounded, color: tokens.textPrimary),
                          ),
                        ],
                      ),
                    ),
              Divider(height: 1, color: tokens.borderSubtle),

              if (_engineNotice != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  color: tokens.bgElevated,
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: tokens.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _engineNotice!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Transcript / Empty Prompt Launcher
              Expanded(
                child: _messages.isEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: tokens.bgElevated,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: tokens.borderSubtle,
                                  width: tokens.borderWidth,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Asisten Operasional Berbasis Data Cabang',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: tokens.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tanyakan via ketik atau tombol mikrofon. Seluruh jawaban dibatasi ketat sesuai hak akses peran ${wsSpec.title}.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: tokens.textSecondary,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'PERTANYAAN CEPAT (${wsSpec.title.toUpperCase()})',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: prompts
                                  .map(
                                    (p) => NusaPillFilter(
                                      label: p.$1,
                                      icon: Icons.auto_awesome_outlined,
                                      selected: false,
                                      onTap: () => _sendMessage(p.$2),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (ctx, idx) {
                          if (_sending && idx == _messages.length) {
                            return _buildThinkingBubble(tokens);
                          }
                          return _buildMessageBubble(tokens, _messages[idx]);
                        },
                      ),
              ),

              // Voice listening or fallback strip
              if (_listeningVoice || _showVoiceFallbackStrip)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: tokens.accentSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: tokens.accent.withOpacity(tokens.isHighContrast ? 1.0 : 0.45),
                      width: tokens.borderWidth,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _listeningVoice ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                            size: 18,
                            color: tokens.accentDark,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _voiceNotice ?? 'Mode Input Suara Aktif',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: tokens.textPrimary,
                              ),
                            ),
                          ),
                          if (!_listeningVoice)
                            InkWell(
                              onTap: () => setState(() {
                                _showVoiceFallbackStrip = false;
                                _voiceNotice = null;
                              }),
                              child: Icon(Icons.close_rounded, size: 16, color: tokens.textSecondary),
                            ),
                        ],
                      ),
                      if (_showVoiceFallbackStrip) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: prompts
                              .map(
                                (p) => NusaPillFilter(
                                  label: '🎙 ${p.$1}',
                                  selected: false,
                                  onTap: () => _sendMessage(p.$2, inputMode: 'voice'),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

              // Follow-up suggestion chips from Unified AI Brain (rendered after assistant replies)
              if (!_sending && _messages.isNotEmpty && _followUpChips.isNotEmpty)
                Container(
                  key: const Key('copilot_followup_chips'),
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < _followUpChips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          NusaPillFilter(
                            label: _followUpChips[i].label,
                            icon: Icons.auto_awesome_outlined,
                            selected: false,
                            onTap: () => _sendMessage(_followUpChips[i].prompt),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // MANDATORY INLINE MODAL ERROR BANNER (Directly above composer/submit button)
              if (_modalError != null)
                Container(
                  key: const Key('copilot_inline_error'),
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.dangerSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: tokens.danger,
                      width: tokens.isHighContrast ? 1.8 : 1.0,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, color: tokens.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _modalError!,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: tokens.danger,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _modalError = null),
                        child: Icon(Icons.close_rounded, size: 16, color: tokens.danger),
                      ),
                    ],
                  ),
                ),

              // Composer bar (Thumb-zone friendly, >= 48dp buttons)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(top: BorderSide(color: tokens.borderSubtle, width: tokens.borderWidth)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Material(
                        color: _listeningVoice ? tokens.accent : tokens.bgElevated,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                          side: BorderSide(
                            color: _listeningVoice ? tokens.accent : tokens.borderSubtle,
                            width: tokens.borderWidth,
                          ),
                        ),
                        child: InkWell(
                          key: const Key('copilot_voice_button'),
                          borderRadius: BorderRadius.circular(13),
                          onTap: _sending ? null : _handleVoiceTap,
                          child: Icon(
                            _listeningVoice ? Icons.mic_rounded : Icons.mic_none_rounded,
                            color: _listeningVoice ? Colors.white : tokens.textPrimary,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const Key('copilot_text_input'),
                        controller: _inputCtrl,
                        enabled: !_sending,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (v) => _sendMessage(v),
                        style: TextStyle(fontSize: 13.5, color: tokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Tanya OXORA Buddy (omzet, stok, tugas)...',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          fillColor: tokens.bgElevated,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Material(
                        color: _sending ? tokens.borderDefault : tokens.accent,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          key: const Key('copilot_send_button'),
                          borderRadius: BorderRadius.circular(13),
                          onTap: _sending ? null : () => _sendMessage(_inputCtrl.text),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
                  ],
                ),
              ),
            ),

            // Large Free-Floating 3D Animated OXORA Buddy Perched Directly ON TOP of the Chat Card!
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              top: mascotTopOffset,
              child: _NusaBuddyMascot(
                key: const Key('copilot_nusa_buddy_mascot'),
                state: _avatarState,
                size: activeMascotSize,
                onGreetingComplete: () {
                  if (mounted && _avatarState == 'greeting') {
                    setState(() => _avatarState = 'idle');
                  }
                },
                onSuccessComplete: () {
                  if (mounted && _avatarState == 'success') {
                    setState(() => _avatarState = _postSuccessAvatarState);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkingBubble(NusaThemeTokens tokens) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 48),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.bgElevated,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NusaShimmerBox(width: 170, height: 12, borderRadius: 6),
            SizedBox(height: 7),
            NusaShimmerBox(width: 220, height: 12, borderRadius: 6),
            SizedBox(height: 7),
            NusaShimmerBox(width: 130, height: 12, borderRadius: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(NusaThemeTokens tokens, CopilotMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 10,
          left: isUser ? 44 : 0,
          right: isUser ? 0 : 28,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? tokens.accent : tokens.bgElevated,
          borderRadius: BorderRadius.circular(14),
          border: isUser
              ? null
              : Border.all(color: tokens.borderSubtle, width: tokens.borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUser && msg.inputMode == 'voice')
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, size: 12, color: Colors.white70),
                    SizedBox(width: 4),
                    Text(
                      'Input Suara',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            _FormattedCopilotText(
              text: msg.text,
              baseStyle: TextStyle(
                fontSize: 13,
                height: 1.42,
                color: isUser ? Colors.white : tokens.textPrimary,
                fontWeight: isUser ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (!isUser) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (msg.cacheHit ||
                            (msg.engineMode ?? _activeEngineMode) == 'semantic_cache' ||
                            (msg.engineMode ?? _activeEngineMode) == 'faq_zero_token')
                        ? Icons.bolt_rounded
                        : Icons.auto_awesome_rounded,
                    size: 11,
                    color: (msg.cacheHit ||
                            (msg.engineMode ?? _activeEngineMode) == 'semantic_cache' ||
                            (msg.engineMode ?? _activeEngineMode) == 'faq_zero_token')
                        ? const Color(0xFF2563EB)
                        : tokens.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    (msg.cacheHit ||
                            (msg.engineMode ?? _activeEngineMode) == 'semantic_cache' ||
                            (msg.engineMode ?? _activeEngineMode) == 'faq_zero_token')
                        ? '0 tok · Cache FAQ'
                        : ((msg.engineMode ?? _activeEngineMode) == 'local_grounded'
                            ? 'Analisis Lokal Real-Time'
                            : (msg.engineMode == 'local_offline'
                                ? 'Mode Offline Lokal'
                                : 'Gemini AI')),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lightweight inline Markdown (`**bold**`, `*italic*`, `` `code` ``, headings & bullets)
/// renderer for Copilot responses with tabular numeric figures for crisp IDR Rupiah readability.
class _FormattedCopilotText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;

  const _FormattedCopilotText({
    required this.text,
    required this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = text
        .replaceAllMapped(RegExp(r'^#{1,3}\s+(.+)$', multiLine: true), (m) => '**${m.group(1)}**')
        .replaceAllMapped(RegExp(r'^-\s+', multiLine: true), (_) => '• ');

    final effectiveBase = baseStyle.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*(?!\s)(.+?)(?<!\s)\*');
    int lastEnd = 0;

    for (final match in pattern.allMatches(normalized)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: normalized.substring(lastEnd, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: effectiveBase.copyWith(fontWeight: FontWeight.w800),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: effectiveBase.copyWith(
              fontFamily: 'monospace',
              fontSize: (effectiveBase.fontSize ?? 13) - 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(3),
            style: effectiveBase.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      }
      lastEnd = match.end;
    }
    if (lastEnd < normalized.length) {
      spans.add(TextSpan(text: normalized.substring(lastEnd)));
    }

    return RichText(
      text: TextSpan(style: effectiveBase, children: spans),
    );
  }
}

/// Unified 3D Articulated Animated WebP mascot "OXORA Buddy" (100% parity with Cloud Web).
/// Perched free-floating directly above the chat card with transparent RGBA background:
/// 1. greeting -> `buddy_greeting.webp` (full-body bear waving right arm -> auto-settle to idle)
/// 2. idle/guiding/guard -> `buddy_idle.webp` (half-body peeking, 2.5D gaze left/right, blinking eyes)
/// 3. thinking -> `buddy_working.webp` (orange headphones + stationary laptop, active typing paw)
/// 4. success -> `buddy_success.webp` (joyful crescent eyes, double bounce, sparkles -> auto-settle)
/// 5. poke -> tactile elastic plushie squish-bounce on tap
class _NusaBuddyMascot extends StatefulWidget {
  final String state;
  final double size;
  final VoidCallback? onGreetingComplete;
  final VoidCallback? onSuccessComplete;

  const _NusaBuddyMascot({
    super.key,
    required this.state,
    this.size = 126,
    this.onGreetingComplete,
    this.onSuccessComplete,
  });

  @override
  State<_NusaBuddyMascot> createState() => _NusaBuddyMascotState();
}

class _NusaBuddyMascotState extends State<_NusaBuddyMascot>
    with TickerProviderStateMixin {
  static const String _assetGreeting = 'assets/images/buddy/buddy_greeting.webp';
  static const String _assetIdle = 'assets/images/buddy/buddy_idle.webp';
  static const String _assetThinking = 'assets/images/buddy/buddy_working.webp';
  static const String _assetSuccess = 'assets/images/buddy/buddy_success.webp';

  late final AnimationController _greetingCtrl;
  late final AnimationController _successCtrl;
  late final AnimationController _pokeCtrl;
  bool _precached = false;

  bool get _isWidgetTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('TestWidgets');

  @override
  void initState() {
    super.initState();
    _greetingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && widget.state == 'greeting') {
          widget.onGreetingComplete?.call();
        }
      });

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && widget.state == 'success') {
          widget.onSuccessComplete?.call();
        }
      });

    _pokeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    );

    _syncControllersForState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached && !_isWidgetTestBinding) {
      _precached = true;
      for (final asset in const [
        _assetGreeting,
        _assetIdle,
        _assetThinking,
        _assetSuccess,
      ]) {
        try {
          precacheImage(AssetImage(asset), context).catchError((_) {});
        } catch (_) {}
      }
    }
  }

  @override
  void didUpdateWidget(covariant _NusaBuddyMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncControllersForState();
    }
  }

  void _syncControllersForState() {
    if (widget.state == 'greeting') {
      _successCtrl.stop();
      _greetingCtrl.forward(from: 0);
      return;
    }
    if (widget.state == 'success') {
      _greetingCtrl.stop();
      _successCtrl.forward(from: 0);
      return;
    }
    _greetingCtrl.stop();
    _successCtrl.stop();
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    _successCtrl.dispose();
    _pokeCtrl.dispose();
    super.dispose();
  }

  void _triggerPoke() {
    _pokeCtrl.forward(from: 0);
  }

  String _activeAssetPath() {
    return switch (widget.state) {
      'greeting' => _assetGreeting,
      'thinking' => _assetThinking,
      'success' => _assetSuccess,
      _ => _assetIdle,
    };
  }

  Widget _buildMascotImage(String assetPath, NusaThemeTokens tokens) {
    // Under widget tests (`pumpAndSettle`), freeze multi-frame animated WebP to frame 0 via ResizeImage
    // while real Android/iOS/Web production builds play full native 18 FPS multi-frame Animated WebP!
    final ImageProvider provider = _isWidgetTestBinding
        ? ResizeImage(AssetImage(assetPath), width: 320, height: 320)
        : AssetImage(assetPath);

    return Image(
      key: ValueKey<String>(assetPath),
      image: provider,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (ctx, error, stack) => Container(
        width: widget.size * 0.65,
        height: widget.size * 0.65,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tokens.accentSoft,
          border: Border.all(color: tokens.accent, width: 2),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: tokens.accent,
          size: widget.size * 0.30,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final assetPath = _activeAssetPath();

    return GestureDetector(
      onTap: _triggerPoke,
      behavior: HitTestBehavior.translucent,
      child: Semantics(
        label: 'OXORA Buddy (${widget.state})',
        child: AnimatedBuilder(
          animation: Listenable.merge([_greetingCtrl, _pokeCtrl]),
          builder: (ctx, child) {
            double dy = 0;
            double scaleX = 1;
            double scaleY = 1;

            // Soft elastic pop-in entrance during first 380ms of Greeting phase
            if (widget.state == 'greeting' && _greetingCtrl.value < 0.18) {
              final k = Curves.easeOutBack.transform(
                (_greetingCtrl.value / 0.18).clamp(0.0, 1.0),
              );
              final s = 0.76 + 0.24 * k;
              scaleX = s;
              scaleY = s;
              dy = 14.0 * (1.0 - k);
            }

            // Interactive plushie squash & stretch on tap
            if (_pokeCtrl.isAnimating) {
              final p = _pokeCtrl.value;
              final envelope = 1.0 - p;
              final osc = math.sin(p * math.pi * 3.0);
              scaleX *= 1.0 + osc * 0.13 * envelope;
              scaleY *= 1.0 - osc * 0.13 * envelope;
              dy += osc * 3.5 * envelope;
            }

            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                alignment: Alignment.bottomCenter,
                scaleX: scaleX,
                scaleY: scaleY,
                child: child,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  alignment: Alignment.bottomCenter,
                  scale: Tween<double>(begin: 0.91, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: _buildMascotImage(assetPath, tokens),
            ),
          ),
        ),
      ),
    );
  }
}
