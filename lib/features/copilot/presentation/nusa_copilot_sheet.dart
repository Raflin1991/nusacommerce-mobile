import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import '../../../core/config/mobile_workspace_config.dart';
import '../../../core/database/offline_database.dart';
import '../../../core/hardware/voice_input_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/nusa_theme_tokens.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/nusa_skeleton.dart';
import '../../../core/widgets/nusa_widgets.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../auth/models/auth_session_model.dart';
import '../../../core/network/repositories/backoffice_repository.dart';

part 'nusa_copilot_sheet_part1.dart';
part 'nusa_copilot_sheet_widgets2.dart';

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
}
