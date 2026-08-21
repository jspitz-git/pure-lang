define ptr @bc_pointer_qualified(ptr %value) {
  ret ptr %value
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_pointer_qualified", !"const char* const*", !"const char* const*"}
