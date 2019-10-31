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
module nondiagonal_so_sub

  implicit none

  private
  public :: nondiagonal_so

contains

  subroutine nondiagonal_so( tpsi, htpsi, info, nspin, ppg )
    use structures
    implicit none
    integer,intent(in) :: nspin
    type(s_orbital_parallel),intent(in) :: info
    type(s_pp_grid),intent(in) :: ppg
    type(s_orbital),intent(in) :: tpsi
    type(s_orbital) :: htpsi
write(*,*) "-------------- nondiagonal_so"
    return
  end subroutine nondiagonal_so

end module nondiagonal_so_sub