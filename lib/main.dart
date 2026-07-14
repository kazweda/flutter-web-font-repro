import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Repro for https://github.com/kazweda/lawsuppli/issues/188
///
/// On Flutter Web (CanvasKit), Japanese punctuation such as "、" and "。"
/// can render too high (closer to the vertical center, like a katakana
/// middle dot "・") when the app relies on the default/fallback font
/// instead of an explicitly-loaded Japanese font such as Noto Sans JP.
void main() {
  final only = Uri.base.queryParameters['only'];

  // ?only=blocked simulates the production CORS failure: notoSansJp() is
  // requested but google_fonts is prevented from fetching it at runtime, so
  // CanvasKit falls back exactly as if the network request had failed.
  if (only == 'blocked') {
    GoogleFonts.config.allowRuntimeFetching = false;
  }

  // ?only=broken reproduces the actual production implementation (see
  // lawsuppli issue #188, comment linking to this repro's issue #4): the
  // whole app runs inside http.runWithClient() with a `withCredentials`
  // BrowserClient, because api.lawsuppli.com requests need credentials.
  // google_fonts' internal http.Client() picks up that same credentialed
  // client (that's what runWithClient is for), so its request to
  // fonts.gstatic.com is sent with `credentials: include` and is genuinely
  // rejected by the browser's CORS check (gstatic doesn't allow credentialed
  // cross-origin requests) instead of just being pre-blocked by a config
  // flag as in ?only=blocked.
  if (only == 'broken') {
    http.runWithClient(
      () => runApp(const FontReproApp()),
      _createCredentialedClient,
    );
    return;
  }

  runApp(const FontReproApp());
}

/// Mirrors lawsuppli's `createCredentialedClient` from issue #4: a
/// BrowserClient with `withCredentials = true`, needed so requests to
/// api.lawsuppli.com carry cookies/auth headers.
http.Client _createCredentialedClient() {
  final client = BrowserClient();
  client.withCredentials = true;
  return client;
}

const _sampleText =
    '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。'
    '何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。';

/// Same sentences as [_sampleText], but split across a heading, bold inline
/// text, and a bullet list, so MarkdownBody builds multiple blocks/TextSpans
/// instead of one contiguous paragraph.
const _markdownRichSampleText = '''
## 吾輩は猫である

**吾輩は猫である。** 名前はまだ無い。どこで生れたかとんと見当がつかぬ。

- 何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。
''';

class FontReproApp extends StatelessWidget {
  const FontReproApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ?only=markdownThemeFont mirrors production: Noto Sans JP is applied
    // app-wide via ThemeData.textTheme (not per-widget), while the
    // MarkdownStyleSheet.p passed to MarkdownBody has no fontFamily of its
    // own (see issue #4 comment's SampleBubble). This tests whether
    // MarkdownBody actually inherits the theme's font in that setup.
    final only = Uri.base.queryParameters['only'];
    final textTheme = only == 'markdownThemeFont'
        ? GoogleFonts.notoSansJpTextTheme()
        : null;
    return MaterialApp(
      title: 'Flutter Web Font Repro',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        textTheme: textTheme,
      ),
      home: const ComparisonPage(),
    );
  }
}

class ComparisonPage extends StatelessWidget {
  const ComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ?only=before or ?only=after renders a single card in isolation, e.g.
    // for a screenshot diff without either card's font registration being
    // able to influence the other via CanvasKit's shared fallback font
    // manager.
    final only = Uri.base.queryParameters['only'];

    final before = _SampleCard(
      label: 'Before: デフォルトフォント（フォント未指定）',
      description: 'CanvasKit のフォールバックに任せた状態。「、」「。」が中央寄りの高さに見える。',
      style: const TextStyle(fontSize: 22, height: 1.8),
    );
    final after = _SampleCard(
      label: 'After: Noto Sans JP（Google Fonts CDN から動的取得）',
      description: 'GoogleFonts.notoSansJp() を明示指定。句読点が正しい位置（左下寄り）に表示される。',
      style: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
    );
    final blocked = _SampleCard(
      label: 'Blocked: Noto Sans JP指定だがフェッチ失敗を模擬（本番CORSブロック相当）',
      description:
          'GoogleFonts.notoSansJp() を指定しているが allowRuntimeFetching=false '
          'によりCDNから取得できない状態。lawsuppli本番のCORSブロックと同じ状況を再現。',
      style: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
    );
    final broken = _SampleCard(
      label: 'Broken: 本番実装を再現（withCredentialsクライアントで実際にCORSブロック）',
      description:
          'issue #4 で判明した修正前のlawsuppli実装を再現。http.runWithClient() と '
          'withCredentials=true のBrowserClientをアプリ全体に適用し（'
          'api.lawsuppli.com向けの認証付き通信のため）、textThemeにNoto Sans JPは '
          '設定していない。GoogleFonts.notoSansJp() のフェッチもこの資格情報付き'
          'クライアント経由になり、fonts.gstatic.comへのリクエストが実際に'
          'ブラウザのCORSチェックで拒否される。',
      style: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
    );
    final markdownBefore = _MarkdownSampleCard(
      label: 'MarkdownBefore: flutter_markdown_plus + フォント未指定',
      description:
          'issue #4 のコメントで共有された本番実装のMarkdownBody部分を再現。'
          'MarkdownBody（内部でRichText/Text.richを生成）で描画し、'
          'styleSheet.pにフォント指定はない状態。',
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 22, height: 1.8),
      ),
    );
    final markdownAfter = _MarkdownSampleCard(
      label: 'MarkdownAfter: flutter_markdown_plus + Noto Sans JP明示指定',
      description:
          'MarkdownBodyのstyleSheet.pにGoogleFonts.notoSansJp()を明示指定した状態。'
          'plainなTextのAfterカードと比べ、MarkdownBody特有の'
          'RichText/Text.rich構成が句読点位置に影響するかを切り分ける。',
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
      ),
    );
    final markdownRichBefore = _MarkdownSampleCard(
      label: 'MarkdownRichBefore: 見出し・太字・箇条書き + フォント未指定',
      description:
          'markdownBeforeと同じ文章を見出し・太字・箇条書きに分割し、'
          'MarkdownBodyが単一段落ではなく複数ブロック/TextSpanを生成する状態にした。'
          'フォント未指定。',
      data: _markdownRichSampleText,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 22, height: 1.8),
        h2: const TextStyle(fontSize: 22, height: 1.8),
        listBullet: const TextStyle(fontSize: 22, height: 1.8),
      ),
    );
    final markdownRichAfter = _MarkdownSampleCard(
      label: 'MarkdownRichAfter: 見出し・太字・箇条書き + Noto Sans JP明示指定',
      description:
          'markdownRichBeforeと同じ構成でNoto Sans JPを明示指定した状態。',
      data: _markdownRichSampleText,
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
        h2: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
        listBullet: GoogleFonts.notoSansJp(fontSize: 22, height: 1.8),
      ),
    );
    final raceBlockJp = _SampleCard(
      label:
          'RaceBlockJp: フォント未指定 + CanvasKit自動フォールバックのnotosansjpだけ取得ブロック',
      description:
          'issue #5 仮説2の検証。before同様フォント未指定だが、web/index.htmlで'
          'window.fetchをパッチし、CanvasKitが自動取得するnotosansjp宛の'
          'リクエストだけを恒久的に失敗させる（notosanssc/notosanshkは通常どおり'
          '取得できる）。DevToolsのRequest Blockingを手動操作せずに、'
          '「JP候補が存在しない状態」を再現するモード。',
      style: const TextStyle(fontSize: 22, height: 1.8),
    );
    final raceBlockScHk = _SampleCard(
      label:
          'RaceBlockScHk: フォント未指定 + notosanssc/notosanshkだけ取得ブロック（対照実験）',
      description:
          'raceBlockJpの逆条件。notosanssc/notosanshk宛のリクエストをブロックし、'
          'notosansjpだけがCanvasKitに取得される状態にする。この対照実験で句読点が'
          '正しい位置に見えれば、raceBlockJpとの差分は「JP候補の有無」が'
          '句読点のグリフ選択を左右することの裏付けになる。',
      style: const TextStyle(fontSize: 22, height: 1.8),
    );
    final markdownThemeFont = _MarkdownSampleCard(
      label:
          'MarkdownThemeFont: ThemeData.textThemeにNoto Sans JP、'
          'styleSheet.pはフォント指定なし',
      description:
          '本番実装(issue #4コメント)を再現: Noto Sans JPはper-widgetではなく'
          'ThemeData(textTheme: GoogleFonts.notoSansJpTextTheme())でアプリ全体に'
          '適用し、MarkdownStyleSheet.pにはfontSize/heightのみ指定してフォント'
          'ファミリーは指定しない。MarkdownBodyがこのテーマのフォントを'
          '継承するのか、それとも無指定と同じ扱いになるのかを確認する。',
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 22, height: 1.8),
      ),
    );

    final cards = switch (only) {
      'before' => [before],
      'after' => [after],
      'blocked' => [blocked],
      'broken' => [broken],
      'markdownBefore' => [markdownBefore],
      'markdownAfter' => [markdownAfter],
      'markdownRichBefore' => [markdownRichBefore],
      'markdownRichAfter' => [markdownRichAfter],
      'markdownThemeFont' => [markdownThemeFont],
      'raceBlockJp' => [raceBlockJp],
      'raceBlockScHk' => [raceBlockScHk],
      _ => [before, const SizedBox(height: 32), after],
    };

    return Scaffold(
      appBar: AppBar(title: const Text('句読点位置バグ再現 (issue #188)')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cards,
            ),
          ),
        ),
      ),
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({
    required this.label,
    required this.description,
    required this.style,
  });

  final String label;
  final String description;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text(_sampleText, style: style),
          ],
        ),
      ),
    );
  }
}

/// Mirrors lawsuppli's production `SampleBubble` (issue #4 comment): renders
/// the sample text through `MarkdownBody`, which builds RichText/Text.rich
/// internally instead of a single plain `Text`, to test whether that
/// rendering path affects punctuation glyph positioning.
class _MarkdownSampleCard extends StatelessWidget {
  const _MarkdownSampleCard({
    required this.label,
    required this.description,
    required this.styleSheet,
    this.data = _sampleText,
  });

  final String label;
  final String description;
  final MarkdownStyleSheet styleSheet;
  final String data;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            MarkdownBody(data: data, styleSheet: styleSheet),
          ],
        ),
      ),
    );
  }
}
