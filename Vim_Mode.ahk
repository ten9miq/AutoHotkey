#Requires AutoHotkey v2.0+
#Include "lib\IMEv2.ahk"

$Esc::{
    IME_SET(0)
    Sleep 1
    Send "{Esc}"
}

$^[::{
    IME_SET(0)
    Sleep 1
    Send "^{[}"
}

#HotIf WinActive("ahk_exe gvim.exe") || WinActive("ahk_exe RLogin.exe") || WinActive("ahk_exe Code.exe") || WinActive("ahk_class ConsoleWindowClass")
$^c::{
    IME_SET(0)
    Sleep 1
    Send "^c"
}
#HotIf