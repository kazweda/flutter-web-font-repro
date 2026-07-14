# flutter-web-font-repro

[kazweda/lawsuppli#188](https://github.com/kazweda/lawsuppli/issues/188)
「句読点の位置が高い」問題の最小再現プロジェクト。

## 症状

Flutter Web（CanvasKitレンダラー）で日本語テキストを描画すると、
明示的な日本語フォント指定がない場合に「、」「。」などの句読点が
本来より高い位置（中黒「・」のような高さ）に表示されることがある。

## 再現方法

```sh
flutter run -d chrome
```

起動すると1画面に2つのカードが並ぶ。

- **Before**: フォント未指定（CanvasKitのデフォルト/フォールバックに依存）
- **After**: `GoogleFonts.notoSansJp()` で Noto Sans JP を明示指定
  （Google Fonts CDNから実行時に取得）

同じ文章を並べて表示するので、句読点の縦位置の違いを目視で比較できる。

`?only=before` / `?only=after` をURLに付けると1枚のカードだけを単独表示できる
（2枚を同時表示すると、フォントごとの行間メトリクスの違いでカード自体の
レイアウト位置がずれ、見た目の比較がしづらくなるため）。

`?only=blocked` は、`GoogleFonts.notoSansJp()`を指定しているにもかかわらず
`GoogleFonts.config.allowRuntimeFetching = false` によりCDNからのフェッチが
できない状態を模擬する。lawsuppli本番で発生していた`withCredentials`
HTTPクライアントによるCORSブロック（フォント取得失敗）と同じ状況を
再現するためのモード。

`?only=broken` は、issue #4で判明した修正前のlawsuppli本番実装をそのまま
再現するモード。`GoogleFonts.config.allowRuntimeFetching`は変更せず、
アプリ全体を`http.runWithClient()`で`withCredentials=true`の
`BrowserClient`（`api.lawsuppli.com`向けの認証付き通信用）配下で実行する。
`google_fonts`パッケージ内部の`http.Client()`もこのゾーンに乗るため
（`runWithClient`の仕様どおり）、`fonts.gstatic.com`へのリクエストが
実際に資格情報付きで送信され、ブラウザのCORSチェックによって**本物の
CORSエラー**として拒否される（`?only=blocked`のような設定フラグによる
事前ブロックではない）。

## 検証で分かったこと（重要な注意）

日本語システムフォント（Hiragino等）がインストール済みのmacOS実機Chromeでは、
`navigator.language`を`en-US`に強制しても、**Beforeカードでも句読点が
正しい位置に見えることがある**。CanvasKitがグリフ描画時にOS側のフォント
マッチングも考慮するためと推測される。

一方、ブラウザのDevTools Networkタブで確認すると、Beforeカード（フォント
未指定）は`fonts.gstatic.com/s/notosanssc/...`（簡体字中国語）や
`.../notosanshk/...`（繁体字・香港）のグリフを自動フェッチしており、
日本語グリフ（`GoogleFonts.notoSansJp()`が明示的に取得する
`fonts.gstatic.com/s/a/<hash>.ttf`）とは異なるリージョンのフォントに
フォールバックしていることが確認できる。これはissue #188の根本原因
（CanvasKitのCJKグリフ選択が日本語向けとは限らない）そのものである。

つまり **見た目の再現性は実行環境（OS/ブラウザにインストール済みの
フォント、優先言語設定）に依存する** 。見た目で再現しない場合も、
Networkタブで上記のフォントリクエストを確認すれば、
「日本語フォントが明示指定されていないと非日本語のCJKフォールバックが
使われる」というissueの本質的な問題は確認できる。

**注意**: issue #188 の報告者は本プロジェクトの検証者と同一人物であり、
実際にmacOS Chromeで句読点のズレを目視確認している。一方この再現
プロジェクトでは、同じmacOS Chrome（優先言語を英語にした状態）で
`?only=before` を単独表示しても目視でのズレは再現しなかった
（Networkタブでは上記の非日本語CJKフォールバックのフェッチは確認済み）。

さらに、本番のCORSブロック（`withCredentials`によりGoogle Fontsの
ランタイム取得が失敗する）状況を模擬した `?only=blocked`
（`GoogleFonts.notoSansJp()`を指定しつつ
`GoogleFonts.config.allowRuntimeFetching = false`でフェッチを止める）
でも同様に目視でのズレは再現しなかった。興味深いことに、このモードの
Networkタブでは`notosanssc`・`notosanshk`に加えて`notosansjp`も
自動フェッチされていることが確認できた。これは google_fonts
パッケージのフェッチとは別に、CanvasKit（Skia）自身が持つCJK
グリフの自動フォールバック取得機構が独立して動いていることを示して
おり、日本語向けの`notosansjp`自体はCanvasKit側で取得できているにも
かかわらず、句読点のような共有コードポイントについては簡体字/繁体字
版のグリフが選ばれている可能性がある（＝フォントファミリー単位では
なく文字＝コードポイント単位でのフォールバック選択が原因、という仮説）。

つまり「macOS + Hiragino搭載環境だから見た目上は再現しない」という
説明だけでは、本番の lawsuppli アプリで実際に目視できた症状を
説明しきれておらず、`before`/`blocked`いずれのモードでも目視再現には
至っていない。

### issue #4: 本番の実装と修正内容

issue #4 で報告された本番（修正後）の実装は次の2点を行っていた。

```dart
void main() {
  usePathUrlStrategy();
  // フォントはassets/google_fonts/にバンドル済みのため、実行時フェッチは行わない。
  // (許可すると、api.lawsuppli.com向けのwithCredentials付きHTTPクライアントが
  // fonts.gstatic.comへのリクエストにも使われ、CORSエラーになる)
  GoogleFonts.config.allowRuntimeFetching = false;
  http.runWithClient(
    () => runApp(const LawSuppliApp()),
    createCredentialedClient,
  );
}
```

```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
  useMaterial3: true,
  appBarTheme: const AppBarTheme(foregroundColor: Colors.white),
  textTheme: GoogleFonts.notoSansJpTextTheme(),
),
```

修正前は `textTheme: GoogleFonts.notoSansJpTextTheme()` が設定されておらず、
`allowRuntimeFetching`も`false`にしていなかったと考えられる。つまり
アプリ全体が`withCredentials`クライアント配下で動く中、
（アプリ全体のデフォルトフォントとしてではなく）実行時にGoogle Fonts CDN
から個別にフォントを取得しようとして本物のCORSエラーで失敗し、かつ
デフォルトの`textTheme`は日本語フォントを指定していなかった、という
状態だったと推測される。`?only=broken`はこの状態を再現している。

`?only=broken`をheadless Chrome（DevTools Protocolで検証、macOS,
Hiragino搭載環境）で確認したところ、狙いどおり本物のCORSエラーが発生した。

```
Access to fetch at 'https://fonts.gstatic.com/s/a/<hash>.ttf' from origin
'http://localhost:8642' has been blocked by CORS policy: The value of the
'Access-Control-Allow-Origin' header in the response must not be the
wildcard '*' when the request's credentials mode is 'include'.

google_fonts was unable to load font NotoSansJP-Regular because the
following exception occurred:
Exception: Failed to load font with url https://fonts.gstatic.com/s/a/<hash>.ttf:
ClientException: Failed to fetch, uri=https://fonts.gstatic.com/s/a/<hash>.ttf
```

`?only=blocked`（設定フラグによる事前ブロック）と異なり、こちらは実際に
ネットワークリクエストが送信され、ブラウザのCORSチェックによって
拒否されている点で本番の障害メカニズムを忠実に再現できている。
ただし、この環境（Hiragino搭載macOS Chrome）では、このエラー発生後も
句読点の目視でのズレは`before`/`after`/`blocked`と同様に再現しなかった
（このマシンにインストール済みの日本語フォントへCanvasKit/OS側の
フォントマッチングがフォールバックしているためと推測される）。

両者（本プロジェクトでの目視非再現 と 本番での目視再現）の違いの原因は
未特定であり、次に検討すべき差分としては、本番で症状を確認した際の
Chromeバージョンや優先言語設定の詳細、OSにインストールされている
フォント構成、フォントサイズ・行間・テキスト内容の違いなどが
挙げられるが、いずれも未検証。

後日、`flutter run -d chrome`の通常ブラウザ（headlessでない、同じmacOS +
Hiragino搭載環境）でも`?only=broken`を検証したところ、同様に本物の
CORSエラーが再現し、かつ句読点の目視ズレは再現しなかった。

### まとめ: コード側の要因では説明がつかない

`before` / `after` / `blocked` / `broken`（本物のCORSエラー確認済み） /
`markdownBefore` / `markdownAfter` / `markdownRichBefore` /
`markdownRichAfter` の8パターン全てで、このマシン（macOS + Hiragino搭載
Chrome）では句読点のズレが目視再現しなかった。フォント指定の有無・
CORSブロックの実態（設定フラグ vs 本物のCORSエラー）・`MarkdownBody`
経由かどうか・見出しや太字や箇条書きの有無、というコード側の変数を
一通り変えても再現しないため、**再現しないのはコードの構成ではなく、
このマシンにインストール済みの日本語システムフォント（Hiragino）による
OSレベルのフォールバックマスキングが支配的要因である**、という仮説が
強く裏付けられた。

次に検討すべきは、Hiraginoのような日本語システムフォントが入っていない
環境（Linux上のheadless Chrome、Docker、CIランナーなど）でこれらの
モードを再検証すること。

## MarkdownBody経由の描画（issue #4のコメントを受けての追加検証）

issue #4 のコメントで、症状が出ているlawsuppli本番実装ではAI応答テキストを
素の`Text`ではなく`flutter_markdown_plus`の`MarkdownBody`（内部で
`RichText`/`Text.rich`を生成）で描画していることが判明した。フォントは
per-widgetではなく`textTheme: GoogleFonts.notoSansJpTextTheme()`でテーマ
全体に適用されている。

この構成の違い（`MarkdownBody`かどうか）が句読点位置のズレに関係するかを
切り分けるため、`?only=markdownBefore` / `?only=markdownAfter`を追加した。

- **MarkdownBefore**: `MarkdownBody`で描画、`styleSheet.p`にフォント指定なし
- **MarkdownAfter**: `MarkdownBody`で描画、`styleSheet.p`に
  `GoogleFonts.notoSansJp()`を明示指定

既存の`before`/`after`（素の`Text`）と同一のサンプル文・フォントサイズ・
行間で揃えてあるので、`MarkdownBody`版だけでズレが再現すれば、
`RichText`/`Text.rich`の内部構成が要因の一つである可能性が高いと言える。

**検証結果**: `?only=markdownBefore` / `?only=markdownAfter` いずれも
このマシン（macOS + Hiragino搭載Chrome）では句読点のズレは目視再現
しなかった。`before`/`after`/`blocked`/`broken`と同じ結果であり、
このマシンでは素の`Text`でも既に再現しないため、`MarkdownBody`が
原因かどうかについて肯定・否定いずれの結論も出せていない。

なお両モードのNetworkタブには`notosanssc`・`notosanshk`・`notosansjp`
のフェッチが確認でき、これは`?only=blocked`で確認済みのCanvasKit
自身の自動CJKフォールバック取得機構によるもの（`MarkdownBody`固有の
挙動ではない）と考えられる。

### 見出し・太字・箇条書きを含むMarkdown（`?only=markdownRichBefore` / `?only=markdownRichAfter`）

単一の連続した段落ではなく、見出し(`##`)・太字(`**...**`)・箇条書き(`-`)で
テキストを分割した場合、`MarkdownBody`は複数のブロック/`TextSpan`を生成する。
この構成差がレイアウト・グリフフォールバックに影響するかを確認するため
追加したモード。`markdownBefore`/`markdownAfter`と同じ文章を、見出し・
太字・箇条書きに分割した`_markdownRichSampleText`を使用する。

**検証結果**: こちらもこのマシンでは句読点のズレは目視再現しなかった。

### テーマ経由のフォント指定（`?only=markdownThemeFont`）

issue #4 のコメントで共有された本番実装をよく見ると、`markdownBefore`/
`markdownAfter`とは異なる重要な違いがある。本番ではNoto Sans JPを
`MarkdownStyleSheet.p`に直接指定するのではなく、`ThemeData(textTheme:
GoogleFonts.notoSansJpTextTheme())`で**アプリ全体**に適用しており、
`MarkdownStyleSheet.p`自体は`TextStyle(height: 1.7, fontSize: 14)`と
フォントファミリーを指定していない。

これまでの`markdownBefore`（テーマにも日本語フォント設定が一切ない）
とも`markdownAfter`（`styleSheet.p`に直接明示指定）とも異なる、
「**テーマにはNoto Sans JPが設定されているが、MarkdownBody側の
スタイルはそれを明示的に継承していない**」という本番と同じ構成を
`?only=markdownThemeFont`で再現する。`flutter_markdown_plus`の
`MarkdownStyleSheet.p`がテーマのフォントファミリーを実際に継承する
のか、それとも継承されず無指定と同じ扱いになるのかを確認する狙い。

## 関連

- 実際のアプリでの原因調査・修正: kazweda/lawsuppli PR
  [#189](https://github.com/kazweda/lawsuppli/pull/189)
  （このリポジトリの再現手順とは別に、本番アプリでは
  `api.lawsuppli.com` 向けの `withCredentials` HTTPクライアントが
  Google Fontsへのランタイム取得をCORSでブロックする問題も併発していた）
