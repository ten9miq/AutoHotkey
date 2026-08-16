#Requires AutoHotkey v2.0+
#SingleInstance Force
#UseHook

global MuhanPending := false
global MuhanPendingHwnd := 0

physicalKeyMonitor := InputHook("V I1")
physicalKeyMonitor.KeyOpt("{All}", "N")
physicalKeyMonitor.OnKeyDown := OnPhysicalKeyDown
physicalKeyMonitor.Start()

*sc029::{
    ClearMuhanPending()
    hwnd := WinExist("A")

    if IME_GetOpenStatus(hwnd) {
        SendEvent "{Esc}"
        Sleep 30
        SendEvent "{Esc}"
        Sleep 30
        IME_SetOpenStatus(hwnd, 0)
    } else {
        IME_SetOpenStatus(hwnd, 1)
    }
}

$sc07B::HandleMuhanKey()

~*LButton::ClearMuhanPending()
~*RButton::ClearMuhanPending()

ClearMuhanPending() {
    global MuhanPending := false
    global MuhanPendingHwnd := 0
}

OnPhysicalKeyDown(inputHook, virtualKey, scanCode) {
    if virtualKey = 0x1D && scanCode = 0x7B
        return
    ClearMuhanPending()
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

IME_GetOpenStatus(hwnd) {
    imeWindow := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    return DllCall("user32\SendMessageW"
        , "Ptr", imeWindow
        , "UInt", 0x0283 ; WM_IME_CONTROL
        , "Ptr", 0x0005 ; IMC_GETOPENSTATUS
        , "Ptr", 0)
}

IME_SetOpenStatus(hwnd, status) {
    imeWindow := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    return DllCall("user32\SendMessageW"
        , "Ptr", imeWindow
        , "UInt", 0x0283 ; WM_IME_CONTROL
        , "Ptr", 0x0006 ; IMC_SETOPENSTATUS
        , "Ptr", status ? 1 : 0)
}