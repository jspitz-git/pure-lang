#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN

/*
  Build from an x64 Visual Studio Developer Command Prompt:

    cl /nologo /W4 /WX /TC windows_canonicalize_appcontainer.c ^
      /link userenv.lib advapi32.lib

  The ordinary child mode is:

    windows_canonicalize_appcontainer.exe --probe TARGET OUTPUT

  The packaged child mode is launched through:

    windows_canonicalize_appcontainer.exe --appcontainer ^
      UNIQUE_PROFILE STAGE WORK PROBE TARGET

  STAGE must contain PROBE and TARGET.  WORK must be a child of STAGE.  Run the
  ordinary child first against TARGET, then the packaged launcher against the
  exact same TARGET.  The launcher bounds the child wait and always attempts to
  delete the profile that it created.  The caller owns the disposable STAGE and
  must remove and verify it in a finally block after collecting both outputs.
*/

#include <windows.h>
#include <aclapi.h>
#include <userenv.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

enum
{
  probe_ok = 0,
  probe_canonicalize_red = 10,
  probe_create_file_failed = 20,
  probe_read_failed = 21,
  probe_enumeration_failed = 22,
  probe_output_failed = 23,
  launcher_usage = 64,
  launcher_profile_failed = 65,
  launcher_acl_failed = 66,
  launcher_process_failed = 67,
  launcher_timeout = 68,
  launcher_cleanup_failed = 69
};

static void
append_line (char *output, size_t output_size, const char *format, ...)
{
  size_t used = strlen (output);
  va_list args;

  if (used >= output_size)
    return;

  va_start (args, format);
  _vsnprintf_s (output + used, output_size - used, _TRUNCATE, format, args);
  va_end (args);
}

static void
append_wide_path (char *output, size_t output_size, const char *label,
                  const wchar_t *path, DWORD length)
{
  char utf8[32767];
  int converted = 0;

  if (length > 0 && length < sizeof (utf8))
    converted = WideCharToMultiByte (CP_UTF8, 0, path, (int) length,
                                     utf8, (int) sizeof (utf8) - 1,
                                     NULL, NULL);

  if (converted > 0)
    {
      utf8[converted] = '\0';
      append_line (output, output_size, "%s=%s\r\n", label, utf8);
    }
  else
    append_line (output, output_size, "%s=\r\n", label);
}

static int
write_output (const wchar_t *path, const char *output)
{
  DWORD written = 0;
  DWORD size = (DWORD) strlen (output);
  HANDLE file = CreateFileW (path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                             FILE_ATTRIBUTE_NORMAL, NULL);

  if (file == INVALID_HANDLE_VALUE)
    return 0;

  int ok = WriteFile (file, output, size, &written, NULL) && written == size;
  CloseHandle (file);
  return ok;
}

static int
enumerate_target (const wchar_t *path, DWORD *error)
{
  wchar_t search[MAX_PATH * 4];
  const wchar_t *leaf;
  WIN32_FIND_DATAW data;
  HANDLE find;
  int found = 0;

  if (wcslen (path) + 2 >= sizeof (search) / sizeof (search[0]))
    {
      *error = ERROR_BUFFER_OVERFLOW;
      return 0;
    }

  wcscpy_s (search, sizeof (search) / sizeof (search[0]), path);
  leaf = wcsrchr (search, L'\\');
  if (! leaf)
    leaf = wcsrchr (search, L'/');
  if (! leaf)
    {
      *error = ERROR_INVALID_NAME;
      return 0;
    }

  wchar_t expected[MAX_PATH * 4];
  wcscpy_s (expected, sizeof (expected) / sizeof (expected[0]), leaf + 1);
  search[leaf - search + 1] = L'*';
  search[leaf - search + 2] = L'\0';

  SetLastError (ERROR_SUCCESS);
  find = FindFirstFileW (search, &data);
  if (find == INVALID_HANDLE_VALUE)
    {
      *error = GetLastError ();
      return 0;
    }

  do
    {
      if (_wcsicmp (data.cFileName, expected) == 0)
        {
          found = 1;
          break;
        }
    }
  while (FindNextFileW (find, &data));

  *error = found ? ERROR_SUCCESS : GetLastError ();
  FindClose (find);
  return found;
}

static int
run_probe (const wchar_t *target, const wchar_t *output_path)
{
  char output[8192] = "";
  wchar_t normalized[32767] = L"";
  wchar_t opened[32767] = L"";
  union
  {
    FILE_NAME_INFO alignment;
    unsigned char storage[sizeof (FILE_NAME_INFO)
                          + 32767 * sizeof (wchar_t)];
  } file_info_buffer;
  FILE_NAME_INFO *file_info
    = (FILE_NAME_INFO *) file_info_buffer.storage;
  DWORD normalized_error;
  DWORD normalized_length;
  DWORD opened_error;
  DWORD opened_length;
  DWORD file_info_error;
  DWORD file_info_length;
  BOOL file_info_ok;
  DWORD open_error;
  DWORD read_error = ERROR_SUCCESS;
  DWORD enum_error = ERROR_SUCCESS;
  DWORD bytes_read = 0;
  unsigned char byte = 0;

  SetLastError (ERROR_SUCCESS);
  HANDLE canonical_handle
    = CreateFileW (target, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                   FILE_FLAG_BACKUP_SEMANTICS, NULL);
  open_error = (canonical_handle == INVALID_HANDLE_VALUE
                ? GetLastError () : ERROR_SUCCESS);
  append_line (output, sizeof (output), "CREATEFILE_HANDLE=%d ERROR=%lu\r\n",
               canonical_handle != INVALID_HANDLE_VALUE,
               (unsigned long) open_error);

  if (canonical_handle == INVALID_HANDLE_VALUE)
    {
      write_output (output_path, output);
      return probe_create_file_failed;
    }

  SetLastError (ERROR_SUCCESS);
  normalized_length
    = GetFinalPathNameByHandleW (canonical_handle, normalized,
                                 (DWORD) (sizeof (normalized)
                                          / sizeof (normalized[0])),
                                 FILE_NAME_NORMALIZED);
  normalized_error = GetLastError ();
  append_line (output, sizeof (output),
               "GETFINAL_NORMALIZED_LENGTH=%lu ERROR=%lu NONEMPTY=%d\r\n",
               (unsigned long) normalized_length,
               (unsigned long) normalized_error,
               normalized_length > 0 && normalized[0] != L'\0');
  append_wide_path (output, sizeof (output), "GETFINAL_NORMALIZED_PATH",
                    normalized, normalized_length);

  SetLastError (ERROR_SUCCESS);
  opened_length
    = GetFinalPathNameByHandleW (canonical_handle, opened,
                                 (DWORD) (sizeof (opened)
                                          / sizeof (opened[0])),
                                 FILE_NAME_OPENED);
  opened_error = GetLastError ();
  append_line (output, sizeof (output),
               "GETFINAL_OPENED_LENGTH=%lu ERROR=%lu NONEMPTY=%d\r\n",
               (unsigned long) opened_length,
               (unsigned long) opened_error,
               opened_length > 0 && opened[0] != L'\0');
  append_wide_path (output, sizeof (output), "GETFINAL_OPENED_PATH",
                    opened, opened_length);

  ZeroMemory (&file_info_buffer, sizeof (file_info_buffer));
  SetLastError (ERROR_SUCCESS);
  file_info_ok
    = GetFileInformationByHandleEx (canonical_handle, FileNameInfo,
                                    file_info,
                                    (DWORD) sizeof (file_info_buffer));
  file_info_error = GetLastError ();
  file_info_length
    = file_info_ok ? file_info->FileNameLength / sizeof (wchar_t) : 0;
  append_line (output, sizeof (output),
               "FILE_NAME_INFO_OK=%d LENGTH=%lu ERROR=%lu NONEMPTY=%d\r\n",
               file_info_ok, (unsigned long) file_info_length,
               (unsigned long) file_info_error,
               file_info_length > 0 && file_info->FileName[0] != L'\0');
  append_wide_path (output, sizeof (output), "FILE_NAME_INFO_PATH",
                    file_info->FileName, file_info_length);
  CloseHandle (canonical_handle);

  SetLastError (ERROR_SUCCESS);
  HANDLE read_handle
    = CreateFileW (target, GENERIC_READ,
                   FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                   NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  int read_ok = (read_handle != INVALID_HANDLE_VALUE
                 && ReadFile (read_handle, &byte, 1, &bytes_read, NULL)
                 && bytes_read == 1);
  if (! read_ok)
    read_error = GetLastError ();
  if (read_handle != INVALID_HANDLE_VALUE)
    CloseHandle (read_handle);
  append_line (output, sizeof (output),
               "READFILE=%d ERROR=%lu BYTES=%lu BYTE=%u\r\n",
               read_ok, (unsigned long) read_error,
               (unsigned long) bytes_read, (unsigned int) byte);

  int enum_ok = enumerate_target (target, &enum_error);
  append_line (output, sizeof (output), "ENUMERATION=%d ERROR=%lu\r\n",
               enum_ok, (unsigned long) enum_error);

  if (! write_output (output_path, output))
    return probe_output_failed;
  if (! read_ok)
    return probe_read_failed;
  if (! enum_ok)
    return probe_enumeration_failed;
  if (normalized_length == 0 || normalized[0] == L'\0')
    return probe_canonicalize_red;
  return probe_ok;
}

static DWORD
grant_path (const wchar_t *path, PSID sid, DWORD permissions)
{
  PACL old_dacl = NULL;
  PACL new_dacl = NULL;
  PSECURITY_DESCRIPTOR descriptor = NULL;
  EXPLICIT_ACCESSW access;
  DWORD status
    = GetNamedSecurityInfoW ((LPWSTR) path, SE_FILE_OBJECT,
                             DACL_SECURITY_INFORMATION, NULL, NULL,
                             &old_dacl, NULL, &descriptor);

  if (status != ERROR_SUCCESS)
    return status;

  ZeroMemory (&access, sizeof (access));
  access.grfAccessPermissions = permissions;
  access.grfAccessMode = GRANT_ACCESS;
  access.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
  access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
  access.Trustee.TrusteeType = TRUSTEE_IS_WELL_KNOWN_GROUP;
  access.Trustee.ptstrName = (LPWSTR) sid;

  status = SetEntriesInAclW (1, &access, old_dacl, &new_dacl);
  if (status == ERROR_SUCCESS)
    status = SetNamedSecurityInfoW ((LPWSTR) path, SE_FILE_OBJECT,
                                    DACL_SECURITY_INFORMATION, NULL, NULL,
                                    new_dacl, NULL);

  if (new_dacl)
    LocalFree (new_dacl);
  if (descriptor)
    LocalFree (descriptor);
  return status;
}

static wchar_t *
quote_command (const wchar_t *probe, const wchar_t *target,
               const wchar_t *output)
{
  size_t needed = wcslen (probe) + wcslen (target) + wcslen (output) + 64;
  wchar_t *command = (wchar_t *) calloc (needed, sizeof (wchar_t));
  if (command)
    _snwprintf_s (command, needed, _TRUNCATE,
                  L"\"%ls\" --probe \"%ls\" \"%ls\"",
                  probe, target, output);
  return command;
}

static int
run_appcontainer (const wchar_t *profile_name, const wchar_t *stage_root,
                  const wchar_t *work_root, const wchar_t *probe,
                  const wchar_t *target)
{
  PSID appcontainer_sid = NULL;
  HRESULT create_result
    = CreateAppContainerProfile (profile_name, profile_name, profile_name,
                                 NULL, 0, &appcontainer_sid);
  int profile_created = SUCCEEDED (create_result);
  int result = launcher_profile_failed;
  DWORD acl_status = ERROR_SUCCESS;
  wchar_t output_path[MAX_PATH * 4];
  wchar_t *command = NULL;
  SIZE_T attribute_size = 0;
  STARTUPINFOEXW startup;
  PROCESS_INFORMATION process;
  SECURITY_CAPABILITIES capabilities;

  ZeroMemory (&startup, sizeof (startup));
  ZeroMemory (&process, sizeof (process));
  ZeroMemory (&capabilities, sizeof (capabilities));

  if (! profile_created)
    {
      fwprintf (stderr, L"PROFILE_CREATE_HRESULT=0x%08lx\n",
                (unsigned long) create_result);
      return launcher_profile_failed;
    }

  acl_status = grant_path (stage_root, appcontainer_sid,
                           FILE_GENERIC_READ | FILE_GENERIC_EXECUTE);
  if (acl_status == ERROR_SUCCESS)
    acl_status = grant_path (work_root, appcontainer_sid,
                             FILE_GENERIC_READ | FILE_GENERIC_WRITE
                             | FILE_GENERIC_EXECUTE | DELETE);
  if (acl_status != ERROR_SUCCESS)
    {
      fprintf (stderr, "ACL_ERROR=%lu\n", (unsigned long) acl_status);
      result = launcher_acl_failed;
      goto cleanup;
    }

  if (_snwprintf_s (output_path, sizeof (output_path) / sizeof (output_path[0]),
                    _TRUNCATE, L"%ls\\appcontainer.txt", work_root) < 0)
    {
      result = launcher_process_failed;
      goto cleanup;
    }
  command = quote_command (probe, target, output_path);
  if (! command)
    {
      result = launcher_process_failed;
      goto cleanup;
    }

  InitializeProcThreadAttributeList (NULL, 1, 0, &attribute_size);
  startup.lpAttributeList
    = (LPPROC_THREAD_ATTRIBUTE_LIST) calloc (1, attribute_size);
  if (! startup.lpAttributeList
      || ! InitializeProcThreadAttributeList (startup.lpAttributeList, 1, 0,
                                              &attribute_size))
    {
      fprintf (stderr, "ATTRIBUTE_LIST_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_process_failed;
      goto cleanup;
    }

  capabilities.AppContainerSid = appcontainer_sid;
  capabilities.Capabilities = NULL;
  capabilities.CapabilityCount = 0;
  capabilities.Reserved = 0;
  if (! UpdateProcThreadAttribute (
        startup.lpAttributeList, 0,
        PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,
        &capabilities, sizeof (capabilities), NULL, NULL))
    {
      fprintf (stderr, "ATTRIBUTE_UPDATE_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_process_failed;
      goto cleanup;
    }

  startup.StartupInfo.cb = sizeof (startup);
  if (! CreateProcessW (probe, command, NULL, NULL, FALSE,
                        EXTENDED_STARTUPINFO_PRESENT
                        | CREATE_UNICODE_ENVIRONMENT,
                        NULL, work_root, &startup.StartupInfo, &process))
    {
      fprintf (stderr, "CREATEPROCESS_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_process_failed;
      goto cleanup;
    }

  DWORD wait_result = WaitForSingleObject (process.hProcess, 15000);
  if (wait_result != WAIT_OBJECT_0)
    {
      TerminateProcess (process.hProcess, launcher_timeout);
      WaitForSingleObject (process.hProcess, 5000);
      result = launcher_timeout;
      goto cleanup;
    }

  DWORD exit_code = launcher_process_failed;
  if (! GetExitCodeProcess (process.hProcess, &exit_code))
    {
      fprintf (stderr, "GET_EXIT_CODE_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_process_failed;
      goto cleanup;
    }
  result = (int) exit_code;

 cleanup:
  if (process.hThread)
    CloseHandle (process.hThread);
  if (process.hProcess)
    CloseHandle (process.hProcess);
  if (startup.lpAttributeList)
    {
      DeleteProcThreadAttributeList (startup.lpAttributeList);
      free (startup.lpAttributeList);
    }
  free (command);
  if (appcontainer_sid)
    FreeSid (appcontainer_sid);

  if (profile_created)
    {
      HRESULT delete_result = DeleteAppContainerProfile (profile_name);
      if (FAILED (delete_result))
        {
          fwprintf (stderr, L"PROFILE_DELETE_HRESULT=0x%08lx\n",
                    (unsigned long) delete_result);
          result = launcher_cleanup_failed;
        }
      else
        printf ("PROFILE_DELETE_HRESULT=0x00000000\n");
    }

  return result;
}

int
wmain (int argc, wchar_t **argv)
{
  if (argc == 4 && wcscmp (argv[1], L"--probe") == 0)
    return run_probe (argv[2], argv[3]);

  if (argc == 7 && wcscmp (argv[1], L"--appcontainer") == 0)
    return run_appcontainer (argv[2], argv[3], argv[4], argv[5], argv[6]);

  fwprintf (stderr,
            L"usage:\n"
            L"  %ls --probe TARGET OUTPUT\n"
            L"  %ls --appcontainer PROFILE STAGE WORK PROBE TARGET\n",
            argv[0], argv[0]);
  return launcher_usage;
}
