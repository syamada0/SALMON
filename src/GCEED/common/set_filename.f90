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
subroutine set_filename
  use salmon_global
  use salmon_parallel, only: nproc_id_global
  use inputoutput
  use scf_data
  implicit none
  
 !file_gs_info=trim(sysname)//"_info.data"
  file_eigen=trim(sysname)//"_eigen.data"

  file_in_rt_bin =trim(directory_read_data)//trim(sysname)//"_rt.bin"
  file_out_rt_bin=trim(sysname)//"_rt.bin"

  file_RT_q=trim(sysname)//"_q.data"
  file_alpha_q=trim(sysname)//"_q_ps.data"
  file_RT_e=trim(sysname)//"_q_e.data"
  file_RT_dip2=trim(sysname)//"_dip2.data"
  file_alpha_dip2=trim(sysname)//"_dip2_ps.data"
  file_RT_dip2_q=trim(sysname)//"_dip2_q.data"
  file_alpha_dip2_q=trim(sysname)//"_dip2_q_ps.data"
  file_RT_dip2_e=trim(sysname)//"_dip2_q_e.data"
  file_external=trim(sysname)//"_ext.data"
  file_Projection=trim(sysname)//"_proj.data"
  
 !file_ini=trim(sysname)//"_ini.data" !removed

  return

end subroutine set_filename

