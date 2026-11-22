{ SPDX-License-Identifier: GPL-2.0-or-later }
unit WaylandActivation;

{$mode delphi}

// Port: bringing the window of another instance to the front (Window menu, AppInstanceMgmt) on Wayland.
//
// A Wayland compositor activates a window only with a token (protocol xdg-activation-v1) that the active program
// requests for the input event the user just made (KWin, GNOME Shell). The instance whose entry was chosen is in the
// background and cannot get such a token itself; its request to come to the front was ignored (KDE Plasma,
// 2026-11-22). So the instance whose Window menu was clicked requests the token (RequestActivationToken) and hands it
// over with the raise request; the other instance puts it into XDG_ACTIVATION_TOKEN, which Qt's xdg-shell uses for
// the next activation of a window (ActivateWithToken).
//
// Qt does not offer the token request to the LCL. The protocol is spoken here through libwayland-client on Qt's own
// connection, in a separate event queue. Qt hands out the connection, the seat, the serial of the last input event
// and the window's surface through its native interface (QWaylandNativeInterface; its functions are called by their
// exported names, so a Qt that lacks them only leaves the token empty). Everything is looked up at run time: on X11, in
// the GTK2 build or when anything is missing, RequestActivationToken returns '' and raising works as before.

interface

uses
  Forms;

function RequestActivationToken(Form: TCustomForm): string;
procedure ActivateWithToken(Form: TCustomForm; const Token: string);

implementation

{$IFDEF LCLQT6}
uses
  SysUtils, ctypes, dynlibs, qt6, qtwidgets;

type
  PWlInterface = ^TWlInterface;
  PPWlInterface = ^PWlInterface;

  TWlMessage = record
    Name: PChar;
    Signature: PChar;
    Types: PPWlInterface;
  end;
  PWlMessage = ^TWlMessage;

  TWlInterface = record
    Name: PChar;
    Version: cint;
    MethodCount: cint;
    Methods: PWlMessage;
    EventCount: cint;
    Events: PWlMessage;
  end;

  // the layout of a QByteArray made by QByteArray::fromRawData (no data header, not owned)
  TRawByteArray = record
    D: Pointer;
    Ptr: PChar;
    Size: PtrInt;
  end;
  PRawByteArray = ^TRawByteArray;

  TRegistryGlobal = procedure(Data, Registry: Pointer; Name: cuint32; Iface: PChar; Version: cuint32); cdecl;
  TRegistryGlobalRemove = procedure(Data, Registry: Pointer; Name: cuint32); cdecl;
  TTokenDone = procedure(Data, TokenObj: Pointer; Token: PChar); cdecl;

  TRegistryListener = record
    Global: TRegistryGlobal;
    GlobalRemove: TRegistryGlobalRemove;
  end;

  TTokenListener = record
    Done: TTokenDone;
  end;

  TState = record
    ActivationName: cuint32;
    Done: Boolean;
    Token: string;
  end;
  PState = ^TState;

var
  // libwayland-client
  wl_display_create_queue: function(Display: Pointer): Pointer; cdecl;
  wl_event_queue_destroy: procedure(Queue: Pointer); cdecl;
  wl_display_roundtrip_queue: function(Display, Queue: Pointer): cint; cdecl;
  wl_proxy_create_wrapper: function(Proxy: Pointer): Pointer; cdecl;
  wl_proxy_wrapper_destroy: procedure(Wrapper: Pointer); cdecl;
  wl_proxy_set_queue: procedure(Proxy, Queue: Pointer); cdecl;
  wl_proxy_add_listener: function(Proxy: Pointer; Impl: Pointer; Data: Pointer): cint; cdecl;
  wl_proxy_destroy: procedure(Proxy: Pointer); cdecl;
  wl_proxy_get_version: function(Proxy: Pointer): cuint32; cdecl;
  wl_proxy_marshal_flags: function(Proxy: Pointer; Opcode: cuint32; Iface: PWlInterface; Version: cuint32;
    Flags: cuint32): Pointer; cdecl; varargs;
  wl_registry_interface, wl_seat_interface, wl_surface_interface: PWlInterface;
  // Qt
  PlatformNativeInterface: function: Pointer; cdecl;
  NativeResourceForIntegration: function(Self: Pointer; Resource: PRawByteArray): Pointer; cdecl;
  NativeResourceForWindow: function(Self: Pointer; Resource: PRawByteArray; Window: QWindowH): Pointer; cdecl;
  LastInputSerial: function(Self: Pointer): cuint; cdecl;

  Loaded: (lsNo, lsYes, lsFailed);

  // xdg-activation-v1, as wayland-scanner would generate it
  NoTypes: array[0..1] of PWlInterface;
  ActivationRequestTypes: array[0..2] of PWlInterface;  // get_activation_token: new_id; activate: string, surface
  TokenSerialTypes: array[0..1] of PWlInterface;        // set_serial: uint, seat
  TokenSurfaceTypes: array[0..0] of PWlInterface;       // set_surface: surface
  ActivationRequests: array[0..2] of TWlMessage;
  TokenRequests: array[0..4] of TWlMessage;
  TokenEvents: array[0..0] of TWlMessage;
  ActivationInterface, TokenInterface: TWlInterface;

const
  WL_MARSHAL_FLAG_DESTROY = 1;

//----------------------------------------------------------------------------------------------------------------------

procedure SetupInterfaces;

  procedure Msg(var M: TWlMessage; Name, Signature: PChar; Types: PPWlInterface);
  begin
    M.Name := Name;
    M.Signature := Signature;
    M.Types := Types;
  end;

begin
  NoTypes[0] := nil;
  NoTypes[1] := nil;
  ActivationRequestTypes[0] := @TokenInterface;
  ActivationRequestTypes[1] := nil;
  ActivationRequestTypes[2] := wl_surface_interface;
  TokenSerialTypes[0] := nil;
  TokenSerialTypes[1] := wl_seat_interface;
  TokenSurfaceTypes[0] := wl_surface_interface;

  Msg(ActivationRequests[0], 'destroy', '', @NoTypes[0]);
  Msg(ActivationRequests[1], 'get_activation_token', 'n', @ActivationRequestTypes[0]);
  Msg(ActivationRequests[2], 'activate', 'so', @ActivationRequestTypes[1]);
  ActivationInterface.Name := 'xdg_activation_v1';
  ActivationInterface.Version := 1;
  ActivationInterface.MethodCount := 3;
  ActivationInterface.Methods := @ActivationRequests[0];
  ActivationInterface.EventCount := 0;
  ActivationInterface.Events := nil;

  Msg(TokenRequests[0], 'set_serial', 'uo', @TokenSerialTypes[0]);
  Msg(TokenRequests[1], 'set_app_id', 's', @NoTypes[0]);
  Msg(TokenRequests[2], 'set_surface', 'o', @TokenSurfaceTypes[0]);
  Msg(TokenRequests[3], 'commit', '', @NoTypes[0]);
  Msg(TokenRequests[4], 'destroy', '', @NoTypes[0]);
  Msg(TokenEvents[0], 'done', 's', @NoTypes[0]);
  TokenInterface.Name := 'xdg_activation_token_v1';
  TokenInterface.Version := 1;
  TokenInterface.MethodCount := 5;
  TokenInterface.Methods := @TokenRequests[0];
  TokenInterface.EventCount := 1;
  TokenInterface.Events := @TokenEvents[0];
end;

//----------------------------------------------------------------------------------------------------------------------

function Load: Boolean;

var
  Wl, Gui, Wc: TLibHandle;

  function Sym(Lib: TLibHandle; const Name: string): Pointer;
  begin
    Result := GetProcedureAddress(Lib, Name);
    if Result = nil then
      Loaded := lsFailed;
  end;

begin
  if Loaded = lsNo then
  begin
    Loaded := lsYes;
    Wl := LoadLibrary('libwayland-client.so.0');
    Gui := LoadLibrary('libQt6Gui.so.6');
    Wc := LoadLibrary('libQt6WaylandClient.so.6');
    if (Wl = NilHandle) or (Gui = NilHandle) or (Wc = NilHandle) then
      Loaded := lsFailed
    else
    begin
      @wl_display_create_queue := Sym(Wl, 'wl_display_create_queue');
      @wl_event_queue_destroy := Sym(Wl, 'wl_event_queue_destroy');
      @wl_display_roundtrip_queue := Sym(Wl, 'wl_display_roundtrip_queue');
      @wl_proxy_create_wrapper := Sym(Wl, 'wl_proxy_create_wrapper');
      @wl_proxy_wrapper_destroy := Sym(Wl, 'wl_proxy_wrapper_destroy');
      @wl_proxy_set_queue := Sym(Wl, 'wl_proxy_set_queue');
      @wl_proxy_add_listener := Sym(Wl, 'wl_proxy_add_listener');
      @wl_proxy_destroy := Sym(Wl, 'wl_proxy_destroy');
      @wl_proxy_get_version := Sym(Wl, 'wl_proxy_get_version');
      @wl_proxy_marshal_flags := Sym(Wl, 'wl_proxy_marshal_flags');
      wl_registry_interface := Sym(Wl, 'wl_registry_interface');
      wl_seat_interface := Sym(Wl, 'wl_seat_interface');
      wl_surface_interface := Sym(Wl, 'wl_surface_interface');
      @PlatformNativeInterface := Sym(Gui, '_ZN15QGuiApplication23platformNativeInterfaceEv');
      @NativeResourceForIntegration := Sym(Wc,
        '_ZN15QtWaylandClient23QWaylandNativeInterface28nativeResourceForIntegrationERK10QByteArray');
      @NativeResourceForWindow := Sym(Wc,
        '_ZN15QtWaylandClient23QWaylandNativeInterface23nativeResourceForWindowERK10QByteArrayP7QWindow');
      @LastInputSerial := Sym(Wc, '_ZNK15QtWaylandClient23QWaylandNativeInterface15lastInputSerialEv');
      if Loaded = lsYes then
        SetupInterfaces;
    end;
  end;
  Result := Loaded = lsYes;
end;

//----------------------------------------------------------------------------------------------------------------------

function IsWayland: Boolean;

var
  S: WideString;

begin
  S := '';
  QGuiApplication_platformName(@S);
  Result := Pos('wayland', LowerCase(String(S))) = 1;
end;

//----------------------------------------------------------------------------------------------------------------------

function Raw(const S: AnsiString): TRawByteArray;

begin
  Result.D := nil;
  Result.Ptr := PChar(S);
  Result.Size := Length(S);
end;

//----------------------------------------------------------------------------------------------------------------------

function FormWindow(Form: TCustomForm): QWindowH;

begin
  Result := nil;
  if Assigned(Form) and Form.HandleAllocated then
    Result := QWidget_windowHandle(TQtWidget(Form.Handle).Widget);
end;

//----------------------------------------------------------------------------------------------------------------------

procedure RegistryGlobal(Data, Registry: Pointer; Name: cuint32; Iface: PChar; Version: cuint32); cdecl;

begin
  if StrComp(Iface, 'xdg_activation_v1') = 0 then
    PState(Data)^.ActivationName := Name;
end;

procedure RegistryGlobalRemove(Data, Registry: Pointer; Name: cuint32); cdecl;

begin
end;

procedure TokenDone(Data, TokenObj: Pointer; Token: PChar); cdecl;

begin
  PState(Data)^.Token := StrPas(Token);
  PState(Data)^.Done := True;
end;

const
  RegistryListener: TRegistryListener = (Global: RegistryGlobal; GlobalRemove: RegistryGlobalRemove);
  TokenListener: TTokenListener = (Done: TokenDone);

//----------------------------------------------------------------------------------------------------------------------

function RequestActivationToken(Form: TCustomForm): string;

var
  Native, Display, Seat, Surface, Queue, Wrapper, Registry, Activation, TokenObj: Pointer;
  Window: QWindowH;
  Serial: cuint;
  State: TState;
  I: Integer;
  S1, S2, S3: AnsiString;
  R1, R2, R3: TRawByteArray;

begin
  Result := '';
  if not IsWayland or not Load then
    Exit;
  Window := FormWindow(Form);
  Native := PlatformNativeInterface();
  if (Window = nil) or (Native = nil) then
    Exit;
  S1 := 'wl_display';
  S2 := 'wl_seat';
  S3 := 'surface';
  R1 := Raw(S1);
  R2 := Raw(S2);
  R3 := Raw(S3);
  Display := NativeResourceForIntegration(Native, @R1);
  Seat := NativeResourceForIntegration(Native, @R2);
  Surface := NativeResourceForWindow(Native, @R3, Window);
  Serial := LastInputSerial(Native);
  if (Display = nil) or (Seat = nil) or (Surface = nil) then
    Exit;

  FillChar(State, SizeOf(State), 0);
  Queue := wl_display_create_queue(Display);
  Wrapper := wl_proxy_create_wrapper(Display);
  wl_proxy_set_queue(Wrapper, Queue);
  Registry := wl_proxy_marshal_flags(Wrapper, 1 {get_registry}, wl_registry_interface,
    wl_proxy_get_version(Wrapper), 0, nil);
  wl_proxy_wrapper_destroy(Wrapper);
  wl_proxy_add_listener(Registry, @RegistryListener, @State);
  wl_display_roundtrip_queue(Display, Queue);

  if State.ActivationName <> 0 then
  begin
    Activation := wl_proxy_marshal_flags(Registry, 0 {bind}, @ActivationInterface, 1, 0,
      State.ActivationName, ActivationInterface.Name, cuint32(1), nil);
    TokenObj := wl_proxy_marshal_flags(Activation, 1 {get_activation_token}, @TokenInterface, 1, 0, nil);
    wl_proxy_add_listener(TokenObj, @TokenListener, @State);
    wl_proxy_marshal_flags(TokenObj, 0 {set_serial}, nil, 1, 0, Serial, Seat);
    wl_proxy_marshal_flags(TokenObj, 2 {set_surface}, nil, 1, 0, Surface);
    wl_proxy_marshal_flags(TokenObj, 3 {commit}, nil, 1, 0);
    I := 0;
    while not State.Done and (I < 5) and (wl_display_roundtrip_queue(Display, Queue) >= 0) do
      Inc(I);
    wl_proxy_marshal_flags(TokenObj, 4 {destroy}, nil, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_proxy_marshal_flags(Activation, 0 {destroy}, nil, 1, WL_MARSHAL_FLAG_DESTROY);
  end;
  wl_proxy_destroy(Registry);
  wl_event_queue_destroy(Queue);
  Result := State.Token;
end;

//----------------------------------------------------------------------------------------------------------------------

function setenv(Name, Value: PChar; Overwrite: cint): cint; cdecl; external 'c';

procedure ActivateWithToken(Form: TCustomForm; const Token: string);

var
  Window: QWindowH;

begin
  Window := FormWindow(Form);
  if (Token = '') or (Window = nil) or not IsWayland then
    Exit;
  // Qt's xdg-shell takes the token from here at the next activation and removes it.
  setenv('XDG_ACTIVATION_TOKEN', PChar(Token), 1);
  QWindow_requestActivate(Window);
end;

{$ELSE}

function RequestActivationToken(Form: TCustomForm): string;

begin
  Result := '';
end;

procedure ActivateWithToken(Form: TCustomForm; const Token: string);

begin
end;

{$ENDIF}

end.
