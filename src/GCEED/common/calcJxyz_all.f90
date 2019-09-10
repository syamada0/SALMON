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
subroutine calcJxyz_all(lg)
use structures,           only: s_rgrid
use salmon_communication, only: comm_is_root, comm_summation
use prep_pp_sub, only: calc_nps,init_jxyz,calc_jxyz
use scf_data
implicit none
  type(s_rgrid),intent(in) :: lg
  integer :: ix,iy,iz
  integer :: i
  integer :: mmx(mg_num(1)*mg_num(2)*mg_num(3))
  integer :: mmy(mg_num(1)*mg_num(2)*mg_num(3))
  integer :: mmz(mg_num(1)*mg_num(2)*mg_num(3))
  integer :: lx(lg%num(1)*lg%num(2)*lg%num(3))
  integer :: ly(lg%num(1)*lg%num(2)*lg%num(3))
  integer :: lz(lg%num(1)*lg%num(2)*lg%num(3))
  real(8) :: alx,aly,alz
  real(8) :: hx,hy,hz

  hx=Hgs(1) 
  hy=Hgs(2) 
  hz=Hgs(3)
  alx=Hgs(1)*dble(lg%num(1))
  aly=Hgs(2)*dble(lg%num(2))
  alz=Hgs(3)*dble(lg%num(3))

  do iz=mg_sta(3),mg_end(3)
  do iy=mg_sta(2),mg_end(2)
  do ix=mg_sta(1),mg_end(1)
    i=(iz-mg_sta(3))*mg_num(1)*mg_num(2)+(iy-mg_sta(2))*mg_num(1)+ix-mg_sta(1)+1
    mmx(i)=ix
    mmy(i)=iy
    mmz(i)=iz
  end do
  end do
  end do
 
  do iz=lg%is(3),lg%ie(3)
  do iy=lg%is(2),lg%ie(2)
  do ix=lg%is(1),lg%ie(1)
    i=(iz-lg%is(3))*lg%num(1)*lg%num(2)+(iy-lg%is(2))*lg%num(1)+ix-lg%is(1)+1
    lx(i)=ix
    ly(i)=iy
    lz(i)=iz
  end do
  end do
  end do
 
  call calc_nps(pp,ppg,alx,aly,alz,lx,ly,lz,lg%num(1)*lg%num(2)*lg%num(3),   &
                                   mmx,mmy,mmz,mg_num(1)*mg_num(2)*mg_num(3),   &
                                   hx,hy,hz)
  call calc_nps(pp,ppg_all,alx,aly,alz,lx,ly,lz,lg%num(1)*lg%num(2)*lg%num(3),   &
                                       lx,ly,lz,lg%num(1)*lg%num(2)*lg%num(3),   &
                                       hx,hy,hz)

  call init_jxyz(ppg)
  call init_jxyz(ppg_all)

  call calc_jxyz(pp,ppg,alx,aly,alz,lx,ly,lz,lg%num(1)*lg%num(2)*lg%num(3),   &
                                    mmx,mmy,mmz,mg_num(1)*mg_num(2)*mg_num(3),   &
                                    hx,hy,hz)
  call calc_jxyz(pp,ppg_all,alx,aly,alz,lx,ly,lz,lg%num(1)*lg%num(2)*lg%num(3),   &
                                    lx,ly,lz,lg%num(1)*lg%num(2)*lg%num(3),   &
                                    hx,hy,hz)
  
return

end subroutine calcJxyz_all
