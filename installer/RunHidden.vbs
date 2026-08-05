Option Explicit

Dim shell
Dim fso
Dim powerShellPath
Dim defaultPowerShell7Path
Dim windowsPowerShellPath
Dim scriptPath
Dim commandLine

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

Function FindOnPath(fileName)
    Dim pathValue
    Dim folders
    Dim folder
    Dim candidate

    pathValue = shell.ExpandEnvironmentStrings("%PATH%")
    folders = Split(pathValue, ";")

    For Each folder In folders
        folder = Trim(Replace(folder, """", ""))

        If Len(folder) > 0 Then
            candidate = fso.BuildPath(folder, fileName)

            If fso.FileExists(candidate) Then
                FindOnPath = candidate
                Exit Function
            End If
        End If
    Next

    FindOnPath = ""
End Function

powerShellPath = FindOnPath("pwsh.exe")

defaultPowerShell7Path = _
    shell.ExpandEnvironmentStrings("%ProgramFiles%") & _
    "\PowerShell\7\pwsh.exe"

If Len(powerShellPath) = 0 Then
    If fso.FileExists(defaultPowerShell7Path) Then
        powerShellPath = defaultPowerShell7Path
    End If
End If

windowsPowerShellPath = _
    shell.ExpandEnvironmentStrings("%SystemRoot%") & _
    "\System32\WindowsPowerShell\v1.0\powershell.exe"

If Len(powerShellPath) = 0 Then
    If fso.FileExists(windowsPowerShellPath) Then
        powerShellPath = windowsPowerShellPath
    End If
End If

If Len(powerShellPath) = 0 Then
    WScript.Quit 1
End If

scriptPath = fso.BuildPath( _
    fso.GetParentFolderName(WScript.ScriptFullName), _
    "CK3WorkshopAutoUpdater.ps1" _
)

commandLine = _
    """" & powerShellPath & _
    """ -NoProfile -ExecutionPolicy Bypass -File """ & _
    scriptPath & _
    """"

shell.Run commandLine, 0, False

Set fso = Nothing
Set shell = Nothing
