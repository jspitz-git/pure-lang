/* Copyright (c) 2026 by the Pure contributors.

   This file is part of the Pure runtime.

   The Pure runtime is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or (at your
   option) any later version. */

#include "pure_jit.hh"

#include <llvm/ADT/SmallVector.h>
#include <llvm/Bitcode/BitcodeReader.h>
#include <llvm/Bitcode/BitcodeWriter.h>
#include <llvm/ExecutionEngine/Orc/LLJIT.h>
#include <llvm/IR/DataLayout.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>

#include <utility>

PureJit::PureJit(std::unique_ptr<llvm::orc::LLJIT> jit) noexcept
  : jit_(std::move(jit))
{
}

PureJit::~PureJit() = default;

llvm::Expected<std::unique_ptr<PureJit> > PureJit::create()
{
  if (llvm::InitializeNativeTarget())
    return llvm::createStringError("failed to initialize the native LLVM target");
  if (llvm::InitializeNativeTargetAsmPrinter())
    return llvm::createStringError
      ("failed to initialize the native LLVM assembly printer");
  if (llvm::InitializeNativeTargetAsmParser())
    return llvm::createStringError
      ("failed to initialize the native LLVM assembly parser");

  llvm::orc::LLJITBuilder builder;
  // Native LLJIT requires its process-symbol JITDylib during construction.
  // LLVM links that dylib into the main dylib's default search order.
  builder.setLinkProcessSymbolsByDefault(true);
  llvm::Expected<std::unique_ptr<llvm::orc::LLJIT> > jit = builder.create();
  if (!jit) return jit.takeError();

  return std::unique_ptr<PureJit>(new PureJit(std::move(*jit)));
}

const llvm::DataLayout& PureJit::data_layout() const noexcept
{
  return jit_->getDataLayout();
}

llvm::orc::ResourceTrackerSP PureJit::create_resource_tracker()
{
  return jit_->getMainJITDylib().createResourceTracker();
}

llvm::Error PureJit::add_module(llvm::orc::ThreadSafeModule module)
{
  return jit_->addIRModule(std::move(module));
}

llvm::Error PureJit::add_module(llvm::orc::ResourceTrackerSP tracker,
                                llvm::orc::ThreadSafeModule module)
{
  return jit_->addIRModule(std::move(tracker), std::move(module));
}

llvm::Error PureJit::add_module_copy(llvm::orc::ResourceTrackerSP tracker,
                                     const llvm::Module& module)
{
  llvm::SmallVector<char, 0> bitcode;
  llvm::raw_svector_ostream out(bitcode);
  llvm::WriteBitcodeToFile(module, out);

  std::unique_ptr<llvm::LLVMContext> context(new llvm::LLVMContext);
  llvm::MemoryBufferRef buffer
    (llvm::StringRef(bitcode.data(), bitcode.size()), module.getName());
  llvm::Expected<std::unique_ptr<llvm::Module> > copy =
    llvm::parseBitcodeFile(buffer, *context);
  if (!copy) return copy.takeError();

  llvm::orc::ThreadSafeModule thread_safe_module
    (std::move(*copy), std::move(context));
  return add_module(std::move(tracker), std::move(thread_safe_module));
}

llvm::Expected<llvm::orc::ExecutorAddr> PureJit::lookup(llvm::StringRef name)
{
  return jit_->lookup(name);
}
