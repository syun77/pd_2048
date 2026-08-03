# Playdate SDK 指示書

この文書は、特定のゲームやリポジトリの構成に依存しない Playdate SDK の基本仕様をまとめたものです。SDK の API はバージョンによって変わる可能性があるため、詳細な仕様や未掲載 API は、使用中の SDK に同梱された Inside Playdate を優先してください。

## SDK の構成

Playdate SDK には、主に次のものが含まれます。

- Lua または C でゲームを作るための API とライブラリ
- Lua/C プロジェクトを .pdx に変換する pdc（Playdate Compiler）
- Playdate Simulator
- CoreLibs、サンプル、型定義、ドキュメント

Lua は開発しやすく、C は性能が厳しい処理に向きます。Lua と C を同一ゲームで併用することもできます。

## ハードウェアの前提

- ディスプレイは 1-bit モノクロ LCD、解像度は 400×240 ピクセル。
- 標準の更新レートは 30 fps、設定可能な最大値は 50 fps。
- 主な入力は D-pad、A/B ボタン、クランク、加速度センサー。Menu ボタンと Lock ボタンはシステム操作に使われます。
- RAM は 16 MB、内蔵フラッシュストレージは 4 GB。
- Simulator は実機より高速に動作することがあるため、性能確認は実機でも行います。

## プロジェクト構造

Lua プロジェクトの source ディレクトリには、最低限 main.lua が必要です。スクリプトと画像・音声・データなどのアセットは同じプロジェクトの source ツリーに置きます。

~~~text
MyGame/
└── source/
    ├── main.lua
    ├── pdxinfo
    ├── images/
    ├── sounds/
    └── data/
~~~

pdxinfo は source 直下に置きます。パス区切りには常に / を使い、Windows のバックスラッシュをコードやアセットパスに使わないでください。Windows Simulator で動いても、実機や他の環境で壊れる可能性があります。

## Lua の読み込みと実行

Playdate Lua は標準 Lua の require ではなく import "path/to/file" を使います。

~~~lua
import "CoreLibs/graphics"
import "game"
~~~

import されたファイルは依存関係をたどってコンパイルされ、同一の compiled bundle 内では一度だけ実行されます。ファイルの返り値だけをモジュール境界として扱えるとは限らないため、公開方法と SDK の import の実行モデルを確認してください。

Playdate の Lua には標準 Lua にない追加代入演算子などがあります。エディタ・型定義には Playdate の import、グローバル playdate、SDK の Lua バージョンと追加構文を認識させます。標準 Lua のライブラリがすべて利用できるとは限らないため、ファイル I/O や OS 操作を標準ライブラリ前提で実装しないでください。

## エントリーポイントとフレームループ

ゲームは通常、main.lua で playdate.update() を定義します。Playdate OS はこの関数を各フレームの直前に呼び出します。

~~~lua
function playdate.update()
    -- 入力、ゲーム状態更新、描画
end
~~~

- デフォルトの呼び出し頻度は 30 fps。
- playdate.display.setRefreshRate(rate) で目標更新レートを変更できます。通常は 30 fps を基準にします。
- rate == 0 は可能な限り高速に呼び出すモードですが固定レートではありません。経過時間は playdate.getCurrentTimeMilliseconds() などの時間基準で計算します。
- update() が長すぎると指定レートを維持できません。重い処理は分割し、必要な場合だけ coroutine.yield() を検討します。
- 描画と状態更新の責務を分離し、フレームごとの処理量を実機で確認します。

## CoreLibs

CoreLibs は SDK に付属する Lua 製のオプションライブラリです。必要なライブラリを明示的に import して使用します。

~~~lua
import "CoreLibs/graphics"
import "CoreLibs/object"
import "CoreLibs/timer"
~~~

利用する機能に応じて、graphics、object、sprite、timer、frameTimer、animation、json などの該当ライブラリと API ドキュメントを確認してください。タイマーを使う場合は CoreLibs/timer の import に加え、毎フレーム playdate.timer.updateTimers() を呼ぶ必要があります。frame timer も playdate.frameTimer.updateTimers() を更新ループから呼びます。

## 入力

入力ボタンには次の定数を使います。

- playdate.kButtonA
- playdate.kButtonB
- playdate.kButtonUp
- playdate.kButtonDown
- playdate.kButtonLeft
- playdate.kButtonRight

基本的な問い合わせ API は次のとおりです。

~~~lua
if playdate.buttonJustPressed(playdate.kButtonA) then
    -- 押下されたフレームに一度だけ実行
end

if playdate.buttonIsPressed(playdate.kButtonB) then
    -- 押下中の各フレームで実行
end

if playdate.buttonJustReleased(playdate.kButtonB) then
    -- 離されたフレームに一度だけ実行
end
~~~

buttonJustPressed は押下から一度だけ true になり、いったん離すまで再び true になりません。長押し、キーリピート、同時押し、入力の優先順位が必要な場合は、フレーム間の状態を管理するか、入力ハンドラ API を使います。ゲームロジックを実機ボタン API に直接結合せず、論理コマンドへ変換すると Simulator、自動入力、リプレイを差し替えやすくなります。

クランク入力は playdate.getCrankPosition()、playdate.getCrankChange()、クランク状態問い合わせ・コールバック API を用途に応じて使います。Simulator ではクランクと加速度センサーもエミュレートできます。

## グラフィックスとディスプレイ

描画 API は playdate.graphics（通常は local gfx = playdate.graphics）を使います。画面は 1-bit なので、色・パターン・アンチエイリアスが実機でどう見えるかを確認してください。

- 座標の原点は画面左上。
- 標準画面サイズは 400×240。
- gfx.clear()、画像、図形、テキスト、Sprite、Tilemap、Offscreen Drawing など目的に合う API を選びます。
- Sprite を使う場合は、毎フレーム必要な Sprite 更新処理を呼び、dirty 更新の仕様を理解します。
- 画面サイズは display scale の影響を受ける API があるため、固定値を使う必要がない箇所では playdate.display.getWidth()、getHeight()、getSize()、getRect() を使います。
- 大量の画像生成、毎フレームの大きなテーブル生成、不要な全画面再描画は避け、メモリとフレーム時間を測定します。

## 音声

音声ファイルは SDK がサポートする形式とエンコード条件に従います。短い効果音には playdate.sound.sampleplayer、長い BGM には playdate.sound.fileplayer など用途に合うプレイヤーを選びます。

~~~lua
local player = playdate.sound.sampleplayer.new("sounds/confirm")
player:play()
~~~

アセットのパスは source からの相対パスで指定し、拡張子の扱いは使用する API と SDK ドキュメントに合わせます。BGM の終了 callback、音量、停止、同時発音数を実機で確認します。

## ファイル、保存データ、JSON

### アセットファイル

playdate.file はゲームに同梱したファイルの読み書き・一覧取得などに使います。読み書き可能な場所、実機と Simulator の差、ファイルが存在しない場合の戻り値を確認し、ファイル操作の失敗を前提にエラーハンドリングします。

### Datastore

playdate.datastore は Lua table や画像を保存するための API です。

~~~lua
playdate.datastore.write(data, "save")
local data = playdate.datastore.read("save")
~~~

- filename に .json 拡張子は付けません。SDK が JSON ファイルとして扱います。
- read は対象が存在しない場合に nil を返す可能性があります。
- 保存データは将来のバージョン変更で読めない場合があるため、必要に応じて schema/version と移行処理を用意します。
- 終了・スリープ時の callback だけを唯一の保存機会にせず、重要な進行状態は適切なタイミングで保存します。

### JSON

SDK の JSON API は文字列またはファイルを Lua table に変換できます。

~~~lua
local stage = json.decodeFile("data/stage.json")
local encoded = json.encode(data)
local formatted = json.encodePretty(data)
~~~

外部データは不正・欠損・型違いを想定し、pcall や型検証を行います。JSON の読み込みと datastore の保存は用途が異なるため、同じファイルを両方の API で管理しないでください。

## メタデータ（pdxinfo）

source 直下の pdxinfo にはゲームのメタデータを設定します。代表的なキーは次のとおりです。

~~~ini
name=My Game
author=Author Name
description=Description
bundleID=com.example.mygame
version=1.0.0
buildNumber=1
~~~

bundleID は逆 DNS 形式の一意な識別子にします。buildNumber は更新判定に使われるため、リリースごとに単調増加させます。metadata は playdate.metadata から読めますが、実行時に変更してもゲームのメタデータ自体は更新されません。

## コンパイルと Simulator

pdc は入力 source ディレクトリと出力 .pdx ディレクトリを受け取ります。

~~~sh
pdc path/to/source path/to/MyGame.pdx
~~~

関連する環境変数・オプションは次のとおりです。

- PLAYDATE_SDK_PATH: SDK の場所。pdc の既定 SDK パスとして利用されます。
- PLAYDATE_LIB_PATH: 外部 import ライブラリの検索場所。
- -sdkpath: SDK の場所を明示指定。
- -I / --libpath: import 検索パスを追加。
- -s / --strip: デバッグ情報を削除。
- -v / --verbose: 詳細ログ。
- -q / --quiet: 通常ログを抑制。
- -k / --skip-unknown: 未認識ファイルを出力へコピーしない。

.pdcignore を source 直下に置くと、コンパイル対象から特定のファイル・フォルダを除外できます。ワイルドカードや正規表現が使えるとは限らないため、使用中 SDK の仕様を確認します。

Simulator では .pdx を開く、ドラッグする、またはダブルクリックして実行します。Simulator は入力やクランクをエミュレートできますが、性能は実機と一致しません。リリース前は実機で入力、描画、音声、保存、消費電力、フレームレートを確認します。

## 実装時の一般原則

- SDK API の前提をラッパーやゲームロジックへ混在させず、入力・描画・音声・保存の境界を分ける。
- 初期化時に大量のアセットや不要なオブジェクトを生成せず、ロード時間・RAM・ガベージコレクションを監視する。
- フレーム依存の処理と時間依存の処理を区別する。ゲーム速度やタイマーを fps 固定のカウンタだけで実装しない。
- Simulator で再現できないデバイス固有の問題を想定し、定期的に実機で確認する。
- API の使い方が曖昧な場合は、使用中 SDK の Inside Playdate、SDK 内の CoreLibs ソース、公式サンプルを確認する。古い記事や第三者ライブラリの仕様を SDK 本体の仕様として扱わない。

## 参照先

- [Inside Playdate — SDK 3.1.1](https://sdk.play.date/3.1.1/Inside%20Playdate.html)
- [Playdate Developer](https://play.date/dev/)
- [How do I make a game for Playdate?](https://help.play.date/games/how-do-i-make-a-game/)

この文書の内容は SDK 3.1.1 の公式ドキュメントと Playdate SDK の一般的な開発モデルに基づいています。SDK を更新したときは、特に API、コンパイラオプション、対応音声形式、Simulator、ハードウェア制約を再確認してください。

