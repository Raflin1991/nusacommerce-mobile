// ignore_for_file: invalid_use_of_protected_member
part of 'business_reports_screen.dart';

class _AiCopilotSheet extends StatefulWidget {
  const _AiCopilotSheet({required this.api});

  final ApiClient api;

  @override
  State<_AiCopilotSheet> createState() => _AiCopilotSheetState();
}


class _AiCopilotSheetState extends State<_AiCopilotSheet> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _sending = false;

  static const List<String> _quickPrompts = [
    'Ringkas performa penjualan periode ini',
    'Produk apa yang paling laris & perlu restok?',
    'Cek anomali void, refund, atau selisih kasir',
    'Saran strategi tingkatkan margin profit',
  ];

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty || _sending) return;

    final historyPayload = _messages
        .where((m) => m['isError'] != true)
        .map((m) => <String, String>{
              'role': m['role'].toString(),
              'text': m['text'].toString(),
            })
        .toList();

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _sending = true;
      if (preset == null) _inputController.clear();
    });
    _scrollToBottom();

    try {
      final res = await BackofficeRepository.resolve(widget.api).sendCopilotMessage({
        'message': text,
        'history': historyPayload,
      });
      final data = Map<String, dynamic>.from((res.data['data'] as Map?) ?? {});
      final reply = (data['reply'] ?? '').toString().trim();
      final provider = (data['provider'] ?? '').toString().trim();
      final tokens = (data['tokens_used'] as num?)?.toInt();

      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'model',
          'text': reply.isEmpty ? 'Copilot tidak mengembalikan jawaban.' : reply,
          'meta': [
            if (provider.isNotEmpty) provider.toUpperCase(),
            if (tokens != null) '$tokens token',
          ].join(' • '),
        });
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'model',
          'text': ApiClient.extractErrorMessage(e),
          'isError': true,
        });
        _sending = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = NusaThemeTokens.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: BoxDecoration(
          color: tokens.bgPage,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.borderDefault,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: tokens.accentSoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.auto_awesome_rounded,
                          color: tokens.accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OXORA AI Copilot',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: tokens.textPrimary,
                            ),
                          ),
                          Text(
                            'Analisa omzet, stok, & risiko kasir berbasis data toko',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _messages.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: tokens.bgSurface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: tokens.borderSubtle),
                            ),
                            child: Text(
                              'Ajukan pertanyaan operasional atau analisa keuangan toko Anda. Copilot akan membaca ringkasan transaksi, margin, stok menipis, dan audit shift terbaru.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Pertanyaan Cepat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _quickPrompts
                                .map(
                                  (q) => ActionChip(
                                    label: Text(
                                      q,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textPrimary,
                                      ),
                                    ),
                                    backgroundColor: tokens.bgElevated,
                                    side: BorderSide(color: tokens.borderSubtle),
                                    onPressed: () => _sendMessage(q),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_sending ? 1 : 0),
                        itemBuilder: (_, idx) {
                          if (_sending && idx == _messages.length) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'AI sedang menganalisa data toko...',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: tokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final msg = _messages[idx];
                          final isUser = msg['role'] == 'user';
                          final isError = msg['isError'] == true;
                          final meta = (msg['meta'] ?? '').toString();
                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.8,
                              ),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? tokens.accent
                                    : (isError
                                        ? tokens.dangerSoft
                                        : tokens.bgSurface),
                                borderRadius: BorderRadius.circular(14),
                                border: isUser
                                    ? null
                                    : Border.all(
                                        color: isError
                                            ? tokens.danger.withOpacity(0.45)
                                            : tokens.borderSubtle,
                                      ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    msg['text'].toString(),
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.4,
                                      color: isUser
                                          ? Colors.white
                                          : (isError
                                              ? tokens.danger
                                              : tokens.textPrimary),
                                    ),
                                  ),
                                  if (meta.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      meta,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: tokens.textTertiary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: tokens.bgSurface,
                  border: Border(top: BorderSide(color: tokens.borderSubtle)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(color: tokens.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Tanya AI Copilot tentang performa toko...',
                          hintStyle: TextStyle(color: tokens.textTertiary),
                          isDense: true,
                          filled: true,
                          fillColor: tokens.bgElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sending ? null : () => _sendMessage(),
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.accent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Icon(Icons.send_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
