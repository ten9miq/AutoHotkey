#Requires AutoHotkey v2.0+
; RCtrl2連打でカーソルをモニター中央に移動
; Alt+F1で固定先モニターを現在カーソルがあるモニターに設定
; Alt+F2で動的 / 固定モードを切り替え

InstallKeybdHook()

; 混在DPIのマルチモニターでも物理ピクセル座標を使用
DllCall("user32\SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")
CoordMode "Mouse", "Screen"

; ダブルタップ閾値（ミリ秒）
doubleTapThreshold := 400

;=== 設定ファイルのパス & 起動時に読み込み ===
iniFile := A_ScriptDir "\RCtrl2連打でモニター中央に移動.ini"

; 固定先モニター番号
FixedMonitor := IniRead(iniFile, "Settings", "FixedMonitor", 0) + 0

; 動的 / 固定モード
; 0 = 動的モード
; 1 = 固定モード
FixedMode := IniRead(iniFile, "Settings", "FixedMode", "ERROR")

; 旧設定との互換
; 旧版では FixedMonitor=0 が動的、FixedMonitor>=1 が固定だったため、
; FixedMode が存在しない場合だけ旧設定から初期モードを推定する
if (FixedMode = "ERROR") {
    FixedMode := (FixedMonitor = 0) ? 0 : 1
} else {
    FixedMode := FixedMode + 0
}


;=== Alt+F1 で固定先モニターを現在カーソルがあるモニターに設定 ===
!F1::SetFixedMonitorFromCursor()

SetFixedMonitorFromCursor() {
    global FixedMode, FixedMonitor, iniFile

    MouseGetPos &mouseX, &mouseY
    currentMonitor := GetMonitorFromPoint(mouseX, mouseY)

    if (currentMonitor >= 1) {
        FixedMonitor := currentMonitor
        FixedMode := 1
        IniWrite FixedMonitor, iniFile, "Settings", "FixedMonitor"
        IniWrite FixedMode, iniFile, "Settings", "FixedMode"

        ToolTip "固定モード / 移動先モニター " FixedMonitor
    } else {
        ToolTip "固定先モニターを判定できませんでした"
    }

    SetTimer RemoveToolTip, -1000
}


;=== Alt+F2 で動的 / 固定モード切り替え ===
!F2::ToggleFixedMode()

ToggleFixedMode() {
    global FixedMode, FixedMonitor, iniFile

    monitorCount := MonitorGetCount()

    if (FixedMode = 0) {
        ; 動的 → 固定

        ; 固定先が未設定または無効なら、現在カーソルがあるモニターを固定先にする
        if (FixedMonitor < 1 || FixedMonitor > monitorCount) {
            MouseGetPos &mouseX, &mouseY
            currentMonitor := GetMonitorFromPoint(mouseX, mouseY)

            if (currentMonitor >= 1) {
                FixedMonitor := currentMonitor
                IniWrite FixedMonitor, iniFile, "Settings", "FixedMonitor"
            }
        }

        FixedMode := 1
    } else {
        ; 固定 → 動的
        FixedMode := 0
    }

    IniWrite FixedMode, iniFile, "Settings", "FixedMode"

    modeText := FixedMode
        ? "固定モード / 移動先モニター " FixedMonitor
        : "動的モード"

    ToolTip "モード：" modeText
    SetTimer RemoveToolTip, -1000
}


;=== 右Ctrl ダブルタップでカーソル移動 ===
~SC11D::{
    global doubleTapThreshold

    if (A_PriorHotkey = A_ThisHotkey
        && A_TimeSincePriorHotkey < doubleTapThreshold) {
        MoveCursorToTargetMonitor()
    }
}


;=== カーソル移動処理 ===
MoveCursorToTargetMonitor() {
    global FixedMode, FixedMonitor

    MouseGetPos &mouseX, &mouseY
    monitorCount := MonitorGetCount()

    if (FixedMode = 1) {
        ; 固定モード：Alt+F1で選んだ固定先へ移動
        destination := FixedMonitor

        ; 固定先が無効なら、現在カーソルがあるモニターにフォールバック
        if (destination < 1 || destination > monitorCount) {
            destination := GetMonitorFromPoint(mouseX, mouseY)
        }
    } else {
        ; 動的モード：現在カーソルがあるモニターへ移動
        destination := GetMonitorFromPoint(mouseX, mouseY)
    }

    if (destination >= 1 && destination <= monitorCount) {
        MoveCursorToMonitorCenter(destination)
    }
}


;=== 指定座標が属するモニター番号を返す ===
GetMonitorFromPoint(x, y) {
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        MonitorGet A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom

        if (x >= monitorLeft && x <= monitorRight
            && y >= monitorTop && y <= monitorBottom) {
            return A_Index
        }
    }

    return 0
}


;=== 指定モニターの中央へカーソルを移動 ===
MoveCursorToMonitorCenter(monitorNumber) {
    monitorCount := MonitorGetCount()

    if (monitorNumber < 1 || monitorNumber > monitorCount) {
        return
    }

    MonitorGet monitorNumber, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom

    centerX := (monitorLeft + monitorRight) // 2
    centerY := (monitorTop + monitorBottom) // 2

    DllCall("user32\SetCursorPos", "Int", centerX, "Int", centerY, "Int")
}


;=== ツールチップを消すタイマー ===
RemoveToolTip() {
    ToolTip
}