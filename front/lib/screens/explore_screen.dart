import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/snackbar_helper.dart';
import 'explore_category_screen.dart';
import 'explore_cardset_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _cardsets = [];
  bool _loading = true;
  bool _error = false;

  // 검색
  final _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchLoading = false;

  static const _categoryIcons = <String, IconData>{
    'translate': Icons.translate,
    'computer': Icons.computer,
    'gavel': Icons.gavel,
    'business': Icons.business,
    'school': Icons.school,
    'category': Icons.category_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        ApiService.getExploreCategories(),
        ApiService.getExploreCardsets(sort: 'popular'),
      ]);
      if (mounted) {
        setState(() {
          _categories = results[0];
          _cardsets = results[1];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchLoading = true;
    });
    try {
      final results = await ApiService.getExploreCardsets(search: query);
      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults = [];
    });
  }

  List<Map<String, dynamic>> get _featuredCardsets =>
      _cardsets.where((c) => c['is_featured'] == true).toList();

  List<Map<String, dynamic>> get _popularCardsets =>
      _cardsets.where((c) => c['is_featured'] != true).toList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('탐색')),
      body: Column(
        children: [
          // 검색바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '카드셋 검색...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
            ),
          ),

          // 본문
          Expanded(
            child: _isSearching
                ? _buildSearchResults(cs)
                : _buildMainContent(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ColorScheme cs) {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('검색 결과가 없습니다.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) =>
          _buildCardsetTile(_searchResults[index], cs),
    );
  }

  Widget _buildMainContent(ColorScheme cs) {
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
              onPressed: _loadData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        children: [
          // 추천 카드셋
          if (_featuredCardsets.isNotEmpty) ...[
            _buildSectionHeader('추천 카드셋'),
            SizedBox(
              height: 180,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _featuredCardsets.length,
                itemBuilder: (context, index) =>
                    _buildFeaturedCard(_featuredCardsets[index], cs),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 카테고리
          if (_categories.isNotEmpty) ...[
            _buildSectionHeader('카테고리'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: _categories
                    .map((cat) => _buildCategoryCard(cat, cs))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 인기 카드셋
          if (_popularCardsets.isNotEmpty) ...[
            _buildSectionHeader('인기 카드셋'),
            ...List.generate(
              _popularCardsets.length,
              (index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildCardsetTile(_popularCardsets[index], cs),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildFeaturedCard(Map<String, dynamic> cardset, ColorScheme cs) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ExploreCardsetScreen(cardsetId: cardset['id'] as String),
        ),
      ),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: cs.primary, size: 24),
                const SizedBox(height: 8),
                Text(
                  cardset['title'] as String? ?? '',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  '카드 ${cardset['card_count'] ?? 0}장 · 다운로드 ${cardset['download_count'] ?? 0}회',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> cat, ColorScheme cs) {
    final iconKey = cat['icon'] as String? ?? 'category';
    final icon = _categoryIcons[iconKey] ?? Icons.category_rounded;
    final name = cat['name'] as String? ?? '';
    final count = cat['cardset_count'] as int? ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExploreCategoryScreen(
            category: cat['id'] as String,
            categoryName: name,
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, size: 28, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count개 카드셋',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardsetTile(Map<String, dynamic> cardset, ColorScheme cs) {
    final title = cardset['title'] as String? ?? '';
    final cardCount = cardset['card_count'] as int? ?? 0;
    final downloadCount = cardset['download_count'] as int? ?? 0;
    final author = cardset['author_name'] as String? ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '카드 $cardCount장 · 다운로드 $downloadCount회${author.isNotEmpty ? ' · $author' : ''}',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
      ),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ExploreCardsetScreen(cardsetId: cardset['id'] as String),
        ),
      ),
    );
  }
}
