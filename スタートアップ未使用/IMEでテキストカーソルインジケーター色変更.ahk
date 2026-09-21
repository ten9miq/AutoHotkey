#Requires AutoHotkey v2.0
#SingleInstance Force

; Windows 11 の「テキスト カーソル インジケーター」の色を、
; アクティブウィンドウの IME 状態に応じて変更します。
; 事前に Windows の設定でテキスト カーソル インジケーターを有効にしてください。

#Include "lib\IMEv2.ahk"

; ===== 設定 =====

; IME ON  = 赤、IME OFF = 青
ImeOnColor := ColorRef(255, 60, 60)
ImeOffColor := ColorRef(0, 150, 255)

; 状態確認の間隔（ミリ秒）
CheckInterval := 200

CursorIndicatorRegKey := "HKCU\SOFTWARE\Microsoft\Accessibility\CursorIndicator"
CursorIndicatorRegValue := "IndicatorColor"

; --validate を付けて起動すると、設定変更なしで構文検査だけを行います。
if A_Args.Length && A_Args[1] = "--validate"
    ExitApp

lastImeState := -1

SetTimer CheckImeAndUpdateIndicator, CheckInterval
CheckImeAndUpdateIndicator()


CheckImeAndUpdateIndicator() {
    global ImeOnColor, ImeOffColor
    global CursorIndicatorRegKey, CursorIndicatorRegValue, lastImeState

    imeState := !!IME_GET()
    if imeState = lastImeState
        return

    color := imeState ? ImeOnColor : ImeOffColor
    try {
        RegWrite color, "REG_DWORD", CursorIndicatorRegKey, CursorIndicatorRegValue
        lastImeState := imeState
        NotifyCursorIndicatorSettingChanged()
    } catch Error as err {
        ; 書き込みに失敗したときは次回のタイマーで再試行する。
        TrayTip "IME インジケーター色変更", "レジストリに書き込めませんでした: " err.Message
    }
}


NotifyCursorIndicatorSettingChanged() {
    ; 設定値が変わったことを通知する。即時の表示更新は Windows 側の実装に依存する。
    static HWND_BROADCAST := 0xFFFF
    static WM_SETTINGCHANGE := 0x001A
    static SMTO_ABORTIFHUNG := 0x0002
    setting := "Software\Microsoft\Accessibility\CursorIndicator"
    result := 0

    DllCall "User32\SendMessageTimeoutW"
        , "Ptr", HWND_BROADCAST
        , "UInt", WM_SETTINGCHANGE
        , "Ptr", 0
        , "WStr", setting
        , "UInt", SMTO_ABORTIFHUNG
        , "UInt", 100
        , "Ptr*", &result
        , "Ptr"
}


; Windows の COLORREF 形式（0x00BBGGRR）へ変換する。
ColorRef(r, g, b) {
    return (b << 16) | (g << 8) | r
}
