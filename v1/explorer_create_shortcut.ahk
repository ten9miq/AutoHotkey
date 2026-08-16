#NoEnv
#SingleInstance Force
#UseHook On
SendMode Event
SetKeyDelay, 10, 5

#If WinActive("ahk_class CabinetWClass") || WinActive("ahk_class ExploreWClass")
$^+t::Explorer_NewText_FocusedNew()
$^+f::Send, ^+n
#If

Explorer_NewText_FocusedNew() {
    KeyWait, t

    Send, {Ctrl up}{Shift up}{Alt up}
    Sleep, 20

    Send, {Esc}
    Sleep, 30

    Send, {F10}
    Sleep, 200

    Send, {Enter}
    Sleep, 160

    Send, {End}
    Sleep, 30

    Send, {Up 2}
    Sleep, 30

    Send, {Enter}
}