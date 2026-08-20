/* Copyright (c) 2026 by the Pure contributors.

   This file is part of the Pure runtime.

   The Pure runtime is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or (at your
   option) any later version. */

#include "coff_jitlink.hh"

#include <llvm/ExecutionEngine/JITLink/JITLink.h>
#include <llvm/ExecutionEngine/Orc/MapperJITLinkMemoryManager.h>
#include <llvm/ExecutionEngine/Orc/MemoryMapper.h>
#include <llvm/ExecutionEngine/Orc/ObjectLinkingLayer.h>

#include <limits>
#include <memory>
#include <utility>

namespace {

// MapperJITLinkMemoryManager pools free address ranges without retaining the
// boundaries of the MemoryMapper reservations that contain them. With a
// page-sized reservation unit, adjacent Windows VirtualAlloc reservations can
// therefore be coalesced and a later graph can straddle both. VirtualProtect
// rejects such a range with ERROR_INVALID_ADDRESS during deinitialization.
// Keep one unadvertised page at the end of every reservation so that pooled
// ranges from distinct VirtualAlloc calls are never adjacent.
class GuardedInProcessMemoryMapper final : public llvm::orc::MemoryMapper {
public:
  static llvm::Expected<std::unique_ptr<GuardedInProcessMemoryMapper> > Create()
  {
    llvm::Expected<std::unique_ptr<llvm::orc::InProcessMemoryMapper> > mapper =
      llvm::orc::InProcessMemoryMapper::Create();
    if (!mapper) return mapper.takeError();
    return std::unique_ptr<GuardedInProcessMemoryMapper>
      (new GuardedInProcessMemoryMapper(std::move(*mapper)));
  }

  unsigned int getPageSize() override { return mapper_->getPageSize(); }

  void reserve(size_t bytes, OnReservedFunction on_reserved) override
  {
    const size_t page_size = getPageSize();
    if (bytes > std::numeric_limits<size_t>::max()-page_size)
      return on_reserved(llvm::createStringError
        ("guarded COFF JIT reservation size overflow"));
    mapper_->reserve
      (bytes+page_size,
       [bytes, page_size, on_reserved = std::move(on_reserved)]
       (llvm::Expected<llvm::orc::ExecutorAddrRange> range) mutable {
        if (!range) return on_reserved(range.takeError());
        if (range->size() < bytes+page_size)
          return on_reserved(llvm::createStringError
            ("guarded COFF JIT reservation is smaller than requested"));
        on_reserved(llvm::orc::ExecutorAddrRange
          (range->Start, static_cast<llvm::orc::ExecutorAddrDiff>(bytes)));
      });
  }

  char *prepare(llvm::jitlink::LinkGraph& graph,
                llvm::orc::ExecutorAddr address,
                size_t content_size) override
  {
    return mapper_->prepare(graph, address, content_size);
  }

  void initialize(AllocInfo& info,
                  OnInitializedFunction on_initialized) override
  {
    mapper_->initialize(info, std::move(on_initialized));
  }

  void deinitialize(llvm::ArrayRef<llvm::orc::ExecutorAddr> allocations,
                    OnDeinitializedFunction on_deinitialized) override
  {
    mapper_->deinitialize(allocations, std::move(on_deinitialized));
  }

  void release(llvm::ArrayRef<llvm::orc::ExecutorAddr> reservations,
               OnReleasedFunction on_released) override
  {
    mapper_->release(reservations, std::move(on_released));
  }

private:
  explicit GuardedInProcessMemoryMapper
  (std::unique_ptr<llvm::orc::InProcessMemoryMapper> mapper)
    : mapper_(std::move(mapper)) {}

  std::unique_ptr<llvm::orc::InProcessMemoryMapper> mapper_;
};

// COFF relocatable objects describe .pdata addresses relative to an image
// base. Unlike a loaded PE image, an in-process JIT graph has no loader-created
// header, so give every allocated graph a synthetic base at its lowest block.
// The colocating mapper below guarantees that every block remains within the
// 32-bit RVA range of this address.
llvm::Error set_coff_image_base(llvm::jitlink::LinkGraph& graph)
{
  llvm::orc::SymbolStringPtr name = graph.intern("__ImageBase");
  llvm::jitlink::Symbol *image_base =
    graph.findExternalSymbolByName(name);
  if (!image_base) return llvm::Error::success();

  llvm::orc::ExecutorAddr base;
  bool found_block = false;
  for (llvm::jitlink::Block *block : graph.blocks()) {
    if (!found_block || block->getAddress().getValue() < base.getValue()) {
      base = block->getAddress();
      found_block = true;
    }
  }
  if (!found_block)
    return llvm::createStringError
      ("COFF JIT graph requests __ImageBase without an allocated block");
  graph.makeAbsolute(*image_base, base);
  return llvm::Error::success();
}

class CoffImageBasePlugin final
  : public llvm::orc::ObjectLinkingLayer::Plugin {
public:
  void modifyPassConfig
  (llvm::orc::MaterializationResponsibility&,
   llvm::jitlink::LinkGraph&,
   llvm::jitlink::PassConfiguration& config) override
  {
    config.PostAllocationPasses.push_back(set_coff_image_base);
  }

  llvm::Error notifyFailed
  (llvm::orc::MaterializationResponsibility&) override
  {
    return llvm::Error::success();
  }

  llvm::Error notifyRemovingResources
  (llvm::orc::JITDylib&, llvm::orc::ResourceKey) override
  {
    return llvm::Error::success();
  }

  void notifyTransferringResources
  (llvm::orc::JITDylib&, llvm::orc::ResourceKey,
   llvm::orc::ResourceKey) override {}
};

} // namespace

llvm::Expected<std::unique_ptr<llvm::orc::ObjectLayer> >
create_windows_coff_object_linking_layer
(llvm::orc::ExecutionSession& session)
{
  // COFF's image-relative ADDR32NB relocations (notably in .pdata) must
  // remain representable as 32-bit RVAs. Allocate every graph's code, data
  // and unwind segments contiguously, without tying unrelated unloadable
  // graphs to one fixed-size arena.
  llvm::Expected<std::unique_ptr<GuardedInProcessMemoryMapper> > mapper =
    GuardedInProcessMemoryMapper::Create();
  if (!mapper) return mapper.takeError();
  size_t page_size = (*mapper)->getPageSize();
  std::unique_ptr<llvm::orc::MapperJITLinkMemoryManager> memory_manager
    (new llvm::orc::MapperJITLinkMemoryManager(page_size,
                                               std::move(*mapper)));

  std::unique_ptr<llvm::orc::ObjectLinkingLayer> layer
    (new llvm::orc::ObjectLinkingLayer(session, std::move(memory_manager)));
  // Match LLJIT's legacy COFF visibility and responsibility contract for
  // exported symbols and late weak/common definitions.
  layer->setOverrideObjectFlagsWithResponsibilityFlags(true);
  layer->setAutoClaimResponsibilityForObjectSymbols(true);
  layer->addPlugin(std::make_shared<CoffImageBasePlugin>());
  return std::unique_ptr<llvm::orc::ObjectLayer>(std::move(layer));
}
