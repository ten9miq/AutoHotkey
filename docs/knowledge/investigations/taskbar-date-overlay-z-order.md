---
type: investigation
status: current
summary: "日付GUIはAlwaysOnTopでもタスクバーの裏へ回るため、各タスクバーの検出とSetWindowPosによる順序更新が必要"
tags: "taskbar, overlay, z-order, multi-monitor, DPI"
paths: "TaskbarDateOverlay.ahk"
last_verified: "2026-10-26"
verified_commit: ""
freshness: version-sensitive
---

# タスクバーの日付オーバーレイが見えない場合

## 確認した原因と対応

`+AlwaysOnTop` を指定した可視GUIでも、同じ最前面グループにあるタスクバーより後ろに並ぶ場合がある。2026-10-26の実機では、元GUIは日付テキストと正常な座標を持っていたが、`WinGetList()` の順序で `Shell_TrayWnd` より後ろだった。

`TaskbarDateOverlay.ahk` の `UpdateDate()` はGUIの表示後に `SetWindowPos(HWND_TOPMOST, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)` を呼び、フォーカスを移さず手前へ戻す。位置だけの更新や起動時のAlwaysOnTop指定では、この順序の維持を保証しない。

複数モニターでは、メインの `Shell_TrayWnd` だけでなく `Shell_SecondaryTrayWnd` も列挙し、タスクバーのHWNDごとにGUIを保持する。これらのExplorerウィンドウクラスはOS更新後に再確認する。

## 検証の境界

AutoHotkey v2.0.28、4モニター、各タスクバーDPI 144の実機で、短時間終了するIncludeラッパーと再読み込み後の本体を確認した。左端に配置する初版では、4個のGUIが各タスクバー内にあり、前面順序、180x36のサイズ、日付文字列の存在、WM_NULLへの応答を確認した。反復更新でサイズが変わらないことも確認した。

これは目視による文字の可読性、アイコンとの重なり、クリック透過の実入力テストを証明しない。異なるDPIの混在、モニター切断、Explorer再起動、全画面、自動非表示の実操作は別途確認が必要。

## 時計の検出と文字サイズ

同日の時計上段対応では、専用の時計HWNDはなく、UIAの時計ボタンを利用した。現在の実機ではClassNameが `SystemTray.AccentButton`、AutomationIdが `SystemTrayIcon` だが、両方とも他の通知領域ボタンと共通だった。そのため、ClassNameで候補を絞り、Nameの先頭 `時計` / `Clock` で識別する。その他の表示言語では検出条件の調整が必要。

4台の時計ボタンは110x48ピクセルだった。時刻テキストそのものは子要素もTextPatternも公開していないため、`GetClockRect()` はボタン全体の矩形を取得する。上1/4に配置する前版では高さが12ピクセルとなり、可読性が不足したため、現在は時計の左隣の下半分に配置する。

`FitDateText()` は実際に設定したフォントを `GetTextExtentPoint32W` で測り、幅と高さが収まるまで0.25ポイント刻みで縮小する。DPI・日付・領域が変わった場合だけ再計測する。実機の領域100x12ピクセルでは、日付文字列の実測43x12、5.25ポイントに収まることをIncludeラッパーで確認した。背景色の透過設定も確認した。

- [Microsoft: GetTextExtentPoint32W](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-gettextextentpoint32w): 選択中のフォントによる文字列の幅と高さを取得する。確認日: 2026-10-26。

## 時計左隣の下半分とクリック透過

現在は `DATE_WIDTH` と `CLOCK_GAP` で時計左隣の幅と間隔を定め、タスクバー下半分を使う。縁取り追加前の4台では領域180x24ピクセル、日付の実測73x21ピクセル、8.25ポイントとなった。文字サイズの下限を8ポイントに上げ、以前の4ポイントまでの縮小は行わない。

重なったアイコンと区別するため、現在は白い太字と1物理ピクセルの黒い縁取りを使う。`SS_OWNERDRAW` のTextコントロールを `WM_DRAWITEM` から描画し、透過色で領域を消してから黒い文字を周囲8方向、白い文字を中央へ描く。測定値にも縁取りの余白を含める。現在の実機では8.25ポイント、縁取り込み79x23ピクセルで収まった。同じ描画関数をメモリー上のDIBへ実行し、白・黒・透過背景の画素が生成されることを確認した。`DATE_X_OFFSET` は拡大率100%時の右方向への移動量で、150%では設定値の1.5倍の物理ピクセル数になる。

GUIの `WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE` を明示する。レイヤードウィンドウとTRANSPARENTの組合せは、透過背景だけでなく文字部分を含むマウスイベントを背後へ通す。`WS_EX_TRANSPARENT` の描画順序に関する一般説明だけでクリック透過を判断しない。

短時間終了ラッパーで4台分のサイズ、下半分への配置、時計左隣への配置、文字の収まりを確認した。各GUIの文字中央付近3点で `WindowFromPoint` と `GetAncestor(GA_ROOT)` を使い、対応するタスクバーがヒットテスト先になることを確認した。再読み込み後の本体でも4個のGUIの中央が背後のタスクバーへ通ることを確認した。これは実際にアイコンをクリックして起動した確認とは区別する。

- [Microsoft: Layered Windows](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows): WS_EX_TRANSPARENT付きレイヤードウィンドウのマウスイベントは背後へ渡される。確認日: 2026-10-26。

## 再検証

- `WinGetList()` は前面から背面の順なので、GUIが対応タスクバーより先にあることを確認する。
- `WinGetPos()` でGUIが対応タスクバーの矩形内にあることを確認する。
- GUIの可視状態、テキストの存在、応答と、実際にユーザーから見える状態を区別する。

## 外部根拠

確認日: 2026-10-26。

- [Microsoft: SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos): HWND_TOPMOSTとSWP_NOACTIVATEなどの定義。
- [AutoHotkey: WinGetList](https://github.com/AutoHotkey/AutoHotkeyDocs/blob/v2/docs/lib/WinGetList.htm): 前面から背面への列挙順。
