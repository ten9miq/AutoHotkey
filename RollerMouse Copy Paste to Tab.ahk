#Requires AutoHotkey v2.0+
#SingleInstance Force
InstallKeybdHook()
SendMode "Input"

; Raw Inputのデバイスパスに含まれる文字列を指定する。
; 同じVID/PIDのRollerMouseをすべて対象にする設定。
global gTargetDevicePatterns := ["VID_0B33&PID_3022","VID_0B33&PID_2000"]

global gDevices := Map()
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

OnMessage(0x00FF, OnRawInput)

if (!RegisterRawInput(0x06, rollerMouseGui.Hwnd)
    || !RegisterRawInput(0x02, rollerMouseGui.Hwnd)) {
    MsgBox "Raw Inputの登録に失敗しました。", "RollerMouse Remap", "Iconx"
    ExitApp
}

; タイマーは常時回さず、キューに投入された時だけ起動する（QueueChord内で開始）。


$^c::QueueChord("C")
$^v::QueueChord("V")


RegisterRawInput(usage, hwnd) {
    ridSize := 8 + A_PtrSize
    rid := Buffer(ridSize, 0)

    NumPut("UShort", 0x01, rid, 0)
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
    global gPending, gTargetCtrlDown, gLastTargetKeyDownTick, gRawInputDetectionWindow

    Critical()
    fromTarget := gTargetCtrlDown
        || ((A_TickCount - gLastTargetKeyDownTick) <= gRawInputDetectionWindow)
    gPending.Push({name: name, tick: A_TickCount, fromTarget: fromTarget})
    SetTimer ProcessPendingChords, 10
}


ProcessPendingChords() {
    global gPending, gTargetCtrlDown, gLastTargetKeyDownTick, gRawInputDetectionWindow, gKeyChordWindow

    Critical()

    while (gPending.Length > 0) {
        pending := gPending[1]

        ; WM_INPUTがホットキー処理より後に届く場合を待つ。
        fromTarget := pending.fromTarget
            || gTargetCtrlDown
            || Abs(gLastTargetKeyDownTick - pending.tick) <= gRawInputDetectionWindow
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
    global gPending, gTargetCtrlDown, gLastTargetKeyDownTick
    global gRawInputDetectionWindow, gKeyChordWindow

    for index, candidate in gPending {
        candidateFromTarget := candidate.fromTarget
            || gTargetCtrlDown
            || Abs(gLastTargetKeyDownTick - candidate.tick) <= gRawInputDetectionWindow
        if (index != 1
            && candidateFromTarget
            && candidate.name != pending.name
            && Abs(candidate.tick - pending.tick) <= gKeyChordWindow)
            return index
    }

    return 0
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

    if (sourceKey = "C") {
        SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{Shift down}{Tab down}{Tab up}{Shift up}{Ctrl up}"
        ; TrayTip, RollerMouse Remap, Copy -> Ctrl+Shift+Tab, 1, 1
    } else {
        SendInput "{Blind}{c up}{v up}{Ctrl up}{Shift up}{Ctrl down}{Tab down}{Tab up}{Ctrl up}"
        ; TrayTip, RollerMouse Remap, Paste -> Ctrl+Tab, 1, 1
    }
}


OnRawInput(wParam, lParam, msg, hwnd) {
    global gDevices, gTargetCtrlDown, gLastTargetKeyDownTick
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
        , "UInt", 0x10000003
        , "Ptr", raw
        , "UInt*", &size
        , "UInt", headerSize
        , "UInt")

    if (result = 0xFFFFFFFF || size <= 0)
        return

    type := NumGet(raw, 0, "UInt")
    hDevice := NumGet(raw, 8, "Ptr")
    deviceKey := "" hDevice

    if (!gDevices.Has(deviceKey))
        gDevices[deviceKey] := GetDevicePath(hDevice)

    if (!IsTargetDevice(deviceKey))
        return

    dataOffset := headerSize

    if (type = 0) {
        buttonFlags := NumGet(raw, dataOffset + 4, "UShort")

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
        , "UInt", 0x20000007
        , "Ptr", 0
        , "UInt*", &chars
        , "UInt")

    if (chars <= 0)
        return ""

    nameBuffer := Buffer((chars + 1) * 2, 0)
    result := DllCall("user32\GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x20000007
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
