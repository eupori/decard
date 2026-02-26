import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import 'explore_cardset_screen.dart';

class ExploreCategoryScreen extends StatefulWidget {
  final String category;
  final String categoryName;

  const ExploreCategoryScreen({
    super.key,
    required this.category,
    required this.categoryName,
  });

  @override
  State<ExploreCategoryScreen> createState() => _ExploreCategoryScreenState();
}

class _ExploreCategoryScreenState extends State<ExploreCategoryScreen> {
  List<Map<String, dynamic>> _cardsets = [];
  bool _loading = true;
  bool _error = false;
  String _sort = 'popular'; // popular / latest

  @override
  void initState() {
    super.initState();
    _loadCardsets();
  }

  Future<void> _loadCardsets() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await ApiService.getExploreCardsets(
        category: widget.category,
        sort: _sort,
      );
      if (mounted) setState(() => _cardsets = results);
    } catch (e) {
      if (mounted) {
        setState(() => _error = true);
        showErrorSnackBar(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSortChanged(String sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _loadCardsets();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      body: Column(
        children: [
          // 정렬 필터
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('인기순'),
                  selected: _sort == 'popular',
                  onSelected: (_) => _onSortChanged('popular'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('최신순'),
                  selected: _sort == 'latest',
                  onSelected: (_) => _onSortChanged('latest'),
                ),
              ],
            ),
          ),

          // 카드셋 리스트
          Expanded(child: _buildBody(cs)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('데이터를 불러올 수 없습니다.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadCardsets,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_cardsets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('아직 카드셋이 없습니다',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCardsets,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _cardsets.length,
        itemBuilder: (context, index) {
          final cardset = _cardsets[index];
          final title = cardset['title'] as String? ?? '';
          final cardCount = cardset['card_count'] as int? ?? 0;
          final downloadCount = cardset['download_count'] as int? ?? 0;
          final author = cardset['author_name'] as String? ?? '';

          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
            title:
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '카드 $cardCount장 · 다운로드 $downloadCount회${author.isNotEmpty ? ' · $author' : ''}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            trailing:
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExploreCardsetScreen(
                    cardsetId: cardset['id'] as String),
              ),
            ),
          );
        },
      ),
    );
  }
}
