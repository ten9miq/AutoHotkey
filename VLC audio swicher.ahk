; AutoHotkey v2.0

#Requires AutoHotkey v2.0

#HotIf WinActive("ahk_class Qt5QWindowIcon")

^+Right::{
    ; 右
    Send("!a")      ; Alt+A
    Sleep(100)
    Send("s")       ; S（ステレオモード）
    Sleep(100)
    Send("{Down 3}{Enter}")  ; 下キー3回（右）
}

^+Left::{
    ; 左
    Send("!a")
    Sleep(100)
    Send("s")
    Sleep(100)
    Send("{Down 2}{Enter}")  ; 下キー2回（左）
}

^+Down::{
    ; ステレオ
    Send("!a")
    Sleep(100)
    Send("s")
    Sleep(100)
    Send("{Down 1}{Enter}")  ; 下キー1回（ステレオ）
}

#HotIf
