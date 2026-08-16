#Requires AutoHotkey v2.0
#SingleInstance Force
#Include %A_ScriptDir%\..\lib\UIAv2.ahk
Persistent

; Caret position monitor for AutoHotkey v2.
; The caret lookup is adapted from the Unlicense implementation in:
; https://github.com/krtek2k/CopyPasta
; It avoids the unstable AccessibleObjectFromEvent -> ComObjQuery path.

CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

global gUpdateIntervalMs := 500
global gCaretMarker := CreateCaretMarker()
global gCaretMarkerVisible := false

ShowTooltipAtMouse(
    "Caret monitor started`n"
    . "500ms間隔で自動更新します。`n"
    . "終了は通知領域アイコンのメニューから行います。"
)
SetTimer(UpdateCaretTooltip, gUpdateIntervalMs)


UpdateCaretTooltip()
{
    static isUpdating := false

    ; UIA呼び出しが長引いた場合のタイマー多重実行を防ぐ。
    if isUpdating
        return

    isUpdating := true

    try
    {
        if GetCaretPosEx(&x, &y, &w, &h, &method)
        {
            message := Format(
                "caret = FOUND`n"
                . "method = {1}`n"
                . "x = {2}`n"
                . "y = {3}`n"
                . "w = {4}`n"
                . "h = {5}",
                method,
                Round(x),
                Round(y),
                Round(w),
                Round(h)
            )
            ShowCaretMarker(x, y, h)
        }
        else
        {
            message := "caret = NOT FOUND"
            HideCaretMarker()
        }
    }
    catch Error as err
    {
        message := Format(
            "caret = ERROR`n{1}",
            err.Message
        )
        HideCaretMarker()
    }

    ShowTooltipAtMouse(message)
    isUpdating := false
}


ShowTooltipAtMouse(text)
{
    MouseGetPos(&mouseX, &mouseY)
    GetWorkAreaAtPoint(
        mouseX,
        mouseY,
        &workLeft,
        &workTop,
        &workRight,
        &workBottom
    )

    tooltipX := Max(workLeft + 8, mouseX - 420)
    tooltipY := Max(workTop + 8, mouseY - 240)
    ToolTip(text, tooltipX, tooltipY)
}


CreateCaretMarker()
{
    ; WS_EX_TRANSPARENT | WS_EX_NOACTIVATE
    marker := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020")
    marker.BackColor := "FF1744"
    return marker
}


ShowCaretMarker(x, y, h)
{
    global gCaretMarker, gCaretMarkerVisible

    markerX := Round(x)
    markerY := Round(y)
    markerHeight := Max(Round(h), 12)

    ; 幅を固定し、選択範囲の幅が返ってもキャレット位置だけを示す。
    gCaretMarker.Show(
        Format(
            "NA x{1} y{2} w{3} h{4}",
            markerX,
            markerY,
            1,
            markerHeight
        )
    )
    gCaretMarkerVisible := true
}


HideCaretMarker()
{
    global gCaretMarker, gCaretMarkerVisible

    if !gCaretMarkerVisible
        return

    gCaretMarker.Hide()
    gCaretMarkerVisible := false
}


GetWorkAreaAtPoint(x, y, &left, &top, &right, &bottom)
{
    monitorCount := MonitorGetCount()

    Loop monitorCount
    {
        MonitorGetWorkArea(A_Index, &areaLeft, &areaTop, &areaRight, &areaBottom)

        if (
            x >= areaLeft
            && x < areaRight
            && y >= areaTop
            && y < areaBottom
        )
        {
            left := areaLeft
            top := areaTop
            right := areaRight
            bottom := areaBottom
            return
        }
    }

    ; 作業領域外の座標だった場合はプライマリモニターを使用する。
    MonitorGetWorkArea(1, &left, &top, &right, &bottom)
}


GetCaretPosEx(&x?, &y?, &w?, &h?, &method?)
{
    x := 0
    y := 0
    w := 0
    h := 0
    method := ""

    static iUIAutomation := 0
    static hOleacc := 0
    static IID_IAccessible
    static guiThreadInfo
    static initialized := Initialize()

    hwndActive := WinExist("A")
    if !hwndActive
        return false

    activeThreadId := DllCall(
        "GetWindowThreadProcessId",
        "Ptr", hwndActive,
        "Ptr", 0,
        "UInt"
    )

    hasThreadInfo := DllCall(
        "GetGUIThreadInfo",
        "UInt", activeThreadId,
        "Ptr", guiThreadInfo,
        "Int"
    )

    hwndFocus := hasThreadInfo
        ? NumGet(guiThreadInfo, 16, "Ptr")
        : hwndActive

    if !hwndFocus
        hwndFocus := hwndActive

    ; MSAA: OBJID_CARET
    if (
        hOleacc
        && !DllCall(
            "oleacc\AccessibleObjectFromWindow",
            "Ptr", hwndFocus,
            "UInt", 0xFFFFFFF8,
            "Ptr", IID_IAccessible,
            "Ptr*", accCaret := ComValue(13, 0),
            "Int"
        )
        && accCaret.Ptr
    )
    {
        if (A_PtrSize = 8)
        {
            varChild := Buffer(24, 0)
            NumPut("UShort", 3, varChild)

            hr := ComCall(
                22,
                accCaret,
                "Int*", &x,
                "Int*", &y,
                "Int*", &w,
                "Int*", &h,
                "Ptr", varChild,
                "Int"
            )
        }
        else
        {
            hr := ComCall(
                22,
                accCaret,
                "Int*", &x,
                "Int*", &y,
                "Int*", &w,
                "Int*", &h,
                "Int64", 3,
                "Int64", 0,
                "Int"
            )
        }

        if !hr
        {
            method := "MSAA / OBJID_CARET"
            return true
        }
    }

    ; UIA-v2: focused element and its ancestors.
    if TryGetCaretPosUIAv2(&x, &y, &w, &h, &method)
    {
        return true
    }

    ; UI Automation: TextPattern2 / TextPattern
    if iUIAutomation
    {
        try
        {
            if (
                !ComCall(
                    8,
                    iUIAutomation,
                    "Ptr*", focusedElement := ComValue(13, 0),
                    "Int"
                )
                && focusedElement.Ptr
            )
            {
                if (
                    !ComCall(
                        16,
                        focusedElement,
                        "Int", 10024,
                        "Ptr*", textPattern2 := ComValue(13, 0),
                        "Int"
                    )
                    && textPattern2.Ptr
                    && !ComCall(
                        10,
                        textPattern2,
                        "Int*", &isActive := 0,
                        "Ptr*", caretRange := ComValue(13, 0),
                        "Int"
                    )
                    && isActive
                    && caretRange.Ptr
                    && TryGetRangeRect(
                        caretRange,
                        &x,
                        &y,
                        &w,
                        &h
                    )
                )
                {
                    method := "Raw UIA / TextPattern2"
                    return true
                }

                if (
                    !ComCall(
                        16,
                        focusedElement,
                        "Int", 10014,
                        "Ptr*", textPattern := ComValue(13, 0),
                        "Int"
                    )
                    && textPattern.Ptr
                    && !ComCall(
                        5,
                        textPattern,
                        "Ptr*", selectionRanges := ComValue(13, 0),
                        "Int"
                    )
                    && selectionRanges.Ptr
                    && !ComCall(
                        3,
                        selectionRanges,
                        "Int*", &rangeCount := 0,
                        "Int"
                    )
                    && rangeCount > 0
                    && !ComCall(
                        4,
                        selectionRanges,
                        "Int", rangeCount - 1,
                        "Ptr*", selectionRange := ComValue(13, 0),
                        "Int"
                    )
                    && selectionRange.Ptr
                    && TryGetRangeRect(
                        selectionRange,
                        &x,
                        &y,
                        &w,
                        &h
                    )
                )
                {
                    method := "Raw UIA / TextPattern"
                    return true
                }
            }
        }
    }

    ; GetGUIThreadInfo fallback
    if hasThreadInfo
    {
        hwndCaret := NumGet(guiThreadInfo, 48, "Ptr")
        if hwndCaret
        {
            x := NumGet(guiThreadInfo, 56, "Int")
            y := NumGet(guiThreadInfo, 60, "Int")
            w := NumGet(guiThreadInfo, 64, "Int") - x
            h := NumGet(guiThreadInfo, 68, "Int") - y

            point := Buffer(8, 0)
            NumPut("Int", x, point, 0)
            NumPut("Int", y, point, 4)

            if DllCall(
                "ClientToScreen",
                "Ptr", hwndCaret,
                "Ptr", point,
                "Int"
            )
            {
                x := NumGet(point, 0, "Int")
                y := NumGet(point, 4, "Int")
                method := "GetGUIThreadInfo"
                return true
            }
        }
    }

    return false


    Initialize()
    {
        try
        {
            iUIAutomation := ComObject(
                "{E22AD333-B25F-460C-83D0-0581107395C9}",
                "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}"
            )
        }

        hOleacc := DllCall(
            "LoadLibraryW",
            "Str", "oleacc.dll",
            "Ptr"
        )

        IID_IAccessible := Buffer(16, 0)
        DllCall(
            "ole32\CLSIDFromString",
            "Str", "{618736E0-3C3D-11CF-810C-00AA00389B71}",
            "Ptr", IID_IAccessible,
            "Int"
        )

        guiThreadInfo := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
        NumPut("UInt", guiThreadInfo.Size, guiThreadInfo)
    }
}


TryGetCaretPosUIAv2(&x, &y, &w, &h, &method)
{
    try element := UIA.GetFocusedElement()
    catch
        return false

    ; TextPattern is often exposed by an ancestor of the focused element.
    Loop 8
    {
        if TryGetCaretFromUIAv2Element(
            element,
            &x,
            &y,
            &w,
            &h,
            &method
        )
        {
            return true
        }

        try parent := element.Parent
        catch
            break

        if !IsObject(parent) || parent.Ptr = element.Ptr
            break

        element := parent
    }

    return false
}


TryGetCaretFromUIAv2Element(element, &x, &y, &w, &h, &method)
{
    try
    {
        if element.IsTextPattern2Available
        {
            pattern := element.GetPattern(UIA.Pattern.Text2)
            range := pattern.GetCaretRange(&isActive)

            if isActive && TryGetUIAv2RangeRect(range, &x, &y, &w, &h)
            {
                method := "UIA-v2 / TextPattern2"
                return true
            }
        }
    }

    try
    {
        if element.IsTextPatternAvailable
        {
            pattern := element.GetPattern(UIA.Pattern.Text)
            ranges := pattern.GetSelection()

            if (
                ranges.Length > 0
                && TryGetUIAv2RangeRect(
                    ranges[ranges.Length],
                    &x,
                    &y,
                    &w,
                    &h
                )
            )
            {
                method := "UIA-v2 / TextPattern"
                return true
            }
        }
    }

    return false
}


TryGetUIAv2RangeRect(range, &x, &y, &w, &h)
{
    try rects := range.GetBoundingRectangles()
    catch
        return false

    if rects.Length = 0
        return false

    ; Selectionの場合は末尾側の矩形をキャレット候補として使う。
    rect := rects[rects.Length]
    x := rect.x
    y := rect.y
    w := rect.w
    h := rect.h
    return true
}


TryGetRangeRect(range, &x, &y, &w, &h)
{
    safeArray := 0

    if ComCall(
        10,
        range,
        "Ptr*", &safeArray,
        "Int"
    )
    {
        return false
    }

    if !safeArray
        return false

    rects := ComValue(0x2005, safeArray, 1)
    if (rects.MaxIndex() < 3)
        return false

    x := rects[0]
    y := rects[1]
    w := rects[2]
    h := rects[3]
    return true
}
