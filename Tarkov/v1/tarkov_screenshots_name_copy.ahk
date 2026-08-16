#Persistent
SetTimer, CheckForNewFiles, 2000 ; 2秒ごとにチェック
return

CheckForNewFiles:
    folder := "C:\Users\" . A_UserName . "\Documents\Escape from Tarkov\Screenshots"
    iniFilePath := A_ScriptDir . "\FileInfo.ini"

    ; INIファイルから前回のファイル数と最後にコピーされたファイル名を読み込む
    lastFileCount := 0
    lastCopiedFile := ""
    IniRead, lastFileCount, %iniFilePath%, FileInfo, FileCount, 0
    IniRead, lastCopiedFile, %iniFilePath%, LastCopied, FileName, ""

    ; フォルダ内の現在のファイル数を計算
    currentFileCount := 0
    Loop, Files, % folder . "\*.*", F
        currentFileCount++

    ; ファイル数に変化があった場合（増加または減少）、最新または最古のファイルを特定
    if (currentFileCount != lastFileCount)
    {
        newestFile := ""
        newestTime := 0
        if (currentFileCount == 0) ; 全てのファイルが削除された場合
        {
            IniWrite, 0, %iniFilePath%, FileInfo, FileCount ; 現在のファイル数を記録
            IniWrite, "", %iniFilePath%, LastCopied, FileName ; 選択されたファイル名を記録
            Return
        }

        Loop, Files, % folder . "\*.*", F
        {
            FileGetTime, fileTime, % A_LoopFileFullPath, M
            if (fileTime > newestTime) ; 最新のファイルを特定
            {
                newestFile := A_LoopFileName
                newestTime := fileTime
            }
        }

        ; 新しいファイルが前回コピーされたファイルと異なる場合にのみクリップボードにコピー
        if (newestFile != "" && newestFile != lastCopiedFile)
        {
            ; SoundPlay, *64 ; システムの警告音を鳴らす
            clipboard := newestFile ; クリップボードに最新のファイル名をコピー
            ClipWait ; クリップボードに何かが格納されるのを待つ
            ; TrayTip, New File Detected, % "Copied to clipboard: " . newestFile, 10, 1  ; 通知を表示
            IniWrite, %currentFileCount%, %iniFilePath%, FileInfo, FileCount ; 現在のファイル数を記録
            IniWrite, %newestFile%, %iniFilePath%, LastCopied, FileName ; 最新のファイル名を記録
            paste_map_input()
        }else{
            ; ファイル名は最後にコピー済みでもファイル数が変更されているならカウントを更新する
            IniWrite, %currentFileCount%, %iniFilePath%, FileInfo, FileCount ; 現在のファイル数を記録
        }
    }

return

paste_map_input(){
    SetTitleMatchMode, 2 ; タイトルが部分的に一致する場合にウィンドウをマッチさせる
    targetTitle := "Tarkov Market - Google Chrome" ; 探すウィンドウのタイトルの一部

    ; すべてのウィンドウをループして、目的のウィンドウを探す
    WinGet, idList, List, ahk_class Chrome_WidgetWin_1 ; Chromeウィンドウのリストを取得
    Loop, %idList%
    {
        thisID := idList%A_Index% ; 現在のウィンドウID
        WinGetTitle, thisTitle, ahk_id %thisID% ; 現在のウィンドウのタイトルを取得
        If InStr(thisTitle, targetTitle) ; タイトルが目的のテキストを含むか
        {
            ; ここでフォーカスを変えずにペーストを行う
            ControlFocus, , ahk_id %thisID% ; 必要に応じて特定のコントロールを指定
            Sleep, 500
            ControlSend, , ^a, ahk_id %thisID% ; 全選択
            ControlSend, , ^v, ahk_id %thisID% ; ウィンドウにペースト
            ; ControlSend, , %name%, ahk_id %thisID% ; 文字列を送信
            break ; ループを終了
        }
    }

}