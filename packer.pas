unit packer;

{$mode objfpc}{$H+}

interface

function BundleToInstaller(folder: string; installer: string):boolean;

implementation
uses sysutils, FastCrc, strutils;

type
  TFileData = array of char;

function RecurseAdd(folder:string; path_appendix:string; var cur_file_id:integer; var bundle:file; var config:string):boolean;
var
  searchResult : TSearchRec;
  f:file;
  arr:TFileData;
  pos, sz:int64;
  ctx:TCRC32Context;
  crc32:cardinal;
begin
  result:=true;

  if (length(folder)>0) and (folder[length(folder)]<>'\') and (folder[length(folder)]<>'/') then begin
    folder:=folder+'\';
  end;

  if (length(path_appendix)>0) and (path_appendix[length(path_appendix)]<>'\') and (path_appendix[length(path_appendix)]<>'/') then begin
    path_appendix:=path_appendix+'\';
  end;

  if FindFirst(folder+'*.*', faAnyFile, searchResult) = 0 then begin
    repeat
      if (searchResult.Attr and faDirectory)<>0 then begin
        if (searchResult.Name<>'.') and (searchResult.Name<>'..') then begin
          result:=RecurseAdd(folder+searchResult.Name, path_appendix+searchResult.Name, cur_file_id, bundle, config);
        end;
      end else begin
        assignfile(f, folder+searchResult.Name);
        try
          FileMode:=fmOpenRead;
          reset(f, 1);
          pos:=FileSize(bundle);
          sz:=FileSize(f);
          SetLength(arr, sz);
          BlockRead(f, arr[0], length(arr));
          BlockWrite(bundle, arr[0], length(arr));

          closefile(f);
          config:=config+'[file_'+inttostr(cur_file_id)+']'+chr($0d)+chr($0a);
          config:=config+'path='+path_appendix+searchResult.Name+chr($0d)+chr($0a);
          config:=config+'offset='+inttostr(pos)+chr($0d)+chr($0a);
          config:=config+'size='+inttostr(sz)+chr($0d)+chr($0a);

          ctx:=CRC32Start();
          crc32:=CRC32End(ctx, @arr[0], length(arr));
          config:=config+'crc32='+inttohex(crc32, 8)+chr($0d)+chr($0a);

          SetLength(arr, 0);
          cur_file_id:=cur_file_id+1;
        except
          result:=false;
        end;
      end;
    until result=true and (FindNext(searchResult) <> 0);
  end;
end;

function BundleToInstaller(folder: string; installer: string):boolean;
var
  srcfile, dstfile:file;
  newname:string;
  config:string;
  cur_file_id:integer;
  cfg_offset:int64;

  arr:TFileData;
begin
  result:=false;
  newname:=installer+'_';
  try
    FileMode:=fmOpenRead;
    assignfile(srcfile, installer);
    reset(srcfile, 1);

    FileMode:=fmOpenReadWrite;
    assignfile(dstfile, newname);
    rewrite(dstfile, 1);

    SetLength(arr, FileSize(srcfile));
    BlockRead(srcfile, arr[0], length(arr));
    BlockWrite(dstfile, arr[0], length(arr));
    CloseFile(srcfile);
    SetLength(arr, 0);

    cur_file_id:=0;
    config:='';
    if RecurseAdd(folder, '', cur_file_id, dstfile, config) then begin
      cfg_offset:=FileSize(dstfile);
      config:=config+'[main]'+chr($0d)+chr($0a);
      config:=config+'build_id=BUILD_'+{$INCLUDE %DATE}+chr($0d)+chr($0a);
      config:=config+'files_count='+inttostr(cur_file_id)+chr($0d)+chr($0a);
      BlockWrite(dstfile, config[1], length(config));
      BlockWrite(dstfile, cfg_offset, sizeof(cfg_offset));
      result:=true;
    end;
  except
    result:=false;
  end;
end;

end.

