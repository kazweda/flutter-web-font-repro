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
使われる」というissueの本質的な問題は確認できる。実際に句読点の位置が
崩れて見えるかどうかは、報告者の環境（Windows Chrome、優先言語設定など）
に強く依存すると考えられる。

## 関連

- 実際のアプリでの原因調査・修正: kazweda/lawsuppli PR
  [#189](https://github.com/kazweda/lawsuppli/pull/189)
  （このリポジトリの再現手順とは別に、本番アプリでは
  `api.lawsuppli.com` 向けの `withCredentials` HTTPクライアントが
  Google Fontsへのランタイム取得をCORSでブロックする問題も併発していた）
