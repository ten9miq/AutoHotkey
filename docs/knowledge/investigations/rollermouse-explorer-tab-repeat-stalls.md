---
type: investigation
status: current
summary: "Explorerだけキー間隔付きSendEventへ切り替えると、RollerMouseによるDownloadsを含む連続タブ移動が安定した"
tags: "file-explorer, tabs, rollermouse, sendinput, sendevent"
paths: "RollerMouse Copy Paste to Tab.ahk"
last_verified: "2026-08-21"
verified_commit: ""
freshness: version-sensitive
---

# RollerMouseからExplorerへの連続タブ移動が止まる

## 結論

File Explorerがタブ端で折り返さないことは原因ではない。物理キーボードの `Ctrl+Tab` では端から反対端へ移動することがユーザー操作で確認されている。

診断ログにより、Raw Input、キュー投入、`explorer.exe` 判定、`SendTabChord` 呼び出し、物理Ctrlの解放待ちまでは正常と確認した。Ctrl解放待ちを追加してもDownloadsタブだけ反応が悪いため、物理Ctrlとの重なりは単独の主因ではない。

原因はプロセス判定ではなく、Explorerへほぼ瞬時の `SendInput` を送っていたことと、Downloadsのビュー切替処理が重なる条件だった可能性が高い。Downloadsと他タブは同じ `explorer.exe`、同じフォーカス先コントロールでも結果が異なるため、プロセス名やフォーカス先コントロールによる分岐ミスでは説明できない。

Explorerだけを `SetKeyDelay 20, 30` の `SendEvent` に変更し、VS Code、サクラエディタ、ブラウザなどは従来の `SendInput` のままにしたところ、Downloadsを含むタブ移動が動作することをユーザー操作で確認した。

## 確認した事実

- Contour公式情報ではCopyボタンは `Ctrl+C` を生成する。
- リポジトリのコメントとRaw Input処理も、RollerMouseがチョード中にCtrlを押下する前提で実装されている。
- `SendTabChord` は元のC/VとCtrl/Shiftを明示的にupにしてから、タブ切替キーをdown/upする。
- AutoHotkeyのBlindモード仕様では、物理Ctrlが押されたままでも `{Blind}{Ctrl up}` によって論理Ctrlをupのままにできる。
- AutoHotkeyの `SendInput` はほぼ瞬時で、`SetKeyDelay` を無視し、送信中の物理入力をバッファする。
- 現在のファイル更新時刻は `2026-08-20 23:58:00`、対応すると考えられるAutoHotkey v2.0.19プロセスの開始時刻は `23:58:09`。古いファイルを実行している可能性は低い。
- Explorerで記録した33回の送信は、すべて `queue`、`dequeue_tab`、`send_begin`、`send_end` まで到達し、実行ファイル判定は常に `explorer.exe`、通常タブ分岐 `page=0` だった。
- 33回中27回は、物理Ctrlがdownの状態で `send_begin` に到達した。
- 6回は `send_end` 時点で物理Ctrlがup、論理Ctrlがdownとなっていた。
- この結果から、ダウンロードタブだけ別プロセスに誤判定される仮説は否定された。
- Ctrl解放待ち版の13回はすべてキュー投入から送信完了まで到達し、`ctrl_release_timeout` は発生しなかった。
- Ctrl解放待ち版では送信開始時のRaw Input、論理Ctrl、物理Ctrlがすべてupだった。
- Downloadsで記録したフォーカスは `DirectUIHWND2` で、他タブでも同じ値が記録された。
- 一部の `send_end` 直後だけ論理Ctrlがdownになったが、100 ms後の `send_settled` ではupに戻った。持続的なCtrl状態ずれではない。
- 上記の状態でもユーザー操作ではDownloadsだけ反応が悪かった。したがってCtrl競合の回避だけでは解消しない。
- Explorer専用 `SendEvent` 版では、Downloadsを含むタブ移動が動作することをユーザーが確認した。

## 無効になった調査結果

Windows UI Automation経由の合成キーで「Explorerは端で折り返さない」と判断したが、物理キーボードで反証された。合成入力そのものが今回の問題条件なので、この試験をExplorer固有仕様の根拠として使ってはいけない。

## 有効だった方法 / 現在の実装

`ProcessPendingChords` で、対象RollerMouseのRaw Inputまたは物理Ctrlがdownの間は、最大750 msまで送信を待つ。これにより元のCtrlと合成Ctrlの重なりを避ける。

この変更により送信開始時のCtrl状態は正常化したが、Downloadsだけ反応が悪い症状は残った。

Explorerだけ `SendInput` から `SendEvent` に変更し、`SetKeyDelay 20, 30` でキー間隔と押下時間を持たせる。ブラウザ、表計算、VS Code、サクラエディタなどの送信方式は変更しない。この分離により、他アプリの既存動作を変えずにExplorerの連続タブ移動が安定した。

## 再発時に必要なログ

RollerMouseの同一ボタンを連打して、各段階を時刻付きで記録する。

- Raw InputのCtrl down/up
- `QueueChord` の呼び出し有無、キー名、キュー長
- `SendTabChord` の直前・直後の `GetKeyState("Ctrl")` と `GetKeyState("Ctrl", "P")`
- 送信方式、送信時刻、前回送信からの間隔

判定方法:

- `QueueChord` 自体が来なくなる: Ctrl論理/物理状態と `$^c` / `$^v` の競合が主因。
- `QueueChord` と送信は記録されるがExplorerだけ移動しない: `SendInput`方式または送信間隔が主因。
- C/Vが120 ms以内に交互に入る: `FindTargetKeyCounterpart` が閉じる操作として消費している。

## 根拠

### Repository

- `RollerMouse Copy Paste to Tab.ahk` — `ProcessPendingChords`, `SendTabChord`, `OnRawInput`
- commit `0f1809a` — Blindモードを導入し、物理Ctrl押下中の自動再押下を抑止した変更。
- commit `b3b9358` — Raw Input判定と保留キュー処理を整理した変更。

### External

- AutoHotkey v2 Send documentation — https://doggy8088.github.io/AutoHotkeyDocs/docs/lib/Send.htm — 確認日: `2026-08-21`
  - 支える事実: Blind時の物理/論理修飾キー状態、SendInputの物理入力バッファ、ほぼ瞬時の送信、`SetKeyDelay`無効。
- AutoHotkey v2 How to Send Keystrokes — https://doggy8088.github.io/AutoHotkeyDocs/docs/howto/SendKeys.htm — 確認日: `2026-08-21`
  - 支える事実: 合成入力は物理入力を完全には再現せず、問題時は送信方式とタイミングの調整が必要。
- Contour Design RollerMouse Pro Help Center — https://www.contourdesign.com/support/help-center/rollermouse-pro — 確認日: `2026-08-21`
  - 支える事実: Copyボタンの動作確認では `Ctrl` と `C` が入力される。

## 未解決・再確認条件

- WindowsまたはAutoHotkey更新後に同じ症状が再発したとき。
- `SendEvent` でも再現する場合、Explorer送信間の最小間隔を設けて比較する。
