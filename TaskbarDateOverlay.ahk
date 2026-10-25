#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "lib\UIAv2.ahk"
Persistent

; ===== 設定 =====
DATE_FORMAT := "MM/dd (ddd)"
TEXT_COLOR := "FFFFFF" ; 白文字（ダークモード向け）
OUTLINE_COLOR := "000000"
OUTLINE_PIXELS := 1   ; 文字の周囲に付ける黒い縁取り（物理ピクセル）
MAX_FONT_SIZE := 10    ; 拡大率100%時のポイント数。領域に合わせて縮小する。
MIN_FONT_SIZE := 8     ; 読めないほど小さくしない。
DATE_WIDTH := 120     ; 拡大率100%時の表示幅
CLOCK_GAP := 4        ; 時計の左隣との間隔
DATE_X_OFFSET := 34   ; 現在の左隣位置から右へずらす距離（拡大率100%時）
TRANSPARENT := "EEAA99"

DateOverlays := Map()
OnMessage(0x2B, DrawDateText) ; WM_DRAWITEM: 日付を縁取り付きで描画する。
UpdateDate()
SetTimer(UpdateDate, 1000)

UpdateDate() {
    global DateOverlays, DATE_FORMAT, DATE_WIDTH, CLOCK_GAP, DATE_X_OFFSET

    taskbars := []
    for className in ["Shell_TrayWnd", "Shell_SecondaryTrayWnd"] {
        for hwnd in WinGetList("ahk_class " className)
            taskbars.Push(hwnd)
    }

    seen := Map()
    date := FormatTime(A_Now, DATE_FORMAT)
    for taskbar in taskbars {
        try {
            WinGetPos(&tx, &ty, &tw, &th, taskbar)
            dpi := DllCall("GetDpiForWindow", "ptr", taskbar, "uint")
        } catch TargetError {
            continue
        }
        if (tw < 200 || th < 18 || !dpi)
            continue

        seen[taskbar] := true
        if !DateOverlays.Has(taskbar)
            DateOverlays[taskbar] := CreateDateOverlay()
        overlay := DateOverlays[taskbar]

        clockRect := GetClockRect(taskbar, overlay)
        ; 時計が取得できない場合は誤った場所へ表示せず、次回再検出する。
        if !clockRect || clockRect.x < tx || clockRect.y < ty
            || clockRect.x + clockRect.w > tx + tw
            || clockRect.y + clockRect.h > ty + th {
            overlay.Window.Hide()
            continue
        }

        gap := Round(CLOCK_GAP * dpi / 96)
        overlayWidth := Min(Round(DATE_WIDTH * dpi / 96), Floor(clockRect.x - tx) - gap)
        ; 時計の左隣で、タスクバーの下半分を使う。
        overlayHeight := th - Floor(th / 2)
        if (overlayWidth < 1 || overlayHeight < 1
            || !FitDateText(overlay, date, overlayWidth, overlayHeight, dpi)) {
            overlay.Window.Hide()
            continue
        }

        x := Round(clockRect.x) - gap - overlayWidth + Round(DATE_X_OFFSET * dpi / 96)
        x := Max(tx, Min(x, tx + tw - overlayWidth))
        y := ty + Floor(th / 2)
        overlay.Text.Move(0, 0, overlayWidth, overlayHeight)
        overlay.Window.Show("x" x " y" y " w" overlayWidth " h" overlayHeight " NoActivate")
        ; タスクバーも最前面。Showだけでは裏に残るので順序を戻す。
        ; HWND_TOPMOST=-1, SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE=0x13
        DllCall("SetWindowPos", "ptr", overlay.Window.Hwnd, "ptr", -1,
            "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)
    }

    removed := []
    for taskbar, overlay in DateOverlays {
        if !seen.Has(taskbar) {
            overlay.Window.Destroy()
            removed.Push(taskbar)
        }
    }
    for taskbar in removed
        DateOverlays.Delete(taskbar)
}

GetClockRect(taskbar, overlay) {
    try {
        if overlay.Clock
            return overlay.Clock.Location
    } catch {
        ; UIA要素が無効になった場合は取得し直す。
        overlay.Clock := 0
    }

    try {
        root := UIA.ElementFromHandle(taskbar)
        for element in root.FindElements({ClassName: "SystemTray.AccentButton"}) {
            ; 実機の時計には専用HWNDがなく、SystemTrayIconも他のボタンと共通。
            ; 現在の日本語環境と英語環境の時計ラベルで識別する。
            if RegExMatch(element.Name, "^(時計|Clock)(?:\s|$)") {
                overlay.Clock := element
                return element.Location
            }
        }
    }
    return 0
}

FitDateText(overlay, date, availableWidth, availableHeight, dpi) {
    global MAX_FONT_SIZE, MIN_FONT_SIZE, OUTLINE_PIXELS

    layoutKey := date "|" availableWidth "|" availableHeight "|" dpi
    if (overlay.LayoutKey = layoutKey)
        return overlay.Fits

    overlay.Text.Value := date
    overlay.LayoutKey := layoutKey
    overlay.Fits := false
    pointSize := MAX_FONT_SIZE
    while (pointSize >= MIN_FONT_SIZE) {
        ; AHKのフォントはシステムDPIで換算されるため、対象DPIに補正する。
        overlay.Text.SetFont("s" (pointSize * dpi / A_ScreenDPI) " bold q3")
        textSize := MeasureDateText(overlay.Text, date)
        textSize.w += OUTLINE_PIXELS * 2
        textSize.h += OUTLINE_PIXELS * 2
        if (textSize.w <= availableWidth && textSize.h <= availableHeight) {
            overlay.FontSize := pointSize
            overlay.TextWidth := textSize.w
            overlay.TextHeight := textSize.h
            overlay.Fits := true
            break
        }
        pointSize -= 0.25
    }
    return overlay.Fits
}

MeasureDateText(control, value) {
    hdc := DllCall("GetDC", "ptr", control.Hwnd, "ptr")
    if !hdc
        throw OSError()
    oldFont := 0
    try {
        font := SendMessage(0x31, 0, 0, , control.Hwnd) ; WM_GETFONT
        oldFont := DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", font, "ptr")
        size := Buffer(8, 0)
        if !DllCall("gdi32\GetTextExtentPoint32W", "ptr", hdc, "str", value,
            "int", StrLen(value), "ptr", size)
            throw OSError()
        return {w: NumGet(size, 0, "int"), h: NumGet(size, 4, "int")}
    } finally {
        if oldFont
            DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", oldFont)
        DllCall("ReleaseDC", "ptr", control.Hwnd, "ptr", hdc)
    }
}

DrawDateText(wParam, lParam, msg, hwnd) {
    controlHwnd := NumGet(lParam, A_PtrSize = 8 ? 24 : 20, "ptr")
    control := GuiCtrlFromHwnd(controlHwnd)
    if !control || control.Name != "OutlinedDate"
        return
    hdc := NumGet(lParam, A_PtrSize = 8 ? 32 : 24, "ptr")
    rect := lParam + (A_PtrSize = 8 ? 40 : 28)
    PaintDateText(control, hdc, rect)
    return true
}

PaintDateText(control, hdc, rect) {
    global TRANSPARENT, TEXT_COLOR, OUTLINE_COLOR, OUTLINE_PIXELS

    background := DllCall("gdi32\CreateSolidBrush", "uint", ColorRef(TRANSPARENT), "ptr")
    oldFont := 0
    oldMode := DllCall("gdi32\SetBkMode", "ptr", hdc, "int", 1) ; TRANSPARENT
    oldColor := DllCall("gdi32\SetTextColor", "ptr", hdc, "uint", ColorRef(OUTLINE_COLOR), "uint")
    try {
        ; 再描画時は透過色で消し、前の日付や縁取りが残らないようにする。
        DllCall("FillRect", "ptr", hdc, "ptr", rect, "ptr", background)
        value := control.Value
        if (value = "")
            return
        font := SendMessage(0x31, 0, 0, , control.Hwnd) ; WM_GETFONT
        oldFont := DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", font, "ptr")
        size := Buffer(8, 0)
        DllCall("gdi32\GetTextExtentPoint32W", "ptr", hdc, "str", value,
            "int", StrLen(value), "ptr", size)
        left := NumGet(rect, 0, "int"), top := NumGet(rect, 4, "int")
        areaWidth := NumGet(rect, 8, "int") - left
        areaHeight := NumGet(rect, 12, "int") - top
        x := left + Floor((areaWidth - NumGet(size, 0, "int")) / 2)
        y := top + Floor((areaHeight - NumGet(size, 4, "int")) / 2)
        ; 周囲8方向を黒で描き、最後に中央を白い太字で描く。
        for offset in [[-1,-1], [0,-1], [1,-1], [-1,0], [1,0], [-1,1], [0,1], [1,1]]
            DllCall("gdi32\TextOutW", "ptr", hdc,
                "int", x + offset[1] * OUTLINE_PIXELS, "int", y + offset[2] * OUTLINE_PIXELS,
                "str", value, "int", StrLen(value))
        DllCall("gdi32\SetTextColor", "ptr", hdc, "uint", ColorRef(TEXT_COLOR))
        DllCall("gdi32\TextOutW", "ptr", hdc, "int", x, "int", y,
            "str", value, "int", StrLen(value))
    } finally {
        if oldFont
            DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", oldFont)
        DllCall("gdi32\SetTextColor", "ptr", hdc, "uint", oldColor)
        DllCall("gdi32\SetBkMode", "ptr", hdc, "int", oldMode)
        DllCall("gdi32\DeleteObject", "ptr", background)
    }
}

ColorRef(hexColor) {
    color := Integer("0x" hexColor)
    return ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
}

CreateDateOverlay() {
    global TRANSPARENT, MAX_FONT_SIZE, TEXT_COLOR

    ; LAYERED + TRANSPARENTで文字部分も含めてクリックを背後へ通す。
    ; WS_EX_LAYERED=0x80000 / WS_EX_TRANSPARENT=0x20 / WS_EX_NOACTIVATE=0x08000000
    window := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08080020 -DPIScale",
        "TaskbarDateOverlay")
    window.BackColor := TRANSPARENT
    window.MarginX := 0
    window.MarginY := 0
    window.SetFont("s" MAX_FONT_SIZE " c" TEXT_COLOR " bold q3", "Segoe UI")
    ; SS_OWNERDRAW=0xD: 背景の透明性を保ったまま、文字を縁取り付きで描く。
    text := window.AddText("vOutlinedDate x0 y0 w1 h1 +0xD", "")
    window.Show("Hide w1 h1")
    WinSetTransColor(TRANSPARENT, window)
    return {Window: window, Text: text, Clock: 0, LayoutKey: "", Fits: false,
        FontSize: 0, TextWidth: 0, TextHeight: 0}
}
