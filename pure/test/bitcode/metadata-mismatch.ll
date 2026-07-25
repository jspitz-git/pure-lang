define i32 @bc_metadata_mismatch() {
  ret i32 1
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_mismatch", !"char*"}
