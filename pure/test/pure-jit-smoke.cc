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

static llvm::orc::ThreadSafeModule make_invalid_module
(PureJit& jit, llvm::StringRef module_name, llvm::StringRef function_name)
{
  std::unique_ptr<llvm::LLVMContext> context(new llvm::LLVMContext);
  std::unique_ptr<llvm::Module> module
    (new llvm::Module(module_name, *context));
  module->setDataLayout(jit.data_layout());
  module->setTargetTriple(jit.target_triple());
  llvm::FunctionType *function_type = llvm::FunctionType::get
    (llvm::Type::getInt32Ty(*context), false);
  llvm::Function *function = llvm::Function::Create
    (function_type, llvm::Function::ExternalLinkage, function_name,
     module.get());
  llvm::BasicBlock *entry = llvm::BasicBlock::Create
    (*context, "entry", function);
  llvm::ReturnInst::Create(*context, entry);
  return llvm::orc::ThreadSafeModule(std::move(module), std::move(context));
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

  std::unique_ptr<llvm::Module> repeated
    (new llvm::Module("pure-jit-repeated-helper", *context));
  repeated->setDataLayout((*jit)->data_layout());
  repeated->setTargetTriple((*jit)->target_triple());
  llvm::Function *shared_helper = llvm::Function::Create
    (function_type, llvm::Function::ExternalLinkage,
     "pure_jit_smoke_shared_helper", repeated.get());
  llvm::BasicBlock *shared_helper_entry = llvm::BasicBlock::Create
    (*context, "entry", shared_helper);
  llvm::IRBuilder<> shared_helper_builder(shared_helper_entry);
  shared_helper_builder.CreateRet(llvm::ConstantInt::get(int32_type, 42));
  llvm::Function *repeated_entry = llvm::Function::Create
    (function_type, llvm::Function::InternalLinkage,
     "pure_jit_smoke_repeated_entry", repeated.get());
  llvm::BasicBlock *repeated_entry_block = llvm::BasicBlock::Create
    (*context, "entry", repeated_entry);
  llvm::IRBuilder<> repeated_entry_builder(repeated_entry_block);
  repeated_entry_builder.CreateRet
    (repeated_entry_builder.CreateCall(shared_helper));

  llvm::orc::ResourceTrackerSP repeated_tracker_one =
    (*jit)->create_resource_tracker();
  if (llvm::Error error = (*jit)->add_module_copy
        (repeated_tracker_one, *repeated, "pure_jit_smoke_repeated_entry",
         "pure_jit_smoke_repeated_one"))
    return report_error(std::move(error));
  llvm::orc::ResourceTrackerSP repeated_tracker_two =
    (*jit)->create_resource_tracker();
  if (llvm::Error error = (*jit)->add_module_copy
        (repeated_tracker_two, *repeated, "pure_jit_smoke_repeated_entry",
         "pure_jit_smoke_repeated_two"))
    return report_error(std::move(error));
  llvm::Expected<std::int32_t (*)()> repeated_one =
    (*jit)->lookup_function<std::int32_t()>("pure_jit_smoke_repeated_one");
  if (!repeated_one) return report_error(repeated_one.takeError());
  llvm::Expected<std::int32_t (*)()> repeated_two =
    (*jit)->lookup_function<std::int32_t()>("pure_jit_smoke_repeated_two");
  if (!repeated_two) return report_error(repeated_two.takeError());
  if ((*repeated_one)() != 42 || (*repeated_two)() != 42) {
    llvm::errs() << "PureJit repeated helper test returned the wrong value\n";
    return 1;
  }
  if (llvm::Error error = repeated_tracker_two->remove())
    return report_error(std::move(error));
  if (llvm::Error error = repeated_tracker_one->remove())
    return report_error(std::move(error));

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

  std::unique_ptr<llvm::Module> invalid
    (new llvm::Module("pure-jit-invalid", *context));
  invalid->setDataLayout((*jit)->data_layout());
  invalid->setTargetTriple((*jit)->target_triple());
  llvm::Function *invalid_function = llvm::Function::Create
    (function_type, llvm::Function::ExternalLinkage,
     "pure_jit_invalid_function", invalid.get());
  llvm::BasicBlock *invalid_entry = llvm::BasicBlock::Create
    (*context, "entry", invalid_function);
  llvm::ReturnInst::Create(*context, invalid_entry);

  llvm::orc::ResourceTrackerSP invalid_tracker =
    (*jit)->create_resource_tracker();
  llvm::Error invalid_error =
    (*jit)->add_module_copy(invalid_tracker, *invalid);
  if (!invalid_error) {
    llvm::errs() << "PureJit accepted an invalid input module\n";
    return 1;
  }
  std::string invalid_message = llvm::toString(std::move(invalid_error));
  if (invalid_message.find("invalid input ORC module") == std::string::npos) {
    llvm::errs() << "PureJit invalid-module error lacks input-stage context: "
                 << invalid_message << '\n';
    return 1;
  }
  if (llvm::Error error = invalid_tracker->remove())
    return report_error(std::move(error));

  llvm::orc::ResourceTrackerSP direct_tracker =
    (*jit)->create_resource_tracker();
  llvm::orc::ThreadSafeModule direct_thread_safe_module
    = make_invalid_module(**jit, "pure-jit-direct-invalid",
                          "pure_jit_direct_invalid_function");
  llvm::Error direct_error = (*jit)->add_module
    (direct_tracker, std::move(direct_thread_safe_module));
  if (!direct_error) {
    llvm::errs() << "PureJit directly accepted an invalid input module\n";
    return 1;
  }
  std::string direct_message = llvm::toString(std::move(direct_error));
  if (direct_message.find("invalid input ORC module") == std::string::npos) {
    llvm::errs() << "PureJit direct invalid-module error lacks input-stage "
                    "context: " << direct_message << '\n';
    return 1;
  }
  if (llvm::Error error = direct_tracker->remove())
    return report_error(std::move(error));

  llvm::orc::ThreadSafeModule untracked_invalid = make_invalid_module
    (**jit, "pure-jit-untracked-invalid",
     "pure_jit_untracked_invalid_function");
  llvm::Error untracked_error =
    (*jit)->add_module(std::move(untracked_invalid));
  if (!untracked_error) {
    llvm::errs() << "PureJit accepted an invalid untracked input module\n";
    return 1;
  }
  std::string untracked_message = llvm::toString(std::move(untracked_error));
  if (untracked_message.find("invalid input ORC module") == std::string::npos) {
    llvm::errs() << "PureJit untracked invalid-module error lacks input-stage "
                    "context: " << untracked_message << '\n';
    return 1;
  }
  return 0;
}
