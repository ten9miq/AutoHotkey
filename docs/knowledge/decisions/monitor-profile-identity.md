---
type: decision
status: current
summary: "RCtrl移動先は接続中のモニターID集合ごとに保存し、列挙番号が変わってもIDから移動先を解決する"
tags: "monitor, display, RCtrl, profile, ini"
paths: "RCtrl2連打でモニター中央に移動.ahk"
last_verified: "2026-10-24"
verified_commit: ""
freshness: version-sensitive
---

# モニター構成別のカーソル移動先

## 判断と理由

モニター番号は接続構成によって変わりうるため、保存対象を番号からデバイスインターフェイス名へ変更した。`GetMonitorIdentity` は `MonitorGetName` のGDI名を `EnumDisplayDevicesW` に渡し、`EDD_GET_DEVICE_INTERFACE_NAME=1` で取得したアクティブなモニターの `DeviceID` を使う。`DISPLAY_DEVICEW` は840バイト、`StateFlags` はオフセット324、`DeviceID` は328。

`BuildMonitorConfigurationKey` はIDをソートして結合する。画面番号、配置、解像度は構成キーに含めない。`FindMonitorById` が操作時の番号へ解決し直すため、保存後に列挙順が変わっても同じIDを選べる。

INIの `MonitorProfileN` ごとに `Configuration`、`FixedMonitorId`、`FixedMode` を保存する。旧 `Settings` は最初の構成へ一度だけ移行し、未登録の構成へ繰り返し適用しない。新規構成の既定は動的モード。Alt+F1で構成別の固定先を保存し、Alt+F2で構成別のモードを保存する。

## 制約と再確認条件

- デバイスインターフェイス名はEDIDの製造番号ではない。接続端子、ドック、ドライバー等の変更でIDが変わった場合は、新しい構成として登録が必要になりうる。
- IDを取得できないリモート画面等ではGDI名へフォールバックする。この場合、番号変更に対する識別の安定性は保証できない。
- 操作のたびに構成を読み直す。実際の抜き差し、ホットキー入力、カーソル移動の確認は、保存・復元ロジックの自動確認と区別する。

## 根拠・検証

- 対象スクリプトの `GetMonitorIdentity`、`BuildMonitorConfigurationKey`、`LoadMonitorProfile`、`SaveMonitorProfile`。
- AutoHotkey v2.0.28の一時 `#Include` ラッパーで構文検証。短時間の `SetTimer` と `/ErrorStdOut` を使用し、終了コード0。
- 一時INIによる保存・復元、単画面と複数画面の分離、同数で異なるIDの分離、列挙順変更、モード独立保存、旧設定の一度限りの移行を自動確認し終了コード0。実機の4画面すべてでGDIフォールバックを使わずIDを取得できた。
- [EnumDisplayDevicesW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumdisplaydevicesw) — 確認日: 2026-10-24。フラグ1でモニターごとのインターフェイス名をDeviceIDに取得する仕様。
- [DISPLAY_DEVICEW](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-display_devicew) — 確認日: 2026-10-24。構造体のフィールド構成とDISPLAY_DEVICE_ACTIVEの意味。
