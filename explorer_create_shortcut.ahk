#Requires AutoHotkey v2.0+
#SingleInstance Force
#UseHook
#Include "lib\UIAv2.ahk"
SendMode "Event"
SetKeyDelay 10, 5

#HotIf WinActive("ahk_class CabinetWClass") || WinActive("ahk_class ExploreWClass")
$^+t::Explorer_NewText_FocusedNew()
$^+f::Send "^+n"
#HotIf

Explorer_NewText_FocusedNew() {
    KeyWait "t"
    Send "{Ctrl up}{Shift up}{Alt up}"

    explorerHwnd := WinGetID("A")

    try {
        folderPath := Explorer_GetActiveTabPath(explorerHwnd)
        filePath := Explorer_GetNewTextPath(folderPath)
        SplitPath filePath, &fileName

        FileOpen(filePath, "w").Close()
        Send "{Esc}{F5}"

        if !Explorer_FocusItem(explorerHwnd, fileName, 2500)
            throw Error("ファイルは作成しましたが、Explorer 上で選択できませんでした。",, filePath)

        Send "{F2}"
    } catch Error as err {
        Send "{Esc}"
        message := err.Message
        if err.Extra
            message .= "`n`n" err.Extra
        MsgBox message, "テキストファイルの作成", "Icon!"
    }
}

Explorer_GetActiveTabPath(explorerHwnd) {
    static IID_IShellBrowser := "{000214E2-0000-0000-C000-000000000046}"

    activeTabHwnd := 0
    try activeTabHwnd := ControlGetHwnd("ShellTabWindowClass1", "ahk_id " explorerHwnd)

    for shellWindow in ComObject("Shell.Application").Windows {
        try {
            if shellWindow.HWND != explorerHwnd
                continue

            if activeTabHwnd {
                shellBrowser := ComObjQuery(shellWindow, IID_IShellBrowser, IID_IShellBrowser)
                ComCall(3, shellBrowser, "Ptr*", &tabHwnd := 0)
                if tabHwnd != activeTabHwnd
                    continue
            }

            folderPath := shellWindow.Document.Folder.Self.Path
            if DirExist(folderPath)
                return RTrim(folderPath, "\")
        }
    }

    Send "^l"

    folderPath := ""
    lastValue := ""
    if !Explorer_WaitUntil(ReadFolderPath, 1000) {
        if lastValue
            throw Error("この場所には直接ファイルを作成できません。",, lastValue)
        throw Error("アクティブタブのパスを取得できませんでした。")
    }

    return RTrim(folderPath, "\")

    ReadFolderPath() {
        focusedElement := UIA.GetFocusedElement()
        if !focusedElement.IsValuePatternAvailable
            return false

        lastValue := focusedElement.Value
        if !DirExist(lastValue)
            return false

        folderPath := lastValue
        return true
    }
}

Explorer_GetNewTextPath(folderPath) {
    baseName := "新しいテキスト ドキュメント"
    filePath := folderPath "\" baseName ".txt"
    suffix := 2

    while FileExist(filePath) {
        filePath := folderPath "\" baseName " (" suffix ").txt"
        suffix++
    }

    return filePath
}

Explorer_FocusItem(explorerHwnd, fileName, timeoutMs) {
    displayName := RegExReplace(fileName, "i)\.txt$")
    item := ""

    found := Explorer_WaitUntil(FindItem, timeoutMs)
    if !found
        return false

    item.SelectionItemPattern.Select()
    item.SetFocus()
    return true

    FindItem() {
        root := UIA.ElementFromHandle(explorerHwnd)
        try item := root.FindElement({Name: fileName, IsSelectionItemPatternAvailable: true})
        catch TargetError
            try item := root.FindElement({Name: displayName, IsSelectionItemPatternAvailable: true})
        return IsObject(item)
    }
}

Explorer_WaitUntil(predicate, timeoutMs, intervalMs := 50) {
    deadline := A_TickCount + timeoutMs
    while A_TickCount < deadline {
        try {
            if predicate()
                return true
        }
        Sleep intervalMs
    }
    return false
}