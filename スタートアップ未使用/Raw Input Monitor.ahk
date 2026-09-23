#Requires AutoHotkey v2.0+
#SingleInstance Force

global gDevices := Map()
global gRegisteredPairs := Map()
global gMonitoring := false
global gLastInput := "なし"
global gMouseLogging := false
global gMouseMotionLogging := false
global gMotionLogPath := ""
global gMotionBuffer := []
global gMotionDropped := 0

monitorGui := Gui("+Resize", "RawInputMonitor")
monitorGui.SetFont("s9", "Consolas")
buttonRow := monitorGui.AddGroupBox("xm ym w1100 h52", "操作")
startButton := monitorGui.AddButton("xp+10 yp+20 w105", "監視開始")
stopButton := monitorGui.AddButton("x+8 yp w105", "監視停止")
reloadButton := monitorGui.AddButton("x+8 yp w125", "設定再読み込み")
clearButton := monitorGui.AddButton("x+8 yp w105", "ログ消去")
clickButton := monitorGui.AddButton("x+8 yp w125", "テストクリック")
mouseLogButton := monitorGui.AddButton("x+8 yp w125", "マウス記録: OFF")
motionLogButton := monitorGui.AddButton("x+8 yp w145", "マウス移動記録: OFF")
closeButton := monitorGui.AddButton("x+8 yp w105", "閉じる")
statusText := monitorGui.AddText("xm y+10 w1100", "状態: 停止中 / マウス記録: OFF / 移動記録: OFF / 最後の入力: なし")
monitorEdit := monitorGui.AddEdit("xm y+8 w1100 h590 ReadOnly -Wrap")
global gEdit := monitorEdit.Hwnd
global gGui := monitorGui.Hwnd
global gStatus := statusText
global gMouseLogButton := mouseLogButton
global gMotionLogButton := motionLogButton
monitorGui.OnEvent("Close", CloseMonitor)
monitorGui.OnEvent("Size", OnGuiSize)
startButton.OnEvent("Click", StartMonitoring)
stopButton.OnEvent("Click", StopMonitoring)
reloadButton.OnEvent("Click", ReloadSettings)
clearButton.OnEvent("Click", ClearLog)
clickButton.OnEvent("Click", SendTestClick)
mouseLogButton.OnEvent("Click", ToggleMouseLogging)
motionLogButton.OnEvent("Click", ToggleMouseMotionLogging)
closeButton.OnEvent("Click", CloseMonitor)
monitorGui.Show()

OnMessage(0x00FF, OnRawInput) ; WM_INPUT

StartMonitoring()

Log("")
Log("=== READY ===")
Log("Raw Input監視の準備が完了しました。")
Log("")

CloseMonitor(*) {
    FlushMotionLog()
    ExitApp
}

StartMonitoring(*) {
    global gMonitoring
    if (gMonitoring)
        return
    gMonitoring := true
    EnumerateAndRegister()
    UpdateStatus("監視中")
    Log("=== MONITORING STARTED ===")
}

StopMonitoring(*) {
    global gMonitoring
    if (!gMonitoring)
        return
    UnregisterRegistered()
    gMonitoring := false
    UpdateStatus("停止中")
    Log("=== MONITORING STOPPED ===")
}

ReloadSettings(*) {
    global gDevices, gRegisteredPairs
    StopMonitoring()
    gDevices := Map()
    gRegisteredPairs := Map()
    Log("=== RELOAD: ENUMERATE DEVICES ===")
    StartMonitoring()
}

ClearLog(*) {
    global gEdit
    ControlSetText("", gEdit)
    Log("=== LOG CLEARED ===")
}

SendTestClick(*) {
    Log("=== TEST LEFT CLICK ===")
    Click("Left")
}

ToggleMouseLogging(*) {
    global gMouseLogging, gMouseLogButton, gMonitoring
    gMouseLogging := !gMouseLogging
    gMouseLogButton.Text := "マウス記録: " (gMouseLogging ? "ON" : "OFF")
    UpdateStatus(gMonitoring ? "監視中" : "停止中")
    Log("=== MOUSE LOGGING " (gMouseLogging ? "ON" : "OFF") " ===")
}

ToggleMouseMotionLogging(*) {
    global gMouseMotionLogging, gMotionLogButton, gMotionLogPath
    gMouseMotionLogging := !gMouseMotionLogging
    gMotionLogButton.Text := "マウス移動記録: " (gMouseMotionLogging ? "ON" : "OFF")
    if (gMouseMotionLogging) {
        basePath := A_ScriptDir "\logs\RawInputMonitor_mouse_motion_" FormatTime(A_Now, "yyyyMMdd_HHmmss") "_" A_TickCount
        gMotionLogPath := basePath ".csv"
        suffix := 1
        while FileExist(gMotionLogPath) {
            gMotionLogPath := basePath "_" suffix ".csv"
            suffix += 1
        }
        EnsureMotionLogFile()
        SetTimer(FlushMotionLog, 100)
    } else {
        SetTimer(FlushMotionLog, 0)
        FlushMotionLog()
    }
    Log("=== MOUSE MOTION LOGGING " (gMouseMotionLogging ? "ON" : "OFF") " === " gMotionLogPath)
}

UpdateStatus(state) {
    global gStatus, gLastInput, gMouseLogging, gMouseMotionLogging
    gStatus.Text := "状態: " state " / マウス記録: " (gMouseLogging ? "ON" : "OFF") " / 移動記録: " (gMouseMotionLogging ? "ON" : "OFF") " / 最後の入力: " gLastInput
}

OnGuiSize(gui, minMax, width, height) {
    global buttonRow, statusText, monitorEdit
    if (minMax = -1 || width <= 0 || height <= 0)
        return

    contentWidth := Max(width - 20, 100)
    editHeight := Max(height - 110, 80)
    buttonRow.Move(10, 10, contentWidth, 52)
    statusText.Move(10, 72, contentWidth, 20)
    monitorEdit.Move(10, 100, contentWidth, editHeight)
}


EnumerateAndRegister()
{
    global gDevices, gGui, gRegisteredPairs

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

        if (ok)
            gRegisteredPairs[pairKey] := pair

        Log("Usage "
            . Format("{:04X}/{:04X}", pair.page, pair.usage)
            . " : "
            . (ok ? "OK" : "FAILED"))
    }
}


UnregisterRegistered()
{
    global gRegisteredPairs
    for pairKey, pair in gRegisteredPairs {
        RegisterRaw(pair.page, pair.usage, 0, true)
    }
    gRegisteredPairs := Map()
}

RegisterRaw(page, usage, hwnd, remove := false)
{
    ; RAWINPUTDEVICE
    ridSize := 8 + A_PtrSize

    rid := Buffer(ridSize, 0)

    NumPut("UShort", page, rid, 0)
    NumPut("UShort", usage, rid, 2)

    ; RIDEV_INPUTSINK / RIDEV_REMOVE
    NumPut("UInt", remove ? 0x00000001 : 0x00000100, rid, 4)

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
    global gDevices, gMonitoring, gLastInput

    if (!gMonitoring)
        return

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

        gLastInput := "KEY " keyName " " state
        UpdateStatus("監視中")

        return
    }

    ; =========================
    ; HID
    ; =========================
    if (type = 2)
    {
        global gMouseLogging, gMouseMotionLogging
        if (!gMouseLogging && !gMouseMotionLogging)
            return
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

        gLastInput := "HID " id
        UpdateStatus("監視中")

        return
    }

    ; =========================
    ; Mouse
    ; =========================
    if (type = 0)
    {
        usFlags := NumGet(raw, dataOff + 0, "UShort")
        buttonFlags := NumGet(raw, dataOff + 4, "UShort")
        buttonData := NumGet(raw, dataOff + 6, "UShort")
        dx := NumGet(raw, dataOff + 12, "Int")
        dy := NumGet(raw, dataOff + 16, "Int")

        global gMouseLogging, gMouseMotionLogging
        if (gMouseMotionLogging && (dx != 0 || dy != 0))
            QueueMotionRecord(meta, hDevice, usFlags, dx, dy, buttonFlags, buttonData)

        ; マウス移動は大量に来るのでボタンだけ表示
        if (buttonFlags = 0 || !gMouseLogging)
            return

        Log("MOUSE "
            . id
            . " Flags=" Format("{:04X}", buttonFlags)
            . " Data=" Format("{:04X}", buttonData))

        gLastInput := "MOUSE Flags=" Format("{:04X}", buttonFlags)
        UpdateStatus("監視中")
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


EnsureMotionLogFile()
{
    global gMotionLogPath
    DirCreate(A_ScriptDir "\logs")
    if (!FileExist(gMotionLogPath))
        FileAppend("tick,type,hDevice,VID,PID,devicePath,usFlags,dx,dy,buttonFlags,buttonData`r`n", gMotionLogPath, "UTF-8")
}

QueueMotionRecord(meta, hDevice, usFlags, dx, dy, buttonFlags, buttonData)
{
    global gMotionBuffer, gMotionDropped, gMouseMotionLogging
    if (!gMouseMotionLogging)
        return
    if (gMotionBuffer.Length >= 5000) {
        gMotionDropped += 1
        return
    }
    csv := A_TickCount ",RAWINPUT," hDevice "," CsvField(meta.vid) "," CsvField(meta.pid) "," CsvField(meta.path) "," usFlags "," dx "," dy "," buttonFlags "," buttonData
    gMotionBuffer.Push(csv "`r`n")
}

FlushMotionLog(*)
{
    global gMotionBuffer, gMotionLogPath, gMotionDropped
    if (gMotionBuffer.Length = 0 && gMotionDropped = 0)
        return
    EnsureMotionLogFile()
    text := ""
    for _, line in gMotionBuffer
        text .= line
    if (gMotionDropped > 0) {
        text .= A_TickCount ",DROPPED,,,,,,,,," gMotionDropped "`r`n"
        gMotionDropped := 0
    }
    if (text != "")
        FileAppend(text, gMotionLogPath, "UTF-8")
    gMotionBuffer := []
}

CsvField(value)
{
    quote := Chr(34)
    return quote StrReplace(value, quote, quote quote) quote
}

GetFirstVisibleLine(hwnd)
{
    return DllCall("user32\SendMessageW", "Ptr", hwnd, "UInt", 0x00CE, "Ptr", 0, "Ptr", 0)
}

IsEditAtBottom(hwnd)
{
    si := Buffer(28, 0)
    NumPut("UInt", 28, si, 0)
    NumPut("UInt", 0x17, si, 4) ; SIF_ALL
    if (!DllCall("user32\GetScrollInfo", "Ptr", hwnd, "Int", 1, "Ptr", si, "Int"))
        return true

    nMax := NumGet(si, 12, "Int")
    nPage := NumGet(si, 16, "UInt")
    nPos := NumGet(si, 20, "Int")
    return (nPos + nPage >= nMax - 1)
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

    ; 追記前の表示位置を保存する。末尾表示中だけ自動スクロールする。
    atBottom := IsEditAtBottom(gEdit)
    firstVisibleLine := GetFirstVisibleLine(gEdit)

    ; 上へスクロール中だけ、一時的なスクロールを画面へ見せない。
    if (!atBottom) {
        DllCall("user32\SendMessageW"
            , "Ptr", gEdit
            , "UInt", 0x000B ; WM_SETREDRAW
            , "Ptr", 0
            , "Ptr", 0)
    }

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

    if (atBottom) {
        DllCall("user32\SendMessageW"
            , "Ptr", gEdit
            , "UInt", 0x00B7 ; EM_SCROLLCARET
            , "Ptr", 0
            , "Ptr", 0)
    } else {
        currentFirstLine := GetFirstVisibleLine(gEdit)
        DllCall("user32\SendMessageW"
            , "Ptr", gEdit
            , "UInt", 0x00B6 ; EM_LINESCROLL
            , "Ptr", 0
            , "Ptr", firstVisibleLine - currentFirstLine)
        DllCall("user32\SendMessageW"
            , "Ptr", gEdit
            , "UInt", 0x000B ; WM_SETREDRAW
            , "Ptr", 1
            , "Ptr", 0)
        DllCall("user32\InvalidateRect", "Ptr", gEdit, "Ptr", 0, "Int", true)
    }
}
