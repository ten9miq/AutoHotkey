; AutoHotkey v1.1
; Explorer's .lnk hotkey path is intentionally bypassed.

#NoEnv
#SingleInstance Force
#Persistent
SendMode Input
SetWorkingDir %A_ScriptDir%

bravePath := "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
sakuraPath := "C:\Program Files (x86)\sakura\sakura.exe"

^!+w::
Run, % """" bravePath """"
return

^!+q::
Run, % """" sakuraPath """"
return
