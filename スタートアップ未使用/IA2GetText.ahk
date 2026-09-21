#Requires AutoHotkey v2.0

IA2_GetTextInterface(pAcc)
{
    static IID_IAccessible :=
        "{618736E0-3C3D-11CF-810C-00AA00389B71}"

    static IID_IAccessible2 :=
        "{E89F726E-C4F4-4C19-BB19-B647D7FA8478}"

    static IID_IAccessibleText :=
        "{24FD2FFB-3AAD-4A08-8335-A3AD89C0FB4B}"

    ; IAccessible
    ;   ↓ IServiceProvider::QueryService
    ; IAccessible2
    ia2 := ComObjQuery(
        pAcc,
        IID_IAccessible,
        IID_IAccessible2
    )

    ; IAccessible2
    ;   ↓ IUnknown::QueryInterface
    ; IAccessibleText
    text := ComObjQuery(
        ia2,
        IID_IAccessibleText
    )

    return text
}