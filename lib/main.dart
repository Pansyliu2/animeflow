import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const Color kBg = Color(0xFF12141C);
const Color kInputBg = Color(0xFF1B2030);
const Color kChipBg = Color(0xFF1B2436);
const Color kAccent = Color(0xFF4A76FF);
const Color kTextSub = Color(0xFF7B839F);
const Color kHintColor = Color(0xFF5A6180);
const Color kCoverBg = Color(0xFF1D2130);
const Color kCoverIcon = Color(0xFF39405A);

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AnimeItem {
  const AnimeItem({
    required this.title,
    required this.cover,
    required this.score,
    required this.year,
    required this.episodes,
    required this.status,
    required this.synopsis,
    required this.url,
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

class AnimeApi {
  static const String _host = 'api.jikan.moe';

  Future<List<AnimeItem>> search(String keyword) async {
    final Uri uri = Uri.https(_host, '/v4/anime', <String, String>{
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
      throw const ApiException('请求太频繁，请等几秒再试');
    }
    if (response.statusCode != 200) {
      throw ApiException('接口返回 ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('返回数据格式异常');
    }
    final Object? data = decoded['data'];
    if (data is! List) {
      return const <AnimeItem>[];
    }

    final List<AnimeItem> items = <AnimeItem>[];
    for (final Object? entry in data) {
      if (entry is Map<String, dynamic>) {
        items.add(_parse(entry));
      }
    }
    return items;
  }

  AnimeItem _parse(Map<String, dynamic> entry) {
    String cover = '';
    final Object? images = entry['images'];
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

    final Object? titleEn = entry['title_english'];
    final Object? titleDefault = entry['title'];
    final Object? scoreRaw = entry['score'];
    final Object? yearRaw = entry['year'];
    final Object? episodesRaw = entry['episodes'];
    final Object? statusRaw = entry['status'];
    final Object? synopsisRaw = entry['synopsis'];
    final Object? urlRaw = entry['url'];

    return AnimeItem(
      title: titleEn is String && titleEn.isNotEmpty
          ? titleEn
          : (titleDefault is String && titleDefault.isNotEmpty
              ? titleDefault
              : '未知标题'),
      cover: cover,
      score: scoreRaw is num ? scoreRaw.toDouble() : null,
      year: yearRaw is num ? yearRaw.toInt() : null,
      episodes: episodesRaw is num ? episodesRaw.toInt() : null,
      status: statusRaw is String
          ? statusRaw.replaceFirst('Currently ', '')
          : '',
      synopsis: synopsisRaw is String ? synopsisRaw.trim() : '',
      url: urlRaw is String ? urlRaw : '',
    );
  }
}

void main() {
  runApp(const AnimeFlowApp());
}

class AnimeFlowApp extends StatelessWidget {
  const AnimeFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimeFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightnes
