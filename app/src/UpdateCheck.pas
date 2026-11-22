{ SPDX-License-Identifier: GPL-2.0-or-later }
unit UpdateCheck;

{$mode delphi}

// Update check through Velopack (ADR-0018). The Velopack library is velopack-pas (third_party/velopack-pas),
// the releases are the GitHub releases of this project. Everything is optional at run time: without
// velopack_libc.dll next to the program, StartupVelopack returns and "Check for Updates ..." stays disabled.

interface

const
  UpdateRepositoryUrl = 'https://github.com/aurora/querymole';     // CommonFuncs.RevivalProjectUrl (ADR-0030)

  // Switched on again by ADR-0037 (ADR-0026 had hidden it for the first alpha). The item is disabled when the
  // Velopack library is missing (development builds, packages built without --velopack).
  UpdateMenuVisible = True;

  // Developer override of the feed (ADR-0037), for testing an update cycle without publishing on the project:
  // - `owner/name` or `https://github.com/owner/name`: the GitHub releases of that repository, read the same way as
  //   those of UpdateRepositoryUrl (API, pre-releases), e.g. a test repository of its own;
  // - anything else: a local folder or URL that holds a vpk release (`releases.<channel>.json`).
  // An existing folder always counts as a folder, so a relative path such as `dist/Releases-linux` works.
  UpdateUrlEnvironment = 'QBR_UPDATE_URL';

// First statement of the program, before the GUI is initialised: lets Velopack handle the install, update
// and uninstall launches (it may end the process) and applies a downloaded update on startup.
procedure StartupVelopack;

// True if the Velopack library was found; the menu item is enabled only then.
function UpdatesAvailable: Boolean;

// Menu command: asks whether there is a newer release and, if the user agrees, downloads it, restarts the
// program and lets Velopack replace the installation.
procedure CheckForUpdatesInteractive;

// Normal start, just before the main loop (ADR-0052): a few seconds after the window shows, asks once whether the
// program may check for updates at every start, and checks quietly if so (a dialog only when there is a new version).
procedure ScheduleStartupUpdateCheck;

// Developer mode --shot-update-question <png> (ADR-0052): the update question with its check boxes, photographed.
procedure ShotUpdateQuestion(const FileName: String);

// Developer mode --selftest-update <report> (ADR-0037): the same steps without dialogs, against QBR_UPDATE_URL (it
// must be set, so that the self-test never runs against the project by accident). Writes the
// feed, the installed version and the result of the check to the report; if there is an update, downloads it and
// starts the updater, which replaces the installation after this process has ended (no restart).
procedure RunUpdateSelftest(const ReportFile: String);

implementation

uses
  {$IFDEF UNIX}BaseUnix,{$ENDIF}
  Classes, SysUtils, Controls, Forms, StdCtrls, ComCtrls, Dialogs, ExtCtrls, Graphics, LCLIntf, LCLType, gnugettext,
  CommonFuncs, ApplicationDataModule, DevTools,
  Velopack.Types, Velopack.App, Velopack.Updater, Velopack.Manager;

// An AppImage is updated by replacing its file, which needs write access to its folder. Velopack would then ask
// for pkexec, but its confirmation dialog cannot open on Linux (vpk 1.3.39, docs/linux-port.md), so the update
// fails after the download. Returns False and the folder if the running AppImage lies in a folder that is not
// writable; True everywhere else (Windows, macOS, a program started outside an AppImage).
function UpdateFolderWritable(out Folder: String): Boolean;
begin
  Folder := '';
  Result := True;
  {$IFDEF UNIX}
  if GetEnvironmentVariable('APPIMAGE') <> '' then
  begin
    Folder := ExtractFileDir(GetEnvironmentVariable('APPIMAGE'));
    Result := fpAccess(Folder, W_OK) = 0;
  end;
  {$ENDIF}
end;

// The developer override of the feed, '' if there is none.
function UpdateOverride: String;
begin
  Result := Trim(GetEnvironmentVariable(UpdateUrlEnvironment));
end;

// True if the override names a GitHub repository (`owner/name` or `https://github.com/owner/name`, see
// UpdateUrlEnvironment); Repo is then its https://github.com/ URL.
function OverrideIsGitHub(const Value: String; out Repo: String): Boolean;
const
  Prefix = 'https://github.com/';
var
  Rest: String;
  I, Slashes: Integer;
begin
  Result := False;
  Repo := '';
  Rest := Value;
  if Pos(Prefix, LowerCase(Rest)) = 1 then
    Delete(Rest, 1, Length(Prefix))
  else
    if (Pos('://', Rest) > 0) or DirectoryExists(Rest) then
      Exit;
  if (Rest <> '') and (Rest[Length(Rest)] = '/') then
    Delete(Rest, Length(Rest), 1);
  Slashes := 0;
  for I := 1 to Length(Rest) do
    if Rest[I] = '/' then
      Inc(Slashes)
    else
      if not (Rest[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.']) then
        Exit;
  if (Slashes <> 1) or (Rest[1] = '/') or (Rest[Length(Rest)] = '/') then
    Exit;
  Repo := Prefix + Rest;
  Result := True;
end;

// What the note in the dialogs and the self-test report name as the feed: the repository URL or the override.
function OverrideFeed: String;
begin
  if not OverrideIsGitHub(UpdateOverride, Result) then
    Result := UpdateOverride;
end;

// A pre-release (alpha, beta) is updated to newer pre-releases as well; a release only to releases. Revival: the
// setting "Offer development versions" in the update dialogs overrides that (ADR-0052).
function UpdatePrerelease: Boolean;
begin
  if (ApplicationDM <> nil) and (ApplicationDM.Options.UpdateDevelopmentVersions = '1') then
    Result := True
  else if (ApplicationDM <> nil) and (ApplicationDM.Options.UpdateDevelopmentVersions = '0') then
    Result := False
  else
    Result := Pos('-', revival_version) > 0;
end;

// revival: the update dialogs with the two settings as check boxes (ADR-0052). Returns True for Yes or OK; the
// check boxes are stored when the dialog closes with any button.
function UpdateQuestion(const Text: String; DlgType: TMsgDlgType; YesNo: Boolean;
  Show: Boolean = True; const ShotFile: String = ''): Boolean;
var
  Dlg: TForm;
  Msg: TLabel;
  AutoCB, DevCB: TCheckBox;
  YesBtn, NoBtn: TButton;
  R: TRect;
begin
  Dlg := TForm.CreateNew(nil);
  try
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poMainFormCenter;
    Dlg.Caption := RevivalProductName + ' - ' + _('Updates');
    Dlg.ClientWidth := 440;
    Msg := TLabel.Create(Dlg);
    Msg.Parent := Dlg;
    Msg.AutoSize := False;
    Msg.WordWrap := True;
    Msg.Caption := Text;
    Msg.SetBounds(16, 16, 408, 20);
    // the height the wrapped text needs in its width
    Msg.Canvas.Font := Msg.Font;
    R := Rect(0, 0, Msg.Width, 0);
    DrawText(Msg.Canvas.Handle, PChar(Text), Length(Text), R, DT_CALCRECT or DT_WORDBREAK);
    Msg.Height := R.Bottom + 4;
    AutoCB := TCheckBox.Create(Dlg);
    AutoCB.Parent := Dlg;
    AutoCB.SetBounds(16, Msg.Top + Msg.Height + 14, 408, 19);
    AutoCB.Caption := _('Check for updates when the program starts');
    AutoCB.Checked := ApplicationDM.Options.UpdateCheckOnStart;
    DevCB := TCheckBox.Create(Dlg);
    DevCB.Parent := Dlg;
    DevCB.SetBounds(16, AutoCB.Top + 24, 408, 19);
    DevCB.Caption := _('Offer development versions (alpha, beta)');
    DevCB.Checked := UpdatePrerelease;
    YesBtn := TButton.Create(Dlg);
    YesBtn.Parent := Dlg;
    YesBtn.Default := True;
    YesBtn.ModalResult := mrYes;
    NoBtn := nil;
    if YesNo then
    begin
      YesBtn.Caption := _('Yes');
      NoBtn := TButton.Create(Dlg);
      NoBtn.Parent := Dlg;
      NoBtn.Caption := _('No');
      NoBtn.Cancel := True;
      NoBtn.ModalResult := mrNo;
      NoBtn.SetBounds(Dlg.ClientWidth - 16 - 80, DevCB.Top + 36, 80, 25);
      YesBtn.SetBounds(NoBtn.Left - 8 - 80, NoBtn.Top, 80, 25);
    end
    else
    begin
      YesBtn.Caption := _('OK');
      YesBtn.Cancel := True;
      YesBtn.SetBounds(Dlg.ClientWidth - 16 - 80, DevCB.Top + 36, 80, 25);
    end;
    Dlg.ClientHeight := YesBtn.Top + YesBtn.Height + 12;
    if ShotFile <> '' then
    begin
      Dlg.Show;
      CaptureWindowToPng(Dlg, ShotFile);
      Exit(False);
    end;
    if not Show then
      Exit(False);
    Result := Dlg.ShowModal = mrYes;
    // the settings, whatever was answered
    ApplicationDM.Options.UpdateCheckOnStart := AutoCB.Checked;
    if DevCB.Checked <> (Pos('-', revival_version) > 0) then
      ApplicationDM.Options.UpdateDevelopmentVersions := IntToStr(Ord(DevCB.Checked))
    else
      ApplicationDM.Options.UpdateDevelopmentVersions := 'auto';
    ApplicationDM.Options.UpdateCheckAsked := True;
    ApplicationDM.Options.StoreOptions;
  finally
    Dlg.Free;
  end;
end;

// An empty string normally; with the developer override (QBR_UPDATE_URL) a paragraph that names the feed and the
// variable. Appended to every update dialog, so that a redirected update is visible before anything is
// downloaded (someone may have been talked into setting the variable) and the source is known when debugging.
function UpdateSourceNote: String;
begin
  Result := '';
  if UpdateOverride <> '' then
    Result := LineEnding + LineEnding + Format(_('Note: updates are not taken from the QueryMole project but from ' +
      '%s (set by the environment variable %s).'), [OverrideFeed, UpdateUrlEnvironment]);
end;

function NotWritableMessage(const Version, Folder: String): String;
begin
  Result := Format(_('Version %s is available, but it cannot be installed automatically: the folder %s is not ' +
    'writable.'), [Version, Folder]) + LineEnding + LineEnding +
    Format(_('Move the AppImage to a folder you can write to and check again, or download the new version from %s.'),
    [UpdateRepositoryUrl + '/releases']);
end;

type
  TUpdateDialogs = class
  private
    FUpdater: TVelopackUpdater;
    FProgress: TForm;
    FBar: TProgressBar;
    procedure HandleCheck(Sender: TObject; AResult: TUpdateCheckResult; const ATarget: TVelopackAsset);
    procedure HandleProgress(Sender: TObject; Percent: Integer);
    procedure HandleDownloaded(Sender: TObject);
    procedure HandleError(Sender: TObject; const AMessage: string);
    procedure ShowProgress;
    procedure CloseProgress;
  public
    Silent: Boolean;   // revival: the check at start, which shows nothing unless there is a new version (ADR-0052)
    destructor Destroy; override;
    procedure Run;
  end;

  // revival: the check a few seconds after the start (ADR-0052)
  TStartupCheck = class
    Timer: TTimer;
    procedure Fire(Sender: TObject);
  end;

var
  GLibraryFound: Boolean = False;
  GDialogs: TUpdateDialogs = nil;

procedure StartupVelopack;
begin
  GLibraryFound := TVelopackApp.Run;
end;

function UpdatesAvailable: Boolean;
begin
  Result := GLibraryFound;
end;

procedure CheckForUpdatesInteractive;
begin
  if not GLibraryFound then
    Exit;
  if GDialogs = nil then
    GDialogs := TUpdateDialogs.Create;
  GDialogs.Silent := False;
  GDialogs.Run;
end;

var
  GStartupCheck: TStartupCheck = nil;

procedure TStartupCheck.Fire(Sender: TObject);
begin
  Timer.Enabled := False;
  if not ApplicationDM.Options.UpdateCheckAsked then
  begin
    // once: whether the program may look for new versions at every start (it asks before downloading anything)
    ApplicationDM.Options.UpdateCheckOnStart := MessageDlg(Format(_('%s can look for a new version each time it ' +
      'starts. It asks before it downloads anything, and you can change this in the options (Browser) and in the ' +
      'update dialog.'), [RevivalProductName]) + LineEnding + LineEnding + _('Check for updates when the program ' +
      'starts?'), mtConfirmation, [mbYes, mbNo], 0) = mrYes;
    ApplicationDM.Options.UpdateCheckAsked := True;
    ApplicationDM.Options.StoreOptions;
  end;
  if ApplicationDM.Options.UpdateCheckOnStart then
  begin
    if GDialogs = nil then
      GDialogs := TUpdateDialogs.Create;
    GDialogs.Silent := True;
    GDialogs.Run;
  end;
end;

procedure ScheduleStartupUpdateCheck;
begin
  // only where updates work (the installed program, the self-updating AppImage), not for the portable packages
  if not GLibraryFound or (UpdateOverride <> '') then
    Exit;
  GStartupCheck := TStartupCheck.Create;
  GStartupCheck.Timer := TTimer.Create(nil);
  GStartupCheck.Timer.Interval := 3000;
  GStartupCheck.Timer.OnTimer := GStartupCheck.Fire;
  GStartupCheck.Timer.Enabled := True;
end;

procedure ShotUpdateQuestion(const FileName: String);
begin
  EnsureMainForm;
  UpdateQuestion(Format(_('Version %s is available. Download and install it now?'), ['0.1.0-alpha.10']),
    mtConfirmation, True, False, FileName);
end;

procedure RunUpdateSelftest(const ReportFile: String);
var
  Report: TStringList;
  Manager: TUpdateManager;
  Info: TUpdateInfo;
  Source: TUpdateSource;
  Url, Folder: String;
begin
  Report := TStringList.Create;
  try
    try
      if not GLibraryFound then
        raise Exception.Create('Velopack library not found');
      if UpdateOverride = '' then
        raise Exception.Create(UpdateUrlEnvironment + ' is not set');
      if OverrideIsGitHub(UpdateOverride, Url) then
      begin
        Source := TUpdateSource.FromGitHub(Url, '', UpdatePrerelease);
        try
          Manager := TUpdateManager.CreateWithSource(Source);
        finally
          Source.Free;
        end;
      end
      else
      begin
        Url := UpdateOverride;
        Manager := TUpdateManager.Create(Url);
      end;
      try
        Report.Add('feed ' + Url);
        Report.Add('installed ' + Manager.CurrentVersion);
        if Manager.CheckForUpdates(Info) <> ucUpdateAvailable then
          Report.Add('no update')
        else
          try
            Report.Add('available ' + Info.TargetFullRelease.Version);
            if not UpdateFolderWritable(Folder) then
              Report.Add('not writable ' + Folder)
            else
            begin
              Manager.DownloadUpdates(Info);
              Report.Add('downloaded');
              Manager.WaitExitThenApplyUpdates(Info.TargetFullRelease, True, False);
              Report.Add('updater started');
            end;
          finally
            Info.Free;
          end;
      finally
        Manager.Free;
      end;
    except
      on E: Exception do
        Report.Add('error ' + E.ClassName + ': ' + E.Message);
    end;
    Report.SaveToFile(ReportFile);
  finally
    Report.Free;
  end;
end;

{ TUpdateDialogs }

destructor TUpdateDialogs.Destroy;
begin
  CloseProgress;
  FUpdater.Free;
  inherited Destroy;
end;

procedure TUpdateDialogs.Run;
var
  Repo: String;
begin
  if FUpdater = nil then
  begin
    FUpdater := TVelopackUpdater.Create(nil);
    if UpdateOverride = '' then
      Repo := UpdateRepositoryUrl
    else
      if not OverrideIsGitHub(UpdateOverride, Repo) then
        Repo := '';
    if Repo <> '' then
      FUpdater.GitHubRepoUrl := Repo
    else
      FUpdater.UpdateUrl := UpdateOverride;
    FUpdater.OnCheckCompleted := HandleCheck;
    FUpdater.OnDownloadProgress := HandleProgress;
    FUpdater.OnDownloadCompleted := HandleDownloaded;
    FUpdater.OnError := HandleError;
  end;
  if FUpdater.Busy then
    Exit;
  // revival: each time, the setting may have changed (ADR-0052)
  if FUpdater.GitHubRepoUrl <> '' then
    FUpdater.GitHubPrerelease := UpdatePrerelease;
  if not Silent then
    Screen.Cursor := crHourGlass;
  try
    FUpdater.CheckForUpdates;
  except
    Screen.Cursor := crDefault;
    raise;
  end;
end;

procedure TUpdateDialogs.HandleCheck(Sender: TObject; AResult: TUpdateCheckResult; const ATarget: TVelopackAsset);
var
  Folder: String;
begin
  Screen.Cursor := crDefault;
  if AResult <> ucUpdateAvailable then
  begin
    if not Silent then
      UpdateQuestion(_('You are running the latest version.') + UpdateSourceNote, mtInformation, False);
  end
  else
    if not UpdateFolderWritable(Folder) then
      MessageDlg(NotWritableMessage(ATarget.Version, Folder) + UpdateSourceNote, mtWarning, [mbOK], 0)
  else
    if UpdateQuestion(Format(_('Version %s is available. Download and install it now?'), [ATarget.Version]) +
      UpdateSourceNote, mtConfirmation, True) then
    begin
      ShowProgress;
      FUpdater.DownloadUpdates;
    end;
end;

procedure TUpdateDialogs.HandleProgress(Sender: TObject; Percent: Integer);
begin
  if FBar <> nil then
    FBar.Position := Percent;
end;

procedure TUpdateDialogs.HandleDownloaded(Sender: TObject);
begin
  CloseProgress;
  if MessageDlg(_('The update has been downloaded. The program has to restart to install it. Restart now?'),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    // The updater waits for this process to end, installs the update and starts the program again.
    FUpdater.ApplyUpdatesAndRestart;
    Application.Terminate;
  end;
  // Otherwise the downloaded update is applied the next time the program starts.
end;

procedure TUpdateDialogs.HandleError(Sender: TObject; const AMessage: string);
begin
  Screen.Cursor := crDefault;
  CloseProgress;
  // revival: the check at start says nothing about failures (no network, GitHub's rate limit); the menu entry does
  if Silent and (FProgress = nil) then
    Exit;
  MessageDlg(_('The update check failed.') + LineEnding + LineEnding + AMessage + UpdateSourceNote, mtError,
    [mbOK], 0);
end;

procedure TUpdateDialogs.ShowProgress;
var
  Caption: TLabel;
begin
  CloseProgress;
  FProgress := TForm.CreateNew(nil);
  FProgress.BorderStyle := bsDialog;
  FProgress.BorderIcons := [];
  FProgress.Position := poMainFormCenter;
  FProgress.Caption := _('Downloading update');
  FProgress.ClientWidth := 360;
  FProgress.ClientHeight := 64;
  Caption := TLabel.Create(FProgress);
  Caption.Parent := FProgress;
  Caption.SetBounds(12, 10, 336, 16);
  Caption.Caption := _('Downloading the update ...');
  FBar := TProgressBar.Create(FProgress);
  FBar.Parent := FProgress;
  FBar.SetBounds(12, 34, 336, 18);
  FBar.Max := 100;
  FProgress.Show;
end;

procedure TUpdateDialogs.CloseProgress;
begin
  FBar := nil;
  FreeAndNil(FProgress);
end;

initialization

finalization
  GDialogs.Free;
  if GStartupCheck <> nil then
  begin
    GStartupCheck.Timer.Free;
    GStartupCheck.Free;
  end;

end.
