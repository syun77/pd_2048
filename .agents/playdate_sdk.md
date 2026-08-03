# Playdate SDK 仕様

特定プロジェクトに依存しない Playdate SDK の要点。細部や SDK 更新後の差分は、使用中 SDK に同梱された Inside Playdate を優先する。

## 基本

- SDK は Lua/C 用 API、pdc、Simulator、CoreLibs、サンプル、ドキュメントを含む。
- Playdate の画面は 1-bit、400×240px。標準 30fps、最大 50fps。
- Simulator は実機より高速なため、性能・入力・音声・保存は可能な限り実機でも確認する。
- source 直下に main.lua が必要。アセットと pdxinfo も通常は source 配下に置く。
- パス区切りは常に / を使う。

## Lua と実行ループ

- 標準の require ではなく import "path/to/file" を使う。import は同一 bundle 内で一度だけ実行される。
- Playdate 固有の Lua 拡張とグローバル playdate を前提にする。標準 Lua の全ライブラリが使えるとは限らない。
- playdate.update() が毎フレームの入力・状態更新・描画の入口。処理を重くしすぎない。
- 標準更新レートは 30fps。時間を扱う処理はフレーム数だけに依存せず、必要なら playdate.getCurrentTimeMilliseconds() を使う。
- playdate.display.setRefreshRate() で目標レートを変更できる。0 は固定レートではない。
- 描画中にゲーム状態を変更しない。

## CoreLibs

必要なライブラリを明示的に import する。

~~~lua
import "CoreLibs/graphics"
import "CoreLibs/timer"
~~~

タイマーを使う場合は CoreLibs/timer を import し、毎フレーム playdate.timer.updateTimers() を呼ぶ。frame timer も同様に playdate.frameTimer.updateTimers() が必要。

## 入力・描画・音声

- 入力には playdate.kButtonA/B/Up/Down/Left/Right と buttonIsPressed、buttonJustPressed、buttonJustReleased を使う。
- buttonJustPressed は押下ごとに一度だけ反応する。長押し・リピートは状態を保持する共通処理で管理する。
- 入力検出とゲーム操作を分離し、可能なら論理コマンドへ変換する。
- 描画は playdate.graphics を使う。1-bit 表示、画面サイズ、display scale、Sprite の dirty 更新を考慮する。
- 短い効果音には playdate.sound.sampleplayer、長い音声には playdate.sound.fileplayer など用途に合うプレイヤーを使う。
- 画像・音声・フォントは処理中に繰り返し読み込まず、必要に応じて初期化時に保持する。

## ファイル・JSON・保存

- 同梱データの読み書きや一覧には playdate.file を使う。欠損・読み込み失敗を処理する。
- json.decode、json.decodeFile、json.encode などで JSON を扱う。外部データは型検証する。
- playdate.datastore.write/read は Lua table や画像の保存に使う。filename に .json は付けない。
- 保存データには必要に応じて version/schema を持たせ、形式変更時の移行やデフォルト値を用意する。

## メタデータ・ビルド

- source 直下の pdxinfo に name、author、description、bundleID、version、buildNumber などを設定する。
- bundleID は一意な逆 DNS 形式、buildNumber はリリースごとに増加させる。
- 基本ビルドは pdc source output.pdx。必要に応じて PLAYDATE_SDK_PATH、PLAYDATE_LIB_PATH、-sdkpath、-I/--libpath を使う。
- .pdcignore で source 内の除外対象を指定できる。
- Simulator では .pdx を開いて実行する。実機への転送やリリース前確認も行う。

## 実装原則

- 既存 API・CoreLibs・サンプルを確認してから独自実装を追加する。
- 入力、ゲームルール、状態、描画、音声、保存の責務を分離する。
- 毎フレームの大量生成・全走査・リソース読み込みを避け、必要な場合は測定してから最適化する。
- 実機固有の制約を Simulator の結果だけで判断しない。

## 参照

- [Inside Playdate — SDK 3.1.1](https://sdk.play.date/3.1.1/Inside%20Playdate.html)
- [Playdate Developer](https://play.date/dev/)

