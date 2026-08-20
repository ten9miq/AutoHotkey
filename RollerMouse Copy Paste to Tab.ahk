#Requires AutoHotkey v2.0+
#SingleInstance Force
InstallKeybdHook()
SendMode "Input"

; Raw Inputのデバイスパスに含まれる文字列を指定する。
; 同じVID/PIDのRollerMouseをすべて対象にする設定。
global gTargetDevicePatterns := ["VID_0B33&PID_3022","VID_0B33&PID_2000"]

; Ctrl+PgUp / Ctrl+PgDn を使うブラウザ。
; 必要に応じて exe 名を追加・削除する。
global gBrowserExecutables := Map(
    "chrome.exe", true,
    "brave.exe", true,
    "msedge.exe", true,
    "firefox.exe", true,
    "vivaldi.exe", true,
    "opera.exe", true,
    "floorp.exe", true,
    "librewolf.exe", true,
    "waterfox.exe", true,
    "zen.exe", true
)

; Ctrl+PgUp / Ctrl+PgDn を使う表計算アプリ。
; LibreOffice / OpenOffice は soffice.bin を全アプリで共有するため、
; Calc だけはウィンドウタイトルも併用して判定する。
global gSpreadsheetExecutables := Map(
    "excel.exe", true,          ; Microsoft Excel
    "et.exe", true,             ; WPS Spreadsheets
    "desktopeditors.exe", true, ; ONLYOFFICE Desktop Editors
    "planmaker.exe", true,      ; SoftMaker / FreeOffice PlanMaker
    "scalc.exe", true            ; LibreOffice Calc launcher
)

global gDevices := Map()
; 対象/非対象の判定結果をデバイスハンドル単位でキャッシュし、高頻度なマウス移動イベントでの再判定を避ける。
global gDeviceIsTarget := Map()
; 対象デバイスのCtrl押下状態。RollerMouseはチョード中Ctrlを押しっぱなしにするため、これが最も確実な入力元判定になる。
global gTargetCtrlDown := false
; 対象デバイス由来のCtrl活動時刻（down/up）。押下状態判定を補う順序ゆらぎ対策。
global gLastTargetKeyDownTick := 0
global gPending := []
global gRawInputDetectionWindow := 40
global gKeyChordWindow := 120
global gTargetCtrlReleaseTimeout := 750
global gLeftButtonDown := false
global gRightButtonDown := false
global gLeftButtonDownTick := 0
global gRightButtonDownTick := 0
global gMouseChordWindow := 150
global gMouseChordTriggered := false
; 再調査時だけtrueにする。本番時は診断用の状態取得・タイマー・ファイルI/Oを実行しない。
global gDiagnosticEnabled := false
global gDiagnosticLogPath := ""
global gDiagnosticBuffer := []
global gLastTabSendTick := 0

; Raw Input用の受信バッファは起動時に一度だけ確保し、イベント毎の再確保を避ける。
; RAWINPUTHEADER(8 + 2*ポインタ長) + RAWMOUSE/RAWKEYBOARD本体で十分な余裕を持たせる。
global gRawInputBuffer := Buffer((8 + 2 * A_PtrSize) + 64, 0)

rollerMouseGui := Gui("+ToolWindow", "RollerMouse Remap")
rollerMouseGui.Show("Hide")

OnMessage(0x00FF, OnRawInput)  ; WM_INPUT

if (!RegisterRawInput(0x06, rollerMouseGui.Hwnd)  ; Generic Desktop / Keyboard
    || !RegisterRawInput(0x02, rollerMouseGui.Hwnd)) {  ; Generic Desktop / Mouse
    MsgBox "Raw Inputの登録に失敗しました。", "RollerMouse Remap", "Iconx"
    ExitApp
}

if (gDiagnosticEnabled) {
    gDiagnosticLogPath := A_ScriptDir "\logs\RollerMouseTabDiag_" FormatTime(, "yyyyMMdd_HHmmss") ".log"
    DirCreate A_ScriptDir "\logs"
    OnExit FlushDiagnosticLog
    LogDiagnostic("startup ahk=" A_AhkVersion " pid=" ProcessExist())
}

; タイマーは常時回さず、キューに投入された時だけ起動する（QueueChord内で開始）。


#HotIf IsTargetCtrlActive()
$^c::QueueChord("C")
$^v::QueueChord("V")
; Shift同時押しでもRollerMouse側の入力を捕捉する（素通りでコピー/ペーストが動くのを防ぐ）。
$^+c::QueueChord("C")
$^+v::QueueChord("V")
#HotIf


IsTargetCtrlActive() {
    global gTargetCtrlDown, gLastTargetKeyDownTick, gRawInputDetectionWindow

    return gTargetCtrlDown
        || (gLastTargetKeyDownTick != 0
            && Abs(A_TickCount - gLastTargetKeyDownTick) <= gRawInputDetectionWindow)
}


RegisterRawInput(usage, hwnd) {
    ridSize := 8 + A_PtrSize
    rid := Buffer(ridSize, 0)

    NumPut("UShort", 0x01, rid, 0)  ; usUsagePage = Generic Desktop
    NumPut("UShort", usage, rid, 2)
    NumPut("UInt", 0x00000100, rid, 4)  ; RIDEV_INPUTSINK
    NumPut("Ptr", hwnd, rid, 8)

    return DllCall("user32\RegisterRawInputDevices"
        , "Ptr", rid
        , "UInt", 1
        , "UInt", ridSize
        , "Int")
}


QueueChord(name) {
    global gPending, gDiagnosticEnabled

    Critical()
    fromTarget := IsTargetCtrlActive()
    gPending.Push({
        name: name,
        tick: A_TickCount,
        fromTarget: fromTarget,
        releaseWaitLogged: false
    })
    if (gDiagnosticEnabled) {
        LogDiagnostic("queue name=" name
            " hotkey=" A_ThisHotkey
            " fromTarget=" (fromTarget ? 1 : 0)
            " pending=" gPending.Length)
    }
    SetTimer ProcessPendingChords, 10
}


ProcessPendingChords() {
    global gPending, gKeyChordWindow, gTargetCtrlDown, gTargetCtrlReleaseTimeout
    global gDiagnosticEnabled

    Critical()

    while (gPending.Length > 0) {
        pending := gPending[1]

        ; WM_INPUTがホットキー処理より後に届く場合を待つ。
        fromTarget := IsChordFromTarget(pending)
        waitTime := fromTarget ? gKeyChordWindow : 30
        age := A_TickCount - pending.tick
        if (age < waitTime)
            return

        ; RollerMouseが元のCtrlを物理的に保持している間に合成Ctrlを送ると、
        ; 物理状態と論理状態が競合する。通常はCtrl upを待ち、Raw Inputの
        ; up取りこぼし時だけタイムアウト後に処理を続ける。
        ctrlStillDown := gTargetCtrlDown || GetKeyState("Ctrl", "P")
        if (fromTarget && ctrlStillDown && age < gTargetCtrlReleaseTimeout) {
            if (gDiagnosticEnabled && !pending.releaseWaitLogged) {
                pending.releaseWaitLogged := true
                LogDiagnostic("wait_ctrl_release name=" pending.name
                    " age=" age
                    " pending=" gPending.Length)
            }
            return
        }

        if (gDiagnosticEnabled && pending.releaseWaitLogged) {
            LogDiagnostic((ctrlStillDown ? "ctrl_release_timeout" : "ctrl_released")
                " name=" pending.name
                " age=" age
                " pending=" gPending.Length)
        }

        if (fromTarget) {
            counterpartIndex := FindTargetKeyCounterpart(pending)
            if (counterpartIndex) {
                if (gDiagnosticEnabled) {
                    counterpart := gPending[counterpartIndex]
                    LogDiagnostic("consume_close first=" pending.name
                        " second=" counterpart.name
                        " age=" (A_TickCount - pending.tick)
                        " pending=" gPending.Length)
                }
                gPending.RemoveAt(counterpartIndex)
                gPending.RemoveAt(1)
                SendCloseTabByKeys()
                continue
            }

            if (gDiagnosticEnabled) {
                LogDiagnostic("dequeue_tab name=" pending.name
                    " age=" (A_TickCount - pending.tick)
                    " pending=" gPending.Length)
            }
            gPending.RemoveAt(1)
            SendTabChord(pending.name)
        } else {
            if (gDiagnosticEnabled) {
                LogDiagnostic("dequeue_passthrough name=" pending.name
                    " age=" (A_TickCount - pending.tick)
                    " pending=" gPending.Length)
            }
            gPending.RemoveAt(1)

            if (pending.name = "C")
                SendInput "^c"
            else
                SendInput "^v"
        }
    }

    ; キューが空になったのでタイマーを停止し、常時ポーリングを避ける。
    SetTimer ProcessPendingChords, 0
}


FindTargetKeyCounterpart(pending) {
    global gPending, gKeyChordWindow

    for index, candidate in gPending {
        if (index != 1
            && IsChordFromTarget(candidate)
            && candidate.name != pending.name
            && Abs(candidate.tick - pending.tick) <= gKeyChordWindow)
            return index
    }

    return 0
}


; キュー内の1件が対象デバイス由来かを判定する（フラグ、現在のCtrl押下状態、時刻のゆらぎの3要素）。
IsChordFromTarget(entry) {
    global gTargetCtrlDown, gLastTargetKeyDownTick, gRawInputDetectionWindow

    return entry.fromTarget
        || gTargetCtrlDown
        || Abs(gLastTargetKeyDownTick - entry.tick) <= gRawInputDetectionWindow
}


LogDiagnostic(event) {
    global gDiagnosticEnabled, gDiagnosticBuffer, gTargetCtrlDown

    if (!gDiagnosticEnabled)
        return

    ctrlLogical := GetKeyState("Ctrl") ? 1 : 0
    ctrlPhysical := GetKeyState("Ctrl", "P") ? 1 : 0
    leftPhysical := GetKeyState("LCtrl", "P") ? 1 : 0
    rightPhysical := GetKeyState("RCtrl", "P") ? 1 : 0
    gDiagnosticBuffer.Push(A_TickCount "`t" event
        "`trawCtrl=" (gTargetCtrlDown ? 1 : 0)
        " logicalCtrl=" ctrlLogical
        " physicalCtrl=" ctrlPhysical
        " physicalL=" leftPhysical
        " physicalR=" rightPhysical)
    SetTimer FlushDiagnosticLog, -250
}


FlushDiagnosticLog(*) {
    global gDiagnosticEnabled, gDiagnosticBuffer, gDiagnosticLogPath

    if (!gDiagnosticEnabled || gDiagnosticBuffer.Length = 0)
        return

    Critical()
    output := ""
    for line in gDiagnosticBuffer
        output .= line "`n"
    gDiagnosticBuffer := []

    try FileAppend output, gDiagnosticLogPath, "UTF-8"
}


SendCloseTabByKeys() {
    SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{F4 down}{F4 up}{Ctrl up}"
}


SendCloseTabByMouse() {
    SendInput "{Blind}{Ctrl down}{F4 down}{F4 up}{Ctrl up}"
}


DismissContextMenu() {
    SendInput "{Esc}"
}


IsBrowserAppActive(exe) {
    global gBrowserExecutables

    return gBrowserExecutables.Has(exe)
}


IsSpreadsheetAppActive(exe) {
    global gSpreadsheetExecutables

    if (gSpreadsheetExecutables.Has(exe))
        return true

    ; LibreOffice / Apache OpenOffice は Writer / Calc / Impress などで
    ; soffice.bin / soffice.exe を共有するため、Calc のときだけ PgUp 系にする。
    if (exe = "soffice.bin" || exe = "soffice.exe") {
        try title := WinGetTitle("A")
        catch
            return false

        return RegExMatch(title, "i)(LibreOffice|OpenOffice).*Calc|Calc.*(LibreOffice|OpenOffice)") != 0
    }

    return false
}


UsePageNavigation(exe) {
    return IsBrowserAppActive(exe) || IsSpreadsheetAppActive(exe)
}


SendExplorerTabChord(sourceKey) {
    ; Explorerは瞬時のSendInputを取りこぼすことがあるため、
    ; 物理キーに近い押下時間を持つSendEventで送る。
    SetKeyDelay 20, 30

    if (sourceKey = "C")
        SendEvent "^+{Tab}"
    else
        SendEvent "^{Tab}"
}


SendTabChord(sourceKey) {
    global gDiagnosticEnabled, gLastTabSendTick

    ; Shift はモード切替に使わない。物理状態をそのまま維持する。
    ; そのため Shift が押されている場合は、送信先アプリ側で
    ; Ctrl+Shift+PgUp/PgDn や Ctrl+Shift+Tab として解釈される。

    try activeExe := StrLower(WinGetProcessName("A"))
    catch
        activeExe := "unknown"

    usePage := UsePageNavigation(activeExe)

    if (gDiagnosticEnabled) {
        isDownloads := 0
        focusedControl := "unknown"
        if (activeExe = "explorer.exe") {
            try isDownloads := InStr(WinGetTitle("A"), "ダウンロード") ? 1 : 0
            try focusedControl := ControlGetClassNN(ControlGetFocus("A"))
        }

        sendTick := A_TickCount
        sendGap := gLastTabSendTick ? sendTick - gLastTabSendTick : -1
        gLastTabSendTick := sendTick
        LogDiagnostic("send_begin name=" sourceKey
            " exe=" activeExe
            " page=" (usePage ? 1 : 0)
            " gap=" sendGap
            " downloads=" isDownloads
            " focus=" focusedControl)
    }

    if (usePage) {
        ; ブラウザ / 表計算アプリ:
        ; Copy  -> Ctrl+PgUp
        ; Paste -> Ctrl+PgDn
        ; Shift は up を送らず、そのまま透過させる。
        if (sourceKey = "C") {
            SendInput "{Blind}{c up}{v up}{Ctrl up}{Ctrl down}{PgUp down}{PgUp up}{Ctrl up}"
        } else {
            SendInput "{Blind}{c up}{v up}{Ctrl up}{Ctrl down}{PgDn down}{PgDn up}{Ctrl up}"
        }
        if (gDiagnosticEnabled) {
            LogDiagnostic("send_end name=" sourceKey " exe=" activeExe " page=1")
            SetTimer LogSettledCtrlState, -100
        }
        return
    }

    if (activeExe = "explorer.exe") {
        SendExplorerTabChord(sourceKey)
        if (gDiagnosticEnabled) {
            LogDiagnostic("send_end name=" sourceKey " exe=" activeExe " page=0 mode=event")
            SetTimer LogSettledCtrlState, -100
        }
        return
    }

    ; その他の通常アプリ:
    ; Copy  -> Ctrl+Shift+Tab（前のタブ）
    ; Paste -> Ctrl+Tab       （次のタブ）
    ;
    ; 物理 Shift がすでに押されている場合は触らない。
    ; Copy 側で Shift が押されていない場合だけ、一時的に Shift を付与する。
    if (sourceKey = "C") {
        SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{Shift down}{Tab down}{Tab up}{Shift up}{Ctrl up}"
    } else {
        SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{Tab down}{Tab up}{Ctrl up}"
    }
    if (gDiagnosticEnabled) {
        LogDiagnostic("send_end name=" sourceKey " exe=" activeExe " page=0 mode=input")
        SetTimer LogSettledCtrlState, -100
    }
}


LogSettledCtrlState() {
    LogDiagnostic("send_settled")
}


OnRawInput(wParam, lParam, msg, hwnd) {
    global gDevices, gDeviceIsTarget, gTargetCtrlDown, gLastTargetKeyDownTick
    global gLeftButtonDown, gRightButtonDown, gMouseChordTriggered
    global gLeftButtonDownTick, gRightButtonDownTick, gMouseChordWindow
    global gRawInputBuffer
    global gDiagnosticEnabled

    Critical()

    headerSize := 8 + (2 * A_PtrSize)
    raw := gRawInputBuffer
    size := raw.Size

    ; 事前確保した固定バッファへ直接取得し、サイズ照会用のDllCallを省いて呼び出しを半減させる。
    result := DllCall("user32\GetRawInputData"
        , "Ptr", lParam
        , "UInt", 0x10000003  ; RID_INPUT
        , "Ptr", raw
        , "UInt*", &size
        , "UInt", headerSize
        , "UInt")

    if (result = 0xFFFFFFFF || size <= 0)
        return

    type := NumGet(raw, 0, "UInt")
    hDevice := NumGet(raw, 8, "Ptr")

    ; ハンドル単位で初回だけパス取得と対象判定を行い、以降はキャッシュ参照で済ませる。
    if (!gDeviceIsTarget.Has(hDevice)) {
        gDevices[hDevice] := GetDevicePath(hDevice)
        gDeviceIsTarget[hDevice] := IsTargetDevice(hDevice)
    }

    if (!gDeviceIsTarget[hDevice])
        return

    dataOffset := headerSize

    if (type = 0) {
        buttonFlags := NumGet(raw, dataOffset + 4, "UShort")

        ; 移動のみのイベント（ボタンフラグ無し）はチョード判定不要なので即戻る。
        if (buttonFlags = 0)
            return

        if (buttonFlags & 0x0001) {
            gLeftButtonDown := true
            gLeftButtonDownTick := A_TickCount
        }
        if (buttonFlags & 0x0002)
            gLeftButtonDown := false
        if (buttonFlags & 0x0004) {
            gRightButtonDown := true
            gRightButtonDownTick := A_TickCount
        }
        if (buttonFlags & 0x0008) {
            gRightButtonDown := false
            if (gMouseChordTriggered)
                SetTimer DismissContextMenu, -100
        }

        if (gLeftButtonDown
            && gRightButtonDown
            && Abs(gLeftButtonDownTick - gRightButtonDownTick) <= gMouseChordWindow
            && !gMouseChordTriggered) {
            gMouseChordTriggered := true
            SendCloseTabByMouse()
        } else if (!gLeftButtonDown && !gRightButtonDown) {
            gMouseChordTriggered := false
        }
        return
    }

    if (type != 1)
        return

    flags := NumGet(raw, dataOffset + 2, "UShort")
    vkey := NumGet(raw, dataOffset + 6, "UShort")
    isDown := !(flags & 0x01)

    ; このデバイスはC/Vをrawで送らずCtrlのみ送る。Ctrlの押下状態と時刻で入力元を判定する。
    if (vkey = 0x11 || vkey = 0xA2 || vkey = 0xA3) {
        gTargetCtrlDown := isDown
        gLastTargetKeyDownTick := A_TickCount
        if (gDiagnosticEnabled) {
            LogDiagnostic("raw_ctrl vkey=" Format("0x{:02X}", vkey)
                " down=" (isDown ? 1 : 0)
                " flags=" Format("0x{:02X}", flags))
        }
    }
}


GetDevicePath(hDevice) {
    chars := 0

    DllCall("user32\GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x20000007  ; RIDI_DEVICENAME
        , "Ptr", 0
        , "UInt*", &chars
        , "UInt")

    if (chars <= 0)
        return ""

    nameBuffer := Buffer((chars + 1) * 2, 0)
    result := DllCall("user32\GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x20000007  ; RIDI_DEVICENAME
        , "Ptr", nameBuffer
        , "UInt*", &chars
        , "UInt")

    if (result = 0xFFFFFFFF)
        return ""

    return StrGet(nameBuffer, chars, "UTF-16")
}


IsTargetDevice(deviceKey) {
    global gDevices, gTargetDevicePatterns

    path := gDevices[deviceKey]

    for pattern in gTargetDevicePatterns {
        if (InStr(path, pattern, false))
            return true
    }

    return false
}
