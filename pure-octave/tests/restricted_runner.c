#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0600
#include <windows.h>
#include <aclapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

static int
fail_windows(const wchar_t *operation)
{
  fwprintf(stderr, L"%ls failed with Windows error %lu\n",
           operation, GetLastError());
  return 125;
}

static int
work_directory_is_low_integrity(const wchar_t *path)
{
  PSECURITY_DESCRIPTOR descriptor = NULL;
  PACL label_acl = NULL;
  DWORD status =
    GetNamedSecurityInfoW((LPWSTR) path, SE_FILE_OBJECT,
                          LABEL_SECURITY_INFORMATION,
                          NULL, NULL, NULL, &label_acl, &descriptor);
  if (status != ERROR_SUCCESS)
    {
      SetLastError(status);
      return 0;
    }

  int is_low = 0;
  if (label_acl)
    {
      for (DWORD index = 0; index < label_acl->AceCount; ++index)
        {
          void *raw_ace = NULL;
          if (!GetAce(label_acl, index, &raw_ace))
            break;
          ACE_HEADER *header = (ACE_HEADER *) raw_ace;
          if (header->AceType == SYSTEM_MANDATORY_LABEL_ACE_TYPE)
            {
              SYSTEM_MANDATORY_LABEL_ACE *ace =
                (SYSTEM_MANDATORY_LABEL_ACE *) raw_ace;
              PSID sid = (PSID) &ace->SidStart;
              PUCHAR count = GetSidSubAuthorityCount(sid);
              if (count && *count > 0)
                {
                  DWORD level =
                    *GetSidSubAuthority(sid, (DWORD) (*count - 1));
                  is_low = level == SECURITY_MANDATORY_LOW_RID;
                }
              break;
            }
        }
    }
  LocalFree(descriptor);
  if (!is_low)
    SetLastError(ERROR_INVALID_SECURITY_DESCR);
  return is_low;
}

static int
token_is_low_no_write_up(HANDLE token)
{
  DWORD label_size = 0;
  GetTokenInformation(token, TokenIntegrityLevel, NULL, 0, &label_size);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER)
    return 0;

  TOKEN_MANDATORY_LABEL *label =
    (TOKEN_MANDATORY_LABEL *) malloc(label_size);
  if (!label)
    {
      SetLastError(ERROR_OUTOFMEMORY);
      return 0;
    }
  if (!GetTokenInformation(token, TokenIntegrityLevel,
                           label, label_size, &label_size))
    {
      free(label);
      return 0;
    }
  PSID sid = label->Label.Sid;
  PUCHAR count = GetSidSubAuthorityCount(sid);
  DWORD level =
    count && *count > 0
    ? *GetSidSubAuthority(sid, (DWORD) (*count - 1))
    : SECURITY_MANDATORY_UNTRUSTED_RID;
  free(label);

  TOKEN_MANDATORY_POLICY policy;
  DWORD policy_size = 0;
  if (!GetTokenInformation(token, TokenMandatoryPolicy,
                           &policy, sizeof(policy), &policy_size))
    return 0;
  if (level != SECURITY_MANDATORY_LOW_RID ||
      !(policy.Policy & TOKEN_MANDATORY_POLICY_NO_WRITE_UP))
    {
      fwprintf(stderr, L"token validation: integrity=%lu policy=0x%lx\n",
               level, policy.Policy);
      SetLastError(ERROR_INVALID_ACCESS);
      return 0;
    }
  return 1;
}

static wchar_t *
append_quoted_argument(wchar_t *output, const wchar_t *argument)
{
  size_t backslashes = 0;
  *output++ = L'"';
  for (const wchar_t *cursor = argument; *cursor; ++cursor)
    {
      if (*cursor == L'\\')
        {
          ++backslashes;
          continue;
        }
      if (*cursor == L'"')
        {
          for (size_t index = 0; index < backslashes * 2 + 1; ++index)
            *output++ = L'\\';
          *output++ = L'"';
        }
      else
        {
          for (size_t index = 0; index < backslashes; ++index)
            *output++ = L'\\';
          *output++ = *cursor;
        }
      backslashes = 0;
    }
  for (size_t index = 0; index < backslashes * 2; ++index)
    *output++ = L'\\';
  *output++ = L'"';
  return output;
}

static wchar_t *
build_command_line(int argc, wchar_t **argv)
{
  size_t capacity = 1;
  for (int index = 2; index < argc; ++index)
    capacity += 2 * wcslen(argv[index]) + 4;

  wchar_t *command_line =
    (wchar_t *) calloc(capacity, sizeof(wchar_t));
  if (!command_line)
    return NULL;

  wchar_t *output = command_line;
  for (int index = 2; index < argc; ++index)
    {
      if (index > 2)
        *output++ = L' ';
      output = append_quoted_argument(output, argv[index]);
    }
  *output = L'\0';
  return command_line;
}

int
wmain(int argc, wchar_t **argv)
{
  if (argc < 3)
    {
      fwprintf(stderr,
               L"usage: restricted_runner WORKDIR PROGRAM [ARG ...]\n");
      return 124;
    }
  if (!work_directory_is_low_integrity(argv[1]))
    return fail_windows(L"low-integrity work-directory validation");

  HANDLE process_token = NULL;
  HANDLE child_token = NULL;
  PSID low_sid = NULL;
  wchar_t *command_line = NULL;
  const wchar_t *failure_operation = L"low-integrity process setup";
  PROCESS_INFORMATION process_info;
  ZeroMemory(&process_info, sizeof(process_info));

  failure_operation = L"OpenProcessToken";
  if (!OpenProcessToken(GetCurrentProcess(),
                        TOKEN_QUERY | TOKEN_ADJUST_DEFAULT,
                        &process_token))
    goto windows_failure;

  SID_IDENTIFIER_AUTHORITY authority =
    SECURITY_MANDATORY_LABEL_AUTHORITY;
  failure_operation = L"AllocateAndInitializeSid";
  if (!AllocateAndInitializeSid(&authority, 1,
                                SECURITY_MANDATORY_LOW_RID,
                                0, 0, 0, 0, 0, 0, 0, &low_sid))
    goto windows_failure;
  TOKEN_MANDATORY_LABEL label;
  label.Label.Attributes = SE_GROUP_INTEGRITY;
  label.Label.Sid = low_sid;
  failure_operation = L"SetTokenInformation(TokenIntegrityLevel)";
  if (!SetTokenInformation(process_token, TokenIntegrityLevel,
                           &label,
                           sizeof(label) + GetLengthSid(low_sid)))
    goto windows_failure;

  failure_operation = L"low-integrity runner-token validation";
  if (!token_is_low_no_write_up(process_token))
    goto windows_failure;

  command_line = build_command_line(argc, argv);
  if (!command_line)
    {
      SetLastError(ERROR_OUTOFMEMORY);
      goto windows_failure;
    }

  STARTUPINFOW startup;
  ZeroMemory(&startup, sizeof(startup));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);

  failure_operation = L"CreateProcessW";
  if (!CreateProcessW(argv[2], command_line, NULL, NULL, TRUE,
                      CREATE_UNICODE_ENVIRONMENT | CREATE_SUSPENDED,
                      NULL, argv[1], &startup, &process_info))
    goto windows_failure;

  failure_operation = L"OpenProcessToken(child)";
  if (!OpenProcessToken(process_info.hProcess, TOKEN_QUERY, &child_token))
    goto windows_failure;
  failure_operation = L"low-integrity child-token validation";
  if (!token_is_low_no_write_up(child_token))
    goto windows_failure;
  CloseHandle(child_token);
  child_token = NULL;

  failure_operation = L"ResumeThread";
  if (ResumeThread(process_info.hThread) == (DWORD) -1)
    goto windows_failure;

  WaitForSingleObject(process_info.hProcess, INFINITE);
  DWORD child_exit = 125;
  failure_operation = L"GetExitCodeProcess";
  if (!GetExitCodeProcess(process_info.hProcess, &child_exit))
    goto windows_failure;

  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  free(command_line);
  FreeSid(low_sid);
  if (child_token)
    CloseHandle(child_token);
  CloseHandle(process_token);
  return (int) child_exit;

windows_failure:
  {
    DWORD error = GetLastError();
    if (process_info.hProcess)
      {
        TerminateProcess(process_info.hProcess, 125);
        WaitForSingleObject(process_info.hProcess, 5000);
      }
    if (process_info.hThread)
      CloseHandle(process_info.hThread);
    if (process_info.hProcess)
      CloseHandle(process_info.hProcess);
    free(command_line);
    if (low_sid)
      FreeSid(low_sid);
    if (child_token)
      CloseHandle(child_token);
    if (process_token)
      CloseHandle(process_token);
    SetLastError(error);
    return fail_windows(failure_operation);
  }
}
