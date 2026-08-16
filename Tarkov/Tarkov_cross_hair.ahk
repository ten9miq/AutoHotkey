; AutoHotkey v2.0

#Requires AutoHotkey v2.0

; 赤点を表示するウィンドウのタイトルまたは一部のタイトルを指定します
windowTitle := "EscapeFromTarkov"

; オフセットを設定（ウィンドウ中央からの調整値）
offsetX := -5  ; 水平方向のオフセット →20 ~2025/02/01
offsetY := 20  ; 垂直方向のオフセット →40 ~2025/02/01

; GUI設定
overlayGui := Gui("+AlwaysOnTop +ToolWindow -Caption +OwnDialogs")
overlayGui.BackColor := "FF0000"  ; 背景色を赤に設定
overlayGui.Show("w2 h2 NoActivate")  ; 幅、高さ2pxのウィンドウを表示
WinSetExStyle("+0x80020", "ahk_id " overlayGui.Hwnd)  ; クリックを透過

; 1000msごとにオーバーレイを更新する
SetTimer(UpdateOverlay, 1000)

UpdateOverlay() {
    global windowTitle, offsetX, offsetY, overlayGui

    ; 指定したウィンドウのハンドルを取得
    hWnd := WinExist(windowTitle)

    ; ウィンドウが存在するか確認
    if !hWnd {
        overlayGui.Hide()  ; ウィンドウが存在しない場合、オーバーレイを非表示にする
        return
    }

    ; ウィンドウの位置とサイズを取得
    WinGetPos(&x, &y, &width, &height, "ahk_id " hWnd)

    ; ウィンドウの中央の位置を計算し、オフセットを適用
    centerX := x + (width / 2) - 2 + offsetX  ; 中心から半分の幅を引いた位置にオフセットを適用
    centerY := y + (height / 2) - 2 + offsetY  ; 中心から半分の高さを引いた位置にオフセットを適用

    ; オーバーレイを中央に移動して再表示
    overlayGui.Show("x" centerX " y" centerY " NoActivate")
}
