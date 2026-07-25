define i32 @bc_pointer_duplicate(ptr %value) {
  ret i32 11
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_pointer_duplicate", !"int", !"const char*"}
