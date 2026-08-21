define ptr @bc_metadata_non_string(ptr %value) {
  ret ptr %value
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_non_string", i32 0, !"char*"}
