/* Copyright (c) 2026 by the Pure contributors.

   This file is part of the Pure runtime.

   The Pure runtime is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or (at your
   option) any later version. */

#include "pure_jit.hh"

#include <llvm/ADT/SmallPtrSet.h>
#include <llvm/ADT/SmallVector.h>
#include <llvm/Bitcode/BitcodeReader.h>
#include <llvm/Bitcode/BitcodeWriter.h>
#include <llvm/ExecutionEngine/Orc/AbsoluteSymbols.h>
#include <llvm/ExecutionEngine/Orc/JITTargetMachineBuilder.h>
#include <llvm/ExecutionEngine/Orc/LLJIT.h>
#include <llvm/ExecutionEngine/Orc/Mangling.h>
#include <llvm/IR/DataLayout.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/GlobalAlias.h>
#include <llvm/IR/GlobalIFunc.h>
#include <llvm/IR/InstIterator.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/IR/Verifier.h>
#include <llvm/Passes/OptimizationLevel.h>
#include <llvm/Passes/PassBuilder.h>
#include <llvm/Support/CodeGen.h>
#include <llvm/Support/MemoryBuffer.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Support/raw_ostream.h>

#include <utility>

PureJit::PureJit(std::unique_ptr<llvm::orc::LLJIT> jit) noexcept
  : jit_(std::move(jit))
{
  jit_->getExecutionSession().setErrorReporter
    ([this](llvm::Error error) { record_session_error(std::move(error)); });
}

PureJit::~PureJit() = default;

void PureJit::record_session_error(llvm::Error error)
{
  std::lock_guard<std::mutex> lock(session_error_mutex_);
  std::string message = llvm::toString(std::move(error));
  if (!session_error_.empty()) session_error_ += "\n";
  session_error_ += message;
}

std::string PureJit::take_session_error()
{
  std::lock_guard<std::mutex> lock(session_error_mutex_);
  std::string message;
  message.swap(session_error_);
  return message;
}

static void collect_dependencies
(llvm::Value *value, llvm::SmallPtrSetImpl<llvm::GlobalValue*>& reachable)
{
  if (!value) return;
  if (llvm::GlobalValue *global = llvm::dyn_cast<llvm::GlobalValue>(value)) {
    if (!reachable.insert(global).second) return;
    if (llvm::Function *function = llvm::dyn_cast<llvm::Function>(global)) {
      for (llvm::Instruction& instruction : llvm::instructions(function))
        collect_dependencies(&instruction, reachable);
    } else if (llvm::GlobalVariable *variable =
                 llvm::dyn_cast<llvm::GlobalVariable>(global)) {
      if (variable->hasInitializer())
        collect_dependencies(variable->getInitializer(), reachable);
    } else if (llvm::GlobalAlias *alias =
                 llvm::dyn_cast<llvm::GlobalAlias>(global)) {
      collect_dependencies(alias->getAliasee(), reachable);
    } else if (llvm::GlobalIFunc *ifunc =
                 llvm::dyn_cast<llvm::GlobalIFunc>(global)) {
      collect_dependencies(ifunc->getResolver(), reachable);
    }
  }
  if (llvm::User *user = llvm::dyn_cast<llvm::User>(value))
    for (llvm::Value *operand : user->operand_values())
      collect_dependencies(operand, reachable);
}

static llvm::Error verify_module(const llvm::Module& module,
                                 llvm::StringRef stage)
{
  std::string verification_error;
  llvm::raw_string_ostream verification_out(verification_error);
  if (llvm::verifyModule(module, &verification_out)) {
    verification_out.flush();
    return llvm::createStringError("invalid %s ORC module: %s",
                                   stage.str().c_str(),
                                   verification_error.c_str());
  }
  return llvm::Error::success();
}

static llvm::Error optimize_module(llvm::Module& module)
{
  llvm::LoopAnalysisManager loops;
  llvm::FunctionAnalysisManager functions;
  llvm::CGSCCAnalysisManager cgscc;
  llvm::ModuleAnalysisManager modules;
  llvm::PassBuilder builder;
  builder.registerLoopAnalyses(loops);
  builder.registerFunctionAnalyses(functions);
  builder.registerCGSCCAnalyses(cgscc);
  builder.registerModuleAnalyses(modules);
  builder.crossRegisterProxies(loops, functions, cgscc, modules);

  llvm::ModulePassManager pipeline =
    builder.buildPerModuleDefaultPipeline(llvm::OptimizationLevel::O1);
  pipeline.run(module, modules);
  return verify_module(module, "optimized");
}

static llvm::Error reduce_to_entry(llvm::Module& module,
                                   llvm::StringRef entry_name,
                                   llvm::StringRef exported_name)
{
  llvm::Function *entry = module.getFunction(entry_name);
  if (!entry)
    return llvm::createStringError("ORC entry symbol '%s' is not a function",
                                   entry_name.str().c_str());

  llvm::SmallPtrSet<llvm::GlobalValue*, 32> reachable;
  collect_dependencies(entry, reachable);

  for (llvm::Function& function : module)
    if (!function.isDeclaration() && !reachable.contains(&function)) {
      function.deleteBody();
      function.setLinkage(llvm::GlobalValue::ExternalLinkage);
    }
  for (llvm::GlobalVariable& variable : module.globals()) {
    bool keep_definition = reachable.contains(&variable) &&
      variable.isConstant() && variable.hasInitializer();
    if (!keep_definition && variable.hasInitializer()) {
      variable.setInitializer(0);
      variable.setLinkage(llvm::GlobalValue::ExternalLinkage);
    }
  }
  for (llvm::Module::alias_iterator alias = module.alias_begin();
       alias != module.alias_end(); ) {
    llvm::GlobalAlias& current = *alias++;
    if (!reachable.contains(&current)) current.eraseFromParent();
  }
  for (llvm::Module::ifunc_iterator ifunc = module.ifunc_begin();
       ifunc != module.ifunc_end(); ) {
    llvm::GlobalIFunc& current = *ifunc++;
    if (!reachable.contains(&current)) current.eraseFromParent();
  }

  if (!exported_name.empty()) entry->setName(exported_name);
  entry->setLinkage(llvm::GlobalValue::ExternalLinkage);
  return verify_module(module, "reduced");
}

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

  llvm::Expected<llvm::orc::JITTargetMachineBuilder> target =
    llvm::orc::JITTargetMachineBuilder::detectHost();
  if (!target) return target.takeError();
  target->setCodeModel(llvm::CodeModel::Large);
  target->setRelocationModel(llvm::Reloc::PIC_);

  llvm::orc::LLJITBuilder builder;
  builder.setJITTargetMachineBuilder(std::move(*target));
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

const llvm::Triple& PureJit::target_triple() const noexcept
{
  return jit_->getTargetTriple();
}

llvm::orc::ResourceTrackerSP PureJit::create_resource_tracker()
{
  return jit_->getMainJITDylib().createResourceTracker();
}

llvm::Error PureJit::register_absolute_symbol
(llvm::orc::ResourceTrackerSP tracker, llvm::StringRef name,
 llvm::orc::ExecutorSymbolDef symbol)
{
  llvm::orc::MangleAndInterner mangle(jit_->getExecutionSession(),
                                      jit_->getDataLayout());
  llvm::orc::SymbolMap symbols;
  symbols[mangle(name)] = symbol;
  return jit_->getMainJITDylib().define
    (llvm::orc::absoluteSymbols(std::move(symbols)), std::move(tracker));
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
                                     const llvm::Module& module,
                                     llvm::StringRef entry_symbol,
                                     llvm::StringRef exported_symbol)
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
  if (!entry_symbol.empty())
    if (llvm::Error error =
          reduce_to_entry(**copy, entry_symbol, exported_symbol))
      return error;
  if (llvm::Error error = optimize_module(**copy)) return error;

  llvm::orc::ThreadSafeModule thread_safe_module
    (std::move(*copy), std::move(context));
  return add_module(std::move(tracker), std::move(thread_safe_module));
}

llvm::Expected<llvm::orc::ExecutorAddr> PureJit::lookup(llvm::StringRef name)
{
  take_session_error();
  llvm::Expected<llvm::orc::ExecutorAddr> address = jit_->lookup(name);
  if (!address) {
    std::string detail = llvm::toString(address.takeError());
    std::string session_error = take_session_error();
    if (!session_error.empty()) detail += ": "+session_error;
    return llvm::createStringError("failed to resolve ORC symbol '%s': %s",
                                   name.str().c_str(), detail.c_str());
  }
  return address;
}
