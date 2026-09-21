#Requires AutoHotkey v2.0
#SingleInstance Force

bravePath := '"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"'

; RealForce Fn+F1: ブラウザ
>+F1:: Run(bravePath)

; RealForce Fn+F2: メール
>+F2::Run "mailto:"
; RealForce Fn+F3: 電卓
>+F3::Run "calc.exe"
; 戻る
$>!Left::Click "X1"
; 進む
$>!Right::Click "X2"

