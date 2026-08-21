define i32 @bc_metadata_const_scalar() {
  ret i32 42
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_const_scalar", !"const int"}
