# AdminPad
Application launch pad (to be run as admin or other users)

![image](https://github.com/therksius/AdminPad/assets/52346746/b2ec539e-31c6-4489-9512-d5b4da17ea74)

## Version history

### 3.2.0.0
- Separated FileBrowser into it's own application.
  This will reduce issues with loading resource heavy folders and stalling AdminPad.
- Added some utility variables/checks ($COMPILED, $SCRIPTDIR, etc).
- Changed the Quick Apps to Shortcuts:
  - Shortcuts in %APPDATA%\AdminPad\Shortcuts are loaded to create buttons.
  - This folder is monitored and buttons are refreshed automatically (1/sec)
  - The Add Shortcut button uses the built-in Windows New Shortcut dialog to create Shortcuts.
- Changed ToolTip object+methods into separated functions.
- Changed the command run method. Now using WScript.Shell > Run method.
- Changed all usage of ExtractAssociatedIcon to Icon-FromFilePath (function using SHGetFileInfo)
  The previous function was not compatible with UNC paths and would throw an error.
- Added a clickable link for the update notes in the status bar. (Hi!)

### 3.1.0.2
- Added resize func invoke to add_Load to hide scrollbars on startup.

### 3.1.0.1
- Fixed "Browse & Fill" button.
