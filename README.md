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
至っていない。両者の違いの原因は未特定であり、次に検討すべき差分と
しては、本番アプリの実際のFlutter Webレンダラー設定（CanvasKit以外の
可能性）、本番で症状を確認した際のChromeバージョンや優先言語設定の
詳細、フォントサイズ・行間・テキスト内容の違いなどが挙げられるが、
いずれも未検証。

## 関連

- 実際のアプリでの原因調査・修正: kazweda/lawsuppli PR
  [#189](https://github.com/kazweda/lawsuppli/pull/189)
  （このリポジトリの再現手順とは別に、本番アプリでは
  `api.lawsuppli.com` 向けの `withCredentials` HTTPクライアントが
  Google Fontsへのランタイム取得をCORSでブロックする問題も併発していた）
