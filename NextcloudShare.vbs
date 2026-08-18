Option Explicit

Dim shell, fso, scriptDir, psScript, mode, quote
Dim dataRoot, logPath, logFile, canLog
Dim selectedPath, selectedName, command, launchResult
Dim launchErrorNumber, launchErrorDescription, argumentIndex
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = fso.BuildPath(scriptDir, "NextcloudShare.ps1")
quote = Chr(34)

If WScript.Arguments.Count < 1 Then
    mode = "Configure"
Else
    mode = WScript.Arguments(0)
End If

dataRoot = fso.BuildPath(shell.ExpandEnvironmentStrings("%LOCALAPPDATA%"), "NextcloudShare")
On Error Resume Next
If Not fso.FolderExists(dataRoot) Then fso.CreateFolder(dataRoot)
Err.Clear
logPath = fso.BuildPath(dataRoot, "NextcloudShare.log")
canLog = False
Set logFile = fso.OpenTextFile(logPath, 8, True)
If Err.Number = 0 Then
    canLog = True
    logFile.Close
End If
Err.Clear

If WScript.Arguments.Count < 2 Then
    LaunchPowerShell ""
Else
    ' Einige Explorer-Versionen starten das Verb einmal je Datei, andere koennen
    ' mehrere Pfade uebergeben. Jeder Pfad wird einheitlich an die Sammellogik
    ' in NextcloudShare.ps1 weitergereicht.
    For argumentIndex = 1 To WScript.Arguments.Count - 1
        LaunchPowerShell WScript.Arguments(argumentIndex)
    Next
End If
On Error GoTo 0

Sub LaunchPowerShell(ByVal pathValue)
    selectedPath = pathValue
    command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File " & quote & psScript & quote & _
              " -Mode " & quote & mode & quote
    If selectedPath <> "" Then
        command = command & " -Path " & quote & selectedPath & quote
    End If

    selectedName = ""
    If selectedPath <> "" Then selectedName = fso.GetFileName(selectedPath)
    If canLog Then
        Set logFile = fso.OpenTextFile(logPath, 8, True)
        If Err.Number = 0 Then
            logFile.WriteLine CStr(Now) & " Launcher: Start; Mode=" & mode & "; Datei=" & selectedName
            logFile.Close
        End If
        Err.Clear
    End If

    launchResult = shell.Run(command, 0, False)
    launchErrorNumber = Err.Number
    launchErrorDescription = Err.Description
    Err.Clear
    If canLog Then
        Set logFile = fso.OpenTextFile(logPath, 8, True)
        If Err.Number = 0 Then
            If launchErrorNumber <> 0 Then
                logFile.WriteLine CStr(Now) & " Launcher: FEHLER " & CStr(launchErrorNumber) & ": " & launchErrorDescription
            Else
                logFile.WriteLine CStr(Now) & " Launcher: PowerShell gestartet. Rueckgabewert=" & CStr(launchResult)
            End If
            logFile.Close
        End If
        Err.Clear
    End If
End Sub
