/* Copyright (c) 2026 by the Pure contributors.

   This file is part of the Pure runtime.

   The Pure runtime is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or (at your
   option) any later version. */

#ifndef PURE_COFF_JITLINK_HH
#define PURE_COFF_JITLINK_HH

#include <llvm/Support/Error.h>

#include <memory>

namespace llvm {
namespace orc {
class ExecutionSession;
class ObjectLayer;
} // namespace orc
} // namespace llvm

llvm::Expected<std::unique_ptr<llvm::orc::ObjectLayer> >
create_windows_coff_object_linking_layer
  (llvm::orc::ExecutionSession& session);

#endif
