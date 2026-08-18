#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

enum {
  FCGI_VERSION_1 = 1,
  FCGI_BEGIN_REQUEST = 1,
  FCGI_END_REQUEST = 3,
  FCGI_PARAMS = 4,
  FCGI_STDIN = 5,
  FCGI_STDOUT = 6,
  FCGI_STDERR = 7,
  FCGI_RESPONDER = 1,
  FCGI_KEEP_CONN = 1,
  FCGI_REQUEST_COMPLETE = 0
};

enum fcgi_io_result {
  FCGI_IO_OK,
  FCGI_IO_TIMEOUT,
  FCGI_IO_EOF,
  FCGI_IO_PROTOCOL,
  FCGI_IO_SYSTEM
};

struct fcgi_record {
  uint8_t type;
  uint16_t request_id;
  uint16_t content_len;
  unsigned char content[UINT16_MAX];
};

static size_t fcgi_encode_record(unsigned char *out, size_t capacity,
                                 uint8_t version, uint8_t type,
                                 uint16_t request_id, const void *content,
                                 uint16_t content_len);
static size_t fcgi_write_name_value(unsigned char *out, size_t capacity,
                                    const void *name, size_t name_len,
                                    const void *value, size_t value_len);
static enum fcgi_io_result fcgi_decode_record(const unsigned char *input,
                                              size_t input_len,
                                              uint16_t expected_request_id,
                                              struct fcgi_record *record);
static enum fcgi_io_result fcgi_write_record(HANDLE pipe, uint8_t type,
                                             uint16_t request_id,
                                             const void *content,
                                             uint16_t content_len,
                                             uint64_t deadline_ms);
static enum fcgi_io_result fcgi_read_record(HANDLE pipe,
                                            struct fcgi_record *record,
                                            uint64_t deadline_ms);

static uint64_t fcgi_now_ms(void) { return GetTickCount64(); }

static enum fcgi_io_result fcgi_transfer(HANDLE pipe, void *buffer, size_t size,
                                         uint64_t deadline_ms, int writing) {
  unsigned char *cursor = buffer;

  while (size != 0) {
    OVERLAPPED operation;
    DWORD transferred = 0;
    DWORD chunk = size > UINT32_MAX ? UINT32_MAX : (DWORD)size;
    BOOL started;
    uint64_t now;
    DWORD wait_ms;

    memset(&operation, 0, sizeof operation);
    operation.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (operation.hEvent == NULL) {
      return FCGI_IO_SYSTEM;
    }

    started = writing ? WriteFile(pipe, cursor, chunk, &transferred, &operation)
                      : ReadFile(pipe, cursor, chunk, &transferred, &operation);
    if (!started && GetLastError() != ERROR_IO_PENDING) {
      DWORD error = GetLastError();
      CloseHandle(operation.hEvent);
      if (!writing &&
          (error == ERROR_BROKEN_PIPE || error == ERROR_HANDLE_EOF)) {
        return FCGI_IO_EOF;
      }
      return FCGI_IO_SYSTEM;
    }

    if (!started) {
      now = fcgi_now_ms();
      if (now >= deadline_ms) {
        CancelIoEx(pipe, &operation);
        GetOverlappedResult(pipe, &operation, &transferred, TRUE);
        CloseHandle(operation.hEvent);
        return FCGI_IO_TIMEOUT;
      }
      wait_ms = deadline_ms - now > UINT32_MAX
                    ? UINT32_MAX
                    : (DWORD)(deadline_ms - now);
      {
        DWORD wait_result = WaitForSingleObject(operation.hEvent, wait_ms);
        if (wait_result != WAIT_OBJECT_0) {
          enum fcgi_io_result wait_error =
              wait_result == WAIT_TIMEOUT ? FCGI_IO_TIMEOUT : FCGI_IO_SYSTEM;
          CancelIoEx(pipe, &operation);
          GetOverlappedResult(pipe, &operation, &transferred, TRUE);
          CloseHandle(operation.hEvent);
          return wait_error;
        }
      }
      if (!GetOverlappedResult(pipe, &operation, &transferred, FALSE)) {
        DWORD error = GetLastError();
        CloseHandle(operation.hEvent);
        if (!writing &&
            (error == ERROR_BROKEN_PIPE || error == ERROR_HANDLE_EOF)) {
          return FCGI_IO_EOF;
        }
        return FCGI_IO_SYSTEM;
      }
    }
    CloseHandle(operation.hEvent);
    if (transferred == 0) {
      return writing ? FCGI_IO_SYSTEM : FCGI_IO_EOF;
    }
    cursor += transferred;
    size -= transferred;
  }
  return FCGI_IO_OK;
}

static size_t fcgi_encode_record(unsigned char *out, size_t capacity,
                                 uint8_t version, uint8_t type,
                                 uint16_t request_id, const void *content,
                                 uint16_t content_len) {
  size_t padding = (8 - (content_len & 7)) & 7;
  size_t total = 8 + (size_t)content_len + padding;

  if (version != FCGI_VERSION_1 || out == NULL || capacity < total ||
      (content_len != 0 && content == NULL)) {
    return 0;
  }
  out[0] = version;
  out[1] = type;
  out[2] = (unsigned char)(request_id >> 8);
  out[3] = (unsigned char)request_id;
  out[4] = (unsigned char)(content_len >> 8);
  out[5] = (unsigned char)content_len;
  out[6] = (unsigned char)padding;
  out[7] = 0;
  if (content_len != 0) {
    memcpy(out + 8, content, content_len);
  }
  memset(out + 8 + content_len, 0, padding);
  return total;
}

static size_t fcgi_encode_length(unsigned char *out, size_t length) {
  if (length < 128) {
    out[0] = (unsigned char)length;
    return 1;
  }
  out[0] = (unsigned char)((length >> 24) | 0x80);
  out[1] = (unsigned char)(length >> 16);
  out[2] = (unsigned char)(length >> 8);
  out[3] = (unsigned char)length;
  return 4;
}

static size_t fcgi_write_name_value(unsigned char *out, size_t capacity,
                                    const void *name, size_t name_len,
                                    const void *value, size_t value_len) {
  size_t name_bytes;
  size_t value_bytes;
  size_t total;
  unsigned char *cursor = out;

  if (name_len > 0x7fffffffU || value_len > 0x7fffffffU ||
      (name_len != 0 && name == NULL) || (value_len != 0 && value == NULL)) {
    return 0;
  }
  name_bytes = name_len < 128 ? 1 : 4;
  value_bytes = value_len < 128 ? 1 : 4;
  if (name_len > SIZE_MAX - value_len - name_bytes - value_bytes) {
    return 0;
  }
  total = name_bytes + value_bytes + name_len + value_len;
  if (out == NULL || capacity < total) {
    return 0;
  }
  cursor += fcgi_encode_length(cursor, name_len);
  cursor += fcgi_encode_length(cursor, value_len);
  if (name_len != 0) {
    memcpy(cursor, name, name_len);
  }
  cursor += name_len;
  if (value_len != 0) {
    memcpy(cursor, value, value_len);
  }
  return total;
}

static enum fcgi_io_result fcgi_decode_record(const unsigned char *input,
                                              size_t input_len,
                                              uint16_t expected_request_id,
                                              struct fcgi_record *record) {
  uint16_t request_id;
  uint16_t content_len;
  size_t total;

  if (input == NULL || record == NULL || input_len < 8) {
    return FCGI_IO_PROTOCOL;
  }
  request_id = ((uint16_t)input[2] << 8) | input[3];
  content_len = ((uint16_t)input[4] << 8) | input[5];
  total = 8 + (size_t)content_len + input[6];
  if (input[0] != FCGI_VERSION_1 || request_id != expected_request_id ||
      input_len < total) {
    return FCGI_IO_PROTOCOL;
  }
  record->type = input[1];
  record->request_id = request_id;
  record->content_len = content_len;
  memcpy(record->content, input + 8, content_len);
  return FCGI_IO_OK;
}

static enum fcgi_io_result fcgi_write_record(HANDLE pipe, uint8_t type,
                                             uint16_t request_id,
                                             const void *content,
                                             uint16_t content_len,
                                             uint64_t deadline_ms) {
  size_t capacity = 8 + (size_t)content_len + 7;
  unsigned char *encoded = malloc(capacity);
  size_t encoded_len;
  enum fcgi_io_result result;

  if (encoded == NULL) {
    return FCGI_IO_SYSTEM;
  }
  encoded_len = fcgi_encode_record(encoded, capacity, FCGI_VERSION_1, type,
                                   request_id, content, content_len);
  if (encoded_len == 0) {
    free(encoded);
    return FCGI_IO_PROTOCOL;
  }
  result = fcgi_transfer(pipe, encoded, encoded_len, deadline_ms, 1);
  free(encoded);
  return result;
}

static enum fcgi_io_result fcgi_read_record(HANDLE pipe,
                                            struct fcgi_record *record,
                                            uint64_t deadline_ms) {
  unsigned char header[8];
  unsigned char *encoded;
  uint16_t content_len;
  size_t trailing;
  enum fcgi_io_result result;

  result = fcgi_transfer(pipe, header, sizeof header, deadline_ms, 0);
  if (result != FCGI_IO_OK) {
    return result;
  }
  content_len = ((uint16_t)header[4] << 8) | header[5];
  trailing = (size_t)content_len + header[6];
  encoded = malloc(sizeof header + trailing);
  if (encoded == NULL) {
    return FCGI_IO_SYSTEM;
  }
  memcpy(encoded, header, sizeof header);
  result = fcgi_transfer(pipe, encoded + sizeof header, trailing, deadline_ms, 0);
  if (result == FCGI_IO_OK) {
    result = fcgi_decode_record(encoded, sizeof header + trailing, 1, record);
  }
  free(encoded);
  return result;
}

#ifndef PURE_FASTCGI_CODEC_TEST
static wchar_t *fcgi_command_line(const wchar_t *pure_exe,
                                  const wchar_t *module_dir,
                                  const wchar_t *worker) {
  const wchar_t *arguments[4] = {pure_exe, L"-L", module_dir, worker};
  size_t capacity = 1;
  size_t used = 0;
  wchar_t *command;
  size_t argument_index;

  for (argument_index = 0; argument_index < 4; ++argument_index) {
    size_t length = wcslen(arguments[argument_index]);
    if (length > (SIZE_MAX - capacity - 3) / 2) {
      return NULL;
    }
    capacity += length * 2 + 3;
  }
  command = malloc(capacity * sizeof *command);
  if (command == NULL) {
    return NULL;
  }
  for (argument_index = 0; argument_index < 4; ++argument_index) {
    const wchar_t *argument = arguments[argument_index];
    if (argument_index != 0) {
      command[used++] = L' ';
    }
    command[used++] = L'"';
    while (*argument != L'\0') {
      size_t slashes = 0;
      while (*argument == L'\\') {
        ++slashes;
        ++argument;
      }
      if (*argument == L'"') {
        while (slashes-- != 0) {
          command[used++] = L'\\';
          command[used++] = L'\\';
        }
        command[used++] = L'\\';
        command[used++] = *argument++;
      } else if (*argument == L'\0') {
        while (slashes-- != 0) {
          command[used++] = L'\\';
          command[used++] = L'\\';
        }
      } else {
        while (slashes-- != 0) {
          command[used++] = L'\\';
        }
        command[used++] = *argument++;
      }
    }
    command[used++] = L'"';
  }
  command[used] = L'\0';
  return command;
}

static int fcgi_append(unsigned char *destination, size_t *used, size_t limit,
                       const unsigned char *source, size_t source_len) {
  if (source_len > limit - *used) {
    return 0;
  }
  memcpy(destination + *used, source, source_len);
  *used += source_len;
  return 1;
}

static int fcgi_wait_process(HANDLE process, uint64_t deadline_ms,
                             DWORD *exit_code) {
  uint64_t now = fcgi_now_ms();
  DWORD wait_ms;
  if (now >= deadline_ms) {
    return 0;
  }
  wait_ms = deadline_ms - now > UINT32_MAX ? UINT32_MAX
                                           : (DWORD)(deadline_ms - now);
  return WaitForSingleObject(process, wait_ms) == WAIT_OBJECT_0 &&
         GetExitCodeProcess(process, exit_code) && *exit_code != STILL_ACTIVE;
}

int wmain(int argc, wchar_t **argv) {
  static volatile LONG pipe_counter;
  const uint16_t request_id = 1;
  const uint64_t deadline_ms = fcgi_now_ms() + 15000;
  const char request_method[] = "POST";
  const char query_string[] = "value%20with%20spaces";
  const char content_length[] = "12";
  const char body[] = "hello=world!";
  const char expected_stdout[] =
      "Status: 201 Created\r\nContent-Type: text/plain\r\n\r\n"
      "method=POST;query=value%20with%20spaces;body=hello=world!\n";
  const char expected_stderr[] = "pure-fastcgi-stderr-marker\n";
  wchar_t pipe_name[128];
  wchar_t *command_line = NULL;
  HANDLE server = INVALID_HANDLE_VALUE;
  HANDLE client = INVALID_HANDLE_VALUE;
  HANDLE attribute_handle = INVALID_HANDLE_VALUE;
  LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
  int attributes_initialized = 0;
  SIZE_T attributes_size = 0;
  STARTUPINFOEXW startup;
  PROCESS_INFORMATION process;
  SECURITY_ATTRIBUTES security;
  unsigned char params[256];
  size_t params_len = 0;
  unsigned char stdout_data[65537];
  unsigned char stderr_data[65537];
  size_t stdout_len = 0;
  size_t stderr_len = 0;
  int end_request_count = 0;
  DWORD process_exit = STILL_ACTIVE;
  int process_started = 0;
  int result = 1;

  memset(&startup, 0, sizeof startup);
  memset(&process, 0, sizeof process);
  memset(&security, 0, sizeof security);
  if (argc != 4) {
    fprintf(stderr, "usage: protocol-harness PURE MODULE-DIR WORKER\n");
    goto cleanup;
  }
  if (swprintf(pipe_name, sizeof pipe_name / sizeof pipe_name[0],
               L"\\\\.\\pipe\\FastCGI\\pure-fastcgi-%lu-%ld",
               GetCurrentProcessId(), InterlockedIncrement(&pipe_counter)) < 0) {
    fprintf(stderr, "could not build the named-pipe path\n");
    goto cleanup;
  }
  security.nLength = sizeof security;
  security.bInheritHandle = TRUE;
  server = CreateNamedPipeW(pipe_name, PIPE_ACCESS_DUPLEX,
                            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT, 1,
                            65536, 65536, 0, &security);
  if (server == INVALID_HANDLE_VALUE) {
    fprintf(stderr, "CreateNamedPipeW failed: %lu\n", GetLastError());
    goto cleanup;
  }

  command_line = fcgi_command_line(argv[1], argv[2], argv[3]);
  if (command_line == NULL) {
    fprintf(stderr, "could not build the Pure command line\n");
    goto cleanup;
  }
  InitializeProcThreadAttributeList(NULL, 1, 0, &attributes_size);
  if (GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
    fprintf(stderr, "attribute-list sizing failed: %lu\n", GetLastError());
    goto cleanup;
  }
  attributes = HeapAlloc(GetProcessHeap(), 0, attributes_size);
  if (attributes == NULL ||
      !InitializeProcThreadAttributeList(attributes, 1, 0, &attributes_size)) {
    fprintf(stderr, "attribute-list initialization failed: %lu\n",
            GetLastError());
    goto cleanup;
  }
  attributes_initialized = 1;
  attribute_handle = server;
  if (!UpdateProcThreadAttribute(attributes, 0,
                                 PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                 &attribute_handle, sizeof attribute_handle,
                                 NULL, NULL)) {
    fprintf(stderr, "handle-list update failed: %lu\n", GetLastError());
    goto cleanup;
  }

  startup.StartupInfo.cb = sizeof startup;
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.StartupInfo.hStdInput = server;
  startup.StartupInfo.hStdOutput = INVALID_HANDLE_VALUE;
  startup.StartupInfo.hStdError = INVALID_HANDLE_VALUE;
  startup.lpAttributeList = attributes;
  if (!CreateProcessW(argv[1], command_line, NULL, NULL, TRUE,
                      EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, NULL,
                      NULL, &startup.StartupInfo, &process)) {
    fprintf(stderr, "CreateProcessW failed: %lu\n", GetLastError());
    goto cleanup;
  }
  process_started = 1;
  CloseHandle(process.hThread);
  process.hThread = NULL;
  CloseHandle(server);
  server = INVALID_HANDLE_VALUE;

  client = CreateFileW(pipe_name, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                       OPEN_EXISTING, FILE_FLAG_OVERLAPPED, NULL);
  if (client == INVALID_HANDLE_VALUE) {
    fprintf(stderr, "CreateFileW failed: %lu\n", GetLastError());
    goto cleanup;
  }

#define ADD_PARAM(name_literal, value, value_len)                              \
  do {                                                                         \
    size_t added = fcgi_write_name_value(                                      \
        params + params_len, sizeof params - params_len, name_literal,          \
        sizeof name_literal - 1, value, value_len);                             \
    if (added == 0) {                                                           \
      fprintf(stderr, "could not encode FastCGI parameters\n");               \
      goto cleanup;                                                             \
    }                                                                           \
    params_len += added;                                                        \
  } while (0)

  ADD_PARAM("REQUEST_METHOD", request_method, sizeof request_method - 1);
  ADD_PARAM("QUERY_STRING", query_string, sizeof query_string - 1);
  ADD_PARAM("CONTENT_LENGTH", content_length, sizeof content_length - 1);
#undef ADD_PARAM

  {
    /* Let the one-shot worker close the inherited server handle after the
       client has drained END_REQUEST; fcgi2 otherwise disconnects the pipe
       immediately after its buffered close records. */
    const unsigned char begin_request[8] = {
        0, FCGI_RESPONDER, FCGI_KEEP_CONN, 0, 0, 0, 0, 0};
    if (fcgi_write_record(client, FCGI_BEGIN_REQUEST, request_id, begin_request,
                          sizeof begin_request, deadline_ms) != FCGI_IO_OK ||
        fcgi_write_record(client, FCGI_PARAMS, request_id, params,
                          (uint16_t)params_len, deadline_ms) != FCGI_IO_OK ||
        fcgi_write_record(client, FCGI_PARAMS, request_id, NULL, 0,
                          deadline_ms) != FCGI_IO_OK ||
        fcgi_write_record(client, FCGI_STDIN, request_id, body, sizeof body - 1,
                          deadline_ms) != FCGI_IO_OK ||
        fcgi_write_record(client, FCGI_STDIN, request_id, NULL, 0,
                          deadline_ms) != FCGI_IO_OK) {
      fprintf(stderr, "could not write the FastCGI request\n");
      goto cleanup;
    }
  }

  for (;;) {
    struct fcgi_record record;
    enum fcgi_io_result read_result =
        fcgi_read_record(client, &record, deadline_ms);
    if (read_result == FCGI_IO_EOF) {
      break;
    }
    if (read_result != FCGI_IO_OK) {
      DWORD read_error = GetLastError();
      DWORD diagnostic_exit = STILL_ACTIVE;
      stdout_data[stdout_len] = 0;
      stderr_data[stderr_len] = 0;
      WaitForSingleObject(process.hProcess, 2000);
      GetExitCodeProcess(process.hProcess, &diagnostic_exit);
      fprintf(stderr,
              "could not read the FastCGI response: %d (Win32 %lu, child %lu)\n",
              read_result, read_error, diagnostic_exit);
      fprintf(stderr, "stdout before read failure (%lu): %s\n",
              (unsigned long)stdout_len, stdout_data);
      fprintf(stderr, "stderr before read failure (%lu): %s\n",
              (unsigned long)stderr_len, stderr_data);
      goto cleanup;
    }
    if (record.type == FCGI_STDOUT) {
      if (!fcgi_append(stdout_data, &stdout_len, 65536, record.content,
                       record.content_len)) {
        fprintf(stderr, "FastCGI stdout exceeded 64 KiB\n");
        goto cleanup;
      }
    } else if (record.type == FCGI_STDERR) {
      if (!fcgi_append(stderr_data, &stderr_len, 65536, record.content,
                       record.content_len)) {
        fprintf(stderr, "FastCGI stderr exceeded 64 KiB\n");
        goto cleanup;
      }
    } else if (record.type == FCGI_END_REQUEST) {
      uint32_t application_status;
      ++end_request_count;
      if (record.content_len != 8) {
        fprintf(stderr, "invalid END_REQUEST length\n");
        goto cleanup;
      }
      application_status = ((uint32_t)record.content[0] << 24) |
                           ((uint32_t)record.content[1] << 16) |
                           ((uint32_t)record.content[2] << 8) |
                           record.content[3];
      if (application_status != 23 ||
          record.content[4] != FCGI_REQUEST_COMPLETE) {
        stdout_data[stdout_len] = 0;
        stderr_data[stderr_len] = 0;
        fprintf(stderr, "unexpected END_REQUEST status: %lu/%u\n",
                (unsigned long)application_status, record.content[4]);
        fprintf(stderr, "stdout before END_REQUEST (%lu): %s\n",
                (unsigned long)stdout_len, stdout_data);
        fprintf(stderr, "stderr before END_REQUEST (%lu): %s\n",
                (unsigned long)stderr_len, stderr_data);
        goto cleanup;
      }
      break;
    } else {
      fprintf(stderr, "unexpected FastCGI record type: %u\n", record.type);
      goto cleanup;
    }
  }

  stdout_data[stdout_len] = 0;
  stderr_data[stderr_len] = 0;
  if (end_request_count != 1) {
    fprintf(stderr, "expected one END_REQUEST, received %d\n",
            end_request_count);
    goto cleanup;
  }
  if (stdout_len != sizeof expected_stdout - 1 ||
      memcmp(stdout_data, expected_stdout, sizeof expected_stdout - 1) != 0) {
    fprintf(stderr, "unexpected FastCGI stdout:\n%s\n", stdout_data);
    goto cleanup;
  }
  if (stderr_len != sizeof expected_stderr - 1 ||
      memcmp(stderr_data, expected_stderr, sizeof expected_stderr - 1) != 0) {
    fprintf(stderr, "unexpected FastCGI stderr:\n%s\n", stderr_data);
    goto cleanup;
  }
  if (!fcgi_wait_process(process.hProcess, deadline_ms, &process_exit) ||
      process_exit != 0) {
    fprintf(stderr, "Pure worker did not exit normally: %lu\n", process_exit);
    goto cleanup;
  }

  puts("pure-fastcgi protocol smoke passed");
  result = 0;

cleanup:
  if (client != INVALID_HANDLE_VALUE) {
    CloseHandle(client);
  }
  if (server != INVALID_HANDLE_VALUE) {
    CloseHandle(server);
  }
  if (process_started && process.hProcess != NULL) {
    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) {
      TerminateProcess(process.hProcess, 1);
      WaitForSingleObject(process.hProcess, 2000);
    }
    CloseHandle(process.hProcess);
  }
  if (process.hThread != NULL) {
    CloseHandle(process.hThread);
  }
  if (attributes != NULL) {
    if (attributes_initialized) {
      DeleteProcThreadAttributeList(attributes);
    }
    HeapFree(GetProcessHeap(), 0, attributes);
  }
  free(command_line);
  return result;
}
#endif
