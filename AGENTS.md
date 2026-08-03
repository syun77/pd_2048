# AGENTS.md

## プロジェクト概要

このリポジトリは、Playdate 向けの 5×5 盤面「2048 回転マージ落ちものパズル」です。実行対象の Playdate プロジェクトは `pd_2048/` 配下にあり、Lua のエントリーポイントは `pd_2048/source/main.lua` です。

現行仕様の正本は `仕様書/playdate_2048_ゲーム仕様書.md` です。入力の抽象化・自動プレイ・将来のリプレイ設計については `仕様書/入力制御とリプレイ設計.md` を参照してください。

Playdate SDK の一般仕様、Lua 実行モデル、`CoreLibs`、入力、描画、音声、保存、`pdc`、Simulator については `.agents/playdate_sdk.md` を参照してください。

AGENTS 関連の補助文書を作成・更新する際は `.agents/AGENTS作成ルール.md` に従い、内容を簡潔に保ってください。

## リポジトリ構成

- `pd_2048/source/`: Playdate Lua ソース、画像以外のアセット、BGM/SE
  - `board/`: 盤面描画、合法判定、回転変換
  - `game/`: ゲーム進行、セッション、マージ、UNDO
  - `input/`: 論理入力、入力履歴、自動プレイ
  - `render/`: ゲーム画面、HUD、オーバーレイ、タイトル描画
  - `scene/`: タイトル、ゲーム、ゲームオーバー、実績、統計シーン
  - `assets/practice/`: PRACTICE 用の連番 JSON ステージ
- `pd_2048/builds/`: `.pdx` 出力先。`.gitkeep` 以外はコミットしない
- `仕様書/`: 日本語のゲーム仕様書と入力・リプレイ設計書
- `.vscode/`: Playdate の Lua 診断、ビルド、シミュレータ起動設定

## 開発環境とビルド

Playdate SDK の `pdc` を使用します。リポジトリルートから次を実行できます。

```sh
pdc pd_2048/source pd_2048/builds
```

VS Code では `Playdate: Build`、または既定の `Playdate: Build and Run` タスクを使います。後者はビルド後に Playdate Simulator を起動します。`pdc` が見つからない場合は Playdate SDK をインストールし、`pdc` を `PATH` に追加してください。

このリポジトリには自動テストスイートがありません。変更後は最低限、`pdc` のビルド、Playdate Simulator での起動、変更対象の操作確認を行ってください。

## Playdate Lua のルール

- Playdate のモジュール読み込みは `require` ではなく `import "path"` を使う。
- Playdate 固有 API と `CoreLibs` を前提にする。標準 Lua の `io`、`os`、`package` は利用しない。
- Lua は 5.4 相当。既存コードに合わせ、インデントはスペース 4 個、代入演算子 `+=` などの Playdate 拡張を許容する。
- グローバル公開が必要なモジュールは既存の `_G.Name = Name` と `return Name` の形式に合わせる。新規コードでは可能な限り依存関係を明示し、不要なグローバルを増やさない。
- 画面更新は `main.lua` → `App:update/draw` → シーン・コントローラの流れに従う。描画処理にゲーム状態の変更を混ぜない。
- 共有設定は `game_config.lua` に集約し、マジックナンバーをゲームロジックへ直接追加しない。

## ゲームロジック上の不変条件

- 論理座標は 1 始まりで、左上が `(1,1)`、右下が `(5,5)`。中央の `(3,3)` は常に空き、ブロック配置・回転・マージの対象外。
- 盤面ルールの判定は `board/board_rules.lua`、回転は `board/board_transform.lua`、マージ候補探索は `game/merge_resolver.lua` に置く。各所で同じルールを再実装しない。
- 回転後に盤面全体を下へ詰める重力処理は現行仕様にない。`applyGravity` は中央セルを空に保つための処理である。
- 1手の順序は、入力受付 → 落下先検索 → DROP/HOLD → 落下確定 → マージ反復 → 必要なら 90 度回転 → 回転後のマージ反復 → NEXT 更新 → ゲームオーバー判定。アニメーション中は入力を受け付けない。
- 乱数生成は `math.random` を使い、既存の連続値制御と UNDO 復元を壊さない。入力履歴だけでは乱数系列を完全再現できない点に注意する。
- モードは NORMAL、TIME ATTACK、CORE RUSH、PRACTICE。モード固有の状態・勝利条件・記録キーは既存の `GameState`、`GameController`、仕様書の対応を確認して変更する。
- 実機入力、自動プレイ、リプレイ入力は論理コマンド経由で扱い、ゲームロジックを Playdate ボタン API に直接結び付けない。

## 変更の進め方

1. 変更対象のモジュールと呼び出し元を確認する。特に `game_controller.lua` は状態遷移の中心なので、変更範囲を小さく保つ。
2. 仕様変更なら実装と `仕様書/playdate_2048_ゲーム仕様書.md` を同じ変更で更新する。入力・リプレイの変更は `仕様書/入力制御とリプレイ設計.md` も更新する。
3. PRACTICE ステージを追加・変更する場合は `pd_2048/source/assets/practice/NNN.json` の連番・既存 JSON のスキーマ・`PracticeStageLoader` の読み込み条件を確認する。
4. ビルドし、Simulator で通常の DROP、HOLD、長押し REWIND、盤面回転、ゲームオーバーを確認する。対象がモード・自動プレイ・PRACTICE・描画なら、その経路も確認する。
5. 生成された `pd_2048/builds/*.pdx`、一時設定、`.DS_Store` をコミットに含めない。変更前から存在する無関係な差分は上書き・削除しない。

## コミット前チェック

```sh
git status --short
pdc pd_2048/source pd_2048/builds
```

ビルドエラーが残る状態で完了扱いにしない。テストを追加できるロジック変更では、少なくとも盤面座標、落下可能セル、回転変換、マージ方向などの境界条件を手動または小さな検証コードで確認する。
