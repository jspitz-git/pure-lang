/* Copyright (c) 2026 by the Pure contributors.

   This file is part of the Pure runtime.

   The Pure runtime is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or (at your
   option) any later version. */

#include "pure_jit.hh"

#include <llvm/ExecutionEngine/Orc/LLJIT.h>
#include <llvm/IR/DataLayout.h>

#include <utility>

PureJit::PureJit(std::unique_ptr<llvm::orc::LLJIT> jit) noexcept
  : jit_(std::move(jit))
{
}

PureJit::~PureJit() = default;

llvm::Expected<std::unique_ptr<PureJit> > PureJit::create()
{
  llvm::Expected<std::unique_ptr<llvm::orc::LLJIT> > jit =
    llvm::orc::LLJITBuilder().create();
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

llvm::Expected<llvm::orc::ExecutorAddr> PureJit::lookup(llvm::StringRef name)
{
  return jit_->lookup(name);
}
