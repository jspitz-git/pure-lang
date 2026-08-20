@pure_faust_sample_format = constant [7 x i8] c"double\00"
@faust_reload_state = internal global i8 0

define ptr @newreload() {
  ret ptr @faust_reload_state
}

define void @deletereload(ptr %dsp) {
  ret void
}

define void @initreload(ptr %dsp, i32 %rate) {
  ret void
}

define void @buildUserInterfacereload(ptr %dsp, ptr %ui) {
  ret void
}

define i32 @getNumInputsreload(ptr %dsp) {
  ret i32 43
}

define i32 @getNumOutputsreload(ptr %dsp) {
  ret i32 43
}

define void @computereload(ptr %dsp, i32 %count, ptr %inputs, ptr %outputs) {
  ret void
}
