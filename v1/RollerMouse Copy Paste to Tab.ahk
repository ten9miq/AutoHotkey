#Requires AutoHotkey v1.1+
#NoEnv
#SingleInstance Force
#Persistent
#InstallKeybdHook
SetBatchLines, -1
ListLines, Off
SendMode, Input

; Raw Inputのデバイスパスに含まれる文字列を指定する。
; 同じVID/PIDのRollerMouseをすべて対象にする設定。
global gTargetDevicePatterns := ["VID_0B33&PID_3022","VID_0B33&PID_2000"]

global gGui
global gDevices := {}
global gLastTargetCtrlDownTick := 0
global gPending := []

Gui, +HwndgGui +ToolWindow
Gui, Show, Hide, RollerMouse Remap

OnMessage(0x00FF, "OnRawInput")

if (!RegisterKeyboardRawInput(gGui))
{
    MsgBox, 16, RollerMouse Remap, Raw Inputの登録に失敗しました。
    ExitApp
}

SetTimer, ProcessPending, 10
return


$^c::
QueueChord("C")
return


$^v::
QueueChord("V")
return


ProcessPending:
ProcessPendingChords()
return


RegisterKeyboardRawInput(hwnd)
{
    ridSize := 8 + A_PtrSize
    VarSetCapacity(rid, ridSize, 0)

    NumPut(0x01, rid, 0, "UShort")
    NumPut(0x06, rid, 2, "UShort")
    NumPut(0x00000100, rid, 4, "UInt")  ; RIDEV_INPUTSINK
    NumPut(hwnd, rid, 8, "Ptr")

    return DllCall("RegisterRawInputDevices"
        , "Ptr", &rid
        , "UInt", 1
        , "UInt", ridSize)
}


QueueChord(name)
{
    global gPending, gLastTargetCtrlDownTick

    Critical
    fromTarget := ((A_TickCount - gLastTargetCtrlDownTick) <= 120)
    gPending.Push({name: name, tick: A_TickCount, fromTarget: fromTarget})
}


ProcessPendingChords()
{
    global gPending

    Critical

    while (gPending.Length() > 0)
    {
        pending := gPending[1]

        ; WM_INPUTがホットキー処理より後に届く場合を待つ。
        if ((A_TickCount - pending.tick) < 30)
            return

        gPending.RemoveAt(1)

        if (pending.fromTarget)
        {
            SendTabChord(pending.name)
        }
        else if (pending.name = "C")
            SendInput, ^c
        else
            SendInput, ^v
    }
}


SendTabChord(sourceKey)
{
    ; RollerMouse側のCtrlが物理的に押されたままでも、修飾キーを確実に組み直す。
    SendEvent, {Ctrl up}{Shift up}

    if (sourceKey = "C")
    {
        SendEvent, {Ctrl down}{Shift down}{Tab down}{Tab up}{Shift up}{Ctrl up}
        ; TrayTip, RollerMouse Remap, Copy -> Ctrl+Shift+Tab, 1, 1
    }
    else
    {
        SendEvent, {Ctrl down}{Tab down}{Tab up}{Ctrl up}
        ; TrayTip, RollerMouse Remap, Paste -> Ctrl+Tab, 1, 1
    }
}


OnRawInput(wParam, lParam, msg, hwnd)
{
    global gDevices, gLastTargetCtrlDownTick

    Critical

    headerSize := 8 + (2 * A_PtrSize)
    size := 0

    DllCall("GetRawInputData"
        , "Ptr", lParam
        , "UInt", 0x10000003
        , "Ptr", 0
        , "UInt*", size
        , "UInt", headerSize
        , "UInt")

    if (size <= 0)
        return

    VarSetCapacity(raw, size, 0)

    result := DllCall("GetRawInputData"
        , "Ptr", lParam
        , "UInt", 0x10000003
        , "Ptr", &raw
        , "UInt*", size
        , "UInt", headerSize
        , "UInt")

    if (result = 0xFFFFFFFF || NumGet(raw, 0, "UInt") != 1)
        return

    hDevice := NumGet(raw, 8, "Ptr")
    deviceKey := "" hDevice

    if (!gDevices.HasKey(deviceKey))
        gDevices[deviceKey] := GetDevicePath(hDevice)

    dataOffset := headerSize
    flags := NumGet(raw, dataOffset + 2, "UShort")
    vkey := NumGet(raw, dataOffset + 6, "UShort")
    isDown := !(flags & 0x01)

    if (vkey = 0x11 || vkey = 0xA2 || vkey = 0xA3)
    {
        if (isDown && IsTargetDevice(deviceKey))
            gLastTargetCtrlDownTick := A_TickCount
        return
    }

}


GetDevicePath(hDevice)
{
    chars := 0

    DllCall("GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x20000007
        , "Ptr", 0
        , "UInt*", chars
        , "UInt")

    if (chars <= 0)
        return ""

    VarSetCapacity(nameBuffer, (chars + 1) * 2, 0)
    result := DllCall("GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x20000007
        , "Ptr", &nameBuffer
        , "UInt*", chars
        , "UInt")

    if (result = 0xFFFFFFFF)
        return ""

    return StrGet(&nameBuffer, chars, "UTF-16")
}


IsTargetDevice(deviceKey)
{
    global gDevices, gTargetDevicePatterns

    path := gDevices[deviceKey]

    for index, pattern in gTargetDevicePatterns
    {
        if (InStr(path, pattern, false))
            return true
    }

    return false
}