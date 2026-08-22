#pragma once

#include <string>
#include <vector>

namespace purepad::detail {

std::vector<wchar_t> BuildChildEnvironmentBlock(
  const std::vector<std::wstring>& inherited,
  const std::wstring& prompt);

} // namespace purepad::detail
