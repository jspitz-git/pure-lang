/* Copyright (c) 2026 by the Pure contributors.

   This file is part of the Pure runtime.

   The Pure runtime is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or (at your
   option) any later version. */

#ifndef PURE_JIT_HH
#define PURE_JIT_HH

#include <llvm/ADT/StringRef.h>
#include <llvm/ExecutionEngine/JITSymbol.h>
#include <llvm/ExecutionEngine/Orc/Core.h>
#include <llvm/ExecutionEngine/Orc/Shared/ExecutorAddress.h>
#include <llvm/ExecutionEngine/Orc/Shared/ExecutorSymbolDef.h>
#include <llvm/ExecutionEngine/Orc/ThreadSafeModule.h>
#include <llvm/Support/Error.h>

#include <memory>
#include <type_traits>
#include <utility>

namespace llvm {

class DataLayout;
class Module;

namespace orc {
class LLJIT;
}

} // namespace llvm

class PureJit {
public:
  static llvm::Expected<std::unique_ptr<PureJit> > create();

  ~PureJit();

  PureJit(const PureJit&) = delete;
  PureJit& operator=(const PureJit&) = delete;

  const llvm::DataLayout& data_layout() const noexcept;

  llvm::orc::ResourceTrackerSP create_resource_tracker();

  llvm::Error register_absolute_symbol
    (llvm::orc::ResourceTrackerSP tracker, llvm::StringRef name,
     llvm::orc::ExecutorSymbolDef symbol);

  template<class T>
  llvm::Error register_absolute_symbol
    (llvm::orc::ResourceTrackerSP tracker, llvm::StringRef name, T *address,
     llvm::JITSymbolFlags flags = llvm::JITSymbolFlags::Exported)
  {
    return register_absolute_symbol
      (std::move(tracker), name,
       llvm::orc::ExecutorSymbolDef::fromPtr(address, flags));
  }

  llvm::Error add_module(llvm::orc::ThreadSafeModule module);
  llvm::Error add_module(llvm::orc::ResourceTrackerSP tracker,
                         llvm::orc::ThreadSafeModule module);
  llvm::Error add_module_copy(llvm::orc::ResourceTrackerSP tracker,
                              const llvm::Module& module,
                              llvm::StringRef exported_symbol = "");

  llvm::Expected<llvm::orc::ExecutorAddr> lookup(llvm::StringRef name);

  template<class FunctionType>
  llvm::Expected<FunctionType*> lookup_function(llvm::StringRef name)
  {
    static_assert(std::is_function<FunctionType>::value,
                  "lookup_function requires a function type");
    llvm::Expected<llvm::orc::ExecutorAddr> address = lookup(name);
    if (!address) return address.takeError();
    return address->toPtr<FunctionType*>();
  }

private:
  explicit PureJit(std::unique_ptr<llvm::orc::LLJIT> jit) noexcept;

  std::unique_ptr<llvm::orc::LLJIT> jit_;
};

#endif
