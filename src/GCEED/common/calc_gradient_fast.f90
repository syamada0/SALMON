!
!  Copyright 2019 SALMON developers
!
!  Licensed under the Apache License, Version 2.0 (the "License");
!  you may not use this file except in compliance with the License.
!  You may obtain a copy of the License at
!
!      http://www.apache.org/licenses/LICENSE-2.0
!
!  Unless required by applicable law or agreed to in writing, software
!  distributed under the License is distributed on an "AS IS" BASIS,
!  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
!  See the License for the specific language governing permissions and
!  limitations under the License.
!
subroutine calc_gradient_fast(mg,tpsi,grad_wk)
use scf_data
use sendrecv_groupob_sub
use structures, only: s_rgrid
implicit none
type(s_rgrid),intent(in) :: mg
real(8) :: tpsi(mg%is_overlap(1):mg%ie_overlap(1) &
&              ,mg%is_overlap(2):mg%ie_overlap(2) &
&              ,mg%is_overlap(3):mg%ie_overlap(3), 1:iobnum, k_sta:k_end)
real(8) :: grad_wk(mg%is(1):mg%ie(1)+1,mg%is(2):mg%ie(2),mg%is(3):mg%ie(3), &
                   1:iobnum,k_sta:k_end,3)
integer :: ix,iy,iz,iob,iik

call sendrecv_copy(tpsi)
call sendrecv_groupob(tpsi)

if(Nd==4)then
  do iik=k_sta,k_end
  do iob=1,iobnum
!$OMP parallel private(iz)
    do iz=mg%is(3),mg%ie(3)
!$OMP do private(iy, ix) 
    do iy=mg%is(2),mg%ie(2)
    do ix=mg%is(1),mg%ie(1)
      grad_wk(ix,iy,iz,iob,iik,1) =  &
        +bN1/Hgs(1)*( tpsi(ix+1,iy,iz,iob,iik) - tpsi(ix-1,iy,iz,iob,iik) )    &
        +bN2/Hgs(1)*( tpsi(ix+2,iy,iz,iob,iik) - tpsi(ix-2,iy,iz,iob,iik) )    &
        +bN3/Hgs(1)*( tpsi(ix+3,iy,iz,iob,iik) - tpsi(ix-3,iy,iz,iob,iik) )    &
        +bN4/Hgs(1)*( tpsi(ix+4,iy,iz,iob,iik) - tpsi(ix-4,iy,iz,iob,iik) )
      grad_wk(ix,iy,iz,iob,iik,2) =  &
        +bN1/Hgs(2)*( tpsi(ix,iy+1,iz,iob,iik) - tpsi(ix,iy-1,iz,iob,iik) )    &
        +bN2/Hgs(2)*( tpsi(ix,iy+2,iz,iob,iik) - tpsi(ix,iy-2,iz,iob,iik) )    &
        +bN3/Hgs(2)*( tpsi(ix,iy+3,iz,iob,iik) - tpsi(ix,iy-3,iz,iob,iik) )    &
        +bN4/Hgs(2)*( tpsi(ix,iy+4,iz,iob,iik) - tpsi(ix,iy-4,iz,iob,iik) )
    end do
    end do
!$OMP end do nowait
!$OMP do private(iy, ix) 
    do iy=mg%is(2),mg%ie(2)
    do ix=mg%is(1),mg%ie(1)
      grad_wk(ix,iy,iz,iob,iik,3) =  &
        +bN1/Hgs(3)*( tpsi(ix,iy,iz+1,iob,iik) - tpsi(ix,iy,iz-1,iob,iik) )    &
        +bN2/Hgs(3)*( tpsi(ix,iy,iz+2,iob,iik) - tpsi(ix,iy,iz-2,iob,iik) )    &
        +bN3/Hgs(3)*( tpsi(ix,iy,iz+3,iob,iik) - tpsi(ix,iy,iz-3,iob,iik) )    &
        +bN4/Hgs(3)*( tpsi(ix,iy,iz+4,iob,iik) - tpsi(ix,iy,iz-4,iob,iik) )
    end do
    end do
!$OMP end do nowait
    end do
!$OMP end parallel
  end do
  end do
end if

end subroutine calc_gradient_fast
