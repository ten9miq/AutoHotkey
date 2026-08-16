#Requires AutoHotkey v2.0+
#SingleInstance Force
#Include "lib\IMEv2.ahk"
#Include "lib\UIAv2.ahk"

EditableScoreThreshold := 7
TooltipIdleTimeout := 1000
ConversionDetectionHoldMs := 10000
ImeConversionHoldMs := 10000
MonitorCycleId := 0
TooltipAnchorVersion := 0
IndicatorOffsetX := -70 ; 負数で左、正数で右
IndicatorOffsetY := 36  ; 負数で上、正数で下
IndicatorColorAlphanumeric := "1677FF"
IndicatorColorJapanese := "FF3B30"
IndicatorColorHalfKatakana := "FF8A00"
IndicatorColorFullAlphanumeric := "00A38C"
IndicatorColorUnknown := "000000"
ProvisionalDisplayPolicy := "Show" ; Show / HideUntilInput
UseFocusChangedEvent := false ; true: UIAフォーカスイベントで即時反応 / false: 可変ポーリングのみ（低負荷）
; --- 診断・計測用の設定（本体機能とは独立） ---
DiagnosticEnabled := false
DiagnosticLogPath := A_ScriptDir "\logs\IME入力モード表示.log"
CandidateWindowLogPath := A_ScriptDir "\logs\IME候補ウィンドウ詳細.tsv"
; --- ここまで診断・計測用の設定 ---
AnchorConfidence := {
    Exact: "Exact",
    Estimated: "Estimated",
    Fallback: "Fallback",
    Invalid: "Invalid"
}
IndicatorState := {
    mode: "Hidden",
    text: "",
    color: "",
    x: 0,
    y: 0,
    anchorVersion: -1,
    exactX: 0,
    exactY: 0,
    exactAnchorVersion: -1
}

InstallKeybdHook()

CoordMode "ToolTip", "Screen"
CoordMode "Caret", "Screen"
CoordMode "Mouse", "Screen"

UIA.SetMaximumDPIAwareness()
CreateImeIndicator()
InitializeImeKeyTracking()
InitializeImeMonitor()

~LButton Up::RememberCaretClickPosition()
~*Space::TrackImeConversionKey()
~*Enter::EndTrackedImeConversion()
~*Esc::EndTrackedImeConversion()

; --- 診断・計測用ホットキー（本体機能とは独立） ---
^!F9::CaptureFocusedCaretInfo()
^!F10::CaptureImeCandidateWindows("BASELINE")
^!F11::CaptureImeCandidateWindows("CANDIDATE")
^!F12::ToggleImeDiagnostics()
; --- ここまで診断・計測用ホットキー ---

; ============================================================================
;  診断・計測用（本体機能とは独立 / ^!F9-F12・DiagnosticEnabledでのみ動作）
; ============================================================================

; フォーカス中コントロールの素性と各キャレット取得の成否を一括記録する
CaptureFocusedCaretInfo() {
    global LastUIASource
    logPath := A_ScriptDir "\logs\IMEフォーカスキャレット詳細.tsv"
    SplitPath logPath, , &logDirectory
    if !DirExist(logDirectory)
        DirCreate logDirectory
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    output := FileExist(logPath) ? ""
        : "time`tproc`twinClass`tfocusHwnd`tfocusClass`tcaretHwnd`trcCaret`tcaretGetPos`tmsaa`tuiaType`tuiaClass`tautoId`thasFocus`ttextPat`tvaluePat`tscore`tuiaCaret`temPosFromChar`n"

    hwnd := WinExist("A")
    try proc := WinGetProcessName("ahk_id " hwnd)
    catch
        proc := ""
    try winClass := WinGetClass("ahk_id " hwnd)
    catch
        winClass := ""

    focusHwnd := 0, focusClass := "", caretHwnd := 0, rcCaret := ""
    info := GetGuiThreadCaretInfo(hwnd)
    if info {
        focusHwnd := info.focusHwnd
        caretHwnd := info.caretHwnd
        off := info.rectOffset
        buf := info.buffer
        rcCaret := (NumGet(buf, off, "Int") "," NumGet(buf, off + 4, "Int")
            "," NumGet(buf, off + 8, "Int") "," NumGet(buf, off + 12, "Int"))
        try focusClass := focusHwnd ? WinGetClass("ahk_id " focusHwnd) : ""
    }

    sysCaretPos := CaretGetPos(&cgx, &cgy) ? cgx "," cgy : "none"

    context := DetectInputContext()
    msaaAnchor := TryGetMsaaCaretAnchor(context)
    msaa := msaaAnchor.found ? msaaAnchor.x "," msaaAnchor.y : "fail:" msaaAnchor.reason

    uiaType := "", uiaClass := "", autoId := "", hasFocus := ""
    textPat := "", valuePat := "", score := "", uiaCaret := "none"
    try {
        element := UIA.GetFocusedElement()
        try uiaType := element.Type
        try uiaClass := SanitizeLogField(element.ClassName)
        try autoId := SanitizeLogField(element.AutomationId)
        try hasFocus := element.HasKeyboardFocus
        try textPat := element.GetPropertyValue(UIA.Property.IsTextPatternAvailable)
        try valuePat := element.GetPropertyValue(UIA.Property.IsValuePatternAvailable)
        try score := GetUIAEditScore(element, false, context)
        if GetUIACaretPos(element, &ux, &uy, context)
            uiaCaret := ux "," uy "(" LastUIASource ")"
    }

    emPos := TryEditControlCaretPos(focusHwnd)

    line := (timestamp "`t" proc "`t" winClass "`t" focusHwnd "`t" focusClass "`t"
        . caretHwnd "`t" rcCaret "`t" sysCaretPos "`t" msaa "`t" uiaType "`t"
        . uiaClass "`t" autoId "`t" hasFocus "`t" textPat "`t" valuePat "`t"
        . score "`t" uiaCaret "`t" emPos "`n")
    if AppendLogWithRetry(logPath, output . line)
        TrayTip "IME入力モード表示", "フォーカスキャレット情報を記録しました"
    else
        TrayTip "IME入力モード表示", "ログファイルが使用中のため記録できませんでした"
}

; クラシックEditコントロールに EM_POSFROMCHAR でキャレットのピクセル位置を問い合わせる
TryEditControlCaretPos(focusHwnd) {
    if !focusHwnd
        return "noFocus"
    try controlClass := WinGetClass("ahk_id " focusHwnd)
    catch
        return "noClass"
    if !RegExMatch(controlClass, "i)Edit")
        return "notEdit:" controlClass
    try {
        selection := SendMessage(0x00B0, 0, 0, , "ahk_id " focusHwnd) ; EM_GETSEL
        caretIndex := (selection >> 16) & 0xFFFF
        packed := SendMessage(0x00D6, caretIndex, 0, , "ahk_id " focusHwnd) ; EM_POSFROMCHAR
        if packed = 0xFFFFFFFF
            return "posFail"
        x := packed & 0xFFFF
        y := (packed >> 16) & 0xFFFF
        if x >= 0x8000
            x -= 0x10000
        if y >= 0x8000
            y -= 0x10000
        point := Buffer(8, 0)
        NumPut "Int", x, "Int", y, point
        DllCall("ClientToScreen", "Ptr", focusHwnd, "Ptr", point)
        return NumGet(point, 0, "Int") "," NumGet(point, 4, "Int")
    } catch as err {
        return "err:" SanitizeLogField(err.Message)
    }
}

ToggleImeDiagnostics() {
    global DiagnosticEnabled, DiagnosticLogPath
    DiagnosticEnabled := !DiagnosticEnabled
    if DiagnosticEnabled {
        SplitPath DiagnosticLogPath, , &logDirectory
        if !DirExist(logDirectory)
            DirCreate logDirectory
        FileAppend "`n--- diagnostics started " FormatTime(, "yyyy-MM-dd HH:mm:ss") " ---`n"
            , DiagnosticLogPath, "UTF-8"
    }
    TrayTip "IME入力モード表示"
        , DiagnosticEnabled ? "診断ログ: ON" : "診断ログ: OFF"
}

CaptureImeCandidateWindows(label := "CANDIDATE") {
    global CandidateWindowLogPath
    SplitPath CandidateWindowLogPath, , &logDirectory
    if !DirExist(logDirectory)
        DirCreate logDirectory

    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
    output := FileExist(CandidateWindowLogPath) ? ""
        : "time`thwnd`tvisible`towner`tprocess`tclass`tx`ty`tw`th`tstyle`texStyle`terror`n"
    output .= timestamp "`tSNAPSHOT_BEGIN`tlabel=" label "`t`t`t`t`t`t`t`t`t`n"
    previousHiddenSetting := A_DetectHiddenWindows
    captured := 0
    windows := []
    try {
        DetectHiddenWindows true
        windows := WinGetList()
        for hwnd in windows {
            errorText := ""
            visible := DllCall("IsWindowVisible", "Ptr", hwnd, "Int")
            owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")
            try processName := WinGetProcessName("ahk_id " hwnd)
            catch Error as err
                processName := "", errorText .= "process:" SanitizeLogField(err.Message) " | "
            try className := WinGetClass("ahk_id " hwnd)
            catch Error as err
                className := "", errorText .= "class:" SanitizeLogField(err.Message) " | "
            try WinGetPos &x, &y, &width, &height, "ahk_id " hwnd
            catch Error as err
                x := y := width := height := "", errorText .= "rect:" SanitizeLogField(err.Message) " | "
            try style := Format("0x{:X}", WinGetStyle("ahk_id " hwnd))
            catch Error as err
                style := "", errorText .= "style:" SanitizeLogField(err.Message) " | "
            try exStyle := Format("0x{:X}", WinGetExStyle("ahk_id " hwnd))
            catch Error as err
                exStyle := "", errorText .= "exStyle:" SanitizeLogField(err.Message) " | "
            output .= (timestamp "`t" hwnd "`t" visible "`t" owner "`t"
                . processName "`t" className "`t" x "`t" y "`t" width "`t" height "`t"
                . style "`t" exStyle "`t" RTrim(errorText, " |") "`n")
            captured += 1
        }
    } finally {
        DetectHiddenWindows previousHiddenSetting
    }
    output .= timestamp "`tSNAPSHOT_END`tcount=" captured "`ttotal=" windows.Length "`t`t`t`t`t`t`t`t`t`n"
    if AppendLogWithRetry(CandidateWindowLogPath, output)
        TrayTip "IME入力モード表示", "候補ウィンドウ情報を " captured " 件記録しました"
    else
        TrayTip "IME入力モード表示", "ログファイルが使用中のため記録できませんでした"
    CaptureTextInputHostElements(timestamp, label)
}

SanitizeLogField(value) {
    return StrReplace(StrReplace(value, "`t", " "), "`n", " ")
}

AppendLogWithRetry(path, text) {
    Loop 5 {
        try {
            FileAppend text, path, "UTF-8"
            return true
        }
        Sleep 50
    }
    return false
}

CaptureTextInputHostElements(timestamp, label) {
    logPath := A_ScriptDir "\logs\IME候補UIA詳細.tsv"
    if !FileExist(logPath)
        output := "time`thostHwnd`tdepth`ttype`tclass`tautomationId`tx`ty`tw`th`toffscreen`n"
    else
        output := ""
    output .= timestamp "`tSNAPSHOT_BEGIN`tlabel=" label "`t`t`t`t`t`t`t`t`n"
    captured := 0
    previousHiddenSetting := A_DetectHiddenWindows
    try {
        DetectHiddenWindows true
        for hwnd in WinGetList("ahk_exe TextInputHost.exe") {
            try root := UIA.ElementFromHandle(hwnd, , false)
            catch
                continue
            output .= FormatCandidateUIAElement(timestamp, hwnd, 0, root)
            captured += 1
            try elements := root.FindAll(UIA.TrueCondition, 4)
            catch
                elements := []
            for element in elements {
                output .= FormatCandidateUIAElement(timestamp, hwnd, 1, element)
                captured += 1
            }
        }
    } finally {
        DetectHiddenWindows previousHiddenSetting
    }
    output .= timestamp "`tSNAPSHOT_END`tcount=" captured "`t`t`t`t`t`t`t`t`n"
    AppendLogWithRetry(logPath, output)
}

FormatCandidateUIAElement(timestamp, hostHwnd, depth, element) {
    try type := element.Type
    catch
        type := ""
    try className := SanitizeLogField(element.ClassName)
    catch
        className := ""
    try automationId := SanitizeLogField(element.AutomationId)
    catch
        automationId := ""
    try {
        rectangle := element.BoundingRectangle
        x := rectangle.l
        y := rectangle.t
        width := rectangle.r - rectangle.l
        height := rectangle.b - rectangle.t
    } catch {
        x := y := width := height := ""
    }
    try offscreen := element.IsOffscreen
    catch
        offscreen := ""
    return (timestamp "`t" hostHwnd "`t" depth "`t" type "`t"
        . className "`t" automationId "`t" x "`t" y "`t"
        . width "`t" height "`t" offscreen "`n")
}

LogAnchorDiagnostic(anchor, isConverting, displayState) {
    global DiagnosticEnabled, DiagnosticLogPath
    static lastSignature := ""
    if !DiagnosticEnabled
        return
    try processName := WinGetProcessName("A")
    catch {
        processName := "unknown"
    }
    signature := (displayState "|" anchor.found "|" anchor.source "|"
        . anchor.confidence "|" anchor.x "|" anchor.y "|" anchor.reason "|"
        . anchor.depth "|" anchor.hwnd "|" anchor.runtimeId "|"
        . isConverting "|" processName)
    if signature = lastSignature
        return
    lastSignature := signature
    line := (FormatTime(, "yyyy-MM-dd HH:mm:ss.fff") "`t"
        . displayState "`t" processName "`t" anchor.source "`t"
        . anchor.confidence "`t" anchor.x "," anchor.y "`t"
        . "fallback=" anchor.isFallback "`tconverting=" isConverting "`t"
        . "depth=" anchor.depth "`thwnd=" anchor.hwnd "`t"
        . "runtimeId=" anchor.runtimeId "`t" anchor.reason "`n")
    AppendLogWithRetry(DiagnosticLogPath, line)
}

; 候補検出一本化の可否を検証するため、各信号を独立に計測して記録する
DiagnoseConversionSignals(context) {
    global DiagnosticEnabled, DiagnosticLogPath, ImeConversionHoldMs, TrackedImeConversionTick
    static lastSignature := ""
    if !DiagnosticEnabled
        return

    trackerActive := (IsSet(TrackedImeConversionTick) && TrackedImeConversionTick
        && A_TickCount - TrackedImeConversionTick <= ImeConversionHoldMs) ? 1 : 0
    try immOpen := IME_GET() ? 1 : 0
    catch
        immOpen := -1
    try converting := IME_GetConverting()
    catch
        converting := -1
    try hasCandidate := IME_HasCandidateList() ? 1 : 0
    catch
        hasCandidate := -1
    uiaComposition := DetectUIACompositionSignal()
    processName := context.processName != "" ? context.processName : "unknown"

    ; 何も起きていないアイドルは1行にまとめてノイズを抑える
    if !trackerActive && converting <= 0 && hasCandidate <= 0 && uiaComposition <= 0 && immOpen <= 0
        signature := "idle|" processName
    else
        signature := trackerActive "|" immOpen "|" converting "|" hasCandidate "|" uiaComposition "|" processName
    if signature = lastSignature
        return
    lastSignature := signature

    line := (FormatTime(, "yyyy-MM-dd HH:mm:ss.fff") "`tCONV`t" processName
        . "`ttracker=" trackerActive "`timmOpen=" immOpen "`tconverting=" converting
        . "`thasCandidate=" hasCandidate "`tuiaComposition=" uiaComposition "`n")
    AppendLogWithRetry(DiagnosticLogPath, line)
}

; UIA探索で未確定文字列（コンポジション）を検出できるかだけを返す
DetectUIACompositionSignal() {
    try currentElement := UIA.GetFocusedElement()
    catch
        return -1
    Loop 7 {
        try {
            textEditPattern := currentElement.TextEditPattern
            try {
                conversionRange := textEditPattern.GetConversionTarget()
                if conversionRange.GetText(-1) != ""
                    return 1
            }
            try {
                compositionRange := textEditPattern.GetActiveComposition()
                if compositionRange.GetText(-1) != ""
                    return 1
            }
        }
        try currentElement := currentElement.Parent
        catch
            break
    }
    return 0
}

; ============================================================================
;  診断・計測用ここまで
; ============================================================================

RememberCaretClickPosition() {
    global lastClickX, lastClickY, lastClickScore, lastClickWindow, lastClickTick
        , TooltipAnchorVersion, TrackedImeConversionTick, DetectedImeConversionTick
    MouseGetPos &lastClickX, &lastClickY, &lastClickWindow
    lastClickTick := A_TickCount
    TrackedImeConversionTick := 0
    DetectedImeConversionTick := 0
    TooltipAnchorVersion += 1
    context := DetectInputContext()
    try lastClickScore := GetUIAEditScore(UIA.ElementFromPoint(lastClickX, lastClickY), true, context)
    catch {
        lastClickScore := 0
    }
    SetTimer RefreshClickedElement, -150
    SetTimer RunImeMonitor, -1 ; イベント未使用時でもクリック直後に即時反映
}

TrackImeConversionKey() {
    global TrackedImeConversionTick
    try {
        if IME_GET() && IsJapaneseImeMode()
            TrackedImeConversionTick := A_TickCount
    }
}

InitializeImeKeyTracking() {
    global ImeKeyMonitor
    ImeKeyMonitor := InputHook("V I1")
    ImeKeyMonitor.KeyOpt("{All}", "N")
    ImeKeyMonitor.OnKeyDown := HandleImeTextKeyDown
    ImeKeyMonitor.Start()
    OnExit CleanupImeKeyTracking
}

CleanupImeKeyTracking(*) {
    global ImeKeyMonitor
    try ImeKeyMonitor.Stop()
}

HandleImeTextKeyDown(inputHook, virtualKey, scanCode) {
    global TrackedImeConversionTick
    if !IsTextInputVirtualKey(virtualKey)
        return
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        return
    try {
        if IME_GET() && IsJapaneseImeMode()
            TrackedImeConversionTick := A_TickCount
    }
}

IsTextInputVirtualKey(virtualKey) {
    return virtualKey >= 0x30 && virtualKey <= 0x39
        || virtualKey >= 0x41 && virtualKey <= 0x5A
        || virtualKey >= 0x60 && virtualKey <= 0x69
        || virtualKey >= 0xBA && virtualKey <= 0xE2
}

IsJapaneseImeMode() {
    try {
        mode := IME_GetConvMode()
        return mode = 9 || mode = 25 || mode = 11 || mode = 27
            || mode = 3 || mode = 19
    }
    return true
}

EndTrackedImeConversion() {
    global TrackedImeConversionTick := 0, DetectedImeConversionTick := 0
}

RefreshClickedElement() {
    global lastClickX, lastClickY, lastClickScore, lastClickTick
    try {
        context := DetectInputContext()
        clickedScore := GetUIAEditScore(UIA.ElementFromPoint(lastClickX, lastClickY), true, context)
        focusedScore := GetUIAEditScore(UIA.GetFocusedElement(), false, context)
        lastClickScore := Max(clickedScore, focusedScore)
        lastClickTick := A_TickCount
    }
}

InitializeImeMonitor() {
    global ImeFocusChangedHandler, UseFocusChangedEvent
    if UseFocusChangedEvent {
        try {
            ImeFocusChangedHandler := UIA.CreateFocusChangedEventHandler(HandleImeFocusChanged)
            UIA.AddFocusChangedEventHandler(ImeFocusChangedHandler)
        }
    }
    OnExit CleanupImeMonitor
    SetTimer RunImeMonitor, -1
}

CleanupImeMonitor(*) {
    global ImeFocusChangedHandler
    if IsSet(ImeFocusChangedHandler)
        try UIA.RemoveFocusChangedEventHandler(ImeFocusChangedHandler)
}

HandleImeFocusChanged(*) {
    SetTimer RunImeMonitor, -1
}

RunImeMonitor() {
    try ShowImeMode()
    finally {
        interval := GetImeMonitorInterval()
        SetTimer RunImeMonitor, -interval
    }
}

GetImeMonitorInterval() {
    global IndicatorState
    switch IndicatorState.mode {
        case "Realtime", "Frozen":
            return 75
        case "Provisional":
            return 100
        default:
            return A_TimeIdleKeyboard <= 2000 ? 150 : 400
    }
}

ShowImeMode() {
    global CurrentAnchorResult, MonitorCycleId
    static running := false
    if running
        return
    running := true
    try {
        MonitorCycleId += 1
        context := DetectInputContext()
        DiagnoseConversionSignals(context)
        CurrentAnchorResult := ResolveAnchor(context)
        if !CurrentAnchorResult.found || !ShouldShowImeIndicator(CurrentAnchorResult) {
            SetIndicatorHidden(CurrentAnchorResult)
            return
        }

        try modeDisplay := GetImeModeDisplay()
        catch {
            SetIndicatorHidden(CurrentAnchorResult)
            return
        }
        UpdateIndicatorState(context, CurrentAnchorResult, modeDisplay, IsImeConversionActive())
    } finally {
        running := false
    }
}

UpdateIndicatorState(context, anchor, modeDisplay, isConverting) {
    global AnchorConfidence, IndicatorState, TooltipAnchorVersion
    anchorChanged := IndicatorState.mode = "Hidden"
        || IndicatorState.anchorVersion != TooltipAnchorVersion

    if !anchor.isFallback {
        IndicatorState.exactX := anchor.x
        IndicatorState.exactY := anchor.y
        IndicatorState.exactAnchorVersion := TooltipAnchorVersion
    }

    nextMode := anchor.confidence = AnchorConfidence.Fallback ? "Provisional" : "Realtime"
    if isConverting
        nextMode := "Frozen"

    positionChanged := false
    if !(isConverting && IndicatorState.mode != "Hidden" && !anchorChanged) {
        position := CalculateIndicatorPosition(context, anchor)
        positionChanged := position.x != IndicatorState.x || position.y != IndicatorState.y
        IndicatorState.x := position.x
        IndicatorState.y := position.y
    }

    visualChanged := IndicatorState.mode = "Hidden"
        || IndicatorState.text != modeDisplay.text
        || IndicatorState.color != modeDisplay.color
        || anchorChanged
        || positionChanged
    IndicatorState.mode := nextMode
    IndicatorState.text := modeDisplay.text
    IndicatorState.color := modeDisplay.color
    IndicatorState.anchorVersion := TooltipAnchorVersion
    LogAnchorDiagnostic(anchor, isConverting, nextMode)
    if visualChanged
        ShowImeIndicator(modeDisplay.text, modeDisplay.color, IndicatorState.x, IndicatorState.y)
}

CalculateIndicatorPosition(context, anchor) {
    global IndicatorOffsetX, IndicatorOffsetY, IndicatorState, TooltipAnchorVersion
    if anchor.isFallback
        && IndicatorState.exactAnchorVersion = TooltipAnchorVersion {
        baseX := IndicatorState.exactX
        baseY := IndicatorState.exactY
    } else if anchor.isFallback {
        baseX := anchor.x
        baseY := anchor.y
    } else {
        baseX := anchor.x
        baseY := anchor.y
    }
    return ClampIndicatorPosition(baseX + IndicatorOffsetX, baseY + IndicatorOffsetY
        , baseX, baseY)
}

ClampIndicatorPosition(x, y, referenceX, referenceY) {
    indicatorWidth := 30
    indicatorHeight := 26
    Loop MonitorGetCount() {
        MonitorGetWorkArea A_Index, &left, &top, &right, &bottom
        if referenceX >= left && referenceX < right
            && referenceY >= top && referenceY < bottom
            return {
                x: Min(Max(x, left + 4), right - indicatorWidth - 4),
                y: Min(Max(y, top + 4), bottom - indicatorHeight - 4)
            }
    }
    return {
        x: Max(x, SysGet(76) + 4),
        y: Max(y, SysGet(77) + 4)
    }
}

SetIndicatorHidden(anchor) {
    global IndicatorState
    if IndicatorState.mode != "Hidden"
        HideImeIndicator()
    IndicatorState.mode := "Hidden"
    IndicatorState.text := ""
    IndicatorState.color := ""
    LogAnchorDiagnostic(anchor, false, "Hidden")
}

IsImeConversionActive() {
    global ImeConversionHoldMs, ConversionDetectionHoldMs, DetectedImeConversionTick, TrackedImeConversionTick
    try {
        if !IME_GET() {  ; IME OFFなら変換は無い。滞留トラッカーを消して即追従へ戻す
            TrackedImeConversionTick := 0
            DetectedImeConversionTick := 0
            return false
        }
    }
    if IsSet(TrackedImeConversionTick) && TrackedImeConversionTick
        && A_TickCount - TrackedImeConversionTick <= ImeConversionHoldMs
        return true

    try {
        if IME_GetConverting() != 0 {
            DetectedImeConversionTick := A_TickCount
            return true
        }
    }

    if IsSet(DetectedImeConversionTick) && DetectedImeConversionTick
        && A_TickCount - DetectedImeConversionTick <= ConversionDetectionHoldMs
        return true
    return false
}

CreateImeIndicator() {
    global ImeIndicatorGui, ImeIndicatorControls, ImeIndicatorCenterControl, ImeIndicatorFonts
    ImeIndicatorGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000")
    ImeIndicatorGui.BackColor := "010203"
    ImeIndicatorGui.MarginX := 0
    ImeIndicatorGui.MarginY := 0
    ImeIndicatorControls := []

    ImeIndicatorGui.SetFont("s10 Norm cFFFFFF", "Meiryo UI")
    for offset in [[1, 0], [0, 1], [2, 1], [1, 2]]
        ImeIndicatorControls.Push(ImeIndicatorGui.AddText(
            "x" offset[1] " y" offset[2] " w28 h24 Center BackgroundTrans", ""))

    ImeIndicatorGui.SetFont("s10 Norm c000000", "Meiryo UI")
    ImeIndicatorCenterControl := ImeIndicatorGui.AddText(
        "x1 y1 w28 h24 Center BackgroundTrans", "")
    ImeIndicatorControls.Push(ImeIndicatorCenterControl)

    fontHeight := -DllCall("MulDiv", "Int", 10, "Int", A_ScreenDPI, "Int", 72, "Int")
    whiteFont := DllCall("gdi32\CreateFontW"
        , "Int", fontHeight, "Int", 0, "Int", 0, "Int", 0, "Int", 400
        , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1
        , "UInt", 0, "UInt", 0, "UInt", 3, "UInt", 0
        , "WStr", "Meiryo UI", "Ptr")
    blackFont := DllCall("gdi32\CreateFontW"
        , "Int", fontHeight, "Int", 0, "Int", 0, "Int", 0, "Int", 500
        , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1
        , "UInt", 0, "UInt", 0, "UInt", 3, "UInt", 0
        , "WStr", "Meiryo UI", "Ptr")
    ImeIndicatorFonts := [whiteFont, blackFont]
    for control in ImeIndicatorControls
        SendMessage(0x30, A_Index = ImeIndicatorControls.Length ? blackFont : whiteFont
            , true, control.Hwnd)

    ImeIndicatorGui.Show("NA x-32000 y-32000 w30 h26")
    WinSetTransColor("010203 255", "ahk_id " ImeIndicatorGui.Hwnd)
    ImeIndicatorGui.Hide()
    OnExit(DeleteImeIndicatorFont)
}

DeleteImeIndicatorFont(*) {
    global ImeIndicatorFonts
    for font in ImeIndicatorFonts
        if font
            DllCall("gdi32\DeleteObject", "Ptr", font)
}

ShowImeIndicator(modeText, color, x, y) {
    global ImeIndicatorGui, ImeIndicatorControls, ImeIndicatorCenterControl
    for control in ImeIndicatorControls
        control.Text := modeText
    ImeIndicatorCenterControl.Opt("c" color)
    ImeIndicatorGui.Show("NA x" x " y" y " w30 h26")
    ; 最前面帯の先頭へ再挿入し、後から出た最前面窓（検索/スタート等）の裏に隠れにくくする
    DllCall("SetWindowPos", "Ptr", ImeIndicatorGui.Hwnd, "Ptr", -1
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)
}

HideImeIndicator() {
    global ImeIndicatorGui
    ImeIndicatorGui.Hide()
}

ShouldShowImeIndicator(anchor) {
    global AnchorConfidence, lastClickTick, ProvisionalDisplayPolicy, TooltipIdleTimeout
    if anchor.confidence != AnchorConfidence.Fallback
        return true
    if ProvisionalDisplayPolicy = "HideUntilInput"
        return A_TimeIdleKeyboard <= TooltipIdleTimeout
    if IsSet(lastClickTick) && A_TickCount - lastClickTick <= TooltipIdleTimeout
        return true
    return A_TimeIdleKeyboard <= TooltipIdleTimeout
}

CreateAnchorResult(found := false, x := 0, y := 0, source := "None"
    , confidence := "Invalid", isFallback := true, reason := "", depth := 0
    , hwnd := 0, runtimeId := "") {
    return {
        found: found,
        x: x,
        y: y,
        source: source,
        confidence: confidence,
        isFallback: isFallback,
        reason: reason,
        depth: depth,
        hwnd: hwnd,
        runtimeId: runtimeId
    }
}

GetElementRuntimeId(element) {
    try return element.RuntimeId
    return ""
}

GetGuiThreadCaretInfo(hwndActive) {
    static guiThreadInfo := Buffer(24 + 6 * A_PtrSize, 0)
    if !hwndActive
        return false
    threadId := DllCall("GetWindowThreadProcessId", "Ptr", hwndActive
        , "Ptr", 0, "UInt")
    NumPut "UInt", guiThreadInfo.Size, guiThreadInfo
    if !DllCall("GetGUIThreadInfo", "UInt", threadId, "Ptr", guiThreadInfo, "Int")
        return false
    return {
        buffer: guiThreadInfo,
        focusHwnd: NumGet(guiThreadInfo, 8 + A_PtrSize, "Ptr"),
        caretHwnd: NumGet(guiThreadInfo, 8 + 5 * A_PtrSize, "Ptr"),
        rectOffset: 8 + 6 * A_PtrSize
    }
}

TryGetMsaaCaretAnchor(context) {
    global AnchorConfidence
    threadInfo := GetGuiThreadCaretInfo(context.hwnd)
    if !threadInfo
        return CreateAnchorResult(, , , "MSAACaret", AnchorConfidence.Invalid
            , true, "GUIThreadInfoUnavailable", , context.hwnd)
    focusHwnd := threadInfo.focusHwnd || context.hwnd

    static iidAccessible := InitializeAccessibleId()
    try {
        result := DllCall("oleacc\AccessibleObjectFromWindow"
            , "Ptr", focusHwnd, "UInt", 0xFFFFFFF8, "Ptr", iidAccessible
            , "Ptr*", accessibleCaret := ComValue(13, 0), "Int")
        if result || !accessibleCaret.Ptr
            return CreateAnchorResult(, , , "MSAACaret", AnchorConfidence.Invalid
                , true, "AccessibleCaretUnavailable", , context.hwnd)

        if A_PtrSize = 8 {
            varChild := Buffer(24, 0)
            NumPut "UShort", 3, varChild
            result := ComCall(22, accessibleCaret
                , "Int*", &x := 0, "Int*", &y := 0
                , "Int*", &width := 0, "Int*", &height := 0
                , "Ptr", varChild, "Int")
        } else {
            result := ComCall(22, accessibleCaret
                , "Int*", &x := 0, "Int*", &y := 0
                , "Int*", &width := 0, "Int*", &height := 0
                , "Int64", 3, "Int64", 0, "Int")
        }
        if !result {
            validationReason := ValidateMsaaCaret(context, focusHwnd, x, y, width, height)
            if validationReason = ""
                return CreateAnchorResult(true, x, y, "MSAACaret"
                    , AnchorConfidence.Exact, false, , , context.hwnd)
            return CreateAnchorResult(, , , "MSAACaret", AnchorConfidence.Invalid
                , true, validationReason, , context.hwnd)
        }
    }
    return CreateAnchorResult(, , , "MSAACaret", AnchorConfidence.Invalid
        , true, "AccessibleCaretRectUnavailable", , context.hwnd)

    InitializeAccessibleId() {
        DllCall "LoadLibraryW", "Str", "oleacc.dll", "Ptr"
        iid := Buffer(16, 0)
        DllCall "ole32\CLSIDFromString"
            , "Str", "{618736E0-3C3D-11CF-810C-00AA00389B71}"
            , "Ptr", iid, "Int"
        return iid
    }
}

ValidateMsaaCaret(context, focusHwnd, x, y, width, height) {
    if !focusHwnd
        return "FocusWindowUnavailable"
    rootHwnd := DllCall("GetAncestor", "Ptr", focusHwnd, "UInt", 2, "Ptr")
    if rootHwnd && rootHwnd != context.hwnd
        return "FocusWindowMismatch"
    if height <= 0 || height > 300 || width < 0
        return "CaretSizeInvalid"
    try WinGetPos &windowX, &windowY, &windowWidth, &windowHeight, "ahk_id " context.hwnd
    catch
        return "ActiveWindowRectUnavailable"
    tolerance := 16
    if x < windowX - tolerance || x > windowX + windowWidth + tolerance
        || y < windowY - tolerance || y > windowY + windowHeight + tolerance
        return "CaretOutsideActiveWindow"
    return ""
}

TryGetGuiThreadCaretAnchor(context) {
    global AnchorConfidence
    threadInfo := GetGuiThreadCaretInfo(context.hwnd)
    if !threadInfo || !threadInfo.caretHwnd
        return CreateAnchorResult(, , , "GUIThreadCaret", AnchorConfidence.Invalid
            , true, "CaretWindowUnavailable", , context.hwnd)
    offset := threadInfo.rectOffset
    threadInfoBuffer := threadInfo.buffer
    left := NumGet(threadInfoBuffer, offset, "Int")
    top := NumGet(threadInfoBuffer, offset + 4, "Int")
    right := NumGet(threadInfoBuffer, offset + 8, "Int")
    bottom := NumGet(threadInfoBuffer, offset + 12, "Int")
    point := Buffer(8, 0)
    NumPut "Int", left, "Int", top, point
    if !DllCall("ClientToScreen", "Ptr", threadInfo.caretHwnd, "Ptr", point, "Int")
        return CreateAnchorResult(, , , "GUIThreadCaret", AnchorConfidence.Invalid
            , true, "ClientToScreenFailed", , context.hwnd)
    x := NumGet(point, 0, "Int")
    y := NumGet(point, 4, "Int")
    return CreateAnchorResult(true, x + Max(right - left, 0), y
        , "GUIThreadCaret", AnchorConfidence.Exact, false, , , context.hwnd)
}

DetectInputContext() {
    hwnd := WinExist("A")
    try processName := WinGetProcessName("ahk_id " hwnd)
    catch {
        processName := ""
    }
    isChromium := processName = "chrome.exe" || processName = "msedge.exe"
    return {
        hwnd: hwnd,
        processName: processName,
        isChromium: isChromium,
        allowParentWalk: !isChromium
    }
}

GetFocusedElementCached() {
    global MonitorCycleId, CachedFocusedElement, CachedFocusedElementCycle
    if IsSet(CachedFocusedElementCycle) && CachedFocusedElementCycle = MonitorCycleId
        return CachedFocusedElement
    CachedFocusedElementCycle := MonitorCycleId
    try CachedFocusedElement := UIA.GetFocusedElement()
    catch
        CachedFocusedElement := ""
    return CachedFocusedElement
}

ResolveAnchor(context) {
    global AnchorConfidence, CaretPositionIsFallback
        , LastUIASource, LastUIAConfidence, LastUIADepth, LastUIAReason
    if CaretGetPos(&caretX, &caretY) {
        CaretPositionIsFallback := false
        return CreateAnchorResult(true, caretX, caretY, "NativeCaret"
            , AnchorConfidence.Exact, false, , , context.hwnd)
    }

    msaaAnchor := TryGetMsaaCaretAnchor(context)
    if msaaAnchor.found
        return msaaAnchor

    focusedElement := GetFocusedElementCached()
    if focusedElement {
        try {
            if !IsUIAElementEditable(focusedElement, context)
                return CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
                    , true, "FocusedElementNotEditable", , context.hwnd, GetElementRuntimeId(focusedElement))
            if GetUIACaretPos(focusedElement, &caretX, &caretY, context)
                return CreateAnchorResult(true, caretX, caretY
                    , LastUIASource, LastUIAConfidence, CaretPositionIsFallback
                    , LastUIAReason, LastUIADepth, context.hwnd, GetElementRuntimeId(focusedElement))
        } catch {
            uiaUnavailable := true
        }
    } else {
        uiaUnavailable := true
    }

    guiThreadAnchor := TryGetGuiThreadCaretAnchor(context)
    if guiThreadAnchor.found
        return guiThreadAnchor
    if IsSet(uiaUnavailable)
        return CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
            , true, "FocusedElementUnavailable", , context.hwnd)
    return CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
        , true, "AnchorUnavailable", , context.hwnd)
}

IsUIAElementEditable(element, context) {
    global EditableScoreThreshold
    score := GetUIAEditScore(element, false, context)
    return score >= EditableScoreThreshold
}

GetUIAEditScore(element, isClickedElement := false, context := unset) {
    try {
        if !element.IsEnabled
            return -100

        type := element.Type
        if !IsSet(context)
            context := DetectInputContext()
        if type = UIA.Type.Button || type = UIA.Type.Link
            || type = UIA.Type.Menu || type = UIA.Type.MenuBar
            || type = UIA.Type.MenuItem || type = UIA.Type.ToolBar
            || type = UIA.Type.Tab || type = UIA.Type.TabItem
            || type = UIA.Type.CheckBox
            || type = UIA.Type.Text
            return -100

        score := 0
        if type = UIA.Type.Edit
            score += 6
        else if type = UIA.Type.ComboBox
            score += 2
        else if type = UIA.Type.DataItem || type = UIA.Type.ListItem
            score -= 8
        else if type = UIA.Type.Custom || type = UIA.Type.Pane
            || type = UIA.Type.Group || type = UIA.Type.DataGrid
            score += 1

        hasKeyboardFocus := element.HasKeyboardFocus
        if hasKeyboardFocus
            score += 3
        if element.IsKeyboardFocusable
            score += 2

        hasTextPattern := false
        try {
            if element.GetPropertyValue(UIA.Property.IsTextPatternAvailable) {
                hasTextPattern := true
                score += 2
                if type = UIA.Type.Document
                    score += IsDocumentEditable(element) ? 3 : -4
            }
        }

        try {
            if element.GetPropertyValue(UIA.Property.IsValuePatternAvailable) {
                if type = UIA.Type.Edit || type = UIA.Type.ComboBox || hasTextPattern
                    score += 4
                if element.GetPropertyValue(UIA.Property.ValueIsReadOnly)
                    score -= 10
            }
        }

        try {
            if element.GetPropertyValue(UIA.Property.IsSelectionItemPatternAvailable)
                && type != UIA.Type.Edit && type != UIA.Type.ComboBox
                score -= 6
        }

        if isClickedElement
            score += 2
        return score
    }
    return -100
}

GetRecentClickEvidence() {
    global lastClickScore, lastClickWindow, lastClickTick
    if !IsSet(lastClickScore) || lastClickScore <= 0
        return 0
    if !IsSet(lastClickWindow) || lastClickWindow != WinExist("A")
        return 0
    if !IsSet(lastClickTick) || A_TickCount - lastClickTick > 300000
        return 0
    return Min(lastClickScore, 2)
}

GetUIACaretPos(element, &caretX, &caretY, context) {
    global AnchorConfidence, LastUIASource, LastUIAConfidence, LastUIADepth, LastUIAReason
    LastUIASource := "None"
    LastUIAConfidence := AnchorConfidence.Invalid
    LastUIADepth := 0
    LastUIAReason := ""
    currentElement := element
    maxDepth := context.allowParentWalk ? 6 : 0
    Loop maxDepth + 1 {
        depth := A_Index - 1
        if GetUIACaretPosFromElement(currentElement, &caretX, &caretY, depth)
            return true
        if A_Index > maxDepth
            break
        try currentElement := currentElement.Parent
        catch
            break
    }
    if GetUIAElementFallbackPos(element, &caretX, &caretY) {
        LastUIASource := "UIAFallback"
        LastUIAConfidence := AnchorConfidence.Fallback
        LastUIAReason := context.allowParentWalk ? "ParentTextRangeUnavailable" : "FocusedTextRangeUnavailable"
        return true
    }
    LastUIAReason := "FallbackUnavailable"
    return false
}

GetUIACaretPosFromElement(element, &caretX, &caretY, depth) {
    global AnchorConfidence, LastUIASource, LastUIAConfidence, LastUIADepth
    sourcePrefix := depth = 0 ? "UIA" : "UIAParent"
    try {
        textPattern := element.TextPattern
        try {
            caretRange := textPattern.GetCaretRange(&isActive)
            if isActive && (GetTextRangeCaretPos(caretRange, &caretX, &caretY)
                || GetDegenerateRangeCaretPos(caretRange, &caretX, &caretY)) {
                LastUIASource := sourcePrefix "CaretRange"
                LastUIAConfidence := depth = 0 ? AnchorConfidence.Exact : AnchorConfidence.Estimated
                LastUIADepth := depth
                return true
            }
        }

        try {
            selection := textPattern.GetSelection()
            if selection.Length {
                selectionRange := selection[selection.Length]
                if GetTextRangeCaretPos(selectionRange, &caretX, &caretY)
                    || GetDegenerateRangeCaretPos(selectionRange, &caretX, &caretY) {
                    LastUIASource := sourcePrefix "Selection"
                    LastUIAConfidence := AnchorConfidence.Estimated
                    LastUIADepth := depth
                    return true
                }
            }
        }

        try {
            textEditPattern := element.TextEditPattern
            try {
                textRange := textEditPattern.GetActiveComposition()
                if GetTextRangeCaretPos(textRange, &caretX, &caretY) {
                    LastUIASource := sourcePrefix "ActiveComposition"
                    LastUIAConfidence := AnchorConfidence.Estimated
                    LastUIADepth := depth
                    return true
                }
            }
            try {
                textRange := textEditPattern.GetConversionTarget()
                if GetTextRangeCaretPos(textRange, &caretX, &caretY) {
                    LastUIASource := sourcePrefix "ConversionTarget"
                    LastUIAConfidence := AnchorConfidence.Estimated
                    LastUIADepth := depth
                    return true
                }
            }
        }
    }
    return false
}

GetTextRangeCaretPos(textRange, &caretX, &caretY) {
    try {
        rectangles := textRange.GetBoundingRectangles()
        if rectangles.Length {
            rectangle := rectangles[rectangles.Length]
            caretX := rectangle.x + rectangle.w
            caretY := rectangle.y
            global CaretPositionIsFallback := false
            return true
        }
    }
    return false
}

; 幅0のキャレット範囲（WinUI TextBox等）は矩形を返さないため、複製して1文字広げて端を採る
GetDegenerateRangeCaretPos(textRange, &caretX, &caretY) {
    try {
        forwardRange := textRange.Clone()
        forwardRange.MoveEndpointByUnit(UIA.TextPatternRangeEndpoint.End, UIA.TextUnit.Character, 1)
        rectangles := forwardRange.GetBoundingRectangles()
        if rectangles.Length {
            rectangle := rectangles[1]
            caretX := rectangle.x
            caretY := rectangle.y
            global CaretPositionIsFallback := false
            return true
        }
    }
    try {
        backwardRange := textRange.Clone()
        backwardRange.MoveEndpointByUnit(UIA.TextPatternRangeEndpoint.Start, UIA.TextUnit.Character, -1)
        rectangles := backwardRange.GetBoundingRectangles()
        if rectangles.Length {
            rectangle := rectangles[rectangles.Length]
            caretX := rectangle.x + rectangle.w
            caretY := rectangle.y
            global CaretPositionIsFallback := false
            return true
        }
    }
    return false
}

GetUIAElementFallbackPos(element, &caretX, &caretY) {
    global lastClickX, lastClickY, CaretPositionIsFallback
    ; 空欄のEdit/ComboBoxはキャレットが左端。クリック位置ではなく入力欄左端を基準にして安定させる
    if IsUIAEmptyInputField(element) {
        try {
            rectangle := element.BoundingRectangle
            if rectangle.r > rectangle.l && rectangle.b > rectangle.t {
                caretX := rectangle.l + 8
                caretY := rectangle.t + Floor((rectangle.b - rectangle.t) / 2)
                CaretPositionIsFallback := true
                return true
            }
        }
    }

    if GetRecentClickEvidence() && IsSet(lastClickX) {
        caretX := lastClickX
        caretY := lastClickY
        CaretPositionIsFallback := true
        return true
    }

    try {
        rectangle := element.BoundingRectangle
        if IsSet(lastClickX) && lastClickX >= rectangle.l && lastClickX <= rectangle.r
            && lastClickY >= rectangle.t && lastClickY <= rectangle.b {
            caretX := lastClickX
            caretY := lastClickY
            CaretPositionIsFallback := true
            return true
        }

        if rectangle.r > rectangle.l && rectangle.b > rectangle.t {
            caretX := rectangle.l + 8
            caretY := rectangle.t + Floor((rectangle.b - rectangle.t) / 2)
            CaretPositionIsFallback := true
            return true
        }
    }
    return false
}

; Edit/ComboBox かつ値が空の入力欄かを判定（空欄はキャレットが左端にある）
IsUIAEmptyInputField(element) {
    try {
        type := element.Type
        if type != UIA.Type.Edit && type != UIA.Type.ComboBox
            return false
        return element.ValuePattern.Value = ""
    }
    return false
}

IsValueReadOnly(element) {
    try {
        if element.GetPropertyValue(UIA.Property.IsValuePatternAvailable)
            return element.GetPropertyValue(UIA.Property.ValueIsReadOnly)
    }
    return false
}

IsDocumentEditable(element) {
    try {
        selection := element.TextPattern.GetSelection()
        if selection.Length
            return !selection[1].GetAttributeValue(UIA.TextAttribute.IsReadOnly)
    }
    return false
}

GetImeModeDisplay() {
    global IndicatorColorAlphanumeric, IndicatorColorJapanese
        , IndicatorColorHalfKatakana, IndicatorColorFullAlphanumeric
        , IndicatorColorUnknown
    if !IME_GET()
        return {text: "A", color: IndicatorColorAlphanumeric}

    switch IME_GetConvMode() {
        case 9, 25:
            return {text: "あ", color: IndicatorColorJapanese}
        case 11, 27:
            return {text: "カ", color: IndicatorColorJapanese}
        case 3, 19:
            return {text: "ｶ", color: IndicatorColorHalfKatakana}
        case 8, 24:
            return {text: "Ａ", color: IndicatorColorFullAlphanumeric}
        default:
            return {text: "あ", color: IndicatorColorUnknown}
    }
}
