define ptr addrspace(1) @bc_metadata_address_space() {
  ret ptr addrspace(1) null
}

!pure.abi = !{!0, !1}
!0 = !{!"version", i32 1}
!1 = !{!"function", !"bc_metadata_address_space", !"char*"}
