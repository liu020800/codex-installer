Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
bat = fso.BuildPath(base, "install.bat")
If Not fso.FileExists(bat) Then
  MsgBox "???? install.bat??????? zip?????????????", 16, "???????"
Else
  shell.Run """" & bat & """", 1, False
End If
