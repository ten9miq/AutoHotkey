#Requires AutoHotkey v2.0+
#SingleInstance Force
; RCtrl2連打でカーソルをモニター中央に移動
; Alt+F1で現在のモニター構成の固定先を、カーソルがあるモニターに設定
; Alt+F2で現在のモニター構成の動的 / 固定モードを切り替え
; 接続構成ごとに保存し、接続変更後は次の操作時に自動で切り替える

InstallKeybdHook()

; 混在DPIのマルチモニターでも物理ピクセル座標を使用
DllCall("user32\SetThreadDpiAwarenessContext", "Ptr", -3, "Ptr")
CoordMode "Mouse", "Screen"

; ダブルタップ閾値（ミリ秒）
doubleTapThreshold := 400

;=== 設定ファイルのパス & 起動時に読み込み ===
iniFile := A_ScriptDir "\RCtrl2連打でモニター中央に移動.ini"

; 旧Settingsは最初の構成にだけ引き継ぐ。新しい構成は動的モードで開始する。
; 起動時に接続変更中だった場合は、次の操作時に再取得する。
try LoadMonitorProfile(GetMonitorConfiguration())


;=== Alt+F1 で固定先モニターを現在カーソルがあるモニターに設定 ===
!F1::SetFixedMonitorFromCursor()

SetFixedMonitorFromCursor() {
    configuration := GetMonitorConfiguration()
    profile := LoadMonitorProfile(configuration)
    MouseGetPos &mouseX, &mouseY
    currentMonitor := GetMonitorFromPoint(mouseX, mouseY)

    if (currentMonitor >= 1 && currentMonitor <= configuration.Ids.Length) {
        profile.FixedMonitorId := configuration.Ids[currentMonitor]
        profile.FixedMode := 1
        SaveMonitorProfile(profile)

        ToolTip "この構成に保存：固定モード / 移動先モニター " currentMonitor
    } else {
        ToolTip "固定先モニターを判定できませんでした"
    }

    SetTimer RemoveToolTip, -1000
}


;=== Alt+F2 で動的 / 固定モード切り替え ===
!F2::ToggleFixedMode()

ToggleFixedMode() {
    configuration := GetMonitorConfiguration()
    profile := LoadMonitorProfile(configuration)
    destination := FindMonitorById(configuration, profile.FixedMonitorId)

    if (profile.FixedMode = 0) {
        ; 動的 → 固定

        ; 固定先が未設定または無効なら、現在カーソルがあるモニターを固定先にする
        if (destination = 0) {
            MouseGetPos &mouseX, &mouseY
            currentMonitor := GetMonitorFromPoint(mouseX, mouseY)

            if (currentMonitor >= 1 && currentMonitor <= configuration.Ids.Length) {
                destination := currentMonitor
                profile.FixedMonitorId := configuration.Ids[currentMonitor]
            }
        }

        profile.FixedMode := 1
    } else {
        ; 固定 → 動的
        profile.FixedMode := 0
    }

    SaveMonitorProfile(profile)

    modeText := profile.FixedMode
        ? "固定モード / 移動先モニター " destination
        : "動的モード"

    ToolTip "この構成に保存：" modeText
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
    configuration := GetMonitorConfiguration()
    profile := LoadMonitorProfile(configuration)
    MouseGetPos &mouseX, &mouseY
    monitorCount := configuration.Ids.Length

    if (profile.FixedMode = 1) {
        ; 固定モード：Alt+F1で選んだ固定先へ移動
        destination := FindMonitorById(configuration, profile.FixedMonitorId)

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


;=== 接続中のモニターを番号ではなくデバイスIDで識別する ===
GetMonitorConfiguration() {
    ids := []
    Loop MonitorGetCount() {
        ids.Push(GetMonitorIdentity(MonitorGetName(A_Index)))
    }
    return {Ids: ids, Key: BuildMonitorConfigurationKey(ids)}
}

BuildMonitorConfigurationKey(ids) {
    names := ""
    for id in ids {
        names .= id "`n"
    }
    ; 列挙順・画面番号・配置・解像度が変わっても同じ接続構成とする。
    return StrReplace(RTrim(Sort(names), "`n"), "`n", "|")
}

GetMonitorIdentity(deviceName) {
    identities := ""
    deviceIndex := 0
    Loop {
        ; DISPLAY_DEVICEW: cb=0, StateFlags=324, DeviceID=328, sizeof=840
        device := Buffer(840, 0)
        NumPut "UInt", device.Size, device, 0
        if !DllCall("user32\EnumDisplayDevicesW", "Str", deviceName,
            "UInt", deviceIndex++, "Ptr", device, "UInt", 1, "Int") {
            break
        }
        if (NumGet(device, 324, "UInt") & 1) {
            id := StrGet(device.Ptr + 328, 128, "UTF-16")
            if (id != "") {
                identities .= StrUpper(id) "`n"
            }
        }
    }
    if (identities != "") {
        return StrReplace(RTrim(Sort(identities), "`n"), "`n", ";")
    }
    ; リモート画面等でIDが得られない場合だけGDI名を使用する。
    return "GDI:" StrUpper(deviceName)
}

FindMonitorById(configuration, id) {
    for index, monitorId in configuration.Ids {
        if (id = monitorId) {
            return index
        }
    }
    return 0
}


;=== 構成ごとの設定読み込み・保存 ===
LoadMonitorProfile(configuration) {
    global iniFile
    sections := FileExist(iniFile) ? IniRead(iniFile) : ""
    nextNumber := 1
    hasProfiles := false
    Loop Parse sections, "`n", "`r" {
        if !RegExMatch(A_LoopField, "^MonitorProfile(\d+)$", &match) {
            continue
        }
        hasProfiles := true
        nextNumber := Max(nextNumber, match[1] + 1)
        if (IniRead(iniFile, A_LoopField, "Configuration", "") = configuration.Key) {
            return {Section: A_LoopField, Key: configuration.Key,
                FixedMode: IniRead(iniFile, A_LoopField, "FixedMode", 0) = "1" ? 1 : 0,
                FixedMonitorId: IniRead(iniFile, A_LoopField, "FixedMonitorId", "")}
        }
    }

    profile := {Section: "MonitorProfile" nextNumber, Key: configuration.Key,
        FixedMode: 0, FixedMonitorId: ""}
    legacyMonitor := IniRead(iniFile, "Settings", "FixedMonitor", "")
    if (!hasProfiles && RegExMatch(legacyMonitor, "^\d+$")) {
        legacyMonitor += 0
        profile.FixedMode := IniRead(iniFile, "Settings", "FixedMode",
            legacyMonitor > 0 ? 1 : 0) = "1" ? 1 : 0
        if (legacyMonitor >= 1 && legacyMonitor <= configuration.Ids.Length) {
            profile.FixedMonitorId := configuration.Ids[legacyMonitor]
        }
        SaveMonitorProfile(profile)
    }
    return profile
}

SaveMonitorProfile(profile) {
    global iniFile
    IniWrite profile.FixedMode, iniFile, profile.Section, "FixedMode"
    IniWrite profile.FixedMonitorId, iniFile, profile.Section, "FixedMonitorId"
    IniWrite profile.Key, iniFile, profile.Section, "Configuration"
}


;=== 指定座標が属するモニター番号を返す ===
GetMonitorFromPoint(x, y) {
    monitorCount := MonitorGetCount()

    Loop monitorCount {
        MonitorGet A_Index, &monitorLeft, &monitorTop, &monitorRight, &monitorBottom

        if (x >= monitorLeft && x < monitorRight
            && y >= monitorTop && y < monitorBottom) {
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
