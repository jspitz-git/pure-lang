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

#include <limits.h>
#include <wctype.h>
#include <stddef.h>
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
  probe_candidate_rejected = 25,
  launcher_usage = 64,
  launcher_profile_failed = 65,
  launcher_acl_failed = 66,
  launcher_process_failed = 67,
  launcher_timeout = 68,
  launcher_cleanup_failed = 69,
  launcher_token_failed = 70,
  launcher_resume_failed = 71,
  launcher_wait_failed = 72,
  launcher_termination_failed = 73,
  probe_file_name_info_failed = 24
};

typedef enum
{
  mutation_none = 0,
  mutation_force_fallback,
  mutation_volume_mismatch,
  mutation_reparse,
  mutation_malformed_path
} fallback_mutation;

typedef struct
{
  char *data;
  size_t length;
  size_t capacity;
  int failed;
} output_builder;

static void
initialize_output (output_builder *output)
{
  output->length = 0;
  output->capacity = 1024;
  output->data = (char *) calloc (output->capacity, sizeof (char));
  output->failed = output->data == NULL;
}

static int
reserve_output (output_builder *output, size_t additional)
{
  size_t required;
  size_t capacity;
  char *resized;

  if (output->failed)
    return 0;

  if (additional > (size_t) -1 - output->length - 1)
    {
      output->failed = 1;
      return 0;
    }

  required = output->length + additional + 1;
  if (required <= output->capacity)
    return 1;

  capacity = output->capacity;
  while (capacity < required)
    {
      if (capacity > (size_t) -1 / 2)
        {
          capacity = required;
          break;
        }
      capacity *= 2;
    }

  resized = (char *) realloc (output->data, capacity);
  if (! resized)
    {
      output->failed = 1;
      return 0;
    }

  output->data = resized;
  output->capacity = capacity;
  return 1;
}

static int
append_line (output_builder *output, const char *format, ...)
{
  va_list args;
  int required;
  int written;

  if (output->failed)
    return 0;

  va_start (args, format);
  required = _vscprintf (format, args);
  va_end (args);
  if (required < 0
      || ! reserve_output (output, (size_t) required))
    {
      output->failed = 1;
      return 0;
    }

  va_start (args, format);
  written
    = _vsnprintf_s (output->data + output->length,
                    output->capacity - output->length, _TRUNCATE,
                    format, args);
  va_end (args);
  if (written != required)
    {
      output->failed = 1;
      return 0;
    }

  output->length += (size_t) written;
  return 1;
}

static int
final_path_length_is_valid (DWORD length)
{
  return length < 32767;
}

static wchar_t *
query_final_path (HANDLE file, DWORD flags, DWORD *length, DWORD *error)
{
  const DWORD capacity = 32767;
  wchar_t *buffer
    = (wchar_t *) calloc ((size_t) capacity, sizeof (wchar_t));

  *length = 0;
  *error = ERROR_SUCCESS;

  if (! buffer)
    {
      *error = ERROR_NOT_ENOUGH_MEMORY;
      return NULL;
    }

  SetLastError (ERROR_SUCCESS);
  DWORD result
    = GetFinalPathNameByHandleW (file, buffer, capacity, flags);
  if (result == 0)
    {
      *error = GetLastError ();
      free (buffer);
      return NULL;
    }

  if (! final_path_length_is_valid (result))
    {
      *error = ERROR_BUFFER_OVERFLOW;
      free (buffer);
      return NULL;
    }

  buffer[result] = L'\0';
  *length = result;
  return buffer;
}

static void
append_wide_path (output_builder *output, const char *label,
                  const wchar_t *path, DWORD length)
{
  char *utf8 = NULL;
  int required = 0;

  if (! path || length == 0)
    {
      append_line (output, "%s=\r\n", label);
      return;
    }

  if (length <= INT_MAX)
    required = WideCharToMultiByte (CP_UTF8, 0, path, (int) length,
                                    NULL, 0, NULL, NULL);

  if (required > 0)
    {
      utf8 = (char *) calloc ((size_t) required + 1, sizeof (char));
      if (utf8
          && WideCharToMultiByte (CP_UTF8, 0, path, (int) length,
                                  utf8, required, NULL, NULL) == required)
        {
          utf8[required] = '\0';
          append_line (output, "%s=%s\r\n", label, utf8);
          free (utf8);
          return;
        }
    }

  free (utf8);
  output->failed = 1;
}

static int file_name_info_force_more_data = 0;
static DWORD file_name_info_attempts = 0;
static DWORD fallback_stage = 0;
static DWORD file_name_info_last_capacity = 0;

static FILE_NAME_INFO *
query_file_name_info (HANDLE file, DWORD *length, DWORD *error)
{
  const DWORD maximum
    = (DWORD) (offsetof (FILE_NAME_INFO, FileName)
                + 32767 * sizeof (wchar_t));
  DWORD capacity
    = (DWORD) (offsetof (FILE_NAME_INFO, FileName)
                + 512 * sizeof (wchar_t));

  *length = 0;
  *error = ERROR_SUCCESS;

  while (capacity <= maximum)
    {
      file_name_info_attempts++;
      file_name_info_last_capacity = capacity;
      FILE_NAME_INFO *info = (FILE_NAME_INFO *) calloc (1, capacity);
      if (! info)
        {
          *error = ERROR_NOT_ENOUGH_MEMORY;
          return NULL;
        }

      SetLastError (ERROR_SUCCESS);
      if (file_name_info_force_more_data)
        SetLastError (ERROR_MORE_DATA);
      else if (GetFileInformationByHandleEx (file, FileNameInfo, info,
                                             capacity))
        {
          DWORD bytes = info->FileNameLength;
          DWORD available
            = capacity - (DWORD) offsetof (FILE_NAME_INFO, FileName);
          if (bytes == 0 || bytes % sizeof (wchar_t) != 0
              || bytes > available)
            {
              *error = ERROR_INVALID_DATA;
              free (info);
              return NULL;
            }

          *length = bytes / sizeof (wchar_t);
          return info;
        }

      *error = GetLastError ();
      free (info);
      if (*error != ERROR_MORE_DATA
          && *error != ERROR_INSUFFICIENT_BUFFER)
        return NULL;

      if (capacity == maximum)
        break;
      if (capacity > maximum / 2)
        capacity = maximum;
      else
        capacity *= 2;
    }

  *error = ERROR_BUFFER_OVERFLOW;
  return NULL;
}

static int
query_file_identity (HANDLE file, FILE_ID_INFO *identity)
{
  return GetFileInformationByHandleEx (file, FileIdInfo, identity,
                                       sizeof (*identity));
}

static int
same_file_identity (const FILE_ID_INFO *left, const FILE_ID_INFO *right)
{
  return left->VolumeSerialNumber == right->VolumeSerialNumber
         && memcmp (left->FileId.Identifier, right->FileId.Identifier,
                    sizeof (left->FileId.Identifier)) == 0;
}

static int
local_drive_root (const wchar_t *target, wchar_t *root, DWORD capacity)
{

  if (! target || wcslen (target) < 3
      || ! ((target[0] >= L'A' && target[0] <= L'Z')
            || (target[0] >= L'a' && target[0] <= L'z'))
      || target[1] != L':'
      || (target[2] != L'\\' && target[2] != L'/'))
    return 0;

  fallback_stage = 10;
  if (! GetVolumePathNameW (target, root, capacity))
    return 0;
  fallback_stage = 11;
  if (wcslen (root) != 3 || root[1] != L':'
      || root[2] != L'\\' || towupper (root[0]) != towupper (target[0]))
    return 0;
  fallback_stage = 12;

  UINT drive_type = GetDriveTypeW (root);
  if (drive_type == DRIVE_UNKNOWN || drive_type == DRIVE_NO_ROOT_DIR
      || drive_type == DRIVE_REMOTE)
    return 0;
  fallback_stage = 13;

  return 1;
}

static int
input_components_are_not_reparse_points (const wchar_t *target,
                                          fallback_mutation mutation)
{
  size_t length = wcslen (target);
  wchar_t *component = (wchar_t *) calloc (length + 1, sizeof (wchar_t));
  size_t start = 3;
  size_t index;
  DWORD attributes;
  int valid = 1;

  if (! component)
    return 0;
  memcpy (component, target, (length + 1) * sizeof (wchar_t));

  for (index = start; index <= length; index++)
    {
      if (index != length && component[index] != L'\\'
          && component[index] != L'/')
        continue;
      if (index == start)
        {
          valid = 0;
          break;
        }

      wchar_t saved = component[index];
      component[index] = L'\0';
      attributes = GetFileAttributesW (component);
      component[index] = saved;
      if (attributes == INVALID_FILE_ATTRIBUTES
          || (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
        valid = 0;
      if (! valid)
        break;
      start = index + 1;
    }

  free (component);
  return valid && mutation != mutation_reparse;
}

static int
valid_volume_relative_path (const wchar_t *path, DWORD length)
{
  DWORD index;
  DWORD component_start = 1;

  if (! path || length == 0 || path[0] != L'\\')
    return 0;

  for (index = 1; index <= length; index++)
    {
      wchar_t current = index == length ? L'\\' : path[index];
      if (index < length
          && (current == L'\0' || current == L'/' || current == L':'))
        return 0;
      if (current != L'\\')
        continue;
      if (index == component_start)
        return length == 1 && index == 1;
      if ((index - component_start == 1
           && path[component_start] == L'.')
          || (index - component_start == 2
              && path[component_start] == L'.'
              && path[component_start + 1] == L'.'))
        return 0;
      component_start = index + 1;
    }

  return 1;
}

static wchar_t *
query_fallback_path (HANDLE file, const wchar_t *target,
                     fallback_mutation mutation, DWORD *length)
{
  wchar_t volume_root[32767];
  FILE_ID_INFO target_identity;
  FILE_ID_INFO reopened_identity;
  DWORD info_length = 0;
  DWORD info_error = ERROR_SUCCESS;
  FILE_NAME_INFO *info = NULL;
  wchar_t *result = NULL;
  HANDLE reopened = INVALID_HANDLE_VALUE;
  int reopened_matches = 0;

  *length = 0;
  fallback_stage = 0;
  if (! local_drive_root (target, volume_root,
                          (DWORD) (sizeof (volume_root)
                                   / sizeof (volume_root[0]))))
    goto cleanup;
  fallback_stage = 1;

  if (! query_file_identity (file, &target_identity))
    goto cleanup;
  fallback_stage = 2;
  if (mutation == mutation_reparse
      && ! input_components_are_not_reparse_points (target, mutation))
    goto cleanup;
  fallback_stage = 3;

  info = query_file_name_info (file, &info_length, &info_error);
  if (! info)
    goto cleanup;
  fallback_stage = 5;
  if (mutation == mutation_malformed_path)
    info->FileName[0] = L'X';
  if (! valid_volume_relative_path (info->FileName, info_length)
      || info_length > 32767 - 7)
    goto cleanup;
  if (info_length != wcslen (target) - 2
      || _wcsnicmp (info->FileName, target + 2, info_length) != 0)
    goto cleanup;
  fallback_stage = 6;

  *length = 6 + info_length;
  result = (wchar_t *) calloc ((size_t) *length + 1, sizeof (wchar_t));
  if (! result)
    {
      *length = 0;
      goto cleanup;
    }
  result[0] = L'\\';
  result[1] = L'\\';
  result[2] = L'?';
  result[3] = L'\\';
  result[4] = (wchar_t) towupper (volume_root[0]);
  result[5] = L':';
  memcpy (result + 6, info->FileName,
          (size_t) info_length * sizeof (wchar_t));
  result[*length] = L'\0';
  fallback_stage = 7;

  reopened
    = CreateFileW (result, FILE_READ_ATTRIBUTES,
                   FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                   NULL, OPEN_EXISTING,
                   FILE_FLAG_BACKUP_SEMANTICS
                   | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (reopened != INVALID_HANDLE_VALUE
      && query_file_identity (reopened, &reopened_identity))
    {
      if (mutation == mutation_volume_mismatch)
        reopened_identity.VolumeSerialNumber ^= 1;
      reopened_matches
        = same_file_identity (&target_identity, &reopened_identity);
    }
  if (! reopened_matches)
    {
      free (result);
      result = NULL;
      *length = 0;
    }
  if (result)
    fallback_stage = 8;

 cleanup:
  if (reopened != INVALID_HANDLE_VALUE)
    CloseHandle (reopened);
  free (info);
  return result;
}

static wchar_t *
query_candidate_path (HANDLE file, const wchar_t *target,
                      fallback_mutation mutation, DWORD *length,
                      DWORD *error, const char **source)
{
  wchar_t *result = NULL;
  DWORD normalized_error = ERROR_ACCESS_DENIED;

  *length = 0;
  *error = ERROR_SUCCESS;
  *source = "REJECTED";

  if (mutation == mutation_none)
    result = query_final_path (file, FILE_NAME_NORMALIZED, length,
                               &normalized_error);
  if (result)
    {
      *source = "NORMALIZED";
      return result;
    }
  if (normalized_error != ERROR_ACCESS_DENIED)
    {
      *error = normalized_error;
      return NULL;
    }

  result = query_fallback_path (file, target, mutation, length);
  if (! result)
    {
      *error = normalized_error;
      return NULL;
    }

  *source = "FALLBACK";
  return result;
}

static fallback_mutation
parse_mutation (const wchar_t *name)
{
  if (wcscmp (name, L"force-fallback") == 0)
    return mutation_force_fallback;
  if (wcscmp (name, L"volume-mismatch") == 0)
    return mutation_volume_mismatch;
  if (wcscmp (name, L"reparse") == 0)
    return mutation_reparse;
  if (wcscmp (name, L"malformed-path") == 0)
    return mutation_malformed_path;
  return mutation_none;
}
static int
write_output (const wchar_t *path, const char *output, size_t output_length)
{
  DWORD written = 0;
  DWORD size;
  if (output_length > MAXDWORD)
    return 0;
  size = (DWORD) output_length;
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
run_probe (const wchar_t *target, const wchar_t *output_path,
           fallback_mutation mutation)
{
  output_builder output;
  wchar_t *normalized = NULL;
  wchar_t *opened = NULL;
  wchar_t *candidate = NULL;
  FILE_NAME_INFO *file_info = NULL;
  DWORD normalized_error;
  DWORD normalized_length;
  DWORD opened_error;
  DWORD opened_length;
  DWORD file_info_error;
  DWORD file_info_length;
  DWORD candidate_error;
  DWORD candidate_length;
  const char *candidate_source;
  DWORD open_error;
  DWORD read_error = ERROR_SUCCESS;
  DWORD enum_error = ERROR_SUCCESS;
  DWORD bytes_read = 0;
  unsigned char byte = 0;

  initialize_output (&output);

  SetLastError (ERROR_SUCCESS);
  HANDLE canonical_handle
    = CreateFileW (target, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                   FILE_FLAG_BACKUP_SEMANTICS, NULL);
  open_error = (canonical_handle == INVALID_HANDLE_VALUE
                ? GetLastError () : ERROR_SUCCESS);
  append_line (&output, "CREATEFILE_HANDLE=%d ERROR=%lu\r\n",
               canonical_handle != INVALID_HANDLE_VALUE,
               (unsigned long) open_error);

  if (canonical_handle == INVALID_HANDLE_VALUE)
    {
      int result
        = (! output.failed
           && write_output (output_path, output.data, output.length)
           ? probe_create_file_failed : probe_output_failed);
      free (output.data);
      return result;
    }

  normalized
    = query_final_path (canonical_handle, FILE_NAME_NORMALIZED,
                        &normalized_length, &normalized_error);
  append_line (&output,
               "GETFINAL_NORMALIZED_LENGTH=%lu ERROR=%lu NONEMPTY=%d\r\n",
               (unsigned long) normalized_length,
               (unsigned long) normalized_error,
               normalized && normalized_length > 0);
  append_wide_path (&output, "GETFINAL_NORMALIZED_PATH",
                    normalized, normalized_length);

  opened
    = query_final_path (canonical_handle, FILE_NAME_OPENED,
                        &opened_length, &opened_error);
  append_line (&output,
               "GETFINAL_OPENED_LENGTH=%lu ERROR=%lu NONEMPTY=%d\r\n",
               (unsigned long) opened_length,
               (unsigned long) opened_error,
               opened && opened_length > 0);
  append_wide_path (&output, "GETFINAL_OPENED_PATH",
                    opened, opened_length);

  file_info
    = query_file_name_info (canonical_handle, &file_info_length,
                            &file_info_error);
  append_line (&output,
               "FILE_NAME_INFO_OK=%d LENGTH=%lu ERROR=%lu NONEMPTY=%d\r\n",
               file_info != NULL, (unsigned long) file_info_length,
               (unsigned long) file_info_error,
               file_info && file_info_length > 0);
  append_wide_path (&output, "FILE_NAME_INFO_PATH",
                    file_info ? file_info->FileName : NULL, file_info_length);
  candidate
    = query_candidate_path (canonical_handle, target, mutation,
                            &candidate_length, &candidate_error,
                            &candidate_source);
  append_line (&output, "CANDIDATE_SOURCE=%s ERROR=%lu NONEMPTY=%d\r\n",
               candidate_source, (unsigned long) candidate_error,
               candidate && candidate_length > 0);
  append_wide_path (&output, "CANDIDATE_PATH", candidate, candidate_length);
  CloseHandle (canonical_handle);

  append_line (&output, "CANDIDATE_FALLBACK_STAGE=%lu\r\n",
               (unsigned long) fallback_stage);
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
  append_line (&output,
               "READFILE=%d ERROR=%lu BYTES=%lu BYTE=%u\r\n",
               read_ok, (unsigned long) read_error,
               (unsigned long) bytes_read, (unsigned int) byte);

  int enum_ok = enumerate_target (target, &enum_error);
  append_line (&output, "ENUMERATION=%d ERROR=%lu\r\n",
               enum_ok, (unsigned long) enum_error);

  int result = probe_ok;
  if (output.failed
      || ! write_output (output_path, output.data, output.length))
    result = probe_output_failed;
  else if (! read_ok)
    result = probe_read_failed;
  else if (! enum_ok)
    result = probe_enumeration_failed;
  else if (! file_info || file_info_length == 0)
    result = probe_file_name_info_failed;
  else if (! candidate || candidate_length == 0)
    result = probe_candidate_rejected;

  free (output.data);
  free (candidate);
  free (file_info);
  free (opened);
  free (normalized);
  return result;
}

static int
run_file_name_info_max_probe (const wchar_t *output_path)
{
  const DWORD maximum
    = (DWORD) (offsetof (FILE_NAME_INFO, FileName)
                + 32767 * sizeof (wchar_t));
  DWORD length = 0;
  DWORD error = ERROR_SUCCESS;
  FILE_NAME_INFO *info;
  output_builder output;
  int result;

  file_name_info_attempts = 0;
  file_name_info_last_capacity = 0;
  file_name_info_force_more_data = 1;
  info = query_file_name_info (INVALID_HANDLE_VALUE, &length, &error);
  file_name_info_force_more_data = 0;

  initialize_output (&output);
  append_line (&output,
               "FILE_NAME_INFO_MAX_ATTEMPTS=%lu LAST_CAPACITY=%lu ERROR=%lu\r\n",
               (unsigned long) file_name_info_attempts,
               (unsigned long) file_name_info_last_capacity,
               (unsigned long) error);
  result = (! info && length == 0 && error == ERROR_BUFFER_OVERFLOW
            && file_name_info_last_capacity == maximum
            && file_name_info_attempts == 7 && ! output.failed
            && write_output (output_path, output.data, output.length))
           ? probe_ok : probe_file_name_info_failed;
  free (info);
  free (output.data);
  return result;
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

static void *
query_token_information (HANDLE token, TOKEN_INFORMATION_CLASS info_class,
                         DWORD *error)
{
  DWORD size = 0;

  SetLastError (ERROR_SUCCESS);
  GetTokenInformation (token, info_class, NULL, 0, &size);
  *error = GetLastError ();
  if (*error != ERROR_INSUFFICIENT_BUFFER || size == 0)
    return NULL;

  void *buffer = calloc (1, size);
  if (! buffer)
    {
      *error = ERROR_NOT_ENOUGH_MEMORY;
      return NULL;
    }

  if (! GetTokenInformation (token, info_class, buffer, size, &size))
    {
      *error = GetLastError ();
      free (buffer);
      return NULL;
    }

  *error = ERROR_SUCCESS;
  return buffer;
}

static int
validate_appcontainer_token (HANDLE process, PSID expected_sid)
{
  HANDLE token = NULL;
  DWORD error = ERROR_SUCCESS;
  DWORD is_appcontainer = 0;
  DWORD returned = 0;
  int sid_match = 0;
  DWORD capability_count = (DWORD) -1;
  TOKEN_APPCONTAINER_INFORMATION *container = NULL;
  TOKEN_GROUPS *capabilities = NULL;
  int valid = 0;

  if (! OpenProcessToken (process, TOKEN_QUERY, &token))
    {
      fprintf (stderr, "OPEN_PROCESS_TOKEN_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      goto cleanup;
    }

  if (! GetTokenInformation (token, TokenIsAppContainer,
                             &is_appcontainer, sizeof (is_appcontainer),
                             &returned))
    {
      fprintf (stderr, "TOKEN_IS_APPCONTAINER_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      goto cleanup;
    }

  container
    = (TOKEN_APPCONTAINER_INFORMATION *)
        query_token_information (token, TokenAppContainerSid, &error);
  if (! container)
    {
      fprintf (stderr, "TOKEN_APPCONTAINER_SID_ERROR=%lu\n",
               (unsigned long) error);
      goto cleanup;
    }
  sid_match = (container->TokenAppContainer
               && EqualSid (container->TokenAppContainer, expected_sid));

  capabilities
    = (TOKEN_GROUPS *)
        query_token_information (token, TokenCapabilities, &error);
  if (! capabilities)
    {
      fprintf (stderr, "TOKEN_CAPABILITIES_ERROR=%lu\n",
               (unsigned long) error);
      goto cleanup;
    }
  capability_count = capabilities->GroupCount;

  printf ("TOKEN_IS_APPCONTAINER=%lu TOKEN_SID_MATCH=%d "
          "TOKEN_CAPABILITIES=%lu\n",
          (unsigned long) is_appcontainer, sid_match,
          (unsigned long) capability_count);
  valid = (is_appcontainer == 1 && sid_match && capability_count == 0);

 cleanup:
  free (capabilities);
  free (container);
  if (token)
    CloseHandle (token);
  return valid;
}

static int
terminate_and_wait (HANDLE process, DWORD exit_code)
{
  if (! TerminateProcess (process, exit_code))
    {
      fprintf (stderr, "TERMINATE_PROCESS_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      return 0;
    }

  DWORD wait_result = WaitForSingleObject (process, 5000);
  if (wait_result != WAIT_OBJECT_0)
    {
      if (wait_result == WAIT_FAILED)
        fprintf (stderr, "TERMINATION_WAIT_ERROR=%lu\n",
                 (unsigned long) GetLastError ());
      else
        fprintf (stderr, "TERMINATION_WAIT_RESULT=%lu\n",
                 (unsigned long) wait_result);
      return 0;
    }

  return 1;
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
                        | CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED,
                        NULL, work_root, &startup.StartupInfo, &process))
    {
      fprintf (stderr, "CREATEPROCESS_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_process_failed;
      goto cleanup;
    }

  if (! validate_appcontainer_token (process.hProcess, appcontainer_sid))
    {
      result = launcher_token_failed;
      if (! terminate_and_wait (process.hProcess, launcher_token_failed))
        result = launcher_termination_failed;
      goto cleanup;
    }

  if (ResumeThread (process.hThread) == (DWORD) -1)
    {
      fprintf (stderr, "RESUME_THREAD_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_resume_failed;
      if (! terminate_and_wait (process.hProcess, launcher_resume_failed))
        result = launcher_termination_failed;
      goto cleanup;
    }

  DWORD wait_result = WaitForSingleObject (process.hProcess, 15000);
  if (wait_result == WAIT_TIMEOUT)
    {
      fprintf (stderr, "PROCESS_WAIT_TIMEOUT=15000\n");
      result = launcher_timeout;
      if (! terminate_and_wait (process.hProcess, launcher_timeout))
        result = launcher_termination_failed;
      goto cleanup;
    }
  else if (wait_result == WAIT_FAILED)
    {
      fprintf (stderr, "PROCESS_WAIT_ERROR=%lu\n",
               (unsigned long) GetLastError ());
      result = launcher_wait_failed;
      if (! terminate_and_wait (process.hProcess, launcher_wait_failed))
        result = launcher_termination_failed;
      goto cleanup;
    }
  else if (wait_result != WAIT_OBJECT_0)
    {
      fprintf (stderr, "PROCESS_WAIT_RESULT=%lu\n",
               (unsigned long) wait_result);
      result = launcher_wait_failed;
      if (! terminate_and_wait (process.hProcess, launcher_wait_failed))
        result = launcher_termination_failed;
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

static int
delete_profile_if_present (const wchar_t *profile_name)
{
  HRESULT result = DeleteAppContainerProfile (profile_name);
  DWORD error = HRESULT_CODE (result);

  if (SUCCEEDED (result))
    {
      printf ("PROFILE_CLEANUP_HRESULT=0x00000000\n");
      return probe_ok;
    }

  if (HRESULT_FACILITY (result) == FACILITY_WIN32
      && (error == ERROR_NOT_FOUND || error == ERROR_FILE_NOT_FOUND
          || error == ERROR_PATH_NOT_FOUND))
    {
      printf ("PROFILE_CLEANUP_ABSENT=1\n");
      return probe_ok;
    }

  fwprintf (stderr, L"PROFILE_CLEANUP_HRESULT=0x%08lx\n",
            (unsigned long) result);
  return launcher_cleanup_failed;
}

int
wmain (int argc, wchar_t **argv)
{
  if (argc == 4 && wcscmp (argv[1], L"--probe") == 0)
    return run_probe (argv[2], argv[3], mutation_none);

  if (argc == 5 && wcscmp (argv[1], L"--probe-mutation") == 0)
    {
      fallback_mutation mutation = parse_mutation (argv[2]);
      if (mutation != mutation_none)
        return run_probe (argv[3], argv[4], mutation);
    }

  if (argc == 3 && wcscmp (argv[1], L"--file-name-info-max") == 0)
    return run_file_name_info_max_probe (argv[2]);


  if (argc == 7 && wcscmp (argv[1], L"--appcontainer") == 0)
    return run_appcontainer (argv[2], argv[3], argv[4], argv[5], argv[6]);

  if (argc == 3 && wcscmp (argv[1], L"--delete-profile") == 0)
    return delete_profile_if_present (argv[2]);

  fwprintf (stderr,
            L"usage:\n"
            L"  %ls --probe TARGET OUTPUT\n"
            L"  %ls --probe-mutation MODE TARGET OUTPUT\n"
            L"  %ls --file-name-info-max OUTPUT\n"
            L"  %ls --appcontainer PROFILE STAGE WORK PROBE TARGET\n"
            L"  %ls --delete-profile PROFILE\n",
            argv[0], argv[0], argv[0], argv[0], argv[0]);
  return launcher_usage;
}
