define i32 @bc_metadata_void_argument(i32 %value) {
  ret i32 %value
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_void_argument", !"int", !"void"}
