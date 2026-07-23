#include "pure_jit.hh"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#include <llvm/Support/raw_ostream.h>

#include <cstdint>
#include <memory>
#include <utility>

static int report_error(llvm::Error error)
{
  llvm::logAllUnhandledErrors(std::move(error), llvm::errs(),
                              "PureJit smoke test: ");
  return 1;
}

int main()
{
  llvm::Expected<std::unique_ptr<PureJit> > jit = PureJit::create();
  if (!jit) return report_error(jit.takeError());

  std::unique_ptr<llvm::LLVMContext> context(new llvm::LLVMContext);
  std::unique_ptr<llvm::Module> module
    (new llvm::Module("pure-jit-smoke", *context));
  module->setDataLayout((*jit)->data_layout());

  llvm::FunctionType *function_type = llvm::FunctionType::get
    (llvm::Type::getInt32Ty(*context), false);
  llvm::Function *function = llvm::Function::Create
    (function_type, llvm::Function::InternalLinkage,
     "pure_jit_smoke_value", module.get());
  llvm::BasicBlock *entry = llvm::BasicBlock::Create
    (*context, "entry", function);
  llvm::IRBuilder<> builder(entry);
  builder.CreateRet(llvm::ConstantInt::get(llvm::Type::getInt32Ty(*context), 42));

  llvm::orc::ResourceTrackerSP tracker = (*jit)->create_resource_tracker();
  if (llvm::Error error =
        (*jit)->add_module_copy(tracker, *module, "pure_jit_smoke_value"))
    return report_error(std::move(error));

  llvm::Expected<std::int32_t (*)()> value =
    (*jit)->lookup_function<std::int32_t()>("pure_jit_smoke_value");
  if (!value) return report_error(value.takeError());
  if ((*value)() != 42) {
    llvm::errs() << "PureJit smoke test returned the wrong value\n";
    return 1;
  }

  if (llvm::Error error = tracker->remove())
    return report_error(std::move(error));
  return 0;
}
