define ptr @bc_metadata_malformed(ptr %value) {
  ret ptr %value
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 2}
!1 = !{!"function", !"bc_metadata_malformed", !"char*", !"char*"}
