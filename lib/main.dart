import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ===== 主题色 =====
const Color kBg = Color(0xFF12141C);
const Color kInputBg = Color(0xFF1B2030);
const Color kChipBg = Color(0xFF1B2436);
const Color kAccent = Color(0xFF4A76FF);
const Color kSub = Color(0xFF7B839F);
const Color kHintText = Color(0xFF5A6180);
const Color kCoverBg = Color(0xFF1D2130);
const Color kCoverIcon = Color(0xFF39405A);
const Color kLine = Color(0xFF191D29);

// ===== 异常 =====
class ApiError implements Exception {
  const ApiError(this.message);

  final String message;

  @override
  String toString() => message;
}

// ===== 数据模型 =====
class AnimeItem {
  const AnimeItem({
    required this.title,
    required this.cover,
    this.score,
    this.year,
    this.episodes,
    this.status = '',
    this.synopsis = '',
    this.url = '',
  });

  final String title;
  final String cover;
  final double? score;
  final int? year;
  final int? episodes;
  final String status;
  final String synopsis;
  final String url;

  String get metaLine {
    final List<String> parts = <String>[];
    if (year != null) {
      parts.add('$year 年');
    }
    if (score != null) {
      parts.add('★ ${score!.toStringAsFixed(1)}');
    }
    if (episodes != null) {
      parts.add('$episodes 话');
    }
    if (status.isNotEmpty) {
      parts.add(status);
    }
    return parts.isEmpty ? '暂无信息' : parts.join(' · ');
  }
}

// ===== 搜索请求 =====
Future<List<AnimeItem>> searchAnime(String keyword) async {
  final Uri uri = Uri.https('api.jikan.moe', '/v4/anime', <String, String>{
    'q': keyword,
    'limit': '20',
    'sfw': 'true',
    'order_by': 'members',
    'sort': 'desc',
  });

  final http.Response response = await http
      .get(uri, headers: <String, String>{'Accept': 'application/json'})
      .timeout(const Duration(seconds: 25));

  if (response.statusCode == 429) {
    throw const ApiError('请求太频繁，请等几秒再试');
  }
  if (response.statusCode != 200) {
    throw ApiError('接口返回 ${response.statusCode}');
  }

  final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map<String, dynamic>) {
    throw const ApiError('返回数据格式异常');
  }
  final Object? data = decoded['data'];
  if (data is! List) {
    return <AnimeItem>[];
  }

  final List<AnimeItem> items = <AnimeItem>[];
  for (final Object? raw in data) {
    if (raw is! Map<String, dynamic>) {
      continue;
    }
    items.add(toItem(raw));
  }
  return items;
}

AnimeItem toItem(Map<String, dynamic> raw) {
  String cover = '';
  final Object? images = raw['images'];
  if (images is Map<String, dynamic>) {
    final Object? jpg = images['jpg'];
    if (jpg is Map<String, dynamic>) {
      final Object? large = jpg['large_image_url'];
      final Object? normal = jpg['image_url'];
      if (large is String && large.isNotEmpty) {
        cover = large;
      } else if (normal is String) {
        cover = normal;
      }
    }
  }

  final Object? titleEn = raw['title_english'];
  final Object? titleDefault = raw['title'];
  final Object? score = raw['score'];
  final Object? year = raw['year'];
  final Object? episodes = raw['episodes'];
  final Object? status = raw['status'];
  final Object? synopsis = raw['synopsis'];
  final Object? url = raw['url'];

  final String english = titleEn is String ? titleEn : '';
  final String fallback = titleDefault is String ? titleDefault : '';

  return AnimeItem(
    title: english.isNotEmpty
        ? english
        : (fallback.isNotEmpty ? fallback : '未知标题'),
    cover: cover,
    score: score is num ? score.toDouble() : null,
    year: year is num ? year.toInt() : null,
    episodes: episodes is num ? episodes.toInt() : null,
    status: status is String ? status.replaceFirst('Currently ', '') : '',
    synopsis: synopsis is String ? synopsis.trim() : '',
    url: url is String ? url : '',
  );
}

void main() {
  runApp(const AnimeFlowApp());
}

// ===== 应用根 =====
class AnimeFlowApp extends StatelessWidget {
  const AnimeFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimeFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kAccent,
          secondary: kAccent,
          surface: kBg,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ===== 封面组件 =====
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final String url;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Widget inner;
    if (url.isEmpty) {
      inner = Container(
        width: width,
        height: height,
        color: kCoverBg,
        child: Icon(
          Icons.image_not_supported,
          size: width * 0.32,
          color: kCoverIcon,
        ),
      );
    } else {
      inner = Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) {
          if (progress == null) {
            return child;
          }
          return Container(
            width: width,
            height: height,
            color: kCoverBg,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: kAccent),
              ),
            ),
          );
        },
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
          return Container(
            width: width,
            height: height,
            color: kCoverBg,
            child: Icon(Icons.broken_image, size: width * 0.32, color: kCoverIcon),
          );
        },
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: inner,
    );
  }
}

// ===== 首页 =====
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController controller = TextEditingController();
  bool loading = false;
  String status = '输入番剧名称开始搜索';
  String error = '';
  List<AnimeItem> items = const <AnimeItem>[];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> doSearch() async {
    if (loading) {
      return;
    }
    final String keyword = controller.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        status = '请先输入关键词';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      loading = true;
      error = '';
      items = const <AnimeItem>[];
      status = '正在搜索：$keyword';
    });

    try {
      final List<AnimeItem> result = await searchAnime(keyword);
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        items = result;
        status = result.isEmpty ? '没有找到结果' : '共 ${result.length} 条结果';
      });
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        status = '搜索失败';
        error = '请求超时，请检查网络后重试';
      });
    } on ApiError catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        status = '搜索失败';
        error = exception.message;
      });
    } catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        status = '搜索失败';
        error = '网络异常：$exception';
      });
    }
  }

  void openDetail(AnimeItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DetailPage(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            buildHeader(),
            Expanded(child: buildBody()),
          ],
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                'AnimeFlow',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kAccent),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (String value) => doSearch(),
                  style: const TextStyle(fontSize: 15, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '例如：Frieren / 芙莉莲',
                    hintStyle: const TextStyle(fontSize: 15, color: kSub),
                    prefixIcon: const Icon(Icons.search, size: 20, color: kSub),
                    filled: true,
                    fillColor: kInputBg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: kAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                height: 44,
                child: ElevatedButton(
                  onPressed: loading ? null : doSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF2A3145),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(Icons.arrow_forward, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(status, style: const TextStyle(fontSize: 11.5, color: kSub)),
        ],
      ),
    );
  }

  Widget buildBody() {
    if (error.isNotEmpty) {
      return buildHint(Icons.error_outline, error);
    }
    if (items.isEmpty) {
      return buildHint(
        loading ? Icons.hourglass_empty : Icons.search,
        loading
            ? '正在搜索，请稍候…'
            : '输入番剧名称后点击搜索\n数据来自 MyAnimeList 公开接口',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, color: kLine),
      itemBuilder: (BuildContext context, int index) {
        final AnimeItem item = items[index];
        return InkWell(
          onTap: () => openDetail(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                CoverImage(url: item.cover, width: 58, height: 82),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.metaLine,
                        style: const TextStyle(fontSize: 11.5, color: kSub),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFF3A4159),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget buildHint(IconData icon, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: kHintText),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: kHintText, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 详情页 =====
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.item});

  final AnimeItem item;

  Future<void> openUrl(BuildContext context) async {
    if (item.url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该条目没有可用的链接')),
      );
      return;
    }
    final Uri? uri = Uri.tryParse(item.url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('链接格式不正确')),
      );
      return;
    }
    try {
      final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开：${item.url}')),
        );
      }
    } catch (exception) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败：$exception')),
        );
      }
    }
  }

  Widget chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: kChipBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Color(0xFFA8C4FF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> chips = <Widget>[];
    if (item.score != null) {
      chips.add(chip('★ ${item.score!.toStringAsFixed(1)}'));
    }
    if (item.year != null) {
      chips.add(chip('${item.year} 年'));
    }
    if (item.episodes != null) {
      chips.add(chip('${item.episodes} 话'));
    }
    if (item.status.isNotEmpty) {
      chips.add(chip(item.status));
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '详情',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CoverImage(url: item.cover, width: 108, height: 152, radius: 10),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.metaLine,
                      style: const TextStyle(fontSize: 11.5, color: kSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(spacing: 6, runSpacing: 6, children: chips),
            ),
          const SizedBox(height: 18),
          Text(
            item.synopsis.isEmpty ? '该来源没有提供简介。' : item.synopsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.75,
              color: Color(0xFFB3BAD0),
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => openUrl(context),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text(
                '在浏览器中打开详情页',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ANIMEFLOW_EOF
