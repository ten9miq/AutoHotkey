#If WinActive("ahk_exe mstsc.exe")
	$!Tab::
		Send,!{PgUp}
	Return
#If

#If WinActive("ahk_exe mstsc.exe")
	$!+Tab::
		Send,!{PgDn}
	Return

	$<^Tab::
		send,!{tab}
		Sleep 50
		send,!{tab Up}
	return

	$<+<^Tab::!+tab
		Sleep 50
		send,!{tab Up}
	return
#If





/* F1:: */
/*   getIMEMode := IME_Get() */
/*   MsgBox, %getIMEMode% */
/*   return */
