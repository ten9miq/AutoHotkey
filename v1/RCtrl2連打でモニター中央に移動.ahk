; RCtrl2連打でカーソルをモニター中央に移動
;
; 動的モード:
;   右Ctrlを2連打した時点で、カーソルが存在するモニター中央へ移動
;
; 固定モード:
;   Alt+F1で現在カーソルが存在するモニターを固定先に設定
;   右Ctrl2連打時は常にそのモニター中央へ移動
;
; Alt+F2:
;   動的モード / 固定モード 切り替え

#NoEnv
#Persistent
#InstallKeybdHook
SetBatchLines, -1

DllCall("SetProcessDPIAware")
CoordMode, Mouse, Screen

doubleTapThreshold := 400

iniFile := A_ScriptDir "\RCtrl2連打でモニター中央に移動.ini"

; 0 = 動的モード
IniRead, FixedMonitor, %iniFile%, Settings, FixedMonitor, 0
FixedMonitor := FixedMonitor + 0

;========================
; Alt+F1
; 現在カーソルが存在するモニターを固定先に設定
;========================
!F1::
    FixedMonitor := GetCurrentMonitor()

    if (FixedMonitor = 0) {
        ToolTip, 固定対象のモニターを判定できませんでした
        SetTimer, _RemoveTip, -1000
        return
    }

    IniWrite, %FixedMonitor%, %iniFile%, Settings, FixedMonitor

    ToolTip, % "固定先モニター：" FixedMonitor
    SetTimer, _RemoveTip, -1000
return

;========================
; Alt+F2
; 動的 / 固定 モード切り替え
;========================
!F2::
    if (FixedMonitor = 0) {
        FixedMonitor := GetCurrentMonitor()

        if (FixedMonitor = 0) {
            ToolTip, 固定対象のモニターを判定できませんでした
            SetTimer, _RemoveTip, -1000
            return
        }

        modeText := "固定モード：モニター " FixedMonitor
    } else {
        FixedMonitor := 0
        modeText := "動的モード"
    }

    IniWrite, %FixedMonitor%, %iniFile%, Settings, FixedMonitor

    ToolTip, %modeText%
    SetTimer, _RemoveTip, -1000
return

;========================
; 右Ctrl ダブルタップ
;========================
~SC11D::
    if (A_PriorHotkey = A_ThisHotkey && A_TimeSincePriorHotkey < doubleTapThreshold) {
        SysGet, totalMon, MonitorCount

        dest := FixedMonitor

        ; 動的モード
        if (dest = 0) {
            dest := GetCurrentMonitor()
        }

        if (dest >= 1 && dest <= totalMon) {
            SysGet, mon, Monitor, %dest%

            cx := (monLeft + monRight) // 2
            cy := (monTop  + monBottom) // 2

            MouseMove, %cx%, %cy%, 0
        }
    }
return

;========================
; 現在マウスが存在するモニター番号を取得
;========================
GetCurrentMonitor() {
    MouseGetPos, mx, my
    SysGet, totalMon, MonitorCount

    Loop, %totalMon% {
        SysGet, mon, Monitor, %A_Index%

        if (mx >= monLeft && mx < monRight && my >= monTop && my < monBottom) {
            return A_Index
        }
    }

    return 0
}

;========================
; ToolTip消去
;========================
_RemoveTip:
    ToolTip
return