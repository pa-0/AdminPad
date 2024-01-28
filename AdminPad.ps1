# set-PSDebug -Trace 2
#region CONSTANTS, ASSEMBLIES & GLOBALS ##########################################################################################
	Add-Type -AssemblyName PresentationFramework, System.Drawing, System.Windows.Forms
	[Windows.Forms.Application]::EnableVisualStyles()

	$VERSION = '3.2.0.0'
	$UPDATE_NOTES = @'
Updates:
3.2.0.0
- Separated FileBrowser into it's own application.
  This will reduce issues with loading resource heavy folders and stalling AdminPad.
- Added some utility variables/checks ($COMPILED, $SCRIPTDIR, etc).
- Changed the Quick Apps to Shortcuts:
  > Shortcuts in %APPDATA%\AdminPad\Shortcuts are loaded to create buttons.
  > This folder is monitored and buttons are refreshed automatically (1/sec)
  > The Add Shortcut button uses the built-in Windows New Shortcut dialog to create Shortcuts.
- Changed ToolTip object+methods into separated functions.
- Changed the command run method. Now using WScript.Shell > Run method.
- Changed all usage of ExtractAssociatedIcon to Icon-FromFilePath (function using SHGetFileInfo)
  The previous function was not compatible with UNC paths and would throw an error.
- Added a clickable link for the update notes in the status bar. (Hi!)
3.1.0.2
- Added resize func invoke to add_Load to hide scrollbars on startup.
3.1.0.1
- Fixed "Browse & Fill" button.
'@

	$APPNAME = "AdminPad"
	$ZWSP =  [char]0x200B # zero width space
	$NBSP =  [char]160 # non-breaking space
	$RELOAD_CHAR = [char]0x27F3

	If ($PSCommandPath) {
		$COMPILED = $False
		$SCRIPTFILEPATH = $PSCommandPath
	} Else {
		$COMPILED = $True
		$SCRIPTFILEPATH = (Get-Process -id $PID).Path
	}
	$SCRIPTDIR = Split-Path $SCRIPTFILEPATH

	$WSHSHELL = New-Object -ComObject WScript.Shell
	$SHELLAPP = New-Object -ComObject Shell.Application
	$SHORTCUTSDIR = "$ENV:appdata\$APPNAME\Shortcuts"
	$SHORTCUTS_DEFAULT = @(
		@{ path=(Get-Command Powershell).Path;           text='1.Powershell'; title='Powershell'},
		@{ path="$ENV:comspec";                          text='2.Cmd Prompt'; title='Command Prompt' },
		@{ path="$ENV:SystemRoot\regedit.exe";           text='3.RegEdit';    title='Registry Editor' },
		@{ path="$ENV:SystemRoot\system32\devmgmt.msc";  text='4.Dev Mgr';    title='Device Manager' },
		@{ path="$ENV:SystemRoot\system32\sysdm.cpl";    text='5.System';     title='Advanced System Settings' },
		@{ path="$ENV:SystemRoot\system32\taskmgr.exe";  text='6.Task Mgr';   title='Task Manager' }
	)

	$CmdHistory_File = "$ENV:appdata\$APPNAME\History.txt"
	$CmdHistory_List = [Collections.ArrayList]{
		If (Test-Path $CmdHistory_File) {
			@(Get-Content $CmdHistory_File | Foreach-Object {$_.trim()}) -ne ''
		} Else {
			@()
		}
	}.Invoke()

	$FolderBrowserDialog = New-Object Windows.Forms.FolderBrowserDialog -Property @{ Description = 'Select folder' }
#endregion CONSTANTS, ASSEMBLIES & GLOBALS ##########################################################################################

#region COMPILE PROMPT ##########################################################################################
	If (!$COMPILED) {
		Write-Host "Enter `"C`" to compile. | Any other input to test run."
		$CompileAsk = Read-Host -Prompt "Enter"
		Clear-Host
		If ($CompileAsk -eq 'C') {
			$CompilerModule = 'PS2EXE'

			If (!(Get-Module $CompilerModule)) { # module is not imported
				Write-Host "$CompilerModule module not imported."
				If (!(Get-Module -ListAvailable $CompilerModule)) { # module is not available
					Write-Host "$CompilerModule module not available. Searching online gallery..."
					If (Find-Module -Name $CompilerModule -ErrorAction:SilentlyContinue) {
						Write-Host "$CompilerModule found. Downloading..."
						Install-Module -Name $CompilerModule -Force -Verbose -Scope CurrentUser
					} Else {
						Write-Host "Cannot find module: $CompilerModule."
						Write-Host "Script will exit now."
						Pause
						Exit
					}
				}
				Write-Host "Importing $CompilerModule module."
				Import-Module $CompilerModule -Verbose
			}
			Write-Host "Compiling..."

			Invoke-ps2exe -inputFile $SCRIPTFILEPATH -iconFile "$SCRIPTDIR\AdminPad.ico" `
				-noConfigFile -noConsole -noOutput -requireAdmin `
				-product $APPNAME -version $VERSION -title $APPNAME `
				-company 'therkSoft' -copyright 'Rob Saunders'

			Read-Host "Press enter to launch application"
			Start-Process "$SCRIPTDIR\AdminPad.exe"
			Exit
		}
	}
#endregion COMPILE PROMPT ##########################################################################################

#region REGISTRY SETUP ##########################################################################################
	$REGKEY = "Registry::HKCU\Software\$APPNAME"
	If (!(Test-Path -Path $REGKEY)) { New-Item -Path $REGKEY -Force | Out-Null }
	$REGKEY = Get-Item $REGKEY
#endregion REGISTRY SETUP ##########################################################################################

#region FUNCTIONS ##########################################################################################
	Function Icon-Extract {
		Param($Path, $Index, [Switch]$LargeIcon)
		$IconExtract = Add-Type -Name IconExtract -MemberDefinition '
			[DllImport("Shell32.dll", SetLastError=true)]
			public static extern int ExtractIconEx(string lpszFile, int nIconIndex, out IntPtr phiconLarge, out IntPtr phiconSmall, int nIcons);
		' -PassThru

		#Initialize variables for reference conversion
		$IconLarge, $IconSmall = 0, 0

		#Call Win32 API Function for handles
		If ($IconExtract::ExtractIconEx($Path, $Index, [ref]$IconLarge, [ref]$IconSmall, 1)) {
			[System.Drawing.Icon]::FromHandle( $( If ($LargeIcon) { $IconLarge } Else { $IconSmall } ) )
		}
	}

	Function Icon-FromFilePath {
		Param($FilePath, [Switch]$LargeIcon)

		Add-Type -TypeDefinition '
			using System;
			using System.Drawing;
			using System.Runtime.InteropServices;

			public class IconFromFilePath
			{
				[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
				public struct SHFILEINFO
				{
					public IntPtr hIcon;
					public int iIcon;
					public uint dwAttributes;
					[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
					public string szDisplayName;
					[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
					public string szTypeName;
				}

				[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
				public static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbSizeFileInfo, uint uFlags);
			}
		'

		$Flags = 0x100
		If (!$LargeIcon) { $Flags += 0x1 }  # Add SHGFI_SMALLICON flag if not requesting a large icon

		$FileInfoStruct = New-Object IconFromFilePath+SHFILEINFO
		$StructSize = [System.Runtime.InteropServices.Marshal]::SizeOf($FileInfoStruct)

		[void][IconFromFilePath]::SHGetFileInfo($FilePath, 0, [ref]$FileInfoStruct, $StructSize, $Flags)
		[System.Drawing.Icon]::FromHandle($FileInfoStruct.hIcon)
	}

	# MsgBox shortcut
	Function MsgBox($Message, $Buttons = 0, $Icon = 0, $Default = 0) {
		# $Buttons: OK, OKCancel, AbortRetryIgnore, YesNoCancel, YesNo, RetryCancel
		# $Icon: None, Info, Warn, Error
		# $DefaultIndex: 0, 1, 2
		Return [Windows.MessageBox]::Show($Message, $APPNAME, $Buttons, $Icon, $Default).ToString()
	}

	# Properties Dialog
	Function PropertiesDialog($FilePath) {
		If (Test-Path $FilePath) {
			If ((Get-Item $FilePath).GetType().Name -eq 'DirectoryInfo') {
				$Folder = $SHELLAPP.NameSpace($FilePath)
				$Folder.Self.InvokeVerb("Properties")
			} Else {
				$Folder = Split-Path $FilePath
				$File = Split-Path $FilePath -Leaf
				$Folder = $SHELLAPP.NameSpace($Folder)
				$File = $Folder.ParseName($File)
				$File.InvokeVerb("Properties")
			}
		}
	}

	# Iterate shortcut list for select control
	Function Get-ShortcutItem($SourceCtrl) {
		Foreach ($Item in $global:Shortcuts_List) {
			If ($Item.Control -eq $SourceCtrl) {
				Return $Item
			}
		}
	}

	# Multi-use exit function
	Function AdminPad-Exit() {
		$fm_Main.Hide()

		# Store the history list in file
		$CmdHistory_List -Join "`r`n" | Out-File -FilePath (New-Item -Path $CmdHistory_File -Force) -NoNewLine

		$AppContext.ExitThread()

		Stop-Process $PID # Kill the process
	}

	# ToolTip functions
	Function ToolTip-Popup {
		param ($Text, $Control, $X, $Y, $Time, $IsBalloon = $True)
		$ToolTip = New-Object Windows.Forms.ToolTip -Property @{ IsBalloon = $IsBalloon }
		$ToolTip.SetToolTip($Control, ' ')
		$ToolTip.Show($Text, $Control, $X, $Y, $Time)
		$ToolTip.add_popup({ $this.dispose() })
	}

	Function ToolTip-Set {
		param ($Control, $Text, $IsBalloon = $False)
		$ToolTip = New-Object Windows.Forms.ToolTip -Property @{ IsBalloon = $IsBalloon }
		$ToolTip.SetToolTip($Control, $Text)
	}

	Function Load-Shortcuts {
		If (!(Test-Path $SHORTCUTSDIR)) {
			New-Item -ItemType Directory -Path $SHORTCUTSDIR
			Foreach ($Item in $SHORTCUTS_DEFAULT) {
				$Shortcut = $WSHSHELL.CreateShortcut("$SHORTCUTSDIR\$($Item.text).lnk")
				$Shortcut.TargetPath = $Item.path
				$Shortcut.Description = $Item.title
				$Shortcut.Save()
			}
		}

		# Create ArrayList to access .Add and .Remove methods
		$global:Shortcuts_List = [Collections.ArrayList]@()
		If ($FolderRead = Get-ChildItem -Filter "*.lnk" -Path $SHORTCUTSDIR -EA 0 | Sort-Object Name) {
			# Define Temp hashtable, when all path+text+title properties are set, add as new item to the button list
			$Temp = @{}
			$FolderRead | Foreach-Object {
				$ReadShortcut = $WSHSHELL.CreateShortcut($_.FullName)
				$Temp.path = $_.FullName
				$Temp.text = $_.Name -replace '\.lnk$',''
				$Temp.title = $ReadShortcut.Description
				If ($Temp.path -and $Temp.text) {
					If (!$Temp.title) { $Temp.title = $Temp.text }
					$null = $global:Shortcuts_List.Add($Temp)
					$Temp = @{}
				}
			}
		}

		$global:ShortcutsChecksum = $FolderRead | Select-Object Name, LastWriteTime | ConvertTo-Json

		# Clear panel of controls
		$pn_Shortcuts.Controls.Clear()
		# Iterate the list and create all the panel buttons
		$ButtonOffset = 0
		Foreach ($Item in $global:Shortcuts_List) {
			# Test if Path is valid before creating button. If path is invalid, button will be skipped
			If (Test-Path $Item.path) {
				$pn_Shortcuts.Controls.Add(($bt_Temp = New-Object Windows.Forms.Button -Property @{
					Image = Icon-FromFilePath $Item.path -LargeIcon
					TextImageRelation = 'ImageAboveText'
					ImageAlign = 'MiddleCenter'
					TextAlign = 'MiddleCenter'
					Anchor = 'Top,Left'
					Text = $Item.text -replace '^[0-9]+\.','' # Strip number prefix to allow sorting of buttons
					Tag = @{AppPath = $Item.Path}
					Bounds = "$ButtonOffset,0,80,60"
					add_Click = { Start-Process $this.Tag.AppPath }
					ContextMenu = $cm_ShortcutItemsMenu
				}))
				$Item.time = (Get-Item $Item.path).LastWriteTime
				$ButtonOffset += 85

				ToolTip-Set $bt_Temp $Item.title

				$Item.Control = $bt_Temp
			}
		}

		# Create button for new shortcuts
		$pn_Shortcuts.Controls.Add(($global:bt_AddShortcut = New-Object Windows.Forms.Button -Property @{
			Bounds = "$ButtonOffset,0,20,60"
			Text = "+"
			add_Click = {
				New-Item -Path "$SHORTCUTSDIR\placeholder.tmp" -Force
				rundll32.exe appwiz.cpl,NewLinkHere $SHORTCUTSDIR\placeholder.tmp
			}
			ContextMenu = $cm_ShortcutItemsMenu
		}))
		ToolTip-Set $bt_AddShortcut 'Add Shortcut'

		ShortcutPanel-HideScroller
	}

	# Run commands, check if valid, save to history
	Function Run-Command($Command) {
		$CommandRun = try { $WSHSHELL.Run($Command) } catch { 0xDEADBEEF }

		If ($CommandRun -eq 0xDEADBEEF) {
			MsgBox "Failed to run '$Command'. Make sure you typed the command correctly, and then try again." 0 'Error'
		} Else {
			If ($CmdHistory_List.contains($Command)) { $CmdHistory_List.Remove($Command) }
			$CmdHistory_List.Insert(0, $Command)
			$cb_Command.Items.Clear()
			$cb_Command.Items.AddRange($CmdHistory_List)
		}
	}

	# Following function adjusts the height of the shortcuts panel to account for horizontal scrollbar height.
	# Normally, if the scrollbars are visible, the horizontal scrollbar covers the buttons and activates the vertical scrollbar.
	# This gets the pixel height of the scrollbar and adds to the panel height so it doesn't cover anything.
	Function ShortcutPanel-HideScroller {
		If ($pn_Shortcuts.HorizontalScroll.Visible) {
			$HScrollHeight = [Windows.Forms.SystemInformation]::HorizontalScrollBarHeight
			$pn_Shortcuts.Height = 60+$HScrollHeight
		} Else {
			$pn_Shortcuts.Height = 60
		}
	}

#endregion FUNCTIONS ##########################################################################################

#region SETUP MAIN FORM ##########################################################################################
	#region MAIN FORM CREATION ##########################################################################################
		$fm_Main = New-Object Windows.Forms.Form -Property @{
			Text = "$APPNAME ($($ENV:username))"
			ClientSize = '500,150'
			Tag = @{}
			MaximizeBox = $False

			# Set form icon to script/application icon
			Icon = Icon-FromFilePath $SCRIPTFILEPATH

			# Handle application closing
			add_Closing = {
				If ($_.CloseReason -eq 'UserClosing') {
					If ((MsgBox "Are you sure you want to close the application?`n`n(Press Alt+F4 or Alt+Q to bypass this prompt.)" 'OKCancel' 'Question' 'Cancel') -eq 'Cancel') {
						$_.Cancel = $True
					}
				}
			}
			add_Closed = { AdminPad-Exit }

			# Setup key binds
			KeyPreview = $True
			add_KeyDown = {
				# Close without prompt, Alt+Q / Alt+F4
				If ($_.Alt -and ( $_.KeyCode -eq 'Q' -or $_.KeyCode -eq 'F4' ) ) {
					$_.SuppressKeyPress = $True
					AdminPad-Exit
				}
				If ($_.KeyCode -eq 'F1') {
					$fm_About.ShowDialog()
				}
			}

			add_Resize = ($fm_Main_ResizeFunc = {
				If ($fm_Main.WindowState -eq 'Normal') {
					# Store window size in registry to restore on next launch
					Set-ItemProperty -Path $REGKEY.PSPath -Name WinSize -Value "$($fm_Main.Width),$($fm_Main.Height)"
					ShortcutPanel-HideScroller
				}
			})

			# Actions to perform on window activation
			add_Load = {
				$this.MinimumSize = $this.Size
				$this.MaximumSize = "$([int32]::maxvalue),$($this.Height)"

				# Check registry for stored window size, restore if valid
				If (($WinSize = $REGKEY.GetValue('WinSize')) -and $WinSize -match '^\d+,\d+$') {
					$fm_Main.Size = $WinSize
				}

				# Check registry for stored TopMost setting, restore if valid
				If (($TopMost = $REGKEY.GetValue('TopMost')) -ne $null) {
					$ch_TopMost.Checked = !!$TopMost # stored value is dword/int, !! casts value to boolean
				}

				ShortcutPanel-HideScroller

				$fm_Main.Activate()
				If (!$REGKEY.GetValue('FirstRun')) {
					ToolTip-Popup 'Toggle Always-on-Top' $ch_TopMost ($ch_TopMost.Width/2) ($ch_TopMost.Height/2) 2500
					Set-ItemProperty -Path $REGKEY.PSPath -Name FirstRun -Value 1
				}
				$cb_Command.Select()
			}
		}

		# Start UIRow variable, useful for adjusting bulk control positions
		$UIRow = 5
	#endregion MAIN FORM CREATION ##########################################################################################

	#region STATUS BAR / INFO PANELS ##########################################################################################
		$fm_Main.Controls.Add(($sb_Main = New-Object Windows.Forms.StatusStrip -Property @{
			ShowItemToolTips = $True
		}))

		$ClickToCopyProps = @{
			BorderSides = 'Right'
			IsLink = $True
			ToolTipText = 'Click to copy'
			add_Click = { Set-Clipboard $this.Text }
		}

		$sb_Main.Items.AddRange(@(
			New-Object Windows.Forms.ToolStripStatusLabel("User:")
			New-Object Windows.Forms.ToolStripStatusLabel($ENV:username) -Property $ClickToCopyProps
			New-Object Windows.Forms.ToolStripStatusLabel("Computer:")
			New-Object Windows.Forms.ToolStripStatusLabel(hostname) -Property $ClickToCopyProps
			New-Object Windows.Forms.ToolStripStatusLabel("Service Tag:")
			New-Object Windows.Forms.ToolStripStatusLabel((Get-WmiObject -Class Win32_BIOS).SerialNumber) -Property $ClickToCopyProps
			New-Object Windows.Forms.ToolStripStatusLabel("Process ID:")
			New-Object Windows.Forms.ToolStripStatusLabel($PID) -Property $ClickToCopyProps
			New-Object Windows.Forms.ToolStripStatusLabel("Version:")
			New-Object Windows.Forms.ToolStripStatusLabel("$($VERSION)") -Property @{
				BorderSides = 'Right'
				IsLink = $True
				ToolTipText = 'View version information'
				add_Click = {
					$fm_About.ShowDialog()
				}
			}
			New-Object Windows.Forms.ToolStripStatusLabel('Export Source') -Property @{
				IsLink = $True
				ToolTipText = 'Export and view Powershell source code'
				add_Click = {
					If (!$SourcePath) {
						$global:SourcePath = New-Object Windows.Forms.SaveFileDialog -Property @{
							Title = 'Export source file'
							InitialDirectory = $ENV:SystemDrive
							FileName = "$APPNAME.ps1"
							Filter = 'Powershell Script|*.ps1|Text files|*.txt|All files|*.*'
						}
					}

					If ($SourcePath.ShowDialog() -eq 'OK') {
						$SourcePath.InitialDirectory = ''
						New-Item -Path $SourcePath.FileName -Force
						If (Test-Path $SourcePath.FileName) {
							Start-Process -FilePath $SCRIPTFILEPATH -ArgumentList "-extract:""$($SourcePath.FileName)"""
						} Else {
							MsgBox "Unable to create file:`n`n$($error[0].toString())" 0 'Error'
						}
					}
				}
			}
		))
	#endregion STATUS BAR / INFO PANELS ##########################################################################################

	#region ALWAYS ON TOP BUTTON ##########################################################################################
		$fm_Main.Controls.Add(($ch_TopMost = New-Object Windows.Forms.Checkbox -Property @{
			Appearance = 'Button'
			Anchor = 'Top,Right'
			Bounds = '480,5,15,15'
			Cursor = 'Help'
			TextAlign = 'MiddleCenter'
			Font = New-Object Drawing.Font('Marlett', 10)
			add_CheckedChanged = {
				$fm_Main.TopMost = $this.Checked

				If ($this.Checked) {
					$this.Text = 'a'
					Set-ItemProperty -Path $REGKEY.PSPath -Name TopMost -Value 1
				} Else {
					$this.Text = ''
					Set-ItemProperty -Path $REGKEY.PSPath -Name TopMost -Value 0
				}
			}
		}))
		ToolTip-Set $ch_TopMost 'Toggle Always-on-Top mode' $True
		$UIRow += 0
	#endregion ALWAYS ON TOP BUTTON/FUNC ##########################################################################################

	#region SHORTCUTS GROUP & PANEL ##########################################################################################
		# Group control, which has the label and border
		$fm_Main.Controls.Add(($gr_Shortcuts = New-Object Windows.Forms.GroupBox -Property @{
			Anchor = 'Top,Left,Right'
			Bounds = "10,$UIRow,480,85"
			Text = 'Shortcuts'
		}))

		# Create the panel control, which has the buttons within it and is scrollable
		$gr_Shortcuts.Controls.Add(($pn_Shortcuts = New-Object Windows.Forms.Panel -Property @{
			Bounds = "10,15,460,60"
			AutoScroll = $True
			Anchor = 'Top,Left,Right'
		}))

		#region SHORTCUT BUTTONS CONTEXT MENU ##########################################################################################
			$cm_ShortcutItemsMenu = New-Object Windows.Forms.ContextMenu -Property @{
				add_Popup = {
					If ($this.SourceControl -eq $global:bt_AddShortcut) {
						$cm_ShortcutItemsMenu.MenuItems | Foreach-Object {
							If ($_.Text -match 'Edit|Delete') { # Disable Edit and Delete menu items if right-click the [+] button
								$_.Enabled = $False
							}
						}
					} Else {
						$cm_ShortcutItemsMenu.MenuItems | Foreach-Object { $_.Enabled = $True }
					}
				}
			}
			[void]$cm_ShortcutItemsMenu.MenuItems.Add((New-Object Windows.Forms.MenuItem -Property @{
				Text = '&Edit'
				add_Click = {
					$Item = Get-ShortcutItem $this.parent.SourceControl
					PropertiesDialog $Item.path
				}
			}))
			[void]$cm_ShortcutItemsMenu.MenuItems.Add((New-Object Windows.Forms.MenuItem -Property @{
				Text = '&Delete'
				add_Click = {
					$Item = Get-ShortcutItem $this.parent.SourceControl
					Remove-Item $Item.path
					Load-Shortcuts
				}
			}))
			[void]$cm_ShortcutItemsMenu.MenuItems.Add((New-Object Windows.Forms.MenuItem -Property @{ Text = '-' }))
			[void]$cm_ShortcutItemsMenu.MenuItems.Add((New-Object Windows.Forms.MenuItem -Property @{
				Text = '&Open Shortcuts folder'
				add_Click = {
					$BrowseShortcutsFolder = New-Object Windows.Forms.OpenFileDialog -Property @{
						Title = 'View Files'
						Filter = 'All files|*.*'
						MultiSelect = $True
						InitialDirectory = $SHORTCUTSDIR
					}
					$BrowseShortcutsFolder.ShowDialog()
					$BrowseShortcutsFolder = $null
				}
			}))
			[void]$cm_ShortcutItemsMenu.MenuItems.Add((New-Object Windows.Forms.MenuItem -Property @{
				Text = 'Reset to &Defaults'
				add_Click = {
					If ((MsgBox "Reset all Shortcuts?" "YesNo" "Question" "No") -eq 'Yes') {
						Remove-Item $SHORTCUTSDIR -Recurse
						Load-Shortcuts
					}
				}
			}))

		#endregion SHORTCUTS BUTTONS CONTEXT MENU ##########################################################################################

		Load-Shortcuts
		$UIRow += 90
	#endregion SHORTCUTS GROUP & PANEL ##########################################################################################

	#region INPUTBOX & CMD LAUNCHER ##########################################################################################
		$fm_Main.Controls.Add((New-Object Windows.Forms.Label -Property @{
			Text = 'Comman&d:'
			Bounds = "10,$UIRow,60,20"
			TextAlign = 'MiddleLeft'
		}))

		$fm_Main.Controls.Add(($cb_Command = New-Object Windows.Forms.ComboBox -Property @{
			Anchor = 'Top,Left,Right'
			Text = ''
			Bounds = "70,$UIRow,370,20"
			add_KeyDown = {
				If ($_.KeyCode -eq 'Return') {
					$_.SuppressKeyPress = $True
					Run-Command $this.text
				} ElseIf ($_.KeyCode -eq 'V' -and $_.Control) {
					If ($Path = Get-Clipboard -Format FileDropList) {
						$_.SuppressKeyPress = $True
						$this.Text = $Path[0].Fullname
					}
				} ElseIf ($_.KeyCode -eq 'Escape') {
					$_.SuppressKeyPress = $True
					$this.Text = ''
				}
			}
		}))
		$cb_Command.Items.AddRange($CmdHistory_List)

		$fm_Main.Controls.Add(($bt_RunCmd = New-Object Windows.Forms.Button -Property @{
			BackgroundImage = (Icon-Extract shell32.dll 137)
			BackgroundImageLayout = 'Center'
			Bounds = "440,$($UIRow-2),25,24"
			Anchor = 'Top,Right'
			add_Click = { Run-Command $cb_Command.text }
		}))
		ToolTip-Set $bt_RunCmd 'Run the command'

		$fm_Main.Controls.Add(($bt_BrowseCmd = New-Object Windows.Forms.Button -Property @{
			Bounds = "465,$($UIRow-2),25,24"
			Anchor = 'Top,Right'
			BackgroundImage = (Icon-Extract shell32.dll 55)
			BackgroundImageLayout = 'Center'
			add_Click = {
				If (!$BrowsePath) {
					$global:BrowsePath = New-Object Windows.Forms.OpenFileDialog -Property @{
						Title = 'Browse...'
						Filter = 'Applications|*.exe;*.msc;*.cpl|All files|*.*'
					}
				}
				$BrowsePath.InitialDirectory = (Get-Location).Path
				If ($BrowsePath.ShowDialog() -eq 'OK') {
					$cb_Command.Text = $BrowsePath.FileName
					Set-Location (Split-Path $BrowsePath.FileName)
				}
			}
		}))
		ToolTip-Set $bt_BrowseCmd 'Browse for file'

		$UIRow += ($cb_Command.Height + 5)
	#endregion INPUTBOX & CMD LAUNCHER ##########################################################################################

#endregion SETUP MAIN FORM ##########################################################################################

#region ABOUT FORM ##########################################################################################
	$fm_About = New-Object Windows.Forms.Form -property @{
		ClientSize = '700,300'
		Icon = Icon-FromFilePath $SCRIPTFILEPATH
		Text = "About $APPNAME $VERSION"
		KeyPreview = $True
		add_KeyDown = {
			If ($_.KeyCode -eq 'Escape') {
				$this.Close()
			}
		}
	}
	$fm_About.Controls.Add((New-Object Windows.Forms.Textbox -Property @{
		AcceptsReturn = $True
		Anchor = 'Top,Right,Left,Bottom'
		Bounds = '0,0,700,300'
		Font = New-Object Drawing.Font('Consolas', 10)
		Multiline = $True
		ReadOnly = $True
		Scrollbars = 'Both'
		Text = $UPDATE_NOTES -replace '\t','    '
		WordWrap = $False
	}))
#endregion ABOUT FORM ##########################################################################################

#region MONITOR SHORTCUTS FOR UPDATES ##########################################################################################
	$ShortcutsTimer = New-Object Windows.Forms.Timer -Property @{
		Interval = 1000
		Add_Tick = {
			$Checksum = Get-ChildItem -Filter "*.lnk" -Path $SHORTCUTSDIR -EA 0 | Select-Object Name, LastWriteTime | ConvertTo-Json
			If ($Checksum -ne $global:ShortcutsChecksum) { Load-Shortcuts }
		}
	}
	$ShortcutsTimer.Start()
#endregion MONITOR SHORTCUTS FOR UPDATES ##########################################################################################

[Windows.Forms.Application]::Run(($AppContext = New-Object Windows.Forms.ApplicationContext($fm_Main)))