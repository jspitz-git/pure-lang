define ptr @bc_pointer_echo(ptr %value) {
  ret ptr %value
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_pointer_echo", !"const char*", !"const char*"}
