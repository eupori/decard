import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_helper.dart';
import 'review_screen.dart';
import 'login_screen.dart';

class ExploreCardsetScreen extends StatefulWidget {
  final String cardsetId;

  const ExploreCardsetScreen({super.key, required this.cardsetId});

  @override
  State<ExploreCardsetScreen> createState() => _ExploreCardsetScreenState();
}

class _ExploreCardsetScreenState extends State<ExploreCardsetScreen> {
  Map<String, dynamic>? _cardset;
  bool _loading = true;
  bool _error = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final detail = await ApiService.getExploreCardsetDetail(widget.cardsetId);
      if (mounted) setState(() => _cardset = detail);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    // 로그인 체크
    final loggedIn = await AuthService.isLoggedIn();
    if (!loggedIn) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
      return;
    }

    setState(() => _downloading = true);
    try {
      final result = await ApiService.downloadCardset(widget.cardsetId);
      if (mounted) {
        showSuccessSnackBar(context, '보관함에 추가되었습니다');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewScreen(session: result),
          ),
        );
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _cardset != null ? (_cardset!['title'] as String? ?? '') : '카드셋',
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: _buildBody(cs),
      bottomNavigationBar: _cardset != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _downloading ? null : _download,
                  child: _downloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('내 보관함에 추가'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error || _cardset == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('카드셋을 불러올 수 없습니다.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadDetail,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final title = _cardset!['title'] as String? ?? '';
    final description = _cardset!['description'] as String? ?? '';
    final authorName = _cardset!['author_name'] as String? ?? '';
    final cardCount = _cardset!['card_count'] as int? ?? 0;
    final downloadCount = _cardset!['download_count'] as int? ?? 0;
    final cards = (_cardset!['cards'] as List<dynamic>?) ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 카드
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    '${authorName.isNotEmpty ? '$authorName · ' : ''}카드 $cardCount장 · 다운로드 $downloadCount회',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 카드 미리보기
          if (cards.isNotEmpty) ...[
            Text(
              '카드 미리보기',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              itemBuilder: (context, index) {
                final card = cards[index] as Map<String, dynamic>;
                final front = card['front'] as String? ?? '';
                final back = card['back'] as String? ?? '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          front,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Divider(color: cs.outlineVariant, height: 1),
                        const SizedBox(height: 6),
                        Text(
                          back,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],

          // 하단 여백 (버튼 가림 방지)
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
