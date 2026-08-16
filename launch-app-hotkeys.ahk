; AutoHotkey v2.0
; Explorer's .lnk hotkey path is intentionally bypassed.

#Requires AutoHotkey v2.0
#SingleInstance Force

bravePath := "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
sakuraPath := "C:\Program Files (x86)\sakura\sakura.exe"

^!+w::Run(bravePath)
^!+q::Run(sakuraPath)
