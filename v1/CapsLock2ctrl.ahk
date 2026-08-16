#UseHook
#InstallKeybdHook
SetCapsLockState, AlwaysOff

; CapsLock をプレフィックス化（Shift/Alt/Win 等と一緒でも発火）
*SC03A::Gosub, __CapsHandler
return

__CapsHandler:
    ; 次の1キーを拾う（基本は EndKey で終了＆そのキーは抑制）
    ih := InputHook("L1 T0.8")
    ih.KeyOpt("{All}", "ES")  ; E=EndKey, S=Suppress

    ; 修飾キーは「終端にしない」＆「抑制しない」
    ; → Alt/Shift/Win は OS 側に通して “押されている状態” を維持させる
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E")
    ih.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-S")

    ih.Start()
    ih.Wait()

    if (ih.EndReason = "Timeout" || ih.EndReason = "Stopped")
        return

    k := ih.EndKey
    if (k = "")
        return

    ; 万一、終端が修飾キーだったら無視（保険）
    if (k ~= "i)^(LCtrl|RCtrl|LAlt|RAlt|LShift|RShift|LWin|RWin)$")
        return

    ; Ctrlだけ付与。Alt/Shift/Win は {Blind} が「物理状態」を反映してくれる
    if (StrLen(k) = 1)
        SendInput, % "{Blind}^" . k
    else
        SendInput, % "{Blind}^{" . k . "}"
return
