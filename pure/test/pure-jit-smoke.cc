#include "pure_jit.hh"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/GlobalVariable.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/Support/raw_ostream.h>

#include <cstdint>
#include <memory>
#include <string>
#include <utility>

static int report_error(llvm::Error error)
{
  llvm::logAllUnhandledErrors(std::move(error), llvm::errs(),
                              "PureJit smoke test: ");
  return 1;
}

static std::int32_t host_value = 41;

static std::int32_t host_increment(std::int32_t value)
{
  return value+1;
}

int main()
{
  llvm::Expected<std::unique_ptr<PureJit> > jit = PureJit::create();
  if (!jit) return report_error(jit.takeError());

  std::unique_ptr<llvm::LLVMContext> context(new llvm::LLVMContext);
  std::unique_ptr<llvm::Module> module
    (new llvm::Module("pure-jit-smoke", *context));
  module->setDataLayout((*jit)->data_layout());

  llvm::Type *int32_type = llvm::Type::getInt32Ty(*context);
  llvm::GlobalVariable *host_data = new llvm::GlobalVariable
    (*module, int32_type, false, llvm::GlobalVariable::ExternalLinkage, 0,
     "pure_jit_smoke_data");
  llvm::FunctionType *increment_type = llvm::FunctionType::get
    (int32_type, int32_type, false);
  llvm::Function *increment = llvm::Function::Create
    (increment_type, llvm::Function::ExternalLinkage,
     "pure_jit_smoke_increment", module.get());
  llvm::FunctionType *function_type = llvm::FunctionType::get
    (int32_type, false);
  llvm::Function *function = llvm::Function::Create
    (function_type, llvm::Function::InternalLinkage,
     "pure_jit_smoke_value", module.get());
  llvm::BasicBlock *entry = llvm::BasicBlock::Create
    (*context, "entry", function);
  llvm::IRBuilder<> builder(entry);
  llvm::Value *host_data_value = builder.CreateLoad(int32_type, host_data);
  builder.CreateRet(builder.CreateCall(increment, host_data_value));

  llvm::orc::ResourceTrackerSP symbol_tracker =
    (*jit)->create_resource_tracker();
  if (llvm::Error error = (*jit)->register_absolute_symbol
        (symbol_tracker, "pure_jit_smoke_data", &host_value))
    return report_error(std::move(error));
  if (llvm::Error error = (*jit)->register_absolute_symbol
        (symbol_tracker, "pure_jit_smoke_increment", &host_increment))
    return report_error(std::move(error));

  llvm::orc::ResourceTrackerSP module_tracker =
    (*jit)->create_resource_tracker();
  if (llvm::Error error =
        (*jit)->add_module_copy(module_tracker, *module,
                                "pure_jit_smoke_value"))
    return report_error(std::move(error));

  llvm::Expected<std::int32_t (*)()> value =
    (*jit)->lookup_function<std::int32_t()>("pure_jit_smoke_value");
  if (!value) return report_error(value.takeError());
  if ((*value)() != 42) {
    llvm::errs() << "PureJit smoke test returned the wrong value\n";
    return 1;
  }

  if (llvm::Error error = module_tracker->remove())
    return report_error(std::move(error));
  if (llvm::Error error = symbol_tracker->remove())
    return report_error(std::move(error));
  llvm::Expected<llvm::orc::ExecutorAddr> removed_symbol =
    (*jit)->lookup("pure_jit_smoke_data");
  if (removed_symbol) {
    llvm::errs() << "PureJit retained a removed absolute symbol\n";
    return 1;
  }
  llvm::consumeError(removed_symbol.takeError());

  llvm::Function *missing_target = llvm::Function::Create
    (function_type, llvm::Function::ExternalLinkage,
     "pure_jit_smoke_missing_target", module.get());
  llvm::Function *missing_entry = llvm::Function::Create
    (function_type, llvm::Function::InternalLinkage,
     "pure_jit_smoke_missing_entry", module.get());
  llvm::BasicBlock *missing_block = llvm::BasicBlock::Create
    (*context, "entry", missing_entry);
  llvm::IRBuilder<> missing_builder(missing_block);
  missing_builder.CreateRet(missing_builder.CreateCall(missing_target));

  llvm::orc::ResourceTrackerSP missing_tracker =
    (*jit)->create_resource_tracker();
  if (llvm::Error error = (*jit)->add_module_copy
        (missing_tracker, *module, "pure_jit_smoke_missing_entry"))
    return report_error(std::move(error));
  llvm::Expected<llvm::orc::ExecutorAddr> missing =
    (*jit)->lookup("pure_jit_smoke_missing_entry");
  if (missing) {
    llvm::errs() << "PureJit resolved an intentionally missing symbol\n";
    return 1;
  }
  std::string missing_error = llvm::toString(missing.takeError());
  if (missing_error.find("pure_jit_smoke_missing_target") == std::string::npos) {
    llvm::errs() << "PureJit missing-symbol error lacks symbol context: "
                 << missing_error << '\n';
    return 1;
  }
  if (llvm::Error error = missing_tracker->remove())
    return report_error(std::move(error));
  return 0;
}
