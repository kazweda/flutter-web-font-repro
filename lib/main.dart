import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Repro for https://github.com/kazweda/lawsuppli/issues/188
///
/// On Flutter Web (CanvasKit), Japanese punctuation such as "、" and "。"
/// can render too high (closer to the vertical center, like a katakana
/// middle dot "・") when the app relies on the default/fallback font
/// instead of an explicitly-loaded Japanese font such as Noto Sans JP.
void main() {
  runApp(const FontReproApp());
}

const _sampleText =
    '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。'
    '何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。';

class FontReproApp extends StatelessWidget {
  const FontReproApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Web Font Repro',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
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

    final cards = switch (only) {
      'before' => [before],
      'after' => [after],
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
