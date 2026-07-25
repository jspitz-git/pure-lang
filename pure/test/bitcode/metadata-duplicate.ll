define ptr @bc_metadata_duplicate(ptr %value) {
  ret ptr %value
}

!pure.abi = !{!0, !1, !2}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_duplicate", !"char*", !"char*"}
!2 = !{!"function", !"bc_metadata_duplicate", !"char*", !"char*"}
