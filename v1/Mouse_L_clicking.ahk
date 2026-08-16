;SetTitleMatchMode, 2  ; タイトルの部分一致を有効にする

; Amazonの特定ページでのみ左クリック連打を有効化
;#If WinActive("Amazon Vine 先取りプログラム ahk_class Chrome_WidgetWin_1")
;    ~$LButton::
;        KeyWait LButton, T0.3
;        If ErrorLevel
;            While GetKeyState("LButton", "P") {
;                Click
;                Sleep 50
;            }
;    return
;#If

; F15キーでどこでも連打機能を有効化
F15::
    Toggle := !Toggle
    clickCount := 0
    startTime := A_TickCount
    
    While (Toggle) {
        Click
        clickCount++
        
        ; 基本的なクリック間隔（秒間約7-8回で開始）
        baseInterval := 95 + (clickCount // 200) * 5  ; 200回ごとに基本間隔を5ms増加
        Random, sleepTime, baseInterval - 5, baseInterval + 5
        
        ; 変動を加える
        Random, variation, -3, 3
        sleepTime += variation
        
        ; 時々、少し長めの間隔を入れる（疲労や注意散漫を模倣）
        if (Mod(clickCount, 30) = 0) {
            Random, extraSleep, 20, 50
            sleepTime += extraSleep
        }
        
        ; 非常に稀に、長い休止を入れる（短い休憩を模倣）
        if (Mod(clickCount, 200) = 0) {
            Random, longPause, 200, 500
            sleepTime += longPause
        }
        
        ; 時間経過に応じて徐々に速度を落とす（疲労を模倣）
        elapsedMinutes := (A_TickCount - startTime) / 60000
        fatigueFactor := Floor(elapsedMinutes / 3)  ; 3分ごとに疲労度が増加
        sleepTime += fatigueFactor * 2
        
        ; 最小間隔を設定して、不自然に速くならないようにする
        sleepTime := Max(sleepTime, 90)
        
        Sleep %sleepTime%
    }
return

F15 Up::
    Toggle := false
return
