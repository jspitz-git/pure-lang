#include <cstdint>
#include <cstdio>
#include <string_view>
#include <windows.h>

namespace {

bool ReadBytes(FILE* file, std::int64_t offset, void* bytes, size_t size) {
  return _fseeki64(file, offset, SEEK_SET) == 0 &&
         std::fread(bytes, 1, size, file) == size;
}

bool WriteBytes(FILE* file, std::int64_t offset, const void* bytes,
                size_t size) {
  return _fseeki64(file, offset, SEEK_SET) == 0 &&
         std::fwrite(bytes, 1, size, file) == size;
}

std::uint32_t LittleEndian32(const unsigned char bytes[4]) {
  return static_cast<std::uint32_t>(bytes[0]) |
         (static_cast<std::uint32_t>(bytes[1]) << 8) |
         (static_cast<std::uint32_t>(bytes[2]) << 16) |
         (static_cast<std::uint32_t>(bytes[3]) << 24);
}

} // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 4) return 2;
  if (!CopyFileW(argv[1], argv[2], FALSE)) return 3;

  FILE* file = nullptr;
  if (_wfopen_s(&file, argv[2], L"r+b") != 0 || !file) return 4;
  unsigned char pe_offset_bytes[4]{};
  if (!ReadBytes(file, 0x3c, pe_offset_bytes, sizeof(pe_offset_bytes))) {
    std::fclose(file);
    return 5;
  }
  const std::uint32_t pe_offset = LittleEndian32(pe_offset_bytes);
  const std::wstring_view mutation(argv[3]);
  bool written = false;
  if (mutation == L"--machine-i386") {
    const unsigned char machine[] = {0x4c, 0x01};
    written = WriteBytes(file, pe_offset + 4, machine, sizeof(machine));
  } else if (mutation == L"--subsystem-console") {
    const unsigned char subsystem[] = {0x03, 0x00};
    written = WriteBytes(file, pe_offset + 24 + 68, subsystem,
                         sizeof(subsystem));
  }
  const bool closed = std::fclose(file) == 0;
  return written && closed ? 0 : 6;
}
