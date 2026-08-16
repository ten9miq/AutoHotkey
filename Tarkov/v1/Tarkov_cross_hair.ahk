#Persistent  ; スクリプトを常に実行状態にする

; 赤点を表示するウィンドウのタイトルまたは一部のタイトルを指定します
WindowTitle := "EscapeFromTarkov"

; オフセットを設定（ウィンドウ中央からの調整値）
OffsetX := -5  ; 水平方向のオフセット →20 ~2025/02/01
OffsetY := 20  ; 垂直方向のオフセット →40 ~2025/02/01

SetTimer, UpdateOverlay, 1000  ; 1000msごとにオーバーレイを更新する ウィンドウが移動した場合への追従に影響、フレームレスウィンドウで全画面であるなら遅くてよし

; GUI設定
Gui, +AlwaysOnTop +ToolWindow -Caption +E0x20 +OwnDialogs ; オーバーレイ設定
Gui, Color, FF0000 ; 背景色を赤に設定
Gui, Show, w2 h2 NoActivate ; 幅, 高さ3pxのウィンドウを表示
Gui, +LastFound +OwnDialogs
WinSet, ExStyle, +0x20, A ; マウスを通過させる
DllCall("SetWindowLong", UInt, WinExist(), Int, -20, UInt, DllCall("GetWindowLong", UInt, WinExist(), Int, -20) | 0x80000 | 0x20) ; クリックを透過

UpdateOverlay:
    ; 指定したウィンドウのハンドルを取得
    WinGet, hWnd, ID, %WindowTitle%
    
    ; ウィンドウが存在するか確認
    if !hWnd
    {
        Gui, Hide  ; ウィンドウが存在しない場合、オーバーレイを非表示にする
        return
    }

    ; ウィンドウの位置とサイズを取得
    WinGetPos, X, Y, Width, Height, ahk_id %hWnd%

    ; ウィンドウの中央の位置を計算し、オフセットを適用
    CenterX := X + (Width / 2) - 2 + OffsetX ; 中心から半分の幅を引いた位置にオフセットを適用
    CenterY := Y + (Height / 2) - 2 + OffsetY ; 中心から半分の高さを引いた位置にオフセットを適用

    ; オーバーレイを中央に移動して再表示
    Gui, Show, x%CenterX% y%CenterY% NoActivate
return
