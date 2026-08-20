@pure_faust_sample_format = constant [7 x i8] c"double\00"
@faust_metadata_anchor = internal constant i32 41
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
  %inputs = load i32, ptr @faust_metadata_anchor
  ret i32 %inputs
}

define i32 @getNumOutputsreload(ptr %dsp) {
  ret i32 41
}

define void @computereload(ptr %dsp, i32 %count, ptr %inputs, ptr %outputs) {
  ret void
}

!llvm.module.flags = !{!0}
!faust.metadata.anchor = !{!1}

!0 = !{i32 1, !"faust.metadata.anchor", ptr @faust_metadata_anchor}
!1 = !{ptr @faust_metadata_anchor}
