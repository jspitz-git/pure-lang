@pure_faust_sample_format = constant [7 x i8] c"double\00"
@"$$__faust__$metadata_retirement_reload$g1$faust_metadata_anchor" =
  external constant i32
@faust_metadata_conflict_anchor = internal constant i32 42
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
  %inputs = load i32, ptr @faust_metadata_conflict_anchor
  ret i32 %inputs
}

define i32 @getNumOutputsreload(ptr %dsp) {
  ret i32 42
}

define void @computereload(ptr %dsp, i32 %count, ptr %inputs, ptr %outputs) {
  ret void
}

!faust.metadata.conflict = !{!0}

!0 = !{ptr @"$$__faust__$metadata_retirement_reload$g1$faust_metadata_anchor",
       ptr @faust_metadata_conflict_anchor}
