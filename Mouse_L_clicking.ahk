; AutoHotkey v2.0

; Amazonの特定ページでのみ左クリック連打を有効化（無効）
;#HotIf WinActive("Amazon Vine 先取りプログラム ahk_class Chrome_WidgetWin_1")
;~$LButton::{
;    if !KeyWait("LButton", "T0.3") {
;        while GetKeyState("LButton", "P") {
;            Click()
;            Sleep(50)
;        }
;    }
;}
;#HotIf

#Requires AutoHotkey v2.0
#SingleInstance Force

toggle := false

; F15キーでどこでも連打機能を有効化
F15::{
    global toggle

    toggle := !toggle
    clickCount := 0
    startTime := A_TickCount

    while toggle {
        Click()
        clickCount++

        ; 基本的なクリック間隔（秒間約7-8回で開始）
        baseInterval := 95 + (clickCount // 200) * 5  ; 200回ごとに基本間隔を5ms増加
        sleepTime := Random(baseInterval - 5, baseInterval + 5)

        ; 変動を加える
        sleepTime += Random(-3, 3)

        ; 時々、少し長めの間隔を入れる（疲労や注意散漫を模倣）
        if Mod(clickCount, 30) = 0
            sleepTime += Random(20, 50)

        ; 非常に稀に、長い休止を入れる（短い休憩を模倣）
        if Mod(clickCount, 200) = 0
            sleepTime += Random(200, 500)

        ; 時間経過に応じて徐々に速度を落とす（疲労を模倣）
        elapsedMinutes := (A_TickCount - startTime) / 60000
        fatigueFactor := Floor(elapsedMinutes / 3)  ; 3分ごとに疲労度が増加
        sleepTime += fatigueFactor * 2

        ; 最小間隔を設定して、不自然に速くならないようにする
        sleepTime := Max(sleepTime, 90)

        Sleep(sleepTime)
    }
}

F15 Up::{
    global toggle
    toggle := false
}
