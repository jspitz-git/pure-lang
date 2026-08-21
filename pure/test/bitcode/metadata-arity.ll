define ptr @bc_metadata_arity(ptr %first, ptr %second) {
  ret ptr %first
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_arity", !"char*", !"char*"}
