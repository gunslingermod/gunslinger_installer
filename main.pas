unit main;

{$mode objfpc}{$H+}

interface

uses
  windows, Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, IniFiles;

type
  TInstallStage= (STAGE_INIT, STAGE_INTEGRITY, STAGE_PACKING, STAGE_SELECT_DIR, STAGE_SELECT_GAME_DIR, STAGE_INSTALL, STAGE_CONFIG, STAGE_OK, STAGE_BAD);
  StringsArr = array of string;

  TCopyThreadData = record
    lock_install:TRTLCriticalSection;
    cmd_in_stop:boolean;
    progress_out:double;
    started:boolean;
    completed_out:boolean;
    error_out:string;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    btn_elipsis: TButton;
    btn_next: TButton;
    edit_path: TEdit;
    Image1: TImage;
    lbl_hint: TLabel;
    progress: TProgressBar;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    Timer1: TTimer;
    procedure btn_elipsisClick(Sender: TObject);
    procedure btn_nextClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure HideControls();
    procedure Timer1Timer(Sender: TObject);
  private
    _bundle:file;
    _stage:TInstallStage;
    _cfg:TIniFile;
    _mod_dir:string;
    _game_dir:string;
    _bad_msg:string;

    _copydata:TCopyThreadData;
    _th_handle:THandle;

    procedure SwitchToStage(s:TInstallStage);

  public

  end;

var
  MainForm: TMainForm;

implementation
uses FastCrc, Localizer, registry, LazUTF8, userltxdumper, packer;

{$R *.lfm}

const
  MAIN_SECTION:string='main';
  FILES_COUNT_PARAM:string='files_count';
  BUILD_ID_PARAM:string='build_id';
  FILE_SECT_PREFIX:string='file_';
  FILE_KEY_PATH:string='path';
  FILE_KEY_OFFSET:string='offset';
  FILE_KEY_SIZE:string='size';
  FILE_KEY_CRC32:string='crc32';

  UNINSTALL_DATA_PATH:string='uninstall.dat';
  USERDATA_PATH:string = 'userdata\';
  USERLTX_PATH:string = 'userdata\user.ltx';
  FSGAME_PATH:string='fsgame.ltx';

type
  TFileBytes = array of char;

function GetMainConfigFromBundle(var bundle:file):TIniFile;
var
  cfg_offset:int64;
  fsz:int64;
  cfg:TMemoryStream;
  c:char;
begin
  result:=nil;
  cfg:=nil;
  cfg_offset:=0;

  try
    // The last 8 bytes are the offset of the config
    fsz:=FileSize(bundle);
    if fsz<=sizeof(cfg_offset) then exit;

    Seek(bundle, fsz-sizeof(cfg_offset));
    BlockRead(bundle, cfg_offset, sizeof(cfg_offset));
    if cfg_offset = 0 then exit;

    Seek(bundle, cfg_offset);
    cfg:=TMemoryStream.Create();
    c:=chr(0);
    repeat
      BlockRead(bundle, c, sizeof(c));
      if c<>chr(0) then cfg.Write(c, sizeof(c));
    until ((c = chr(0)) or eof(bundle));

    cfg.Seek(0, soBeginning);
    result:=TIniFile.Create(cfg);
    FreeAndNil(cfg);
  except
    FreeAndNil(cfg);
    FreeAndNil(result);
  end;
end;

class function TryHexToInt(hex: string; var out_val: cardinal): boolean;
var
  i: integer; //err code
  r: Int64;   //result
begin
  val('$'+trim(hex),r, i);
  if i<>0 then begin
    result := false;
  end else begin
    result := true;
    out_val:=cardinal(r);
  end;
end;

function ReadFromBundle(var bundle:file; offset:int64; size:int64; var arr:TFileBytes):boolean;
var
  arrsz:integer;
begin
  result:=false;
  try
    if offset+size >= FileSize(bundle) then exit;
    arrsz:=length(arr);
    if int64(arrsz) < size then exit;
    Seek(bundle, offset);
    BlockRead(bundle, arr[0], size);
    result:=true;
  except
    result:=false;
  end;
end;

function ReadFileFromBundle(var bundle:file; cfg:TIniFile; index:cardinal):TFileBytes;
var
  offset, size:int64;
  intsz:integer;
  sect:string;
begin
  setlength(result, 0);
  sect:=FILE_SECT_PREFIX+inttostr(index);
  if not cfg.SectionExists(sect) then exit;
  offset:=cfg.ReadInt64(sect, FILE_KEY_OFFSET, -1);
  size:=cfg.ReadInt64(sect, FILE_KEY_SIZE, -1);
  if (offset < 0) or (size < 0) or (size >= $8FFFFFFF) then exit;
  intsz:=integer(size);
  setlength(result, intsz);
  if not ReadFromBundle(bundle, offset, size, result) then begin
    setlength(result, 0);
  end;
end;

function GetFilesCount(var {%H-}bundle:file; cfg:TIniFile):integer;
begin
  result:=cfg.ReadInteger(MAIN_SECTION, FILES_COUNT_PARAM, 0);
end;

function ValidateBundle(var bundle:file; cfg:TIniFile):boolean;
var
  i, cnt:integer;
  crc32, crc_ref:cardinal;
  sect, crcstr:string;
  ctx:TCRC32Context;
  arr:TFileBytes;
begin
  result:=false;
  setlength(arr, 0);
  try
     cnt:=GetFilesCount(bundle, cfg);
     if cnt <= 0 then exit;
     for i:=0 to cnt-1 do begin
       Application.ProcessMessages();
       sect:=FILE_SECT_PREFIX+inttostr(i);

       if not cfg.SectionExists(sect) then exit;
       if cfg.ReadString(sect, FILE_KEY_PATH, '') = '' then exit;

       crcstr:=cfg.ReadString(sect, FILE_KEY_CRC32, '');
       if crcstr='' then exit;
       crc_ref:=0;
       if not TryHexToInt(crcstr, crc_ref) then exit;

       arr:=ReadFileFromBundle(bundle, cfg, i);
       if length(arr) = 0 then exit;
       Application.ProcessMessages();

       ctx:=CRC32Start();
       crc32:=CRC32End(ctx, @arr[0], length(arr));
       if crc_ref <> crc32 then exit;

       setlength(arr, 0);
     end;
     result:=true;
  except
    result:=false;
    setlength(arr, 0);
  end;
end;

function SelectGuessedGameInstallDir():string;
const
  REG_PATH:string = 'SOFTWARE\GSC Game World\STALKER-COP';
  REG_PARAM:string = 'InstallPath';
var
  reg:TRegistry;
begin
  try
    Reg:=TRegistry.Create(KEY_READ);
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    Reg.OpenKey(REG_PATH,false);
    result:=Reg.ReadString(REG_PARAM);
    Reg.Free;
  except
    result:='';
  end;

  result:=WinCPToUTF8(trim(result));
end;

function CreateFsgame(parent_root:string):boolean;
var
  f:textfile;
begin
  result:=false;
  assignfile(f, FSGAME_PATH);
  try
    rewrite(f);
    parent_root:= '$game_root$ = false| false| '+ UTF8ToWinCP(parent_root);
    writeln(f, parent_root);
    writeln(f, '$app_data_root$ = false | false | $fs_root$| '+USERDATA_PATH);
    writeln(f, '$arch_dir$ = false| false| $game_root$');
    writeln(f, '$arch_dir_levels$ = false| false| $game_root$| levels\');
    writeln(f, '$arch_dir_resources$ = false| false| $game_root$| resources\');
    writeln(f, '$arch_dir_localization$ = false| false| $game_root$| localization\');
    writeln(f, '$arch_dir_patches$ = false| true| $fs_root$| patches\');
    writeln(f, '$game_arch_mp$ = false| false| $game_root$| mp\');
    writeln(f, '$game_data$ = false| true| $fs_root$| gamedata\');
    writeln(f, '$game_ai$ = true| false| $game_data$| ai\');
    writeln(f, '$game_spawn$ = true| false| $game_data$| spawns\');
    writeln(f, '$game_levels$ = true| false| $game_data$| levels\');
    writeln(f, '$game_meshes$ = true| true| $game_data$| meshes\');
    writeln(f, '$game_anims$ = true| true| $game_data$| anims\');
    writeln(f, '$game_dm$ = true| true| $game_data$| meshes\');
    writeln(f, '$game_shaders$ = true| true| $game_data$| shaders\');
    writeln(f, '$game_sounds$ = true| true| $game_data$| sounds\');
    writeln(f, '$game_textures$ = true| true| $game_data$| textures\');
    writeln(f, '$game_config$ = true| false| $game_data$| configs\');
    writeln(f, '$game_weathers$ = true| false| $game_config$| environment\weathers');
    writeln(f, '$game_weather_effects$ = true| false| $game_config$| environment\weather_effects');
    writeln(f, '$textures$ = true| true| $game_data$| textures\');
    writeln(f, '$level$ = false| false| $game_levels$');
    writeln(f, '$game_scripts$ = true| false| $game_data$| scripts\');
    writeln(f, '$logs$ = true| false| $app_data_root$| logs\');
    writeln(f, '$screenshots$ = true| false| $app_data_root$| screenshots\');
    writeln(f, '$game_saves$ = true| false| $app_data_root$| savedgames\');
    writeln(f, '$downloads$ = false| false| $app_data_root$');
    closefile(f);
    result:=true;
  except
    result:=false;
  end;
end;

function CheckAndCorrectUserltx():boolean;

var
  f:textfile;
begin
  result:=FileExists(USERLTX_PATH);
  if not result then begin
    ForceDirectories(USERDATA_PATH);
    assignfile(f, USERLTX_PATH);
    try
      rewrite(f);
      DumpUserLtx(f, screen.Width, screen.Height);
      closefile(f);
      result:=true;
    except
      result:=false;
    end;
  end;
end;

procedure PushToArray(var a:StringsArr; s:string);
var
  i:integer;
begin
  i:=length(a);
  setlength(a, i+1);
  a[i]:=s;
end;

function IsGameInstalledInDir(dir:string):boolean;
var
  files:StringsArr;
  i:integer;
  filename:string;
begin
  result:=false;

  setlength(files, 0);
  PushToArray(files, 'resources\configs.db');
  PushToArray(files, 'resources\resources.db0');
  PushToArray(files, 'resources\resources.db1');
  PushToArray(files, 'resources\resources.db2');
  PushToArray(files, 'resources\resources.db3');
  PushToArray(files, 'resources\resources.db4');
  PushToArray(files, 'levels\levels.db0');
  PushToArray(files, 'levels\levels.db1');

  if (length(dir)>0) and (dir[length(dir)]<>'\') and (dir[length(dir)]<>'/') then begin
    dir:=dir+'\';
  end;

  for i:=0 to length(files)-1 do begin
    filename:=dir+files[i];
    if not FileExists(filename) then begin
      exit;
    end;
  end;

  result:=true;
end;

function PreparePathForFile(filepath:string):boolean;
begin
  result:=false;
  while (length(filepath)>0) and (filepath[length(filepath)]<>'\') and (filepath[length(filepath)]<>'/') do begin
    filepath:=leftstr(filepath, length(filepath)-1);
  end;

  if length(filepath)<=0 then begin
     result:=true;
     exit;
  end;
  result:=ForceDirectories(filepath);
end;

function DirectoryIsEmpty(Directory:string): boolean;
var
  sr: TSearchRec;
  i: Integer;
begin
   Result := false;
   FindFirst( IncludeTrailingPathDelimiter( Directory ) + '*', faAnyFile, sr );
   for i := 1 to 2 do
      if ( sr.Name = '.' ) or ( sr.Name = '..' ) then
         Result := FindNext( sr ) <> 0;
   FindClose( sr );
end;

procedure KillFileAndEmptyDir(filepath:string);
begin
  DeleteFile(filepath);
  while (length(filepath)>0) and (filepath[length(filepath)]<>'\') and (filepath[length(filepath)]<>'/') do begin
   filepath:=leftstr(filepath, length(filepath)-1);
  end;

  if (length(filepath)>0) and DirectoryExists(filepath) and DirectoryIsEmpty(filepath) then begin
    RemoveDir(filepath);
  end;
end;

function RevertChanges(changes_cfg:string):boolean;
var
   install_log:textfile;
   filepath:string;
begin
  result:=false;
  assignfile(install_log, changes_cfg);
  try
    reset(install_log);
    while not eof(install_log) do begin
      readln(install_log, filepath);
      KillFileAndEmptyDir(filepath);
    end;
    KillFileAndEmptyDir(USERLTX_PATH);
    KillFileAndEmptyDir(FSGAME_PATH);
    CloseFile(install_log);
    KillFileAndEmptyDir(changes_cfg)
  except
    result:=false;
  end;
end;

function ConfirmDirForInstall(dir:string):boolean;
var
  res:integer;
begin
  result:=true;
  if not DirectoryExists(dir) then begin
    res:=Application.MessageBox(PAnsiChar(LocalizeString('confirm_dir_unexist')), PAnsiChar(LocalizeString('msg_confirm')), MB_YESNO or MB_ICONQUESTION);
    result:= res=IDYES;
  end else if not DirectoryIsEmpty(dir) then begin
    res:=Application.MessageBox(PAnsiChar(LocalizeString('confirm_dir_nonempty')), PAnsiChar(LocalizeString('msg_confirm')), MB_YESNO or MB_ICONQUESTION);
    result:= res=IDYES;
  end;
end;

function ConfirmGameDir(dir:string):boolean;
var
  res:integer;
begin
  result:=true;
  if not IsGameInstalledInDir(dir) then begin
    res:=Application.MessageBox(PAnsiChar(LocalizeString('msg_no_game_in_dir')), PAnsiChar(LocalizeString('msg_confirm')), MB_YESNO or MB_ICONQUESTION);
    result:= res=IDYES;
  end;
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  _stage:=STAGE_INIT;
  _copydata.started:=false;
  InitializeCriticalSection(_copydata.lock_install);
  HideControls();

  self.Image1.Top:=0;
  self.Image1.Left:=0;
  self.Image1.Width:=self.Image1.Picture.Width;
  self.Image1.Height:=self.Image1.Picture.Height;
  self.Width:=self.Image1.Width;
  self.Height:=self.Image1.Height;

  edit_path.Left:=30;
  edit_path.Width:=self.Width-100;
  edit_path.Top:=(self.Height) div 2;

  progress.Left:=edit_path.Left;
  progress.Width:=edit_path.Width;
  progress.Top:=edit_path.Top;

  lbl_hint.Left:=edit_path.Left;
  lbl_hint.Top:=edit_path.Top - lbl_hint.Height - 2;

  btn_elipsis.Top:=edit_path.Top-1;
  btn_elipsis.Left:=edit_path.Left+edit_path.Width+5;

  btn_next.Top:=edit_path.Top+edit_path.Height+20;
  btn_next.Left:=edit_path.Left + ((edit_path.Width - btn_next.Width) div 2);

  _cfg:=nil;
  SwitchToStage(STAGE_INTEGRITY);
  timer1.Interval:=200;
  timer1.Enabled:=true;
end;

procedure TMainForm.btn_elipsisClick(Sender: TObject);
begin
  SelectDirectoryDialog1.FileName:='';
  SelectDirectoryDialog1.InitialDir:=edit_path.Text;
  if SelectDirectoryDialog1.Execute() then begin
    edit_path.Text:=SelectDirectoryDialog1.FileName;
  end;
end;

procedure TMainForm.btn_nextClick(Sender: TObject);
begin
  if (length(edit_path.Text)>0) and (edit_path.Text[length(edit_path.Text)]<>'\') and (edit_path.Text[length(edit_path.Text)]<>'/') then begin
    edit_path.Text:=edit_path.Text+'\';
  end;

  if (_stage = STAGE_SELECT_DIR) and (ConfirmDirForInstall(edit_path.Text)) then begin
    _mod_dir:=edit_path.Text;
     SwitchToStage(STAGE_SELECT_GAME_DIR);
  end else if (_stage = STAGE_SELECT_GAME_DIR) and (ConfirmGameDir(edit_path.Text)) then begin
     _game_dir:=edit_path.Text;
     SwitchToStage(STAGE_INSTALL);
  end else if (_stage = STAGE_BAD) or (_stage=STAGE_OK) then begin
    Application.Terminate();
  end else if (_stage = STAGE_PACKING) then begin
    if BundleToInstaller(edit_path.Text, Application.ExeName) then begin
      Application.MessageBox(PAnsiChar(LocalizeString('packing_completed')), '', MB_OK);
      SwitchToStage(STAGE_OK);
    end else begin
      _bad_msg:='err_unk';
      SwitchToStage(STAGE_BAD);
    end;
  end;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  res:integer;
  dis_tmr:boolean;
begin
  if (_stage=STAGE_OK) or (_stage=STAGE_BAD) then begin
    exit;
  end;

  CloseAction:=caNone;
  dis_tmr:=false;
  if Timer1.Enabled then begin
    dis_tmr:=true;
    timer1.Enabled:=false;
  end;

  res:=Application.MessageBox(PAnsiChar(LocalizeString('confirm_close')), PAnsiChar(LocalizeString('msg_confirm')), MB_YESNO or MB_ICONQUESTION);
  if res = IDYES then begin
    _bad_msg:=LocalizeString('user_cancelled');
    SwitchToStage(STAGE_BAD);
  end;

  if dis_tmr then begin
    timer1.Enabled:=true;
  end;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FreeAndNil(_cfg);
  DeleteCriticalSection(_copydata.lock_install);
end;

procedure TMainForm.HideControls();
begin
  edit_path.Text:='';
  edit_path.Hide;
  lbl_hint.Caption:='';
  lbl_hint.Hide;
  btn_elipsis.Hide;
  btn_next.Hide;
  progress.hide;
end;

procedure CopierThread(frm:TMainForm); stdcall;
var
  bundle:file;
  cfg:TIniFile;
  badmsg:string;

  install_log:textfile;
  i, total:integer;
  arr:TFileBytes;
  fname:string;
  outf:file;
begin
  EnterCriticalSection(frm._copydata.lock_install);
  try
     frm._copydata.started:=true;
     frm._copydata.completed_out:=false;
     frm._copydata.progress_out:=0;
     frm._copydata.error_out:='';

     bundle:=frm._bundle;
     cfg:=frm._cfg;
  finally
    LeaveCriticalSection(frm._copydata.lock_install);
  end;

  badmsg:='';
  setlength(arr, 0);

  //Start magic
  assignfile(install_log, UNINSTALL_DATA_PATH);
  try
    rewrite(install_log);
    total:=GetFilesCount(bundle, cfg);
    for i:=0 to total-1 do begin
      EnterCriticalSection(frm._copydata.lock_install);
      try
        //Check for stop cmd
        frm._copydata.progress_out:= (i+1) / total;
        if frm._copydata.cmd_in_stop then begin;
          badmsg:='user_cancelled';
        end;
      finally
        LeaveCriticalSection(frm._copydata.lock_install);
      end;

      if badmsg<>'' then break;
      //-------------
      arr:=ReadFileFromBundle(bundle, cfg, i);
      if length(arr) = 0 then begin
        badmsg:='err_cant_read_bundle_content';
        break;
      end;

      fname:=cfg.ReadString(FILE_SECT_PREFIX+inttostr(i), FILE_KEY_PATH, '');
      writeln(install_log, fname);
      if not PreparePathForFile(fname) then begin
        badmsg:='err_cant_create_dir';
      end else begin
        assignfile(outf, fname);
        try
          rewrite(outf, 1);
          BlockWrite(outf, arr[0], length(arr));
          closefile(outf);
        except
          badmsg:='err_writing_file';
        end;
      end;
      if badmsg<>'' then break;
    end;
  except
    badmsg:='err_unk';
  end;

  try
    // Guarantee file closing - need for further revert
    closefile(install_log);
  except
  end;

  setlength(arr, 0);
  // Finish
  EnterCriticalSection(frm._copydata.lock_install);
  try
     frm._copydata.completed_out:=true;
     frm._copydata.error_out:=badmsg;
     frm._copydata.progress_out:=1;
  finally
    LeaveCriticalSection(frm._copydata.lock_install);
  end;
end;

procedure TMainForm.Timer1Timer(Sender: TObject);
var
  valid_bundle:boolean;
  cfg:TIniFile;
  build_id:string;
  tid:cardinal;

begin
  if (_stage = STAGE_INTEGRITY) and (_cfg = nil) then begin
    timer1.Enabled:=false;

    assignfile(_bundle, Application.ExeName);
    valid_bundle:=false;
    cfg:=nil;
    try
      FileMode:=fmOpenRead;
      reset(_bundle, 1);
      cfg:=GetMainConfigFromBundle(_bundle);
      if cfg <> nil then begin
        build_id:=cfg.ReadString(MAIN_SECTION, BUILD_ID_PARAM, '');
        if length(build_id) > 0 then begin
          self.Caption:=self.Caption+' ('+build_id+')';
        end;
        valid_bundle:=ValidateBundle(_bundle, cfg);
      end else begin
        valid_bundle:=false;
      end;
    except
      valid_bundle:=false;
    end;

    if valid_bundle then begin
      _cfg:=cfg;
      SwitchToStage(STAGE_SELECT_DIR);
    end else if (cfg=nil) then begin
      FreeAndNil(cfg);
      CloseFile(_bundle);
      SwitchToStage(STAGE_PACKING);
    end else begin
      Application.MessageBox(PAnsiChar(LocalizeString('err_bundle_corrupt')),PAnsiChar(LocalizeString('err_caption')), MB_OK);
      FreeAndNil(cfg);
      CloseFile(_bundle);
      SwitchToStage(STAGE_BAD);
      _bad_msg:='err_cant_read_bundle_content';
    end;
    timer1.Enabled:=true;

  end else if _stage = STAGE_INSTALL then begin
    timer1.Enabled:=false;
    _bad_msg:='';
    EnterCriticalSection(_copydata.lock_install);
    try
      if _copydata.progress_out < 0 then begin
        _copydata.progress_out:=0;
        _copydata.completed_out:=false;
        _copydata.cmd_in_stop:=false;
        _copydata.error_out:='';
        _copydata.started:=true;;
        if not ForceDirectories(_mod_dir) or not SetCurrentDir(_mod_dir) then begin
          _bad_msg:='err_cant_create_dir';
          SwitchToStage(STAGE_BAD);
        end else begin
          _mod_dir:='./';
          tid:=0;
          _th_handle:=CreateThread(nil, 0, @CopierThread, self, 0, tid);
          if _th_handle = 0 then begin
            _copydata.started:=false;
          end;
          CloseHandle(_th_handle);
        end;
      end else if _copydata.completed_out then begin;
        if length(_copydata.error_out) > 0 then begin
          _bad_msg:=_copydata.error_out;
          SwitchToStage(STAGE_BAD);
        end else begin
          SwitchToStage(STAGE_CONFIG);
        end;
      end;
      progress.Position:=progress.Min+round((progress.Max-progress.Min)*_copydata.progress_out);
    finally
      LeaveCriticalSection(_copydata.lock_install);
    end;
    timer1.Enabled:=true;

  end else if _stage = STAGE_CONFIG then begin
    timer1.Enabled:=false;
    if not CreateFsgame(_game_dir) or not CheckAndCorrectUserltx() then begin
      _bad_msg:='err_writing_file';
      SwitchToStage(STAGE_BAD);
    end else begin
      SwitchToStage(STAGE_OK);
    end;
    timer1.Enabled:=true;

  end else if _stage = STAGE_BAD then begin
    timer1.Enabled:=false;
    EnterCriticalSection(_copydata.lock_install);
    try
      if _copydata.started and not _copydata.completed_out then begin
        _copydata.cmd_in_stop:=true;
      end else if _copydata.started then begin
        RevertChanges(UNINSTALL_DATA_PATH);
        _copydata.started:=false;
      end else begin
        lbl_hint.Caption:=LocalizeString(_bad_msg);
        btn_next.Enabled:=true;
      end;
    finally
      LeaveCriticalSection(_copydata.lock_install);
    end;
    timer1.Enabled:=true;
  end;
end;

procedure TMainForm.SwitchToStage(s: TInstallStage);
begin
  HideControls();
  case s of
    STAGE_INTEGRITY: begin
      assert(_stage = STAGE_INIT);
      lbl_hint.Caption:=LocalizeString('stage_integrity_check');
      lbl_hint.Show;
    end;

    STAGE_PACKING: begin
      assert(_stage = STAGE_INIT);
      lbl_hint.Caption:=LocalizeString('stage_packing_select');
      lbl_hint.Show;
      btn_next.Caption:=LocalizeString('btn_next');
      btn_next.Show();
      edit_path.Text:=GetCurrentDir();
      edit_path.Show;
      btn_elipsis.Show();
    end;

    STAGE_SELECT_DIR: begin
      assert(_stage = STAGE_INTEGRITY);
      btn_next.Caption:=LocalizeString('btn_next');
      btn_next.Show();
      edit_path.Text:=GetCurrentDir()+'\GUNSLINGER_Mod\';
      edit_path.Show;
      lbl_hint.Caption:=LocalizeString('hint_select_install_dir');
      lbl_hint.Show();
      btn_elipsis.Show();
    end;

    STAGE_SELECT_GAME_DIR: begin
      assert(_stage = STAGE_SELECT_DIR);
      btn_next.Caption:=LocalizeString('btn_next');
      btn_next.Show();
      edit_path.Text:=SelectGuessedGameInstallDir();
      edit_path.Show;
      lbl_hint.Caption:=LocalizeString('hint_select_game_dir');
      lbl_hint.Show();
      btn_elipsis.Show();
    end;

    STAGE_INSTALL: begin
      assert(_stage = STAGE_SELECT_GAME_DIR);
      lbl_hint.Caption:=LocalizeString('installing');
      lbl_hint.Show();
      progress.Max:=100;
      progress.Min:=0;
      progress.Position:=0;
      progress.Show();
      _copydata.progress_out:=-1;
      _copydata.started:=false;
    end;

    STAGE_CONFIG: begin
      assert(_stage = STAGE_INSTALL);
      lbl_hint.Caption:=LocalizeString('stage_finalizing');
      lbl_hint.Show();
    end;

    STAGE_OK: begin
      btn_next.Caption:=LocalizeString('exit_installer');
      btn_next.Show();
      lbl_hint.Caption:=LocalizeString('success_install');
      lbl_hint.Show();
    end;

    STAGE_BAD: begin
      btn_next.Caption:=LocalizeString('exit_installer');
      btn_next.Show();
      lbl_hint.Caption:=LocalizeString('reverting_changes');
      lbl_hint.Show();
      btn_next.Enabled:=false;
    end;
  end;
  _stage:=s;
end;

end.

