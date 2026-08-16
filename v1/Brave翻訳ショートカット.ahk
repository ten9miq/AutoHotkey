#IfWinActive ahk_exe chrome.exe
^e::
    Send, +{F10}
    Sleep, 150
    Send, t
    Sleep, 150
return
#IfWinActive

#IfWinActive ahk_exe brave.exe
^e::
    Send, +{F10}
    Sleep, 150
    Send, t
    Sleep, 150
return
#IfWinActive