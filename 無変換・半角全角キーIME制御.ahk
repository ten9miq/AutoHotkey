#Requires AutoHotkey v2.0+
#SingleInstance Force
#UseHook
#Include "lib\UIAv2.ahk"

global MuhanPending := false
global MuhanPendingHwnd := 0
global ImeTextInputCount := 0
global ImeTextInputHwnd := 0
global ImeCancelDepth := 0
global ImeStatusCacheHwnd := 0
global ImeStatusCacheValue := 0
global ImeStatusCacheTick := 0
global LastKeyDownVk := 0
global RdpActiveCacheValue := false
global RdpActiveCacheTick := 0

physicalKeyMonitor := InputHook("V I1 L0")
physicalKeyMonitor.KeyOpt("{All}", "N")
physicalKeyMonitor.OnKeyDown := OnPhysicalKeyDown
physicalKeyMonitor.OnKeyUp := OnPhysicalKeyUp
physicalKeyMonitor.Start()

#HotIf !IsRemoteDesktopActive()
*sc029::{
    ClearMuhanPending()
    hwnd := WinExist("A")

    if IME_GetOpenStatus(hwnd) {
        cancelled := CancelImeComposition(hwnd)
        if !cancelled || IsChromiumWindow(hwnd) {
            ; 打鍵追跡で確信できる場合はUIA(重いクロスプロセスCOM)を回避し、無情報時のみUIAへフォールバック
            if HasLikelyImeText(hwnd)
                compositionState := GetImeCancelDepth(hwnd)
            else
                compositionState := GetImeCompositionState()
            if compositionState >= 1 {
                SendEvent "{Esc}"
                Sleep 20
            }
            if compositionState >= 2 {
                SendEvent "{Esc}"
                Sleep 20
            }
            if compositionState >= 3 {
                SendEvent "{Esc}"
                Sleep 20
            }
        }
        ClearImeTextInput()
        IME_SetOpenStatus(hwnd, 0)
    } else {
        ClearImeTextInput()
        IME_SetOpenStatus(hwnd, 1)
    }
}
#HotIf

$sc07B::HandleMuhanKey()

~*LButton::ClearInputPending()
~*RButton::ClearInputPending()

ClearInputPending() {
    ClearMuhanPending()
    ClearImeTextInput()
}

ClearMuhanPending() {
    global MuhanPending := false
    global MuhanPendingHwnd := 0
}

OnPhysicalKeyDown(inputHook, virtualKey, scanCode) {
    global LastKeyDownVk
    if virtualKey = 0x1D && scanCode = 0x7B
        return
    isRepeat := (virtualKey = LastKeyDownVk)
    LastKeyDownVk := virtualKey
    ClearMuhanPending()

    if virtualKey = 0x0D {
        ClearImeTextInput()
        return
    }

    if virtualKey = 0x09 {
        hwnd := WinExist("A")
        if HasLikelyImeText(hwnd)
            MarkImeConversion(hwnd)
        else
            ClearImeTextInput()
    } else if virtualKey = 0x08 {
        DecrementImeTextInput(WinExist("A"))
    } else if virtualKey = 0x20 || virtualKey = 0x1C {
        hwnd := WinExist("A")
        if HasLikelyImeText(hwnd)
            AdvanceImeCancelDepth(hwnd)
    } else if IsTextInputKey(virtualKey) && !IsCommandModifierDown()
        TrackImeTextInput(WinExist("A"), isRepeat)
}

OnPhysicalKeyUp(inputHook, virtualKey, scanCode) {
    global LastKeyDownVk
    if virtualKey = LastKeyDownVk
        LastKeyDownVk := 0
}

TrackImeTextInput(hwnd, isRepeat := false) {
    global ImeTextInputCount, ImeTextInputHwnd, ImeCancelDepth
    ; リピート中は同一ウィンドウのIME状態が不変なのでクロスプロセス問い合わせを省く
    if !(isRepeat && ImeTextInputHwnd = hwnd && ImeTextInputCount > 0) {
        if !IME_GetOpenStatusCached(hwnd)
            return
    }
    if ImeTextInputHwnd != hwnd {
        ImeTextInputCount := 0
        ImeTextInputHwnd := hwnd
    }
    ImeTextInputCount++
    ImeCancelDepth := 1
}

DecrementImeTextInput(hwnd) {
    global ImeTextInputCount, ImeTextInputHwnd, ImeCancelDepth
    if ImeTextInputHwnd = hwnd && ImeTextInputCount > 0 {
        ImeTextInputCount--
        if ImeTextInputCount = 0
            ImeCancelDepth := 0
    }
}

MarkImeConversion(hwnd) {
    global ImeCancelDepth
    if HasLikelyImeText(hwnd)
        ImeCancelDepth := Max(ImeCancelDepth, 2)
}

AdvanceImeCancelDepth(hwnd) {
    global ImeCancelDepth
    if HasLikelyImeText(hwnd)
        ImeCancelDepth := Min(Max(ImeCancelDepth, 1) + 1, 3)
}

HasLikelyImeText(hwnd) {
    global ImeTextInputCount, ImeTextInputHwnd
    return ImeTextInputHwnd = hwnd && ImeTextInputCount > 0
}

GetImeCancelDepth(hwnd) {
    global ImeCancelDepth
    return HasLikelyImeText(hwnd) ? Max(ImeCancelDepth, 1) : 0
}

ClearImeTextInput() {
    global ImeTextInputCount := 0
    global ImeTextInputHwnd := 0
    global ImeCancelDepth := 0
}

IsTextInputKey(virtualKey) {
    return virtualKey = 0x20
        || virtualKey >= 0x30 && virtualKey <= 0x5A
        || virtualKey >= 0x60 && virtualKey <= 0x6F
        || virtualKey >= 0xBA && virtualKey <= 0xE2
}

IsCommandModifierDown() {
    return GetKeyState("Ctrl", "P")
        || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P")
        || GetKeyState("RWin", "P")
}

IsRemoteDesktopActive() {
    global RdpActiveCacheValue, RdpActiveCacheTick
    if (A_TickCount - RdpActiveCacheTick) < 300
        return RdpActiveCacheValue

    active := false
    try {
        processName := WinGetProcessName("A")
        active := processName = "mstsc.exe"
            || processName = "msrdc.exe"
            || processName = "RdClient.Windows.exe"
    }
    RdpActiveCacheValue := active
    RdpActiveCacheTick := A_TickCount
    return active
}

    IsChromiumWindow(hwnd) {
        try return WinGetClass("ahk_id " hwnd) ~= "^Chrome_WidgetWin_[01]$"
        catch TargetError
        return false
    }

CancelImeComposition(hwnd) {
    focusHwnd := GetFocusedHwnd(hwnd)
    himc := DllCall("imm32\ImmGetContext", "Ptr", focusHwnd, "Ptr")
    if !himc
        return false

    try return DllCall("imm32\ImmNotifyIME"
        , "Ptr", himc
        , "UInt", 0x0015  ; NI_COMPOSITIONSTR
        , "UInt", 0x0004  ; CPS_CANCEL
        , "UInt", 0
        , "Int") != 0
    finally DllCall("imm32\ImmReleaseContext", "Ptr", focusHwnd, "Ptr", himc)
}

GetFocusedHwnd(fallbackHwnd) {
    static threadInfo := Buffer(24 + (A_PtrSize * 6))
    NumPut("UInt", threadInfo.Size, threadInfo)
    if DllCall("user32\GetGUIThreadInfo", "UInt", 0, "Ptr", threadInfo, "Int")
        return NumGet(threadInfo, 8 + A_PtrSize, "Ptr") || fallbackHwnd
    return fallbackHwnd
}

GetImeCompositionState() {
    try currentElement := UIA.GetFocusedElement()
    catch
        return -1

    queried := false
    Loop 7 {
        try {
            textEditPattern := currentElement.TextEditPattern
            try {
                conversionRange := textEditPattern.GetConversionTarget()
                conversionText := conversionRange.GetText(-1)
                queried := true
                if conversionText != ""
                    return 2
            }
            try {
                compositionRange := textEditPattern.GetActiveComposition()
                compositionText := compositionRange.GetText(-1)
                queried := true
                if compositionText != ""
                    return 1
            }
        }
        try currentElement := currentElement.Parent
        catch
            break
    }
    return queried ? 0 : -1
}

HandleMuhanKey() {
    global MuhanPending, MuhanPendingHwnd
    hwnd := WinExist("A")

    if MuhanPending && MuhanPendingHwnd = hwnd {
        ClearMuhanPending()
        SetTimer ConfirmCompositionAndDisableIme, -1
        return
    }

    MuhanPending := true
    MuhanPendingHwnd := hwnd
    SendEvent "{vk1Dsc07B down}"
    Sleep 30
    SendEvent "{vk1Dsc07B up}"
    SetTimer ConvertCompositionToHalfwidthAlnum, -1
}

ConvertCompositionToHalfwidthAlnum() {
    if !IME_GetOpenStatus(WinExist("A")) {
        ClearMuhanPending()
        return
    }
    SendEvent "{F10}"
}

ConfirmCompositionAndDisableIme() {
    IME_SetOpenStatus(WinExist("A"), 0)
}

IME_GetOpenStatus(hwnd, timeout := 200) {
    imeWindow := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    result := 0
    ok := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", imeWindow
        , "UInt", 0x0283  ; WM_IME_CONTROL
        , "Ptr", 0x0005   ; IMC_GETOPENSTATUS
        , "Ptr", 0
        , "UInt", 0x0003  ; SMTO_BLOCK | SMTO_ABORTIFHUNG
        , "UInt", timeout
        , "Ptr*", &result
        , "Ptr")
    return ok ? result : 0
}

; 連打時のクロスプロセス問い合わせを間引くための短時間キャッシュ
IME_GetOpenStatusCached(hwnd) {
    global ImeStatusCacheHwnd, ImeStatusCacheValue, ImeStatusCacheTick
    if ImeStatusCacheHwnd = hwnd && (A_TickCount - ImeStatusCacheTick) < 400
        return ImeStatusCacheValue
    ; 追跡目的の非クリティカル問い合わせなので入力スレッドのブロックを短くする
    status := IME_GetOpenStatus(hwnd, 80)
    ImeStatusCacheHwnd := hwnd
    ImeStatusCacheValue := status
    ImeStatusCacheTick := A_TickCount
    return status
}

IME_SetOpenStatus(hwnd, status) {
    global ImeStatusCacheHwnd, ImeStatusCacheValue, ImeStatusCacheTick
    imeWindow := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    result := 0
    ret := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", imeWindow
        , "UInt", 0x0283  ; WM_IME_CONTROL
        , "Ptr", 0x0006   ; IMC_SETOPENSTATUS
        , "Ptr", status ? 1 : 0
        , "UInt", 0x0003  ; SMTO_BLOCK | SMTO_ABORTIFHUNG
        , "UInt", 200
        , "Ptr*", &result
        , "Ptr")
    ImeStatusCacheHwnd := hwnd
    ImeStatusCacheValue := status ? 1 : 0
    ImeStatusCacheTick := A_TickCount
    return ret
}
