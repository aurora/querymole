unit AppInstanceMgmt;

{$mode delphi}

interface

uses {$IFDEF MSWINDOWS}Windows{$ELSE}BaseUnix, ExtCtrls{$ENDIF}, SysUtils, Forms, TntMenus, Classes;

type
  PAppInstanceInfo = ^TAppInstanceInfo;
  TAppInstanceInfo = packed record
    AppHandle: THandle;
    ConnectionString: Array [0 .. 100] of Char;
    ApplicationCaption: Array [0 .. 100] of Char;
  end;

  PAppInstances = ^TAppInstances;
  TAppInstances = packed record
    InstanceCount: Integer;
    Instances: Array [0..100] of TAppInstanceInfo;
  end;

  TDataMenuItem = class(TTntMenuItem)
    constructor Create(AOwner: TComponent; AppHandle: THandle); reintroduce;
  private
    FAppHandle: THandle;
  public
    procedure Click; reintroduce; override;
    property AppHandle: THandle read FAppHandle;
  end;

function RegisterApplication(App: TApplication;
  ConnectionString: WideString; AllowOnlyOneInstance: Boolean = False): Boolean;

procedure UnregisterApplication(App: TApplication);

procedure BuildRegisterApplicationMenuItems(MenuItem: TTntMenuItem);

//----------------------------------------------------------------------------------------------------------------------

implementation

{$IFDEF MSWINDOWS}
const
  // Port: the original shared 'MySQLGuiInstanceManagement' with MySQL Administrator. Its record holds a THandle, which
  // has 8 bytes in this 64-bit program and 4 in the original 32-bit programs, so the layouts no longer match.
  MappingName = 'QueryMoleInstanceManagement';

var
  MappingHandle: THandle; // Central handle for file mapping used for instance management.

//----------------------------------------------------------------------------------------------------------------------

function AppWindow(App: TApplication): THandle;

// Port: the VCL's Application.Handle was the window of the taskbar button, which the original restores and brings to
// the front. The LCL's is a hidden helper window; the main form's window takes its place.

begin
  if Assigned(App.MainForm) then
    Result := App.MainForm.Handle
  else
    Result := App.Handle;
end;

{$ELSE}

// Port: the instance list lives in Windows shared memory in the original. Elsewhere each instance writes a file
// <pid>.instance (caption and connection, one per line) into a folder of the user's runtime directory, and the Window
// menu lists the files whose process still runs. Choosing an entry writes <pid>.raise; the instance with that pid looks
// for it twice a second and brings its main window to the front (no process can raise another's window on X11 or
// Wayland reliably, the window manager decides).

type
  TRaiseWatcher = class
  private
    FTimer: TTimer;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  Registered: Boolean;
  Watcher: TRaiseWatcher;

//----------------------------------------------------------------------------------------------------------------------

function InstanceDir: string;

begin
  Result := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if (Result <> '') and DirectoryExists(Result) then
    Result := IncludeTrailingPathDelimiter(Result) + 'querymole-instances'
  else
    Result := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'querymole-instances-' + IntToStr(fpGetUID);
  if not DirectoryExists(Result) then
  begin
    ForceDirectories(Result);
    fpChmod(Result, &700);
  end;
  Result := IncludeTrailingPathDelimiter(Result);
end;

//----------------------------------------------------------------------------------------------------------------------

procedure RaiseMainForm;

begin
  if Assigned(Application.MainForm) then
  begin
    Application.Restore;
    Application.MainForm.ShowOnTop;
  end;
end;

//----------------------------------------------------------------------------------------------------------------------

constructor TRaiseWatcher.Create;

begin
  inherited Create;

  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

//----------------------------------------------------------------------------------------------------------------------

destructor TRaiseWatcher.Destroy;

begin
  FTimer.Free;

  inherited;
end;

//----------------------------------------------------------------------------------------------------------------------

procedure TRaiseWatcher.TimerTick(Sender: TObject);

var
  F: string;

begin
  F := InstanceDir + IntToStr(fpGetPID) + '.raise';
  if FileExists(F) then
  begin
    DeleteFile(F);
    RaiseMainForm;
  end;
end;

{$ENDIF}

//----------------------------------------------------------------------------------------------------------------------

constructor TDataMenuItem.Create(AOwner: TComponent; AppHandle: THandle);

begin
  inherited Create(AOwner);

  FAppHandle := AppHandle;
end;

//----------------------------------------------------------------------------------------------------------------------

procedure TDataMenuItem.Click;

{$IFNDEF MSWINDOWS}
var
  L: TStringList;
{$ENDIF}

begin
  inherited;

  {$IFDEF MSWINDOWS}
  if (IsIconic(FAppHandle)) then
     ShowWindow(FAppHandle, SW_RESTORE);

  SetForegroundWindow(FAppHandle);
  {$ELSE}
  // Port: AppHandle is the process id of the instance here.
  if TPid(FAppHandle) = fpGetPID then
    RaiseMainForm
  else
  begin
    L := TStringList.Create;
    try
      try
        L.SaveToFile(InstanceDir + IntToStr(FAppHandle) + '.raise');
      except
        // The instance may have ended meanwhile.
      end;
    finally
      L.Free;
    end;
  end;
  {$ENDIF}
end;

//----------------------------------------------------------------------------------------------------------------------

function RegisterApplication(App: TApplication; ConnectionString: WideString; AllowOnlyOneInstance: Boolean): Boolean;

{$IFDEF MSWINDOWS}
var
  AppInstances: PAppInstances;
  S: string;
  I: Integer;
  LastError: Cardinal;
{$ELSE}
var
  L: TStringList;
  F: string;
{$ENDIF}

begin
  Result := True;

  {$IFDEF MSWINDOWS}
  if MappingHandle = 0 then
  begin
    MappingHandle := CreateFileMapping($FFFFFFFF, nil, PAGE_READWRITE, 0, SizeOf(TAppInstances), MappingName);
    if MappingHandle = 0 then
      RaiseLastOSError
  end;

  if MappingHandle <> 0 then
  begin
    LastError := GetLastError;
    AppInstances := MapViewOfFile(MappingHandle, FILE_MAP_ALL_ACCESS, 0, 0, SizeOf(TAppInstances));

    if Assigned(AppInstances) then
    begin
      if LastError <> ERROR_ALREADY_EXISTS then
        AppInstances^.InstanceCount := 1
      else //already runing
      begin
        if AllowOnlyOneInstance then
        begin
          for I := 0 to AppInstances^.InstanceCount - 1 do
            if (WideSameText(
              UTF8Decode(AppInstances^.Instances[I].ApplicationCaption),
              App.Title)) then
            begin
              if (IsIconic(AppInstances^.Instances[I].AppHandle)) then
                 ShowWindow(AppInstances^.Instances[I].AppHandle, SW_RESTORE);

              SetForegroundWindow(AppInstances^.Instances[I].AppHandle);

              Result := False;

              Exit;
            end;
        end;

        Inc(AppInstances^.InstanceCount);
      end;

      AppInstances^.Instances[AppInstances^.InstanceCount - 1].AppHandle := AppWindow(App);

      // Port: the original copied the text without its terminating zero and without a length limit.
      S := Copy(UTF8Encode(App.Title), 1, 100);
      FillChar(AppInstances^.Instances[AppInstances^.InstanceCount - 1].ApplicationCaption, 101, 0);
      StrMove(AppInstances^.Instances[AppInstances^.InstanceCount - 1].ApplicationCaption,
        PChar(S), Length(S));

      AppInstances^.Instances[AppInstances^.InstanceCount - 1].ConnectionString[0] := Char(0);
      S := Copy(UTF8Encode(ConnectionString), 1, 100);
      FillChar(AppInstances^.Instances[AppInstances^.InstanceCount - 1].ConnectionString, 101, 0);
      StrMove(AppInstances^.Instances[AppInstances^.InstanceCount - 1].ConnectionString,
        PChar(S), Length(S));

      UnmapViewOfFile(AppInstances);
    end;
  end
  {$ELSE}
  L := TStringList.Create;
  try
    L.Add(UTF8Encode(App.Title));
    L.Add(UTF8Encode(ConnectionString));
    F := InstanceDir + IntToStr(fpGetPID);
    try
      L.SaveToFile(F + '.tmp');
      RenameFile(F + '.tmp', F + '.instance');
      DeleteFile(F + '.raise');
      Registered := True;
      Watcher := TRaiseWatcher.Create;
    except
      // Without the folder the Window menu lists no instance, as before.
    end;
  finally
    L.Free;
  end;
  {$ENDIF}
end;

//----------------------------------------------------------------------------------------------------------------------

procedure UnregisterApplication(App: TApplication);

{$IFDEF MSWINDOWS}
var
  AppInstances: PAppInstances;
  I: Integer;
  J: Integer;
  Handle: THandle;
{$ELSE}
var
  F: string;
{$ENDIF}

begin
  {$IFDEF MSWINDOWS}
  if MappingHandle <> 0 then
  begin
    AppInstances := MapViewOfFile(MappingHandle, FILE_MAP_ALL_ACCESS, 0, 0, SizeOf(TAppInstances));
    Handle := AppWindow(App);

    // find current application
    for I := 0 to AppInstances^.InstanceCount - 1 do
      if (AppInstances^.Instances[I].AppHandle = Handle) then
      begin
        // move down all other instances
        // Port: the original moved the entries below the current one up by one, from the last one, so that all of
        // them ended up as copies of the last; move them from the first one.
        for J := I + 1 to AppInstances^.InstanceCount - 1 do
          AppInstances^.Instances[J - 1] := AppInstances^.Instances[J];

        break;
      end;

    Dec(AppInstances^.InstanceCount);
    UnmapViewOfFile(AppInstances);
  end;
  {$ELSE}
  if Registered then
  begin
    FreeAndNil(Watcher);
    F := InstanceDir + IntToStr(fpGetPID);
    DeleteFile(F + '.instance');
    DeleteFile(F + '.raise');
    Registered := False;
  end;
  {$ENDIF}
end;

//----------------------------------------------------------------------------------------------------------------------

{$IFNDEF MSWINDOWS}
function ComparePids(List: TStringList; Index1, Index2: Integer): Integer;

begin
  Result := StrToIntDef(List[Index1], 0) - StrToIntDef(List[Index2], 0);
end;
{$ENDIF}

procedure BuildRegisterApplicationMenuItems(MenuItem: TTntMenuItem);

var
  I: Integer;
  CurrentCount: Integer;
  AppMenuItem: TTntMenuItem;
{$IFDEF MSWINDOWS}
  AppInstances: PAppInstances;
{$ELSE}
  Dir: string;
  SR: TSearchRec;
  Pids: TStringList;
  L: TStringList;
  Pid: Integer;
{$ENDIF}

begin
  CurrentCount := MenuItem.Count;

  {$IFDEF MSWINDOWS}
  if MappingHandle <> 0 then
  begin
    AppInstances := MapViewOfFile(MappingHandle, FILE_MAP_ALL_ACCESS, 0, 0, SizeOf(TAppInstances));

    // Find current application.
    for I := 0 to AppInstances^.InstanceCount - 1 do
    begin
      AppMenuItem := TDataMenuItem.Create(MenuItem.Owner,
        AppInstances^.Instances[I].AppHandle);
      AppMenuItem.Caption := UTF8Decode(AppInstances^.Instances[I].ApplicationCaption);

      if (AppInstances^.Instances[I].ConnectionString <> '') then
       AppMenuItem.Caption := AppMenuItem.Caption +
        ' - ' + UTF8Decode(AppInstances^.Instances[I].ConnectionString);
      AppMenuItem.OnDrawItem := MenuItem.OnDrawItem;      // Port: TntMenus' OnDrawItem
      AppMenuItem.OnMeasureItem := MenuItem.OnMeasureItem;
      MenuItem.Add(AppMenuItem);
    end;

    MenuItem.Enabled := True;

    UnmapViewOfFile(AppInstances);
  end;
  {$ELSE}
  Dir := InstanceDir;
  Pids := TStringList.Create;
  L := TStringList.Create;
  try
    if FindFirst(Dir + '*.instance', faAnyFile, SR) = 0 then
    try
      repeat
        Pid := StrToIntDef(ChangeFileExt(SR.Name, ''), 0);
        if Pid <= 0 then
          Continue;
        // A file left behind by an instance that crashed.
        if (Pid <> fpGetPID) and (fpKill(Pid, 0) <> 0) and (fpGetErrno = ESysESRCH) then
          DeleteFile(Dir + SR.Name)
        else
          Pids.Add(IntToStr(Pid));
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;

    // The order of registration, as in the original's list.
    Pids.CustomSort(ComparePids);
    for I := 0 to Pids.Count - 1 do
    begin
      try
        L.LoadFromFile(Dir + Pids[I] + '.instance');
      except
        Continue;
      end;
      if L.Count = 0 then
        Continue;

      AppMenuItem := TDataMenuItem.Create(MenuItem.Owner, THandle(StrToInt(Pids[I])));
      AppMenuItem.Caption := L[0];
      if (L.Count > 1) and (L[1] <> '') then
        AppMenuItem.Caption := AppMenuItem.Caption + ' - ' + L[1];
      AppMenuItem.OnDrawItem := MenuItem.OnDrawItem;
      AppMenuItem.OnMeasureItem := MenuItem.OnMeasureItem;
      MenuItem.Add(AppMenuItem);
    end;

    MenuItem.Enabled := True;
  finally
    L.Free;
    Pids.Free;
  end;
  {$ENDIF}

  for I := 0 to CurrentCount - 1 do
    MenuItem.Delete(0);
end;

//----------------------------------------------------------------------------------------------------------------------

initialization
finalization
  {$IFDEF MSWINDOWS}
  if MappingHandle <> 0 then
    CloseHandle(MappingHandle);
  {$ELSE}
  Watcher.Free;
  {$ENDIF}
end.
