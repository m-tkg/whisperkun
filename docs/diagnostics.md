# 診断ログの採取

whisperkun は subsystem `com.mtkg.whisperkun`（`Sources/whisperkun/Support/Log.swift` で一元化、
本番/ローカル検証ビルド共通）で OSLog に出力する。`Resources/Info.plist` の `OSLogPreferences` で
debug レベルを常時 Enable + Persist しているため、事象の発生後・アプリ再起動後でも取り出せる。

## 採取コマンド

```sh
log show --predicate 'subsystem == "com.mtkg.whisperkun"' --debug --info --last 1h --style compact
```

- `--last` は事象からの経過に応じて調整する（`--last 3h` など）。
- リアルタイムで追う場合は `log stream --predicate 'subsystem == "com.mtkg.whisperkun"' --debug`、
  もしくは Console.app で subsystem を絞り「情報/デバッグメッセージを含める」を有効にする。

## カテゴリと読みどころ

| カテゴリ | 内容 |
|---|---|
| `transcription` | phase 遷移の背骨ログ（`phase: idle -> preparing gen=N` など）。固着時はどこで遷移が止まったかをまずここで確認する |
| `coordinator` | begin/end/cancel と drop（`begin dropped: ...`）。ホットキーからの開始/停止要求が届いたか |
| `hotkey` | 押下/解放の検出（`applyDownState`）、解放取りこぼしの保険（`reconcile`）、タップ無効化（`tap disabled`）、長時間押下スナップショット（`long-hold`） |

## 「認識中」のまま固着したとき

HUD が「認識中」のまま戻らない事象は、解放イベントの取りこぼし + `CGEventSource.flagsState` が
解放後も幽霊的に down を返し続けることが原因と推定している（別の修飾キーや英数キーを押すと
集約フラグが再評価され復帰する）。発生したら:

1. **復帰操作（別キーを押す等）をする前に、発生時刻をメモする**。復帰後でもログは残るが、
   時刻が分かるとスナップショットの特定が速い。
2. 上記コマンドでログを採取する。
3. `hotkey` カテゴリの `long-hold` 行（押下 15 秒超で 2 秒ごとに出る）を確認する:

   ```
   long-hold: tick=68 elapsed=17s flags=... keys=[59:s0h0] modifierIsDown=true phase=listening gen=3 isActive=true isFinishing=false
   ```

   - `keys=[59:s0h0]` — keyCode 59（左Control）の物理状態。`s`=combinedSessionState、
     `h`=hidSystemState、`1`=down / `0`=up。
   - **物理的にキーを離しているのに `modifierIsDown=true` が続き、`keys` が `s0h0`（両ストア up）で
     `flags` のクラスビットだけ立ったまま**なら、幽霊 flags 固着で確定。
   - `long-hold` 行自体が出ていなければ releaseWatch が回っていない（別の問題）。
4. 併せて `reconcile` 行（250ms ごと）の `isDown`/`keys` の時系列と、`transcription` の
   phase 遷移が `listening` で止まっていることを確認する。

過去の経緯: 解放判定を `keyState` に切替えたところ hold 中の稀な false で誤停止する regression が
出たため（v1.0.23 → v1.0.24 で revert）、判定は `flagsState` のまま、`keyState` は観測のみに使う。
