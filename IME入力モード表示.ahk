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
MonitorRunning := false
MonitorRequested := false
MonitorTimerArmed := false
MonitorNextDueTick := 0
ImeCircuitOpenUntil := 0
UiaCircuitOpenUntil := 0
MsaaCircuitOpenUntil := 0
TrackedImeConversionTick := 0
DetectedImeConversionTick := 0
LastTextInputTick := 0
LastHandledTextInputTick := 0
LastConversionKeyTick := 0
LastHandledConversionKeyTick := 0
LastAnchorActivityTick := 0
LastAnchorProbeTick := 0
AnchorProbeNotBeforeTick := 0
AnchorProbePending := true
AnchorContextHwnd := 0
AnchorContextFocusHwnd := 0
ImeQueryTimeoutMs := 35
ImeStaleReuseMs := 300
ImeCircuitSlowMs := 40
ImeCircuitCooldownMs := 300
UiaCircuitSlowMs := 50
UiaCircuitBaseCooldownMs := 1000
UiaCircuitMaxCooldownMs := 30000
UiaCircuitSlowCount := 0
MsaaCircuitSlowMs := 50
MsaaCircuitBaseCooldownMs := 1000
MsaaCircuitMaxCooldownMs := 30000
MsaaCircuitSlowCount := 0
AnchorProbeQuietMs := 120
ChromiumAnchorProbeMinIntervalMs := 250
DefaultAnchorProbeMinIntervalMs := 120
InputContextCacheMs := 1000
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
DiagnosticDeepUiaEnabled := false ; true の場合だけ変換中UIA探索も診断する
DiagnosticLogPath := A_ScriptDir "\logs\IME入力モード表示.log"
CandidateWindowLogPath := A_ScriptDir "\logs\IME候補ウィンドウ詳細.tsv"
PerformanceDiagnosticEnabled := false
PerformanceSlowThresholdMs := 20
PerformanceLogMaxBytes := 4 * 1024 * 1024
PerformanceLogQueueMax := 128
PerformanceLogPath := A_ScriptDir "\logs\IME入力モード表示_性能.tsv"
PerformanceLogQueue := []
PerformanceLogFlushArmed := false
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
^!+F9::CaptureIa2CaretInfo()
^!F10::CaptureImeCandidateWindows("BASELINE")
^!F11::CaptureImeCandidateWindows("CANDIDATE")
^!F12::ToggleImeDiagnostics()
^!+F12::TogglePerformanceDiagnostics()
; --- ここまで診断・計測用ホットキー ---

; ============================================================================
;  診断・計測用（本体機能とは独立 / ^!F9-F12・^!+F12でのみ動作）
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

; Chromium / Electron が公開する IAccessible2 のテキストキャレットを手動診断する
; 常時監視からは呼ばず、同期問い合わせが入力ホットパスへ入らないようにする
CaptureIa2CaretInfo() {
    global lastClickX, lastClickY, lastClickWindow
    logPath := A_ScriptDir "\logs\IME_IA2キャレット詳細.tsv"
    SplitPath logPath, , &logDirectory
    if !DirExist(logDirectory)
        DirCreate logDirectory

    context := DetectInputContext()
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss") "." Format("{:03}", A_MSec)
    header := FileExist(logPath) ? ""
        : "time`tproc`thwnd`tfocusHwnd`tsource`tpoint`tchildId`tobjectHr"
        . "`tia2Available`ttextAvailable`tcaretHr`tcaretOffset`tnCharacters"
        . "`textentsHr`tx`ty`twidth`theight`telapsedMs`tnote`n"
    output := ""

    threadInfo := GetGuiThreadCaretInfo(context.hwnd)
    focusHwnd := threadInfo && threadInfo.focusHwnd ? threadInfo.focusHwnd : context.hwnd
    windowProbe := ProbeIa2CaretFromWindow(focusHwnd)
    output .= FormatIa2CaretDiagnosticLine(timestamp, context, "OBJID_CLIENT"
        , "", windowProbe)

    focusedProbe := ProbeIa2CaretFromAccessibleFocus(focusHwnd)
    output .= FormatIa2CaretDiagnosticLine(timestamp, context, "MSAA_accFocus"
        , "", focusedProbe)

    uiaLegacyProbe := ProbeIa2CaretFromUiaFocusedElement()
    output .= FormatIa2CaretDiagnosticLine(timestamp, context, "UIA_LegacyIAccessible"
        , "", uiaLegacyProbe)

    if context.rendererHwnd && context.rendererHwnd != focusHwnd {
        rendererProbe := ProbeIa2CaretFromWindow(context.rendererHwnd)
        output .= FormatIa2CaretDiagnosticLine(timestamp, context, "RendererClient"
            , "", rendererProbe)
        rendererFocusProbe := ProbeIa2CaretFromAccessibleFocus(context.rendererHwnd)
        output .= FormatIa2CaretDiagnosticLine(timestamp, context, "RendererAccFocus"
            , "", rendererFocusProbe)
    }

    if IsSet(lastClickX) && IsSet(lastClickY) && IsSet(lastClickWindow)
        && lastClickWindow = context.hwnd {
        pointProbe := ProbeIa2CaretFromPoint(lastClickX, lastClickY)
        output .= FormatIa2CaretDiagnosticLine(timestamp, context, "ClickPoint"
            , lastClickX "," lastClickY, pointProbe)
    }

    if AppendLogWithRetry(logPath, header . output)
        TrayTip "IME入力モード表示", "IA2キャレット情報を記録しました"
    else
        TrayTip "IME入力モード表示", "IA2ログを記録できませんでした"
}

ProbeIa2CaretFromUiaFocusedElement() {
    started := PerformanceNow()
    probe := CreateIa2ProbeResult()
    probe.childId := 0
    try {
        element := UIA.GetFocusedElement()
        if !element {
            probe.note := "FocusedElementUnavailable"
            return probe
        }
        if !element.GetPropertyValue(UIA.Property.IsLegacyIAccessiblePatternAvailable) {
            probe.note := "LegacyPatternUnavailable"
            return probe
        }
        accessible := element.LegacyIAccessiblePattern.GetIAccessible()
        probe.objectHr := 0
        if !accessible || !ComObjValue(accessible) {
            probe.note := "IAccessibleUnavailable"
            return probe
        }
        FillIa2TextProbe(accessible, probe)
    } catch as error {
        probe.note := "Exception:" error.What
    } finally {
        probe.elapsedMs := PerformanceElapsedMs(started)
    }
    return probe
}

ProbeIa2CaretFromAccessibleFocus(hwnd) {
    started := PerformanceNow()
    probe := CreateIa2ProbeResult()
    probe.childId := 0
    if !hwnd {
        probe.note := "NoFocusHwnd"
        probe.elapsedMs := PerformanceElapsedMs(started)
        return probe
    }

    static iidAccessible := CreateGuidBuffer(
        "{618736E0-3C3D-11CF-810C-00AA00389B71}")
    try {
        probe.objectHr := DllCall("oleacc\AccessibleObjectFromWindow"
            , "Ptr", hwnd, "UInt", 0xFFFFFFFC, "Ptr", iidAccessible
            , "Ptr*", accessible := ComValue(13, 0), "Int") ; OBJID_CLIENT
        if probe.objectHr || !accessible.Ptr {
            probe.note := "AccessibleObjectUnavailable"
            return probe
        }

        current := accessible
        Loop 8 {
            focusVariant := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
            focusHr := ComCall(17, current, "Ptr", focusVariant, "Int") ; get_accFocus
            if focusHr
                break
            variantType := NumGet(focusVariant, 0, "UShort")
            if variantType != 9 && variantType != 13 { ; VT_DISPATCH / VT_UNKNOWN
                DllCall "oleaut32\VariantClear", "Ptr", focusVariant
                break
            }
            focusPointer := NumGet(focusVariant, 8, "Ptr")
            if !focusPointer
                break
            ; COMラッパーへ所有権を移し、VARIANT側の二重Releaseを防ぐ
            NumPut "Ptr", 0, focusVariant, 8
            nextAccessible := ComValue(variantType, focusPointer)
            current := nextAccessible
            probe.childId := A_Index
        }
        FillIa2TextProbe(current, probe)
    } catch as error {
        probe.note := "Exception:" error.What
    } finally {
        probe.elapsedMs := PerformanceElapsedMs(started)
    }
    return probe
}

ProbeIa2CaretFromWindow(hwnd) {
    started := PerformanceNow()
    probe := CreateIa2ProbeResult()
    probe.childId := 0
    if !hwnd {
        probe.note := "NoFocusHwnd"
        probe.elapsedMs := PerformanceElapsedMs(started)
        return probe
    }

    static iidAccessible := CreateGuidBuffer(
        "{618736E0-3C3D-11CF-810C-00AA00389B71}")
    try {
        probe.objectHr := DllCall("oleacc\AccessibleObjectFromWindow"
            , "Ptr", hwnd, "UInt", 0xFFFFFFFC, "Ptr", iidAccessible
            , "Ptr*", accessible := ComValue(13, 0), "Int") ; OBJID_CLIENT
        if !probe.objectHr && accessible.Ptr
            FillIa2TextProbe(accessible, probe)
        else
            probe.note := "AccessibleObjectUnavailable"
    } catch as error {
        probe.note := "Exception:" error.What
    }
    probe.elapsedMs := PerformanceElapsedMs(started)
    return probe
}

ProbeIa2CaretFromPoint(x, y) {
    started := PerformanceNow()
    probe := CreateIa2ProbeResult()
    childVariant := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    try {
        probe.objectHr := DllCall("oleacc\AccessibleObjectFromPoint"
            , "Int64", (y << 32) | (x & 0xFFFFFFFF)
            , "Ptr*", accessible := ComValue(13, 0)
            , "Ptr", childVariant, "Int")
        probe.childId := NumGet(childVariant, 8, "Int")
        if !probe.objectHr && accessible.Ptr
            FillIa2TextProbe(accessible, probe)
        else
            probe.note := "AccessibleObjectUnavailable"
    } catch as error {
        probe.note := "Exception:" error.What
    }
    probe.elapsedMs := PerformanceElapsedMs(started)
    return probe
}

FillIa2TextProbe(accessible, probe) {
    static iidAccessible := "{618736E0-3C3D-11CF-810C-00AA00389B71}"
    static iidAccessible2 := "{E89F726E-C4F4-4C19-BB19-B647D7FA8478}"
    static iidAccessibleText := "{24FD2FFB-3AAD-4A08-8335-A3AD89C0FB4B}"
    try {
        ia2 := ComObjQuery(accessible, iidAccessible, iidAccessible2)
        probe.ia2Available := !!ia2
        if !ia2 {
            probe.note := "IAccessible2Unavailable"
            return
        }
        text := ComObjQuery(ia2, iidAccessibleText)
        probe.textAvailable := !!text
        if !text {
            probe.note := "IAccessibleTextUnavailable"
            return
        }

        probe.caretHr := ComCall(5, text, "Int*", &caretOffset := -1, "Int")
        probe.caretOffset := caretOffset
        try {
            ComCall(17, text, "Int*", &nCharacters := -1, "Int")
            probe.nCharacters := nCharacters
        }
        if probe.caretHr <= 1 && caretOffset >= 0 {
            probe.extentsHr := ComCall(6, text
                , "Int", caretOffset, "Int", 0 ; IA2_COORDTYPE_SCREEN_RELATIVE
                , "Int*", &x := 0, "Int*", &y := 0
                , "Int*", &width := 0, "Int*", &height := 0, "Int")
            probe.x := x
            probe.y := y
            probe.width := width
            probe.height := height
            if probe.extentsHr = 0
                probe.note := "OK"
            else
                probe.note := "CharacterExtentsFailed"
        } else
            probe.note := "InactiveCaret"
    } catch as error {
        probe.note := "Exception:" error.What
    }
}

CreateIa2ProbeResult() {
    return {
        childId: -1,
        objectHr: -1,
        ia2Available: false,
        textAvailable: false,
        caretHr: -1,
        caretOffset: -1,
        nCharacters: -1,
        extentsHr: -1,
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        elapsedMs: 0,
        note: "NotQueried"
    }
}

FormatIa2CaretDiagnosticLine(timestamp, context, source, point, probe) {
    return (timestamp "`t" context.processName "`t" context.hwnd "`t"
        . context.focusHwnd "`t" source "`t" point "`t" probe.childId "`t"
        . probe.objectHr "`t" probe.ia2Available "`t" probe.textAvailable "`t"
        . probe.caretHr "`t" probe.caretOffset "`t" probe.nCharacters "`t"
        . probe.extentsHr "`t" probe.x "`t" probe.y "`t" probe.width "`t"
        . probe.height "`t" Format("{:.3f}", probe.elapsedMs) "`t"
        . SanitizeLogField(probe.note) "`n")
}

CreateGuidBuffer(guidText) {
    guid := Buffer(16, 0)
    DllCall "ole32\CLSIDFromString", "Str", guidText, "Ptr", guid, "Int"
    return guid
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
        AppendLogWithRetry(DiagnosticLogPath
            , "`n--- diagnostics started " FormatTime(, "yyyy-MM-dd HH:mm:ss") " ---`n")
    }
    TrayTip "IME入力モード表示"
        , DiagnosticEnabled ? "診断ログ: ON" : "診断ログ: OFF"
}

TogglePerformanceDiagnostics() {
    global PerformanceDiagnosticEnabled
    PerformanceDiagnosticEnabled := !PerformanceDiagnosticEnabled
    TrayTip "IME入力モード表示"
        , PerformanceDiagnosticEnabled ? "性能診断TSV: ON" : "性能診断TSV: OFF"
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
    RotateLogIfNeeded(path, StrLen(text) * 3)
    Loop 5 {
        try {
            FileAppend text, path, "UTF-8"
            return true
        }
        Sleep 50
    }
    return false
}

RotateLogIfNeeded(path, incomingBytes := 0, maxBytes := 4 * 1024 * 1024) {
    try currentBytes := FileGetSize(path)
    catch
        return
    if currentBytes + incomingBytes <= maxBytes
        return
    try {
        if FileExist(path ".1")
            FileDelete path ".1"
        FileMove path, path ".1"
    }
}

PerformanceNow() {
    DllCall("QueryPerformanceCounter", "Int64*", &counter := 0)
    return counter
}

PerformanceElapsedMs(startCounter) {
    static frequency := 0
    if !frequency
        DllCall("QueryPerformanceFrequency", "Int64*", &frequency)
    return (PerformanceNow() - startCounter) * 1000 / frequency
}

QueueSlowPerformance(context, operation, elapsedMs, caretSource := "", timedOut := false) {
    global PerformanceDiagnosticEnabled, PerformanceSlowThresholdMs
        , PerformanceLogQueue, PerformanceLogQueueMax, PerformanceLogFlushArmed
    if !PerformanceDiagnosticEnabled || elapsedMs < PerformanceSlowThresholdMs
        return
    processName := context.processName != "" ? context.processName : "unknown"
    line := (FormatTime(, "yyyy-MM-dd HH:mm:ss.fff") "`t" processName "`t"
        . context.hwnd "`t" operation "`t" Format("{:.3f}", elapsedMs) "`t"
        . SanitizeLogField(caretSource) "`t" (timedOut ? 1 : 0) "`n")
    if PerformanceLogQueue.Length >= PerformanceLogQueueMax
        PerformanceLogQueue.RemoveAt(1)
    PerformanceLogQueue.Push(line)
    if !PerformanceLogFlushArmed {
        PerformanceLogFlushArmed := true
        SetTimer FlushPerformanceLog, -500
    }
}

FlushPerformanceLog() {
    global PerformanceLogQueue, PerformanceLogFlushArmed
    PerformanceLogFlushArmed := false
    if !PerformanceLogQueue.Length
        return
    if A_TimeIdleKeyboard < 250 {
        PerformanceLogFlushArmed := true
        SetTimer FlushPerformanceLog, -500
        return
    }

    output := ""
    Loop Min(32, PerformanceLogQueue.Length)
        output .= PerformanceLogQueue.RemoveAt(1)
    WritePerformanceLog(output)
    if PerformanceLogQueue.Length {
        PerformanceLogFlushArmed := true
        SetTimer FlushPerformanceLog, -500
    }
}

WritePerformanceLog(text) {
    global PerformanceLogPath, PerformanceLogMaxBytes
    SplitPath PerformanceLogPath, , &logDirectory
    try {
        if !DirExist(logDirectory)
            DirCreate logDirectory
        header := FileExist(PerformanceLogPath)
            ? ""
            : "time`tprocess`thwnd`toperation`tdurationMs`tcaretSource`ttimedOut`n"
        RotateLogIfNeeded(PerformanceLogPath, StrLen(header . text) * 3, PerformanceLogMaxBytes)
        if !FileExist(PerformanceLogPath)
            header := "time`tprocess`thwnd`toperation`tdurationMs`tcaretSource`ttimedOut`n"
        FileAppend header . text, PerformanceLogPath, "UTF-8"
    }
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
DiagnoseConversionSignals(context, imeSnapshot) {
    global DiagnosticEnabled, DiagnosticDeepUiaEnabled, DiagnosticLogPath
        , ImeConversionHoldMs, TrackedImeConversionTick
    static lastSignature := ""
    if !DiagnosticEnabled
        return

    trackerActive := (IsSet(TrackedImeConversionTick) && TrackedImeConversionTick
        && A_TickCount - TrackedImeConversionTick <= ImeConversionHoldMs) ? 1 : 0
    immOpen := imeSnapshot.valid ? (imeSnapshot.open ? 1 : 0) : -1
    converting := imeSnapshot.valid ? imeSnapshot.converting : -1
    hasCandidate := converting = 2 ? 1 : (converting >= 0 ? 0 : -1)
    uiaComposition := DiagnosticDeepUiaEnabled ? DetectUIACompositionSignal() : -2
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
        , LastAnchorActivityTick, AnchorProbeNotBeforeTick, AnchorProbePending
    MouseGetPos &lastClickX, &lastClickY, &lastClickWindow
    lastClickTick := A_TickCount
    LastAnchorActivityTick := lastClickTick
    AnchorProbeNotBeforeTick := lastClickTick + 150
    AnchorProbePending := true
    TrackedImeConversionTick := 0
    DetectedImeConversionTick := 0
    TooltipAnchorVersion += 1
    lastClickScore := 0
    SetTimer RefreshClickedElement, -150
    RequestImeMonitor() ; イベント未使用時でもクリック直後に即時反映
}

TrackImeConversionKey() {
    global LastConversionKeyTick, LastAnchorActivityTick, AnchorProbePending
    LastConversionKeyTick := A_TickCount
    LastAnchorActivityTick := LastConversionKeyTick
    AnchorProbePending := true
    RequestImeMonitor()
}

InitializeImeKeyTracking() {
    global ImeKeyMonitor
    ImeKeyMonitor := InputHook("V I1")
    ImeKeyMonitor.KeyOpt("{All}", "-N")
    ImeKeyMonitor.KeyOpt(GetImeTextInputKeyList(), "N")
    ImeKeyMonitor.KeyOpt(GetImeCaretNavigationKeyList(), "N")
    ImeKeyMonitor.OnKeyDown := HandleImeTextKeyDown
    ImeKeyMonitor.Start()
    OnExit CleanupImeKeyTracking
}

CleanupImeKeyTracking(*) {
    global ImeKeyMonitor
    try ImeKeyMonitor.Stop()
}

HandleImeTextKeyDown(inputHook, virtualKey, scanCode) {
    global LastTextInputTick, LastAnchorActivityTick, AnchorProbePending
    if IsCaretNavigationVirtualKey(virtualKey) {
        LastAnchorActivityTick := A_TickCount
        AnchorProbePending := true
        RequestImeMonitor()
        return
    }
    if !IsTextInputVirtualKey(virtualKey)
        return
    if GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        return
    RequestImeMonitor()
    if GetKeyState("Ctrl", "P") || GetKeyState("Alt", "P")
        return
    LastTextInputTick := A_TickCount
    LastAnchorActivityTick := LastTextInputTick
    AnchorProbePending := true
}

GetImeTextInputKeyList() {
    keys := ""
    for range in [[0x30, 0x39], [0x41, 0x5A], [0x60, 0x69], [0xBA, 0xE2]]
        Loop range[2] - range[1] + 1
            keys .= "{vk" Format("{:02X}", range[1] + A_Index - 1) "}"
    return keys
}

GetImeCaretNavigationKeyList() {
    keys := ""
    for virtualKey in [0x08, 0x09, 0x0D, 0x1B, 0x21, 0x22, 0x23, 0x24
        , 0x25, 0x26, 0x27, 0x28, 0x2E]
        keys .= "{vk" Format("{:02X}", virtualKey) "}"
    return keys
}

IsTextInputVirtualKey(virtualKey) {
    return virtualKey >= 0x30 && virtualKey <= 0x39
        || virtualKey >= 0x41 && virtualKey <= 0x5A
        || virtualKey >= 0x60 && virtualKey <= 0x69
        || virtualKey >= 0xBA && virtualKey <= 0xE2
}

IsCaretNavigationVirtualKey(virtualKey) {
    return virtualKey = 0x08 || virtualKey = 0x09 || virtualKey = 0x0D
        || virtualKey = 0x1B || virtualKey >= 0x21 && virtualKey <= 0x28
        || virtualKey = 0x2E
}

IsJapaneseImeMode(mode) {
    return mode = 9 || mode = 25 || mode = 11 || mode = 27
        || mode = 3 || mode = 19
}

EndTrackedImeConversion() {
    global TrackedImeConversionTick := 0, DetectedImeConversionTick := 0
        , LastAnchorActivityTick, AnchorProbePending
    LastAnchorActivityTick := A_TickCount
    AnchorProbePending := true
    RequestImeMonitor()
}

RefreshClickedElement() {
    global AnchorProbePending
    ; クリック点UIAとフォーカスUIAを重複取得せず、次の監視サイクルへ1回だけ集約する
    AnchorProbePending := true
    RequestImeMonitor()
}

InitializeImeMonitor() {
    global ImeFocusChangedHandler, UseFocusChangedEvent, MonitorTimerArmed, MonitorNextDueTick
    if UseFocusChangedEvent {
        try {
            ImeFocusChangedHandler := UIA.CreateFocusChangedEventHandler(HandleImeFocusChanged)
            UIA.AddFocusChangedEventHandler(ImeFocusChangedHandler)
        }
    }
    OnExit CleanupImeMonitor
    MonitorTimerArmed := true
    MonitorNextDueTick := A_TickCount + 1
    SetTimer RunImeMonitor, -1
}

CleanupImeMonitor(*) {
    global ImeFocusChangedHandler
    if IsSet(ImeFocusChangedHandler)
        try UIA.RemoveFocusChangedEventHandler(ImeFocusChangedHandler)
}

HandleImeFocusChanged(*) {
    RequestImeMonitor()
}

RunImeMonitor() {
    global MonitorRunning, MonitorRequested, MonitorTimerArmed, MonitorNextDueTick
    MonitorTimerArmed := false
    MonitorNextDueTick := 0
    if MonitorRunning {
        MonitorRequested := true
        return
    }
    MonitorRunning := true
    MonitorRequested := false
    try ShowImeMode()
    finally {
        MonitorRunning := false
        interval := MonitorRequested ? 1 : GetImeMonitorInterval()
        MonitorTimerArmed := true
        MonitorNextDueTick := A_TickCount + interval
        SetTimer RunImeMonitor, -interval
    }
}

RequestImeMonitor() {
    global MonitorRunning, MonitorRequested, MonitorTimerArmed, MonitorNextDueTick
    MonitorRequested := true
    if MonitorRunning
        return
    if MonitorTimerArmed && IsSet(MonitorNextDueTick)
        && MonitorNextDueTick - A_TickCount <= 10
        return
    MonitorTimerArmed := true
    MonitorNextDueTick := A_TickCount + 1
    SetTimer RunImeMonitor, -1
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
    global CurrentAnchorResult, MonitorCycleId, PerformanceDiagnosticEnabled
    static running := false
    if running
        return
    running := true
    cycleStarted := PerformanceDiagnosticEnabled ? PerformanceNow() : 0
    try {
        MonitorCycleId += 1
        context := DetectInputContext()
        PrepareAnchorContext(context)
        imeSnapshot := CaptureImeSnapshot(context)
        ApplyPendingImeInput(imeSnapshot)
        DiagnoseConversionSignals(context, imeSnapshot)
        if !imeSnapshot.valid {
            CurrentAnchorResult := CreateAnchorResult(, , , "None", "Invalid"
                , true, imeSnapshot.reason, , context.hwnd)
            SetIndicatorHidden(CurrentAnchorResult)
            return
        }

        anchorStarted := PerformanceDiagnosticEnabled ? PerformanceNow() : 0
        CurrentAnchorResult := ResolveAnchor(context)
        if CurrentAnchorResult.found
            RememberGoodAnchor(CurrentAnchorResult, context)
        if anchorStarted
            QueueSlowPerformance(context, "ResolveAnchor"
                , PerformanceElapsedMs(anchorStarted), CurrentAnchorResult.source, false)
        if !CurrentAnchorResult.found || !ShouldShowImeIndicator(CurrentAnchorResult) {
            SetIndicatorHidden(CurrentAnchorResult)
            return
        }

        modeDisplay := GetImeModeDisplay(imeSnapshot)
        UpdateIndicatorState(context, CurrentAnchorResult, modeDisplay
            , IsImeConversionActive(imeSnapshot))
    } finally {
        ClearCycleCaches()
        if cycleStarted && IsSet(context) {
            caretSource := IsSet(CurrentAnchorResult) ? CurrentAnchorResult.source : "None"
            timedOut := IsSet(imeSnapshot) ? imeSnapshot.timedOut : false
            QueueSlowPerformance(context, "監視サイクル"
                , PerformanceElapsedMs(cycleStarted), caretSource, timedOut)
        }
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
    if anchor.isFallback && !IsPointerFallbackSource(anchor.source)
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

IsPointerFallbackSource(source) {
    return source = "RecentClickFallback"
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

CaptureImeSnapshot(context) {
    global ImeQueryTimeoutMs, ImeCircuitOpenUntil, ImeCircuitSlowMs
        , ImeCircuitCooldownMs, LastGoodImeSnapshot
    if A_TickCount < ImeCircuitOpenUntil
        return GetReusableImeSnapshot(context, false, "IMECircuitOpen")

    started := PerformanceNow()
    timedOut := false
    queryFailed := false
    open := false
    convMode := 0
    converting := 0

    focusHwnd := _IME_GetFocusHwnd("ahk_id " context.hwnd)
    imeWnd := focusHwnd
        ? DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", focusHwnd, "Ptr")
        : 0
    if imeWnd && !TrySendImeControl(imeWnd, 0x0005, 0, ImeQueryTimeoutMs
        , &openValue, &openTimedOut) {
        timedOut := openTimedOut
        queryFailed := openTimedOut
    } else if imeWnd {
        open := openValue != 0
        if open {
            if !TrySendImeControl(imeWnd, 0x0001, 0, ImeQueryTimeoutMs
                , &modeValue, &modeTimedOut) {
                timedOut := timedOut || modeTimedOut
                queryFailed := modeTimedOut
            } else {
                convMode := modeValue
            }
            if !queryFailed
                try converting := IME_GetConverting("ahk_id " context.hwnd)
        }
    }

    elapsedMs := PerformanceElapsedMs(started)
    if timedOut || elapsedMs >= ImeCircuitSlowMs
        ImeCircuitOpenUntil := A_TickCount + ImeCircuitCooldownMs
    QueueSlowPerformance(context, "IME取得", elapsedMs, "", timedOut)

    if queryFailed
        return GetReusableImeSnapshot(context, timedOut
            , timedOut ? "IMEQueryTimedOut" : "IMEQueryUnavailable")
    snapshot := {
        valid: true,
        open: open,
        convMode: convMode,
        converting: converting,
        stale: false,
        timedOut: timedOut,
        capturedTick: A_TickCount,
        hwnd: context.hwnd,
        reason: ""
    }
    LastGoodImeSnapshot := snapshot
    return snapshot
}

TrySendImeControl(imeWnd, wParam, lParam, timeoutMs, &value, &timedOut) {
    value := 0
    timedOut := false
    succeeded := DllCall("user32\SendMessageTimeoutW"
        , "Ptr", imeWnd
        , "UInt", 0x0283 ; WM_IME_CONTROL
        , "Ptr", wParam
        , "Ptr", lParam
        , "UInt", 0x22 ; SMTO_ABORTIFHUNG | SMTO_ERRORONEXIT
        , "UInt", timeoutMs
        , "Ptr*", &value
        , "Ptr")
    if succeeded
        return true
    timedOut := A_LastError = 1460
    return false
}

GetReusableImeSnapshot(context, timedOut, reason) {
    global ImeStaleReuseMs, LastGoodImeSnapshot
    if IsSet(LastGoodImeSnapshot)
        && LastGoodImeSnapshot.hwnd = context.hwnd
        && A_TickCount - LastGoodImeSnapshot.capturedTick <= ImeStaleReuseMs {
        return {
            valid: true,
            open: LastGoodImeSnapshot.open,
            convMode: LastGoodImeSnapshot.convMode,
            converting: LastGoodImeSnapshot.converting,
            stale: true,
            timedOut: timedOut,
            capturedTick: LastGoodImeSnapshot.capturedTick,
            hwnd: context.hwnd,
            reason: reason
        }
    }
    return {
        valid: false,
        open: false,
        convMode: 0,
        converting: 0,
        stale: false,
        timedOut: timedOut,
        capturedTick: A_TickCount,
        hwnd: context.hwnd,
        reason: reason
    }
}

ApplyPendingImeInput(imeSnapshot) {
    global LastTextInputTick, LastHandledTextInputTick
        , LastConversionKeyTick, LastHandledConversionKeyTick, TrackedImeConversionTick
    if !imeSnapshot.valid
        return

    latestTick := 0
    if IsSet(LastTextInputTick)
        && (!IsSet(LastHandledTextInputTick) || LastTextInputTick != LastHandledTextInputTick) {
        latestTick := Max(latestTick, LastTextInputTick)
        LastHandledTextInputTick := LastTextInputTick
    }
    if IsSet(LastConversionKeyTick)
        && (!IsSet(LastHandledConversionKeyTick) || LastConversionKeyTick != LastHandledConversionKeyTick) {
        latestTick := Max(latestTick, LastConversionKeyTick)
        LastHandledConversionKeyTick := LastConversionKeyTick
    }
    if latestTick && A_TickCount - latestTick <= 1000
        && imeSnapshot.open && IsJapaneseImeMode(imeSnapshot.convMode)
        TrackedImeConversionTick := latestTick
}

IsImeConversionActive(imeSnapshot) {
    global ImeConversionHoldMs, ConversionDetectionHoldMs, DetectedImeConversionTick, TrackedImeConversionTick
    if !imeSnapshot.open {  ; IME OFFなら変換は無い。滞留トラッカーを消して即追従へ戻す
        TrackedImeConversionTick := 0
        DetectedImeConversionTick := 0
        return false
    }
    if IsSet(TrackedImeConversionTick) && TrackedImeConversionTick
        && A_TickCount - TrackedImeConversionTick <= ImeConversionHoldMs
        return true

    if imeSnapshot.converting != 0 {
        DetectedImeConversionTick := A_TickCount
        return true
    }

    if IsSet(DetectedImeConversionTick) && DetectedImeConversionTick
        && A_TickCount - DetectedImeConversionTick <= ConversionDetectionHoldMs
        return true
    return false
}

ClearCycleCaches() {
    global CachedFocusedElement, CachedFocusedElementCycle
    CachedFocusedElement := ""
    CachedFocusedElementCycle := -1
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
    global AnchorConfidence, ProvisionalDisplayPolicy, TooltipIdleTimeout
    if anchor.confidence != AnchorConfidence.Fallback
        return true
    if ProvisionalDisplayPolicy = "Show"
        return true
    ; HideUntilInput の場合だけ、最後のキー入力から一定時間後に隠す
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

TryResolveMsaaAnchor(context) {
    global AnchorConfidence, MsaaCircuitOpenUntil, MsaaCircuitSlowCount
        , MsaaCircuitSlowMs, MsaaCircuitBaseCooldownMs, MsaaCircuitMaxCooldownMs
    if A_TickCount < MsaaCircuitOpenUntil
        return CreateAnchorResult(, , , "MSAACaret", AnchorConfidence.Invalid
            , true, "MSAACircuitOpen", , context.hwnd)

    started := PerformanceNow()
    result := CreateAnchorResult(, , , "MSAACaret", AnchorConfidence.Invalid
        , true, "MSAAUnavailable", , context.hwnd)
    try result := TryGetMsaaCaretAnchor(context)
    finally {
        elapsedMs := PerformanceElapsedMs(started)
        UpdateSlowProbeCircuit(&MsaaCircuitOpenUntil, &MsaaCircuitSlowCount
            , elapsedMs, MsaaCircuitSlowMs
            , MsaaCircuitBaseCooldownMs, MsaaCircuitMaxCooldownMs)
        QueueSlowPerformance(context, "MSAA取得", elapsedMs, result.source, false)
    }
    return result
}

UpdateSlowProbeCircuit(&openUntil, &slowCount, elapsedMs
    , slowThresholdMs, baseCooldownMs, maxCooldownMs) {
    if elapsedMs >= slowThresholdMs {
        slowCount := Min(slowCount + 1, 6)
        cooldownMs := Min(maxCooldownMs, baseCooldownMs * (2 ** (slowCount - 1)))
        openUntil := A_TickCount + cooldownMs
        return
    }
    if elapsedMs < slowThresholdMs / 2
        slowCount := 0
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

PrepareAnchorContext(context) {
    global AnchorContextHwnd, AnchorContextFocusHwnd, AnchorProbePending
        , AnchorProbeNotBeforeTick, LastAnchorProbeTick, TooltipAnchorVersion
        , LastGoodAnchor, lastClickScore, lastClickWindow
        , UiaCircuitOpenUntil, UiaCircuitSlowCount
        , MsaaCircuitOpenUntil, MsaaCircuitSlowCount
    if !AnchorContextHwnd {
        AnchorContextHwnd := context.hwnd
        AnchorContextFocusHwnd := context.focusHwnd
        AnchorProbePending := true
        return
    }
    if AnchorContextHwnd = context.hwnd
        && AnchorContextFocusHwnd = context.focusHwnd
        return

    AnchorContextHwnd := context.hwnd
    AnchorContextFocusHwnd := context.focusHwnd
    AnchorProbePending := true
    AnchorProbeNotBeforeTick := 0
    LastAnchorProbeTick := 0
    UiaCircuitOpenUntil := 0
    UiaCircuitSlowCount := 0
    MsaaCircuitOpenUntil := 0
    MsaaCircuitSlowCount := 0
    TooltipAnchorVersion += 1
    LastGoodAnchor := ""
    if IsSet(lastClickWindow) && GetRootWindowHwnd(lastClickWindow) != context.hwnd
        lastClickScore := 0
}

DetectInputContext() {
    global InputContextCacheMs
    static chromiumProcesses := Map(
        "chrome.exe", true,
        "msedge.exe", true,
        "brave.exe", true,
        "chatgpt.exe", true,
        "codex.exe", true)
    static cachedContext := "", cachedTick := 0
    hwnd := WinExist("A")
    threadInfo := GetGuiThreadCaretInfo(hwnd)
    focusHwnd := threadInfo && threadInfo.focusHwnd ? threadInfo.focusHwnd : hwnd
    if IsObject(cachedContext) && cachedContext.hwnd = hwnd
        && cachedContext.focusHwnd = focusHwnd
        && A_TickCount - cachedTick <= InputContextCacheMs
        return cachedContext
    try processName := WinGetProcessName("ahk_id " hwnd)
    catch {
        processName := ""
    }
    try windowClass := WinGetClass("ahk_id " hwnd)
    catch
        windowClass := ""
    rendererHwnd := FindChromiumAncestorHwnd(focusHwnd, hwnd)
    if !rendererHwnd
        rendererHwnd := FindChromiumRendererChildHwnd(hwnd)
    isChromium := chromiumProcesses.Has(StrLower(processName))
        || RegExMatch(windowClass, "i)^Chrome_") || !!rendererHwnd
    cachedContext := {
        hwnd: hwnd,
        focusHwnd: focusHwnd,
        processName: processName,
        windowClass: windowClass,
        rendererHwnd: rendererHwnd,
        isChromium: isChromium,
        allowParentWalk: !isChromium
    }
    cachedTick := A_TickCount
    return cachedContext
}

FindChromiumRendererChildHwnd(rootHwnd) {
    if !rootHwnd
        return 0
    try childWindows := WinGetControlsHwnd("ahk_id " rootHwnd)
    catch
        return 0
    ; 異常に多い子を無制限に走査せず、通常のChromiumウィンドウに十分な上限を設ける
    for childHwnd in childWindows {
        if A_Index > 256
            break
        try childClass := WinGetClass("ahk_id " childHwnd)
        catch
            continue
        if RegExMatch(childClass, "i)^Chrome_RenderWidgetHostHWND\d*$")
            return childHwnd
    }
    return 0
}

FindChromiumAncestorHwnd(focusHwnd, rootHwnd) {
    currentHwnd := focusHwnd
    Loop 8 {
        if !currentHwnd
            break
        try currentClass := WinGetClass("ahk_id " currentHwnd)
        catch
            currentClass := ""
        if RegExMatch(currentClass, "i)^Chrome_RenderWidgetHostHWND\d*$")
            return currentHwnd
        if currentHwnd = rootHwnd
            break
        currentHwnd := DllCall("GetParent", "Ptr", currentHwnd, "Ptr")
    }
    return 0
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
        , AnchorProbePending, LastAnchorProbeTick
    if !context.hwnd
        return CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
            , true, "ActiveWindowUnavailable")

    if CaretGetPos(&caretX, &caretY) {
        AnchorProbePending := false
        CaretPositionIsFallback := false
        return CreateAnchorResult(true, caretX, caretY, "NativeCaret"
            , AnchorConfidence.Exact, false, , , context.hwnd)
    }

    guiThreadAnchor := TryGetGuiThreadCaretAnchor(context)
    if guiThreadAnchor.found {
        AnchorProbePending := false
        return guiThreadAnchor
    }

    if !ShouldRunHeavyAnchorProbe(context)
        return ResolveDeferredAnchor(context, "AnchorProbeDeferred")

    LastAnchorProbeTick := A_TickCount
    msaaAnchor := TryResolveMsaaAnchor(context)
    if msaaAnchor.found {
        AnchorProbePending := false
        return SelectStableAnchor(context, msaaAnchor)
    }

    uiaAnchor := TryResolveUiaAnchor(context)
    AnchorProbePending := msaaAnchor.reason = "MSAACircuitOpen"
        || uiaAnchor.reason = "UIACircuitOpen"
    if AnchorProbePending
        ScheduleAnchorProbeAfterCircuit(msaaAnchor, uiaAnchor)
    if uiaAnchor.reason = "FocusedElementNotEditable" {
        AnchorProbePending := false
        InvalidateStableAnchor(context)
        return uiaAnchor
    }
    if uiaAnchor.found {
        AnchorProbePending := false
        return SelectStableAnchor(context, uiaAnchor)
    }

    stableAnchor := GetReusableAnchor(context, uiaAnchor.reason)
    if stableAnchor.found
        return stableAnchor

    pointerAnchor := TryGetPointerFallbackAnchor(context, uiaAnchor.reason)
    if pointerAnchor.found
        return SelectStableAnchor(context, pointerAnchor)
    return uiaAnchor
}

ScheduleAnchorProbeAfterCircuit(msaaAnchor, uiaAnchor) {
    global AnchorProbeNotBeforeTick, MsaaCircuitOpenUntil, UiaCircuitOpenUntil
    retryTick := 0
    if msaaAnchor.reason = "MSAACircuitOpen"
        retryTick := MsaaCircuitOpenUntil
    if uiaAnchor.reason = "UIACircuitOpen"
        retryTick := retryTick ? Min(retryTick, UiaCircuitOpenUntil) : UiaCircuitOpenUntil
    if retryTick
        AnchorProbeNotBeforeTick := Max(AnchorProbeNotBeforeTick, retryTick)
}

ShouldRunHeavyAnchorProbe(context) {
    global AnchorProbePending, AnchorProbeNotBeforeTick, LastAnchorActivityTick
        , LastAnchorProbeTick, AnchorProbeQuietMs
        , ChromiumAnchorProbeMinIntervalMs, DefaultAnchorProbeMinIntervalMs
    if !AnchorProbePending
        return false
    if A_TickCount < AnchorProbeNotBeforeTick
        return false
    if LastAnchorActivityTick
        && A_TickCount - LastAnchorActivityTick < AnchorProbeQuietMs
        return false
    minInterval := context.isChromium
        ? ChromiumAnchorProbeMinIntervalMs : DefaultAnchorProbeMinIntervalMs
    return !LastAnchorProbeTick
        || A_TickCount - LastAnchorProbeTick >= minInterval
}

ResolveDeferredAnchor(context, reason) {
    stableAnchor := GetReusableAnchor(context, reason)
    if stableAnchor.found
        return stableAnchor
    pointerAnchor := TryGetPointerFallbackAnchor(context, reason)
    if pointerAnchor.found
        return pointerAnchor
    return CreateAnchorResult(, , , "None", "Invalid", true, reason, , context.hwnd)
}

SelectStableAnchor(context, candidate) {
    stableAnchor := GetReusableAnchor(context, "LowerConfidenceCandidate")
    if !stableAnchor.found || GetAnchorConfidenceRank(candidate.confidence)
        >= GetAnchorConfidenceRank(stableAnchor.confidence)
        return candidate
    return stableAnchor
}

GetAnchorConfidenceRank(confidence) {
    global AnchorConfidence
    if confidence = AnchorConfidence.Exact
        return 3
    if confidence = AnchorConfidence.Estimated
        return 2
    if confidence = AnchorConfidence.Fallback
        return 1
    return 0
}

InvalidateStableAnchor(context) {
    global LastGoodAnchor
    if IsSet(LastGoodAnchor) && IsObject(LastGoodAnchor)
        && LastGoodAnchor.hwnd = context.hwnd
        LastGoodAnchor := ""
}

TryGetPointerFallbackAnchor(context, reason := "AnchorUnavailable") {
    global AnchorConfidence, CaretPositionIsFallback
        , lastClickX, lastClickY, lastClickWindow
    if GetRecentClickEvidence() && IsSet(lastClickX) && IsSet(lastClickY)
        && GetRootWindowHwnd(lastClickWindow) = context.hwnd {
        CaretPositionIsFallback := true
        return CreateAnchorResult(true, lastClickX, lastClickY
            , "RecentClickFallback", AnchorConfidence.Fallback, true
            , reason, , context.hwnd)
    }

    return CreateAnchorResult(, , , "PointerFallback", AnchorConfidence.Invalid
        , true, "RecentClickUnavailable", , context.hwnd)
}

GetRootWindowHwnd(hwnd) {
    if !hwnd
        return 0
    rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") ; GA_ROOT
    return rootHwnd ? rootHwnd : hwnd
}

TryResolveUiaAnchor(context) {
    global AnchorConfidence, CaretPositionIsFallback, EditableScoreThreshold
        , LastUIASource, LastUIAConfidence, LastUIADepth, LastUIAReason
        , UiaCircuitOpenUntil, UiaCircuitSlowMs, UiaCircuitSlowCount
        , UiaCircuitBaseCooldownMs, UiaCircuitMaxCooldownMs
    if A_TickCount < UiaCircuitOpenUntil
        return CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
            , true, "UIACircuitOpen", , context.hwnd)

    started := PerformanceNow()
    result := CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
        , true, "FocusedElementUnavailable", , context.hwnd)
    try {
        focusedElement := GetFocusedElementCached()
        if focusedElement {
            runtimeId := GetElementRuntimeId(focusedElement)
            editScore := GetUIAEditScore(focusedElement, false, context)
            UpdateRecentClickEvidenceFromFocusedElement(context, editScore)
            if editScore < EditableScoreThreshold {
                result := CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
                    , true, "FocusedElementNotEditable", , context.hwnd, runtimeId)
            } else if GetUIACaretPos(focusedElement, &caretX, &caretY, context) {
                result := CreateAnchorResult(true, caretX, caretY
                    , LastUIASource, LastUIAConfidence, CaretPositionIsFallback
                    , LastUIAReason, LastUIADepth, context.hwnd, runtimeId)
            } else {
                result := CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
                    , true, LastUIAReason != "" ? LastUIAReason : "AnchorUnavailable"
                    , LastUIADepth, context.hwnd, runtimeId)
            }
        }
    } catch {
        result := CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
            , true, "FocusedElementUnavailable", , context.hwnd)
    } finally {
        elapsedMs := PerformanceElapsedMs(started)
        UpdateSlowProbeCircuit(&UiaCircuitOpenUntil, &UiaCircuitSlowCount
            , elapsedMs, UiaCircuitSlowMs
            , UiaCircuitBaseCooldownMs, UiaCircuitMaxCooldownMs)
        QueueSlowPerformance(context, "UIA取得", elapsedMs, result.source, false)
    }
    return result
}

UpdateRecentClickEvidenceFromFocusedElement(context, editScore) {
    global EditableScoreThreshold, lastClickScore, lastClickTick, lastClickWindow
    if !IsSet(lastClickTick) || A_TickCount - lastClickTick > 300000
        return
    if !IsSet(lastClickWindow)
        return
    if GetRootWindowHwnd(lastClickWindow) != context.hwnd
        return
    lastClickScore := editScore >= EditableScoreThreshold ? editScore : 0
}

RememberGoodAnchor(anchor, context) {
    global LastGoodAnchor, TooltipAnchorVersion
    if anchor.source = "CachedAnchor"
        return
    if IsSet(LastGoodAnchor) && IsObject(LastGoodAnchor)
        && LastGoodAnchor.hwnd = context.hwnd
        && LastGoodAnchor.focusHwnd = context.focusHwnd
        && LastGoodAnchor.anchorVersion = TooltipAnchorVersion
        && GetAnchorConfidenceRank(anchor.confidence)
            < GetAnchorConfidenceRank(LastGoodAnchor.confidence)
        return
    LastGoodAnchor := {
        x: anchor.x,
        y: anchor.y,
        source: anchor.source,
        confidence: anchor.confidence,
        isFallback: anchor.isFallback,
        reason: anchor.reason,
        runtimeId: anchor.runtimeId,
        hwnd: context.hwnd,
        focusHwnd: context.focusHwnd,
        anchorVersion: TooltipAnchorVersion,
        capturedTick: A_TickCount
    }
}

GetReusableAnchor(context, reason) {
    global AnchorConfidence, LastGoodAnchor, TooltipAnchorVersion
    if IsSet(LastGoodAnchor) && IsObject(LastGoodAnchor)
        && LastGoodAnchor.hwnd = context.hwnd
        && LastGoodAnchor.focusHwnd = context.focusHwnd
        && LastGoodAnchor.anchorVersion = TooltipAnchorVersion {
        return CreateAnchorResult(true, LastGoodAnchor.x, LastGoodAnchor.y
            , "CachedAnchor", LastGoodAnchor.confidence, LastGoodAnchor.isFallback
            , reason, , context.hwnd, LastGoodAnchor.runtimeId)
    }
    return CreateAnchorResult(, , , "None", AnchorConfidence.Invalid
        , true, reason, , context.hwnd)
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
    if GetUIAElementFallbackPos(element, &caretX, &caretY, &fallbackSource) {
        LastUIASource := fallbackSource
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
            if isActive
                && (GetTextRangeCaretPos(caretRange, &caretX, &caretY)
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
                if (GetTextRangeCaretPos(selectionRange, &caretX, &caretY)
                    || GetDegenerateRangeCaretPos(selectionRange, &caretX, &caretY)) {
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

GetUIAElementFallbackPos(element, &caretX, &caretY, &source) {
    global lastClickX, lastClickY, CaretPositionIsFallback
    source := "UIAFallback"
    ; 空欄のEdit/ComboBoxはキャレットが左端。クリック位置ではなく入力欄左端を基準にして安定させる
    if IsUIAEmptyInputField(element) {
        try {
            rectangle := element.BoundingRectangle
            if rectangle.r > rectangle.l && rectangle.b > rectangle.t {
                caretX := rectangle.l + 8
                caretY := rectangle.t + Floor((rectangle.b - rectangle.t) / 2)
                source := "UIAEmptyInputField"
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

GetImeModeDisplay(imeSnapshot) {
    global IndicatorColorAlphanumeric, IndicatorColorJapanese
        , IndicatorColorHalfKatakana, IndicatorColorFullAlphanumeric
        , IndicatorColorUnknown
    if !imeSnapshot.open
        return {text: "A", color: IndicatorColorAlphanumeric}

    switch imeSnapshot.convMode {
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
