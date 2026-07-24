#include "pure_jit.hh"

#include <llvm/IR/BasicBlock.h>
#include <llvm/IR/Constants.h>
#include <llvm/IR/Function.h>
#include <llvm/IR/GlobalVariable.h>
#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Module.h>
#ifdef PURE_JIT_ELF_DEBUG_OBJECTS
#include <llvm/ExecutionEngine/Orc/TargetProcess/JITLoaderGDB.h>
#endif
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

#ifdef PURE_JIT_ELF_DEBUG_OBJECTS
extern "C" jit_descriptor __jit_debug_descriptor;

static bool registered_debug_object_contains(llvm::StringRef name)
{
  for (jit_code_entry *entry = __jit_debug_descriptor.first_entry;
       entry; entry = entry->next_entry) {
    llvm::StringRef object(entry->symfile_addr, entry->symfile_size);
    if (object.contains(name)) return true;
  }
  return false;
}
#endif

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
#ifdef PURE_JIT_ELF_DEBUG_OBJECTS
  if (!registered_debug_object_contains("pure_jit_smoke_value")) {
    llvm::errs() << "PureJit did not register the generated function name\n";
    return 1;
  }
#endif
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

  std::unique_ptr<llvm::Module> provider
    (new llvm::Module("pure-jit-provider", *context));
  provider->setDataLayout((*jit)->data_layout());
  provider->setTargetTriple((*jit)->target_triple());
  llvm::Function *provider_function = llvm::Function::Create
    (increment_type, llvm::Function::ExternalLinkage,
     "pure_jit_smoke_provider", provider.get());
  llvm::BasicBlock *provider_entry = llvm::BasicBlock::Create
    (*context, "entry", provider_function);
  llvm::IRBuilder<> provider_builder(provider_entry);
  provider_builder.CreateRet(provider_builder.CreateAdd
    (provider_function->getArg(0), llvm::ConstantInt::get(int32_type, 1)));

  llvm::orc::ResourceTrackerSP provider_tracker =
    (*jit)->create_resource_tracker();
  if (llvm::Error error =
        (*jit)->add_module_copy(provider_tracker, *provider))
    return report_error(std::move(error));

  std::unique_ptr<llvm::Module> consumer
    (new llvm::Module("pure-jit-consumer", *context));
  consumer->setDataLayout((*jit)->data_layout());
  consumer->setTargetTriple((*jit)->target_triple());
  llvm::Function *provider_declaration = llvm::Function::Create
    (increment_type, llvm::Function::ExternalLinkage,
     "pure_jit_smoke_provider", consumer.get());
  llvm::Function *consumer_function = llvm::Function::Create
    (function_type, llvm::Function::ExternalLinkage,
     "pure_jit_smoke_consumer", consumer.get());
  llvm::BasicBlock *consumer_entry = llvm::BasicBlock::Create
    (*context, "entry", consumer_function);
  llvm::IRBuilder<> consumer_builder(consumer_entry);
  consumer_builder.CreateRet(consumer_builder.CreateCall
    (provider_declaration, llvm::ConstantInt::get(int32_type, 41)));

  llvm::orc::ResourceTrackerSP consumer_tracker =
    (*jit)->create_resource_tracker();
  if (llvm::Error error =
        (*jit)->add_module_copy(consumer_tracker, *consumer))
    return report_error(std::move(error));
  llvm::Expected<std::int32_t (*)()> consumer_address =
    (*jit)->lookup_function<std::int32_t()>("pure_jit_smoke_consumer");
  if (!consumer_address) return report_error(consumer_address.takeError());
  if ((*consumer_address)() != 42) {
    llvm::errs() << "PureJit provider consumer returned the wrong value\n";
    return 1;
  }
  if (llvm::Error error = consumer_tracker->remove())
    return report_error(std::move(error));
  if (llvm::Error error = provider_tracker->remove())
    return report_error(std::move(error));
  llvm::Expected<llvm::orc::ExecutorAddr> removed_provider =
    (*jit)->lookup("pure_jit_smoke_provider");
  if (removed_provider) {
    llvm::errs() << "PureJit retained a removed provider symbol\n";
    return 1;
  }
  llvm::consumeError(removed_provider.takeError());

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
