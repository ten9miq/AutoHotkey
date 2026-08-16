; SetTitleMatchMode,RegEx ; winActiveで正規表現を使う方法
#Include IME.ahk  ; IMEの操作ライブラリの読み込み

$Esc::
  ; Send {vkF2sc070}  ; Kana
  ; Send {vkF4sc029}  ; ZenHan
  IME_SET(0)
  Sleep 1
  Send,{Esc}
  Return

$^[::
  ; Send {vkF2sc070}  ; Kana
  ; Send {vkF4sc029}  ; ZenHan
  IME_SET(0)
  Sleep 1
  Send,^{[}
  Return


#If WinActive("ahk_exe gvim.exe") || WinActive("ahk_exe RLogin.exe") || WinActive("ahk_exe Code.exe") || WinActive("ahk_class ConsoleWindowClass")
$^c::
  ; Send {vkF2sc070}  ; Kana
  ; Send {vkF4sc029}  ; ZenHan
  IME_SET(0)
  Sleep 1
  Send,^{c}
  Return
#If

/* F1:: */
/*   getIMEMode := IME_Get() */
/*   MsgBox, %getIMEMode% */
/*   return */
