#Requires AutoHotkey v2.0+
#SingleInstance Force

global gDevices := Map()

monitorGui := Gui("+Resize", "RollerMouse Raw Input Monitor")
monitorGui.SetFont("s9", "Consolas")
monitorEdit := monitorGui.AddEdit("xm ym w1100 h650 ReadOnly -Wrap")
global gEdit := monitorEdit.Hwnd
global gGui := monitorGui.Hwnd
monitorGui.OnEvent("Close", CloseMonitor)
monitorGui.Show()

OnMessage(0x00FF, OnRawInput) ; WM_INPUT

EnumerateAndRegister()

Log("")
Log("=== READY ===")
Log("RollerMouse の Copy、Paste をそれぞれ1回ずつ押してください。")
Log("")

CloseMonitor(*) {
    ExitApp
}


EnumerateAndRegister()
{
    global gDevices, gGui

    ; RAWINPUTDEVICELIST
    entrySize := (A_PtrSize = 8) ? 16 : 8

    count := 0
    result := DllCall("user32\GetRawInputDeviceList"
        , "Ptr", 0
        , "UInt*", &count
        , "UInt", entrySize
        , "UInt")

    if (result = 0xFFFFFFFF)
    {
        Log("GetRawInputDeviceList failed")
        return
    }

    list := Buffer(count * entrySize, 0)

    result := DllCall("user32\GetRawInputDeviceList"
        , "Ptr", list
        , "UInt*", &count
        , "UInt", entrySize
        , "UInt")

    pairs := Map()

    Loop count {
        off := (A_Index - 1) * entrySize

        hDevice := NumGet(list, off, "Ptr")
        type := NumGet(list, off + A_PtrSize, "UInt")

        meta := GetDeviceMeta(hDevice, type)

        key := "" hDevice
        gDevices[key] := meta

        if (type = 0)
        {
            ; Mouse
            page := 0x01
            usage := 0x02
            typeName := "MOUSE"
        }
        else if (type = 1)
        {
            ; Keyboard
            page := 0x01
            usage := 0x06
            typeName := "KEYBOARD"
        }
        else
        {
            ; HID
            page := meta.page
            usage := meta.usage
            typeName := "HID"
        }

        pairKey := Format("{:04X}:{:04X}", page, usage)

        if (!pairs.Has(pairKey))
            pairs[pairKey] := { page: page, usage: usage }

        Log("DEVICE TYPE=" typeName
            . " VID=" meta.vid
            . " PID=" meta.pid
            . " Usage=" Format("{:04X}/{:04X}", page, usage))

        if (meta.path != "")
            Log(" " meta.path)
    }

    Log("")
    Log("=== Register Raw Input ===")

    for pairKey, pair in pairs {
        ok := RegisterRaw(pair.page, pair.usage, gGui)

        Log("Usage "
            . Format("{:04X}/{:04X}", pair.page, pair.usage)
            . " : "
            . (ok ? "OK" : "FAILED"))
    }
}


RegisterRaw(page, usage, hwnd)
{
    ; RAWINPUTDEVICE
    ridSize := 8 + A_PtrSize

    rid := Buffer(ridSize, 0)

    NumPut("UShort", page, rid, 0)
    NumPut("UShort", usage, rid, 2)

    ; RIDEV_INPUTSINK
    NumPut("UInt", 0x00000100, rid, 4)

    NumPut("Ptr", hwnd, rid, 8)

    return DllCall("user32\RegisterRawInputDevices"
        , "Ptr", rid
        , "UInt", 1
        , "UInt", ridSize
        , "Int")
}


GetDeviceMeta(hDevice, type)
{
    meta := {path: "", vid: "????", pid: "????", page: 0, usage: 0}

    ; -------------------------
    ; Device Path
    ; -------------------------
    chars := 0

    DllCall("user32\GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x20000007
        , "Ptr", 0
        , "UInt*", &chars
        , "UInt")

    if (chars > 0) {
        nameBuf := Buffer((chars + 1) * 2, 0)
        chars2 := chars

        result := DllCall("user32\GetRawInputDeviceInfoW"
            , "Ptr", hDevice
            , "UInt", 0x20000007
            , "Ptr", nameBuf
            , "UInt*", &chars2
            , "UInt")

        if (result != 0xFFFFFFFF)
            meta.path := StrGet(nameBuf, chars2, "UTF-16")
    }

    ; VID / PIDをデバイスパスから取得
    path := meta.path

    if RegExMatch(path, "i)VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})", &match) {
        meta.vid := match[1]
        meta.pid := match[2]
    }

    ; -------------------------
    ; RID_DEVICE_INFO
    ; -------------------------
    info := Buffer(32, 0)
    NumPut("UInt", 32, info, 0)

    cb := 32

    result := DllCall("user32\GetRawInputDeviceInfoW"
        , "Ptr", hDevice
        , "UInt", 0x2000000B
        , "Ptr", info
        , "UInt*", &cb
        , "UInt")

    if (result != 0xFFFFFFFF) {
        if (type = 2) {
            vendor := NumGet(info, 8, "UInt")
            product := NumGet(info, 12, "UInt")

            meta.vid := Format("{:04X}", vendor)
            meta.pid := Format("{:04X}", product)

            meta.page := NumGet(info, 20, "UShort")
            meta.usage := NumGet(info, 22, "UShort")
        }
    }

    return meta
}


OnRawInput(wParam, lParam, msg, hwnd)
{
    global gDevices

    ; RAWINPUTHEADER
    headerSize := 8 + (2 * A_PtrSize)

    size := 0

    DllCall("user32\GetRawInputData"
        , "Ptr", lParam
        , "UInt", 0x10000003 ; RID_INPUT
        , "Ptr", 0
        , "UInt*", &size
        , "UInt", headerSize
        , "UInt")

    if (size <= 0)
        return

    raw := Buffer(size, 0)

    result := DllCall("user32\GetRawInputData"
        , "Ptr", lParam
        , "UInt", 0x10000003
        , "Ptr", raw
        , "UInt*", &size
        , "UInt", headerSize
        , "UInt")

    if (result = 0xFFFFFFFF)
        return

    type := NumGet(raw, 0, "UInt")
    hDevice := NumGet(raw, 8, "Ptr")

    key := "" hDevice

    if (!gDevices.Has(key))
        gDevices[key] := GetDeviceMeta(hDevice, type)

    meta := gDevices[key]

    id := "VID=" meta.vid " PID=" meta.pid

    dataOff := headerSize

    ; =========================
    ; Keyboard
    ; =========================
    if (type = 1)
    {
        makeCode := NumGet(raw, dataOff + 0, "UShort")
        flags := NumGet(raw, dataOff + 2, "UShort")
        vkey := NumGet(raw, dataOff + 6, "UShort")

        state := (flags & 0x01) ? "UP" : "DOWN"
        keyName := GetRawKeyName(vkey, makeCode, flags)

        Log("KEY "
            . id
            . " Key=" keyName
            . " VK=" Format("{:02X}", vkey)
            . " SC=" Format("{:03X}", makeCode)
            . " " state)

        return
    }

    ; =========================
    ; HID
    ; =========================
    if (type = 2)
    {
        sizeHid := NumGet(raw, dataOff + 0, "UInt")
        count := NumGet(raw, dataOff + 4, "UInt")

        total := sizeHid * count

        ; ログが巨大にならないよう最大64byte
        showBytes := (total > 64) ? 64 : total

        hex := HexDump(raw, dataOff + 8, showBytes)

        Log("HID "
            . id
            . " Usage="
            . Format("{:04X}/{:04X}", meta.page, meta.usage)
            . " Size=" sizeHid
            . " Count=" count
            . " DATA=[" hex "]")

        return
    }

    ; =========================
    ; Mouse
    ; =========================
    if (type = 0)
    {
        buttonFlags := NumGet(raw, dataOff + 4, "UShort")
        buttonData := NumGet(raw, dataOff + 6, "UShort")

        ; マウス移動は大量に来るのでボタンだけ表示
        if (buttonFlags = 0)
            return

        Log("MOUSE "
            . id
            . " Flags=" Format("{:04X}", buttonFlags)
            . " Data=" Format("{:04X}", buttonData))
    }
}


GetRawKeyName(vkey, makeCode, flags)
{
    scanCode := makeCode

    ; RI_KEY_E0。右Ctrlなどの拡張キーを区別する。
    if (flags & 0x02)
        scanCode |= 0x100

    keyName := GetKeyName("vk" Format("{:02X}", vkey)
        . "sc" Format("{:03X}", scanCode))

    return (keyName != "") ? keyName : "Unknown"
}


HexDump(buf, offset, length)
{
    result := ""

    Loop length {
        b := NumGet(buf, offset + A_Index - 1, "UChar")

        if (result != "")
            result .= " "

        result .= Format("{:02X}", b)
    }

    return result
}


Log(text)
{
    global gEdit

    line := "[" A_TickCount "] " text "`r`n"

    ; ログ更新中にユーザーが選択した範囲を維持する。
    selectionStart := 0
    selectionEnd := 0

    DllCall("user32\SendMessageW"
        , "Ptr", gEdit
        , "UInt", 0x00B0 ; EM_GETSEL
        , "UInt*", &selectionStart
        , "UInt*", &selectionEnd)

    ; 選択中はログを更新しない。
    if (selectionStart != selectionEnd)
        return

    ; Edit末尾へキャレットを移動して追記
    textLength := DllCall("user32\SendMessageW"
        , "Ptr", gEdit
        , "UInt", 0x000E ; WM_GETTEXTLENGTH
        , "Ptr", 0
        , "Ptr", 0)

    DllCall("user32\SendMessageW"
        , "Ptr", gEdit
        , "UInt", 0x00B1 ; EM_SETSEL
        , "Ptr", textLength
        , "Ptr", textLength)

    DllCall("user32\SendMessageW"
        , "Ptr", gEdit
        , "UInt", 0x00C2 ; EM_REPLACESEL
        , "Ptr", 0
        , "WStr", line)

    DllCall("user32\SendMessageW"
        , "Ptr", gEdit
        , "UInt", 0x00B7 ; EM_SCROLLCARET
        , "Ptr", 0
        , "Ptr", 0)
}
