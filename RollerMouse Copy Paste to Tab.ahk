#Requires AutoHotkey v2.0+
#SingleInstance Force
InstallKeybdHook()
SendMode "Input"

; Raw Inputのデバイスパスに含まれる文字列を指定する。
; 同じVID/PIDのRollerMouseをすべて対象にする設定。
global gTargetDevicePatterns := ["VID_0B33&PID_3022","VID_0B33&PID_2000"]

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
global gLeftButtonDown := false
global gRightButtonDown := false
global gLeftButtonDownTick := 0
global gRightButtonDownTick := 0
global gMouseChordWindow := 150
global gMouseChordTriggered := false

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
    global gPending

    Critical()
    fromTarget := IsTargetCtrlActive()
    gPending.Push({name: name, tick: A_TickCount, fromTarget: fromTarget})
    SetTimer ProcessPendingChords, 10
}


ProcessPendingChords() {
    global gPending, gKeyChordWindow

    Critical()

    while (gPending.Length > 0) {
        pending := gPending[1]

        ; WM_INPUTがホットキー処理より後に届く場合を待つ。
        fromTarget := IsChordFromTarget(pending)
        waitTime := fromTarget ? gKeyChordWindow : 30
        if ((A_TickCount - pending.tick) < waitTime)
            return

        if (fromTarget) {
            counterpartIndex := FindTargetKeyCounterpart(pending)
            if (counterpartIndex) {
                gPending.RemoveAt(counterpartIndex)
                gPending.RemoveAt(1)
                SendCloseTabByKeys()
                continue
            }

            gPending.RemoveAt(1)
            SendTabChord(pending.name)
        } else {
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


SendCloseTabByKeys() {
    SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{F4 down}{F4 up}{Ctrl up}"
}


SendCloseTabByMouse() {
    SendInput "{Blind}{Ctrl down}{F4 down}{F4 up}{Ctrl up}"
}


DismissContextMenu() {
    SendInput "{Esc}"
}


SendTabChord(sourceKey) {
    ; Blindモードで、物理Ctrlが押下中でも送信後の自動再押下を防ぐ。
    ; Shiftはupを送らず物理状態を維持し、同時押し時はシート切替ショートカットになる。

    if (sourceKey = "C") {
        ; SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{Shift down}{Tab down}{Tab up}{Shift up}{Ctrl up}"
        ; TrayTip, RollerMouse Remap, Copy -> Ctrl+Shift+Tab, 1, 1
        SendInput "{Blind}{c up}{v up}{Ctrl up}{Ctrl down}{PgUp down}{PgUp up}{Ctrl up}"
    } else {
        ; SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{Tab down}{Tab up}{Ctrl up}"
        ; TrayTip, RollerMouse Remap, Paste -> Ctrl+Tab, 1, 1
        SendInput "{Blind}{c up}{v up}{Ctrl up}{Ctrl down}{PgDn down}{PgDn up}{Ctrl up}"
    }
}


OnRawInput(wParam, lParam, msg, hwnd) {
    global gDevices, gDeviceIsTarget, gTargetCtrlDown, gLastTargetKeyDownTick
    global gLeftButtonDown, gRightButtonDown, gMouseChordTriggered
    global gLeftButtonDownTick, gRightButtonDownTick, gMouseChordWindow
    global gRawInputBuffer

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
