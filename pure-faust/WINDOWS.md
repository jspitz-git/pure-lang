# pure-faust on Windows

The Windows runtime installs only `faust2.pure`.  DSP loading is delegated to
the Pure core, including its Faust bitcode loader and runtime support.

The runtime deliberately excludes the legacy native bridge (`faust.dll`,
`faust.pure`, and `pure.cpp`) and developer tools such as Faust, Clang, and
LLVM.  Those developer tools belong to the optional `FaustDeveloper`
component.

Task 5 will expand this note with complete Windows usage and validation
instructions.
