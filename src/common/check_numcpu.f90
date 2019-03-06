!
!  Copyright 2017 SALMON developers
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
module check_numcpu_sub
  implicit none

contains

subroutine check_numcpu(nproc_mxin,nproc_mxin_s,nproc_mxin_s_dm)
  use inputoutput, only: nproc_k,nproc_ob
  use salmon_parallel, only: nproc_size_global
  implicit none
  integer,intent(in) :: nproc_mxin(3)
  integer,intent(in) :: nproc_mxin_s(3)
  integer,intent(out) :: nproc_mxin_s_dm(3)
  integer :: j
  
  if(nproc_k*nproc_ob*nproc_mxin(1)*nproc_mxin(2)*nproc_mxin(3)/=nproc_size_global)then
    write(*,*) "inumcpu_check error!"
    write(*,*) "number of cpu is not correct!"
    stop
  end if
  do j=1,3
    if(nproc_mxin_s(j)<nproc_mxin(j))then
      write(*,*) "inumcpu_check error!"
      write(*,*) "nproc_domain_s is smaller than nproc_domain."
      stop
    end if
  end do
  if(nproc_mxin_s(1)*nproc_mxin_s(2)*nproc_mxin_s(3)>nproc_size_global)then
    write(*,*) "inumcpu_check error!"
    write(*,*) "product of nproc_domain_s is larger than nproc."
    stop
  end if
  if(mod(nproc_mxin_s(1),nproc_mxin(1))/=0)then
    write(*,*) "inumcpu_check error!"
    write(*,*) "nproc_domain_s(1) is not mutiple of nproc_domain(1)."
    stop
  end if
  if(mod(nproc_mxin_s(2),nproc_mxin(2))/=0)then
    write(*,*) "inumcpu_check error!"
    write(*,*) "nproc_domain_s(2) is not mutiple of nproc_domain(2)."
    stop
  end if
  if(mod(nproc_mxin_s(3),nproc_mxin(3))/=0)then
    write(*,*) "inumcpu_check error!"
    write(*,*) "nproc_domain_s(3) is not mutiple of nproc_domain(3)."
    stop
  end if
  nproc_mxin_s_dm(1:3)=nproc_mxin_s(1:3)/nproc_mxin(1:3)
  
end subroutine check_numcpu

end module check_numcpu_sub
