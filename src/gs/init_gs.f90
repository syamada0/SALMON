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

module init_gs
  implicit none
  
contains

!===================================================================================================================================

SUBROUTINE init_wf(lg,mg,system,info,spsi)
  use structures
  use salmon_global, only: yn_periodic,natom,rion
  use gram_schmidt_orth
  implicit none

  type(s_rgrid)           ,intent(in) :: lg,mg
  type(s_dft_system)      ,intent(in) :: system
  type(s_orbital_parallel),intent(in) :: info
  type(s_orbital)                     :: spsi
  !
  integer :: ik,io,is,iseed,a,ix,iy,iz
  real(8) :: xx,yy,zz,x1,y1,z1,rr,rnd,Xmax,Ymax,Zmax
  real(8),parameter :: a_B=0.529177d0

  select case(yn_periodic)
  case('n')
  
    Xmax=0.d0 ; Ymax=0.d0 ; Zmax=0.d0
    do a=1,natom
      if ( abs(Rion(1,a)) > Xmax ) Xmax=abs(Rion(1,a))
      if ( abs(Rion(2,a)) > Ymax ) Ymax=abs(Rion(2,a))
      if ( abs(Rion(3,a)) > Zmax ) Zmax=abs(Rion(3,a))
    end do
    
    Xmax=Xmax+1.d0/a_B ; Ymax=Ymax+1.d0/a_B ; Zmax=Zmax+1.d0/a_B
    
    iseed=123
    do is=1,system%nspin
    do io=1,system%no
      call quickrnd_ns ; x1=Xmax*(2.d0*rnd-1.d0)
      call quickrnd_ns ; y1=Ymax*(2.d0*rnd-1.d0)
      call quickrnd_ns ; z1=Zmax*(2.d0*rnd-1.d0)
      if(info%io_s <= io .and. io <= info%io_e) then
!$OMP parallel do collapse(2) private(iz,iy,ix,xx,yy,zz,rr)
        do iz=mg%is(3),mg%ie(3)
        do iy=mg%is(2),mg%ie(2)
        do ix=mg%is(1),mg%ie(1)
          xx=lg%coordinate(ix,1) ; yy=lg%coordinate(iy,2) ; zz=lg%coordinate(iz,3)
          rr=sqrt((xx-x1)**2+(yy-y1)**2+(zz-z1)**2)
          spsi%rwf(ix,iy,iz,is,io,1,1) = exp(-0.5d0*(rr*a_B)**2)*(a_B)**(3/2)
        end do
        end do
        end do
      end if
    end do
    end do
    
  case('y')
  
    Xmax = sqrt(sum(system%primitive_a(1:3,1)**2))
    Ymax = sqrt(sum(system%primitive_a(1:3,2)**2))
    Zmax = sqrt(sum(system%primitive_a(1:3,3)**2))

    iseed=123
    do is=1,system%nspin
    do ik=1,system%nk
    do io=1,system%no
      call quickrnd_ns ; x1=Xmax*rnd
      call quickrnd_ns ; y1=Ymax*rnd
      call quickrnd_ns ; z1=Zmax*rnd
      if(info%ik_s <= ik .and. ik <= info%ik_e .and.   &
         info%io_s <= io .and. io <= info%io_e) then
!$OMP parallel do collapse(2) private(iz,iy,ix,xx,yy,zz,rr)
        do iz=mg%is(3),mg%ie(3)
        do iy=mg%is(2),mg%ie(2)
        do ix=mg%is(1),mg%ie(1)
          xx=lg%coordinate(ix,1) ; yy=lg%coordinate(iy,2) ; zz=lg%coordinate(iz,3)
          rr=sqrt((xx-x1)**2+(yy-y1)**2+(zz-z1)**2)
          spsi%zwf(ix,iy,iz,is,io,ik,1) = exp(-0.5d0*rr**2)
        end do
        end do
        end do
      end if
    end do
    end do
    end do
    
  end select
  
  call gram_schmidt(system, mg, info, spsi)
    
  return

CONTAINS

  subroutine quickrnd_ns
  implicit none
  integer,parameter :: im=6075,ia=106,ic=1283
  iseed=mod(iseed*ia+ic,im) ; rnd=real(iseed,8)/real(im,8)
  end subroutine quickrnd_ns

END SUBROUTINE init_wf

end module init_gs
