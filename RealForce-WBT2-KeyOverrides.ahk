#Requires AutoHotkey v2.0
#SingleInstance Force

bravePath := '"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"'

; RealForce Fn+F1: ブラウザ
>+F1:: Run(bravePath)

; RealForce Fn+F2: メール
>+F2::Run "mailto:"
; RealForce Fn+F3: 電卓
>+F3::LaunchCalculator()
; 戻る
$>!Left::Click "X1"
; 進む
$>!Right::Click "X2"

; ブラウザと表計算アプリではHID-RemapperのCtrl+PageUp/Downをそのまま通す。
; それ以外ではCtrl+PageDown -> Ctrl+Tab、Ctrl+PageUp -> Ctrl+Shift+Tabに変換する。
global gTabPageNavigationExecutables := Map(
    "chrome.exe", true,
    "brave.exe", true,
    "msedge.exe", true,
    "firefox.exe", true,
    "vivaldi.exe", true,
    "opera.exe", true,
    "floorp.exe", true,
    "librewolf.exe", true,
    "waterfox.exe", true,
    "zen.exe", true,
    "excel.exe", true,          ; Microsoft Excel
    "et.exe", true,             ; WPS Spreadsheets
    "desktopeditors.exe", true, ; ONLYOFFICE Desktop Editors
    "planmaker.exe", true,      ; SoftMaker / FreeOffice PlanMaker
    "scalc.exe", true           ; LibreOffice Calc launcher
)

#HotIf !IsTabPageNavigationTarget()
$^PgDn::SendInput "^{Tab}"
$^+PgDn::SendInput "^{Tab}"
$^PgUp::SendInput "^+{Tab}"
$^+PgUp::SendInput "^+{Tab}"
#HotIf

IsTabPageNavigationTarget() {
    global gTabPageNavigationExecutables

    try exe := StrLower(WinGetProcessName("A"))
    catch
        return false

    if (gTabPageNavigationExecutables.Has(exe))
        return true

    ; LibreOffice / Apache OpenOffice は複数アプリでプロセスを共有するため、
    ; Calcのウィンドウタイトルの場合だけ対象にする。
    if (exe = "soffice.bin" || exe = "soffice.exe") {
        try title := WinGetTitle("A")
        catch
            return false

        return RegExMatch(title, "i)(LibreOffice|OpenOffice).*Calc|Calc.*(LibreOffice|OpenOffice)") != 0
    }

    return false
}

LaunchCalculator() {
    Run "calc.exe"

    ; 電卓のウィンドウが作られてから前面に出す。
    if hwnd := WinWait("ahk_exe CalculatorApp.exe",, 5)
        WinActivate(hwnd)
}
