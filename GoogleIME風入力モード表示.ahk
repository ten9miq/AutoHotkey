#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include "lib\IMEv2.ahk"
#Include "lib\UIAv2.ahk"

; Mozcと同様に2.5秒保持し、16msごとに透明度を32下げてフェードアウトする。
IndicatorDisplayMs := 2500
IndicatorFadeIntervalMs := 16
IndicatorFadeAlphaDelta := 32
IndicatorLogicalWidth := 44
IndicatorLogicalHeight := 48
IndicatorWidth := 44
IndicatorHeight := 48
IndicatorFrameColor := "168BD2" ; グローなしでもMozcの見た目に近い明るさ
IndicatorOffsetX := -22 ; 突起先端と本体中央をキャレットに合わせる
IndicatorOffsetY := 24 ; 96 DPI基準。対象ウィンドウのDPIに合わせて拡大する
IndicatorAboveGap := 8 ; 上側表示時の矢印先端とキャレット上端の間隔
IndicatorDpi := 0
IndicatorPointsDown := false
ImePollActiveMs := 180 ; 変化検出直後やウィンドウ切替直後の追従間隔
ImePollIdleMs := 350 ; 無変化が続くときの省電力間隔
ImePollIdleAfterMs := 3000 ; この時間無変化ならアイドル間隔へ落とす
ImeShowDebounceMs := 60 ; 変化連続時に重いキャレット解決を1回へ集約

LastImeSignature := ""
IndicatorHideVersion := 0
LastImeChangeTick := A_TickCount
LastPollForegroundHwnd := 0
CurrentPollIntervalMs := ImePollActiveMs
PendingImeSnapshot := ""
PendingImeShowVersion := 0

CoordMode "Caret", "Screen"
CoordMode "Mouse", "Screen"
UIA.SetMaximumDPIAwareness()
CreateInputModeIndicator()
OnMessage(0x02E0, HandleInputModeIndicatorDpiChanged) ; WM_DPICHANGED

SetTimer WatchImeMode, ImePollActiveMs

WatchImeMode() {
    global LastImeSignature, LastImeChangeTick, LastPollForegroundHwnd
        , ImePollIdleAfterMs, ImePollActiveMs, ImePollIdleMs

    snapshot := GetImeModeSnapshot()
    windowSwitched := snapshot.hwnd != LastPollForegroundHwnd
    if windowSwitched {
        LastPollForegroundHwnd := snapshot.hwnd
        LastImeChangeTick := A_TickCount
        ApplyImePollInterval(ImePollActiveMs)
    }

    if !snapshot.valid
        return

    signature := snapshot.open "|" snapshot.convMode
    ; 起動直後とウィンドウ切替直後はベースライン更新のみで吹き出しを出さない。
    if LastImeSignature = "" || windowSwitched {
        LastImeSignature := signature
        return
    }
    if signature = LastImeSignature {
        if A_TickCount - LastImeChangeTick >= ImePollIdleAfterMs
            ApplyImePollInterval(ImePollIdleMs)
        return
    }

    LastImeSignature := signature
    LastImeChangeTick := A_TickCount
    ApplyImePollInterval(ImePollActiveMs)
    QueueInputModeIndicator(snapshot)
}

ApplyImePollInterval(intervalMs) {
    global CurrentPollIntervalMs
    if intervalMs = CurrentPollIntervalMs
        return
    CurrentPollIntervalMs := intervalMs
    SetTimer WatchImeMode, intervalMs
}

; ポーリング粒度を超えて連続した変化を最新スナップショットの1回にまとめる。
QueueInputModeIndicator(snapshot) {
    global PendingImeSnapshot, PendingImeShowVersion, ImeShowDebounceMs
    PendingImeSnapshot := snapshot
    PendingImeShowVersion += 1
    version := PendingImeShowVersion
    SetTimer (*) => FlushInputModeIndicator(version), -ImeShowDebounceMs
}

FlushInputModeIndicator(version) {
    global PendingImeSnapshot, PendingImeShowVersion
    if version != PendingImeShowVersion
        return
    ShowInputModeIndicator(PendingImeSnapshot)
}

ShowInputModeIndicator(snapshot) {
    global IndicatorDisplayMs, IndicatorOffsetX, IndicatorOffsetY
        , IndicatorWidth, IndicatorHeight, IndicatorHideVersion, IndicatorDpi
        , InputModeIndicatorGui, InputModeIndicatorText

    anchor := ResolveCaretAnchor()
    if !anchor.found
        return

    display := GetImeModeDisplay(snapshot)
    UpdateInputModeIndicatorDpi(GetWindowDpi(snapshot.hwnd))
    SetInputModeIndicatorWideFont(display.HasOwnProp("wide") && display.wide)
    InputModeIndicatorText.Text := display.text
    InputModeIndicatorText.Opt("c" display.color)
    scaledOffsetX := ScaleIndicatorPixels(IndicatorOffsetX, IndicatorDpi)
    scaledOffsetY := ScaleIndicatorPixels(IndicatorOffsetY, IndicatorDpi)
    position := ClampToWorkArea(anchor.x + scaledOffsetX
        , anchor.y + scaledOffsetY, anchor.x, anchor.y)
    SetInputModeIndicatorArrowDirection(position.above)
    IndicatorHideVersion += 1
    version := IndicatorHideVersion
    SetIndicatorWindowAlpha(InputModeIndicatorGui, 255)
    InputModeIndicatorGui.Show("NA x" position.x " y" position.y
        . " w" IndicatorWidth " h" IndicatorHeight)
    ArrangeIndicatorWindowOrder()
    SetTimer (*) => StartInputModeIndicatorFade(version), -IndicatorDisplayMs
}

ArrangeIndicatorWindowOrder() {
    global InputModeIndicatorGui
    DllCall "user32\SetWindowPos", "Ptr", InputModeIndicatorGui.Hwnd, "Ptr", -1
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13
}

StartInputModeIndicatorFade(version) {
    global IndicatorFadeIntervalMs, IndicatorHideVersion
    if version != IndicatorHideVersion
        return
    SetTimer (*) => FadeInputModeIndicator(version, 255), -IndicatorFadeIntervalMs
}

FadeInputModeIndicator(version, alpha) {
    global IndicatorFadeIntervalMs, IndicatorFadeAlphaDelta
        , IndicatorHideVersion, InputModeIndicatorGui
    if version != IndicatorHideVersion
        return

    nextAlpha := Max(alpha - IndicatorFadeAlphaDelta, 0)
    if nextAlpha = 0 {
        InputModeIndicatorGui.Hide()
        return
    }
    SetIndicatorWindowAlpha(InputModeIndicatorGui, nextAlpha)
    SetTimer (*) => FadeInputModeIndicator(version, nextAlpha)
        , -IndicatorFadeIntervalMs
}

SetIndicatorWindowAlpha(guiWindow, alpha) {
    if !DllCall("user32\SetLayeredWindowAttributes", "Ptr", guiWindow.Hwnd
        , "UInt", 0, "UChar", alpha, "UInt", 2, "Int")
        throw Error("Failed to set indicator window alpha")
}

GetImeModeSnapshot() {
    hwnd := WinExist("A")
    if !hwnd
        return {valid: false, hwnd: 0, open: false, convMode: 0}

    focusHwnd := _IME_GetFocusHwnd("ahk_id " hwnd)
    imeHwnd := focusHwnd
        ? DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", focusHwnd, "Ptr")
        : 0
    if !imeHwnd
        return {valid: false, hwnd: hwnd, open: false, convMode: 0}
    if !SendImeControl(imeHwnd, 0x0005, &open)
        return {valid: false, hwnd: hwnd, open: false, convMode: 0}

    convMode := 0
    if open && !SendImeControl(imeHwnd, 0x0001, &convMode)
        return {valid: false, hwnd: hwnd, open: false, convMode: 0}
    return {valid: true, hwnd: hwnd, open: open != 0, convMode: convMode}
}

SendImeControl(imeHwnd, command, &value) {
    value := 0
    return !!DllCall("user32\SendMessageTimeoutW"
        , "Ptr", imeHwnd, "UInt", 0x0283, "Ptr", command, "Ptr", 0
        , "UInt", 0x22, "UInt", 35, "Ptr*", &value, "Ptr")
}

ResolveCaretAnchor() {
    if CaretGetPos(&x, &y)
        return {found: true, x: x, y: y, source: "NativeCaret"}

    context := GetInputContext()
    guiAnchor := TryGetGuiThreadCaret(context)
    if guiAnchor.found
        return guiAnchor

    msaaAnchor := TryGetMsaaCaret(context)
    if msaaAnchor.found
        return msaaAnchor

    focusedElement := GetFocusedEditableElement()
    if !focusedElement
        return {found: false, x: 0, y: 0, source: "NotEditable"}

    uiaAnchor := TryGetUiaCaret(focusedElement)
    if uiaAnchor.found
        return uiaAnchor

    emptyFieldAnchor := TryGetUiaEmptyInputFieldAnchor(focusedElement)
    if emptyFieldAnchor.found
        return emptyFieldAnchor

    MouseGetPos &mouseX, &mouseY
    return {found: true, x: mouseX, y: mouseY, source: "MouseFallback"}
}

GetInputContext() {
    hwnd := WinExist("A")
    threadInfo := GetGuiThreadInfo(hwnd)
    focusHwnd := threadInfo && threadInfo.focusHwnd ? threadInfo.focusHwnd : hwnd
    return {hwnd: hwnd, focusHwnd: focusHwnd, threadInfo: threadInfo}
}

GetGuiThreadInfo(hwnd) {
    if !hwnd
        return false
    threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
    info := Buffer(24 + 6 * A_PtrSize, 0)
    NumPut "UInt", info.Size, info
    if !DllCall("GetGUIThreadInfo", "UInt", threadId, "Ptr", info, "Int")
        return false
    offset := 8 + 6 * A_PtrSize
    return {
        buffer: info,
        focusHwnd: NumGet(info, 8 + A_PtrSize, "Ptr"),
        caretHwnd: NumGet(info, 8 + 5 * A_PtrSize, "Ptr"),
        left: NumGet(info, offset, "Int"),
        top: NumGet(info, offset + 4, "Int"),
        right: NumGet(info, offset + 8, "Int")
    }
}

TryGetGuiThreadCaret(context) {
    info := context.threadInfo
    if !info || !info.caretHwnd
        return {found: false, x: 0, y: 0, source: "GUIThreadCaret"}

    point := Buffer(8, 0)
    NumPut "Int", info.left, "Int", info.top, point
    if !DllCall("ClientToScreen", "Ptr", info.caretHwnd, "Ptr", point, "Int")
        return {found: false, x: 0, y: 0, source: "GUIThreadCaret"}
    return {
        found: true,
        x: NumGet(point, 0, "Int") + Max(info.right - info.left, 0),
        y: NumGet(point, 4, "Int"),
        source: "GUIThreadCaret"
    }
}

TryGetMsaaCaret(context) {
    focusHwnd := context.focusHwnd || context.hwnd
    static iidAccessible := CreateAccessibleGuid()
    try {
        result := DllCall("oleacc\AccessibleObjectFromWindow"
            , "Ptr", focusHwnd, "UInt", 0xFFFFFFF8, "Ptr", iidAccessible
            , "Ptr*", accessibleCaret := ComValue(13, 0), "Int")
        if result || !accessibleCaret.Ptr
            return {found: false, x: 0, y: 0, source: "MSAACaret"}

        if A_PtrSize = 8 {
            child := Buffer(24, 0)
            NumPut "UShort", 3, child
            result := ComCall(22, accessibleCaret
                , "Int*", &x := 0, "Int*", &y := 0
                , "Int*", &width := 0, "Int*", &height := 0
                , "Ptr", child, "Int")
        } else {
            result := ComCall(22, accessibleCaret
                , "Int*", &x := 0, "Int*", &y := 0
                , "Int*", &width := 0, "Int*", &height := 0
                , "Int64", 3, "Int64", 0, "Int")
        }
        if !result && height > 0 && height <= 300 && width >= 0
            return {found: true, x: x, y: y, source: "MSAACaret"}
    }
    return {found: false, x: 0, y: 0, source: "MSAACaret"}
}

CreateAccessibleGuid() {
    DllCall "LoadLibraryW", "Str", "oleacc.dll", "Ptr"
    guid := Buffer(16, 0)
    DllCall "ole32\CLSIDFromString"
        , "Str", "{618736E0-3C3D-11CF-810C-00AA00389B71}", "Ptr", guid, "Int"
    return guid
}

GetFocusedEditableElement() {
    try element := UIA.GetFocusedElement()
    catch
        return false
    return GetEditableScore(element) >= 7 ? element : false
}

GetEditableScore(element) {
    try {
        if !element.IsEnabled
            return -100
        type := element.Type
        if type = UIA.Type.Button || type = UIA.Type.Link
            || type = UIA.Type.Menu || type = UIA.Type.MenuItem
            || type = UIA.Type.Tab || type = UIA.Type.TabItem
            || type = UIA.Type.CheckBox || type = UIA.Type.Text
            return -100

        score := 0
        if type = UIA.Type.Edit
            score += 6
        else if type = UIA.Type.ComboBox
            score += 2
        else if type = UIA.Type.DataItem || type = UIA.Type.ListItem
            score -= 8
        else if type = UIA.Type.Custom || type = UIA.Type.Pane
            || type = UIA.Type.Group || type = UIA.Type.Document
            score += 1

        if element.HasKeyboardFocus
            score += 3
        if element.IsKeyboardFocusable
            score += 2
        try if element.GetPropertyValue(UIA.Property.IsTextPatternAvailable)
            score += 2
        try {
            if element.GetPropertyValue(UIA.Property.IsValuePatternAvailable) {
                score += 4
                if element.GetPropertyValue(UIA.Property.ValueIsReadOnly)
                    score -= 10
            }
        }
        return score
    }
    return -100
}

TryGetUiaEmptyInputFieldAnchor(element) {
    try rectangle := element.BoundingRectangle
    catch
        return {found: false, x: 0, y: 0, source: "UIAEmptyInputField"}
    if rectangle.r <= rectangle.l || rectangle.b <= rectangle.t
        return {found: false, x: 0, y: 0, source: "UIAEmptyInputField"}

    if IsUiaEmptyInputField(element) {
        return {
            found: true,
            x: rectangle.l + 8,
            y: rectangle.t + Floor((rectangle.b - rectangle.t) / 2),
            source: "UIAEmptyInputField"
        }
    }
    return {found: false, x: 0, y: 0, source: "UIAEmptyInputField"}
}

IsUiaEmptyInputField(element) {
    try {
        type := element.Type
        if type != UIA.Type.Edit && type != UIA.Type.ComboBox
            return false
        return element.ValuePattern.Value = ""
    }
    return false
}

TryGetUiaCaret(element) {
    try {
        textPattern := element.TextPattern
        try {
            range := textPattern.GetCaretRange(&isActive)
            if isActive {
                anchor := GetTextRangeEnd(range)
                if anchor.found
                    return anchor
                anchor := GetDegenerateRangeEnd(range)
                if anchor.found
                    return anchor
            }
        }
        try {
            selection := textPattern.GetSelection()
            if selection.Length {
                anchor := GetTextRangeEnd(selection[selection.Length])
                if anchor.found
                    return anchor
                anchor := GetDegenerateRangeEnd(selection[selection.Length])
                if anchor.found
                    return anchor
            }
        }
    }
    return {found: false, x: 0, y: 0, source: "UIACaret"}
}

GetTextRangeEnd(range) {
    try {
        rectangles := range.GetBoundingRectangles()
        if rectangles.Length {
            rectangle := rectangles[rectangles.Length]
            return {found: true, x: rectangle.x + rectangle.w
                , y: rectangle.y, source: "UIATextRange"}
        }
    }
    return {found: false, x: 0, y: 0, source: "UIATextRange"}
}

GetDegenerateRangeEnd(range) {
    try {
        forward := range.Clone()
        forward.MoveEndpointByUnit(UIA.TextPatternRangeEndpoint.End
            , UIA.TextUnit.Character, 1)
        rectangles := forward.GetBoundingRectangles()
        if rectangles.Length
            return {found: true, x: rectangles[1].x
                , y: rectangles[1].y, source: "UIADegenerateRange"}
    }
    try {
        backward := range.Clone()
        backward.MoveEndpointByUnit(UIA.TextPatternRangeEndpoint.Start
            , UIA.TextUnit.Character, -1)
        rectangles := backward.GetBoundingRectangles()
        if rectangles.Length {
            rectangle := rectangles[rectangles.Length]
            return {found: true, x: rectangle.x + rectangle.w
                , y: rectangle.y, source: "UIADegenerateRange"}
        }
    }
    return {found: false, x: 0, y: 0, source: "UIADegenerateRange"}
}

GetImeModeDisplay(snapshot) {
    if !snapshot.open
        return {text: "A", color: "1677FF"}
    switch snapshot.convMode {
        case 9, 25:
            return {text: "あ", color: "FF3B30"}
        case 11, 27:
            return {text: "カ", color: "FF3B30"}
        case 3, 19:
            return {text: "_ｶ", color: "FF8A00"}
        case 8, 24:
            return {text: "Ａ", color: "25cd04", wide: true}
        default:
            return {text: "あ", color: "000000"}
    }
}

CreateInputModeIndicator() {
    global IndicatorWidth, IndicatorHeight
        , InputModeIndicatorGui, InputModeIndicatorText
    InputModeIndicatorGui := Gui(
        "+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x20 +E0x80000 +E0x08000000")
    InputModeIndicatorGui.BackColor := "FAFAFA"
    InputModeIndicatorGui.MarginX := 0
    InputModeIndicatorGui.MarginY := 0
    InputModeIndicatorGui.SetFont("s11 Norm c000000", "Meiryo UI")
    InputModeIndicatorText := InputModeIndicatorGui.AddText(
        "x1 y7 w42 h40 Center +0x200 BackgroundTrans", "")
    InputModeIndicatorGui.Show("NA x-32000 y-32000 w" IndicatorWidth
        . " h" IndicatorHeight)
    DisableIndicatorDwmShadow(InputModeIndicatorGui.Hwnd)
    UpdateInputModeIndicatorDpi(A_ScreenDPI)
    OnMessage(0x000F, PaintInputModeIndicator)
    OnExit DeleteInputModeIndicatorFont
    InputModeIndicatorGui.Hide()
}

HandleInputModeIndicatorDpiChanged(wParam, lParam, message, hwnd) {
    if !IsInputModeIndicatorWindow(hwnd)
        return
    dpi := wParam & 0xFFFF
    if dpi
        UpdateInputModeIndicatorDpi(dpi)
}

IsInputModeIndicatorWindow(hwnd) {
    global InputModeIndicatorGui
    return hwnd = InputModeIndicatorGui.Hwnd
}

UpdateInputModeIndicatorDpi(dpi) {
    global IndicatorDpi, IndicatorLogicalWidth, IndicatorLogicalHeight
        , IndicatorWidth, IndicatorHeight, InputModeIndicatorGui
        , InputModeIndicatorText
        , InputModeIndicatorFont, InputModeIndicatorWideFont, IndicatorPointsDown
    if !dpi || dpi = IndicatorDpi
        return

    IndicatorDpi := dpi
    IndicatorWidth := ScaleIndicatorPixels(IndicatorLogicalWidth, dpi)
    IndicatorHeight := ScaleIndicatorPixels(IndicatorLogicalHeight, dpi)
    InputModeIndicatorText.Move(
        ScaleIndicatorPixels(1, dpi)
        , ScaleIndicatorPixels(IndicatorPointsDown ? 1 : 7, dpi)
        , ScaleIndicatorPixels(42, dpi), ScaleIndicatorPixels(40, dpi))

    fontHeight := -DllCall("MulDiv", "Int", 11, "Int", dpi, "Int", 72, "Int")
    newFont := DllCall("gdi32\CreateFontW"
        , "Int", fontHeight, "Int", 0, "Int", 0, "Int", 0, "Int", 400
        , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1
        , "UInt", 0, "UInt", 0, "UInt", 6, "UInt", 0
        , "WStr", "Meiryo UI", "Ptr")
    wideFontWidth := ScaleIndicatorPixels(15, dpi)
    newWideFont := DllCall("gdi32\CreateFontW"
        , "Int", fontHeight, "Int", wideFontWidth, "Int", 0, "Int", 0, "Int", 500
        , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1
        , "UInt", 0, "UInt", 0, "UInt", 6, "UInt", 0
        , "WStr", "Meiryo UI", "Ptr")
    if newFont && newWideFont {
        oldFont := IsSet(InputModeIndicatorFont) ? InputModeIndicatorFont : 0
        oldWideFont := IsSet(InputModeIndicatorWideFont) ? InputModeIndicatorWideFont : 0
        InputModeIndicatorFont := newFont
        InputModeIndicatorWideFont := newWideFont
        SendMessage 0x30, newFont, true, InputModeIndicatorText.Hwnd
        if oldFont
            DllCall "gdi32\DeleteObject", "Ptr", oldFont
        if oldWideFont
            DllCall "gdi32\DeleteObject", "Ptr", oldWideFont
    } else {
        if newFont
            DllCall "gdi32\DeleteObject", "Ptr", newFont
        if newWideFont
            DllCall "gdi32\DeleteObject", "Ptr", newWideFont
    }

    ResizeIndicatorWindow(InputModeIndicatorGui, dpi)
    DllCall "user32\RedrawWindow", "Ptr", InputModeIndicatorGui.Hwnd
        , "Ptr", 0, "Ptr", 0, "UInt", 0x185
}

SetInputModeIndicatorArrowDirection(pointsDown) {
    global IndicatorPointsDown, IndicatorDpi, InputModeIndicatorGui
        , InputModeIndicatorText
    if pointsDown = IndicatorPointsDown
        return

    IndicatorPointsDown := pointsDown
    InputModeIndicatorText.Move(, ScaleIndicatorPixels(pointsDown ? 1 : 7
        , IndicatorDpi))
    ApplyIndicatorWindowRegion(InputModeIndicatorGui.Hwnd, IndicatorDpi)
    DllCall "user32\RedrawWindow", "Ptr", InputModeIndicatorGui.Hwnd
        , "Ptr", 0, "Ptr", 0, "UInt", 0x185
}

SetInputModeIndicatorWideFont(useWideFont) {
    global InputModeIndicatorFont, InputModeIndicatorWideFont, InputModeIndicatorText
    font := useWideFont ? InputModeIndicatorWideFont : InputModeIndicatorFont
    if font
        SendMessage 0x30, font, true, InputModeIndicatorText.Hwnd
}

ResizeIndicatorWindow(guiWindow, dpi) {
    global IndicatorWidth, IndicatorHeight
    hwnd := guiWindow.Hwnd
    if !DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
        return
    DllCall "user32\SetWindowPos", "Ptr", hwnd, "Ptr", 0
        , "Int", 0, "Int", 0, "Int", IndicatorWidth, "Int", IndicatorHeight
        , "UInt", 0x15
    ApplyIndicatorWindowRegion(hwnd, dpi)
}

ApplyIndicatorWindowRegion(hwnd, dpi) {
    global IndicatorPointsDown
    if !DllCall("user32\IsWindow", "Ptr", hwnd, "Int")
        return
    points := Buffer(7 * 8, 0)
    FillIndicatorPolygonBuffer(points, IndicatorPointsDown, dpi, false)
    region := DllCall("gdi32\CreatePolygonRgn", "Ptr", points
        , "Int", 7, "Int", 1, "Ptr")
    if !region
        return
    if !DllCall("user32\SetWindowRgn", "Ptr", hwnd, "Ptr", region
        , "Int", true, "Int")
        DllCall "gdi32\DeleteObject", "Ptr", region
}

; 吹き出しの論理頂点（96 DPI基準）。上向き/下向きの唯一の定義。
GetIndicatorPolygon(pointsDown) {
    return pointsDown
        ? [[0, 0], [44, 0], [44, 42], [28, 42], [22, 48], [16, 42], [0, 42]]
        : [[0, 6], [16, 6], [22, 0], [28, 6], [44, 6], [44, 48], [0, 48]]
}

; forOutline=true は枠線描画用に右下端を1px内側へ寄せてはみ出しを防ぐ。
FillIndicatorPolygonBuffer(buffer, pointsDown, dpi, forOutline) {
    global IndicatorWidth, IndicatorHeight
    for point in GetIndicatorPolygon(pointsDown) {
        x := ScaleIndicatorPixels(point[1], dpi)
        y := ScaleIndicatorPixels(point[2], dpi)
        if forOutline {
            x := Min(x, IndicatorWidth - 1)
            y := Min(y, IndicatorHeight - 1)
        }
        NumPut "Int", x, "Int", y, buffer, (A_Index - 1) * 8
    }
}

DeleteInputModeIndicatorFont(*) {
    global InputModeIndicatorFont, InputModeIndicatorWideFont
    if IsSet(InputModeIndicatorFont) && InputModeIndicatorFont
        DllCall "gdi32\DeleteObject", "Ptr", InputModeIndicatorFont
    if IsSet(InputModeIndicatorWideFont) && InputModeIndicatorWideFont
        DllCall "gdi32\DeleteObject", "Ptr", InputModeIndicatorWideFont
    InputModeIndicatorFont := 0
    InputModeIndicatorWideFont := 0
}

DisableIndicatorDwmShadow(hwnd) {
    policy := Buffer(4, 0)
    NumPut "Int", 1, policy ; DWMNCRP_DISABLED
    try DllCall "dwmapi\DwmSetWindowAttribute", "Ptr", hwnd
        , "UInt", 2, "Ptr", policy, "UInt", 4, "Int"
}

PaintInputModeIndicator(wParam, lParam, message, hwnd) {
    global IndicatorDpi, IndicatorFrameColor, IndicatorWidth, IndicatorHeight
        , InputModeIndicatorGui, IndicatorPointsDown
    if hwnd != InputModeIndicatorGui.Hwnd
        return

    paint := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
    hdc := DllCall("BeginPaint", "Ptr", hwnd, "Ptr", paint, "Ptr")
    brush := DllCall("gdi32\CreateSolidBrush", "UInt", 0x00FAFAFA, "Ptr")
    pen := DllCall("gdi32\CreatePen", "Int", 0, "Int", 1
        , "UInt", RgbHexToColorRef(IndicatorFrameColor), "Ptr")
    oldBrush := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
    oldPen := DllCall("gdi32\SelectObject", "Ptr", hdc, "Ptr", pen, "Ptr")
    points := Buffer(7 * 8, 0)
    FillIndicatorPolygonBuffer(points, IndicatorPointsDown, IndicatorDpi, true)
    DllCall "gdi32\Polygon", "Ptr", hdc, "Ptr", points, "Int", 7
    DllCall "gdi32\SelectObject", "Ptr", hdc, "Ptr", oldBrush
    DllCall "gdi32\SelectObject", "Ptr", hdc, "Ptr", oldPen
    DllCall "gdi32\DeleteObject", "Ptr", brush
    DllCall "gdi32\DeleteObject", "Ptr", pen
    DllCall "EndPaint", "Ptr", hwnd, "Ptr", paint
    return 0
}

RgbHexToColorRef(rgbHex) {
    red := Integer("0x" SubStr(rgbHex, 1, 2))
    green := Integer("0x" SubStr(rgbHex, 3, 2))
    blue := Integer("0x" SubStr(rgbHex, 5, 2))
    return red | (green << 8) | (blue << 16)
}

GetWindowDpi(hwnd) {
    dpi := 96
    if hwnd {
        try windowDpi := DllCall("user32\GetDpiForWindow", "Ptr", hwnd, "UInt")
        if IsSet(windowDpi) && windowDpi
            dpi := windowDpi
    }
    return dpi
}

ScaleIndicatorPixels(logicalPixels, dpi) {
    return Round(logicalPixels * dpi / 96)
}

ClampToWorkArea(x, y, referenceX, referenceY) {
    global IndicatorDpi, IndicatorWidth, IndicatorHeight, IndicatorAboveGap
    margin := ScaleIndicatorPixels(4, IndicatorDpi)
    Loop MonitorGetCount() {
        MonitorGetWorkArea A_Index, &left, &top, &right, &bottom
        if referenceX >= left && referenceX < right
            && referenceY >= top && referenceY < bottom {
            above := false
            if y + IndicatorHeight + margin > bottom {
                yAboveCaret := referenceY - IndicatorHeight
                    - ScaleIndicatorPixels(IndicatorAboveGap, IndicatorDpi)
                if yAboveCaret >= top + margin {
                    y := yAboveCaret
                    above := true
                }
            }
            return {
                x: Min(Max(x, left + margin), right - IndicatorWidth - margin),
                y: Min(Max(y, top + margin), bottom - IndicatorHeight - margin),
                above: above
            }
        }
    }
    return {x: x, y: y, above: false}
}
