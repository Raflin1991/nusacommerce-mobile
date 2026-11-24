// ignore_for_file: invalid_use_of_protected_member
part of 'nusa_copilot_sheet.dart';

extension _NusaCopilotSheetStatePart1Ext on _NusaCopilotSheetState {

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
      final repo = BackofficeRepository.resolve();
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

      final res = await repo.sendCopilotMessage({
          'message': text,
          'input_mode': inputMode,
          'session_id': _sessionId,
          'workspace': workspace.name,
          if (historyPayload.isNotEmpty) 'history': historyPayload,
      });

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
