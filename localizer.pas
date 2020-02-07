unit Localizer;

{$mode objfpc}{$H+}

interface

function LocalizeString(str:string):string;

implementation
uses windows;

function LocalizeString(str: string): string;
var
  locale:cardinal;
const
  RUS_ID:cardinal=1049;
begin
  result:=str;
  locale:=GetSystemDefaultLangID();
  if str = 'err_caption' then begin
      if locale = RUS_ID then result:='Ошибка!' else result:='Error!';
  end else if str = 'err_bundle_corrupt' then begin
    if locale = RUS_ID then result:='Установочные файлы мода повреждены!' else result:='The installer is corrupted!';
  end else if str = 'btn_next' then begin
    if locale = RUS_ID then result:='Далее' else result:='Next';
  end else if str = 'stage_integrity_check' then begin
    if locale = RUS_ID then result:='Пожалуйста, подождите...' else result:='Please wait...';
  end else if str = 'hint_select_install_dir' then begin
    if locale = RUS_ID then result:='Укажите путь для установки мода (желательно только из латинских символов)' else result:='Select the installation directory for the mod (please use Latin symbols only)';
  end else if str = 'msg_confirm' then begin
    if locale = RUS_ID then result:='Требуется подтверждение' else result:='Please confirm';
  end else if str = 'confirm_dir_nonempty' then begin
    if locale = RUS_ID then result:='Выбранная Вами директория не пуста. Продолжить установку в нее?' else result:='The selected directory is not empty, continue installation?';
  end else if str = 'confirm_dir_unexist' then begin
    if locale = RUS_ID then result:='Выбранная Вами директория не существует. Создать и продолжить установку в нее?' else result:='The selected directory doesn''t exist. Create it and continue installation?';
  end else if str = 'hint_select_game_dir' then begin
    if locale = RUS_ID then result:='Выберите директорию, в которой установлена оригинальная игра' else result:='Please select the directory where the game is installed';
  end else if str = 'msg_no_game_in_dir' then begin
    if locale = RUS_ID then result:='Похоже, что оригинальная игра НЕ установлена в выбраной Вами директории. Продолжить?' else result:='Looks like the game is NOT installed in the selected directory. Continue anyway?';
  end else if str = 'installing' then begin
    if locale = RUS_ID then result:='Подождите, идет установка мода...' else result:='Installing mod, please wait...';
  end else if str = 'err_cant_create_dir' then begin
    if locale = RUS_ID then result:='Не удалось создать директорию' else result:='Can''t create directory';
  end else if str = 'err_cant_read_bundle_content' then begin
    if locale = RUS_ID then result:='Не удалось прочитать файл с контентом' else result:='Can''t read content file';
  end else if str = 'err_writing_file' then begin
    if locale = RUS_ID then result:='Не удалось записать файл с контентом' else result:='Can''t write content file';
  end else if str = 'stage_finalizing'  then begin
    if locale = RUS_ID then result:='Настройка мода...' else result:='Finalizing...';
  end else if str = 'err_unk'  then begin
    if locale = RUS_ID then result:='Неизвестная ошибка' else result:='Unknown error';
  end else if str = 'exit_installer'  then begin
    if locale = RUS_ID then result:='Выход' else result:='Exit';
  end else if str = 'success_install'  then begin
    if locale = RUS_ID then result:='Установка успешно завершена' else result:='The mod has been successfully installed';
  end else if str = 'confirm_close'  then begin
    if locale = RUS_ID then result:='Выйти из установщика?' else result:='Exit installer?';
  end else if str = 'user_cancelled'  then begin
    if locale = RUS_ID then result:='Отменено пользователем' else result:='Cancelled by user';
  end else if str = 'reverting_changes'  then begin
    if locale = RUS_ID then result:='Идет завершение установки и откат изменений, подождите...' else result:='Stopping installation, please wait...';
  end else if str = 'stage_packing_select'  then begin
    if locale = RUS_ID then result:='Выберите директорию для упаковки' else result:='Select directory for packing';
  end else if str = 'packing_completed'  then begin
    if locale = RUS_ID then result:='Запаковка успешно завершена' else result:='Packing successful';
  end else if str = 'gamedir_not_supported'  then begin
    if locale = RUS_ID then result:='Директория не подходит для установки мода. Пожалуйста, выберите другую.' else result:='The mod can''t be installed to the selected directory. Please select another location.';
  end;
end;

end.

