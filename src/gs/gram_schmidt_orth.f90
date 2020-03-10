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
!=======================================================================
module gram_schmidt_orth
  use structures, only: s_dft_system, s_rgrid, s_orbital_parallel, s_orbital, s_process_info
  use pack_unpack, only: copy_data
  use gram_schmidt_so_sub, only: gram_schmidt_so, SPIN_ORBIT_ON
  implicit none

contains

  subroutine gram_schmidt(sys, rg, wfi, wf, pinfo)
    use salmon_global, only: yn_gbp
    use timer
    implicit none
    type(s_dft_system),       intent(in)    :: sys
    type(s_rgrid),        intent(in)    :: rg
    type(s_orbital_parallel),      intent(in)    :: wfi
    type(s_orbital), intent(inout) :: wf
    type(s_process_info) :: pinfo

    if ( SPIN_ORBIT_ON ) then
      call gram_schmidt_so(sys, rg, wfi, wf)
      return
    end if

    call timer_begin(LOG_CALC_GRAM_SCHMIDT)

    !if (if_divide_rspace) then:
    if(yn_gbp=='y') then
      call gbp_gram_schmidt_col_complex8(sys, rg, wfi, wf)
    elseif(yn_gbp=='c') then
      call gram_schmidt_col_complex8_cblas(sys, rg, wfi, wf, pinfo)
    elseif(yn_gbp=='r') then
      call gram_schmidt_col_rblas(sys, rg, wfi, wf, pinfo)
    elseif (allocated(wf%rwf)) then
      call gram_schmidt_col_real8(sys, rg, wfi, wf)
    elseif (allocated(wf%zwf)) then
      call gram_schmidt_col_complex8_org(sys, rg, wfi, wf)
    else
      stop "Wavefunctions are not allocated!"
    end if

    call timer_end(LOG_CALC_GRAM_SCHMIDT)

    return
  end subroutine

  subroutine gram_schmidt_col_real8(sys, rg, wfi, wf)
    ! Only for the colinear L(S)DA:
    use timer
    use communication, only: comm_bcast, comm_summation
    implicit none
    type(s_dft_system),       intent(in)    :: sys
    type(s_rgrid),        intent(in)    :: rg
    type(s_orbital_parallel),      intent(in)    :: wfi
    type(s_orbital), intent(inout) :: wf

    integer :: nsize_rg
    integer :: ik, im, ispin
    integer :: io1, io2
    real(8) :: coeff(1:sys%no), coeff_tmp(1:sys%no)
    real(8) :: norm2, norm2_tmp
    real(8), dimension( &
      & rg%is_array(1):rg%ie_array(1), &
      & rg%is_array(2):rg%ie_array(2), &
      & rg%is_array(3):rg%ie_array(3)) &
      & :: wf_io1, wf_exc, wf_exc_tmp

    nsize_rg =  (rg%ie_array(1) - rg%is_array(1) + 1) &
      & * (rg%ie_array(2) - rg%is_array(2) + 1) &
      & * (rg%ie_array(3) - rg%is_array(3) + 1)

    do im = wfi%im_s, wfi%im_e
    do ik = wfi%ik_s, wfi%ik_e
    do ispin = 1, sys%nspin

      ! Loop for all orbit #io1:
      do io1 = 1, sys%no

        ! Retrieve orbit #io1 into "wf_io1":
        if (wfi%io_s<= io1 .and. io1 <= wfi%io_e) then
          call copy_data( &
            & wf%rwf(:, :, :, ispin, io1, ik, im), &
            & wf_io1)
        end if
        if (wfi%if_divide_orbit) &
          & call comm_bcast(wf_io1, wfi%icomm_o, wfi%irank_io(io1))

        ! Calculate overlap coefficients:
        coeff_tmp = 0d0
        do io2 = 1, io1 - 1
          if (wfi%io_s<= io2 .and. io2 <= wfi%io_e) then
            coeff_tmp(io2) = dot_wf( &
              & wf%rwf(:, :, :, ispin, io2, ik, im), &
              & wf_io1)
          end if
        end do
        if (wfi%if_divide_rspace .or. wfi%if_divide_orbit) then
          call comm_summation(coeff_tmp, coeff, sys%no, wfi%icomm_ro)
        else
          coeff = coeff_tmp
        endif

        ! Calculate exclusion term "wf_exc":
        wf_exc_tmp = 0d0
        do io2 = 1, io1 - 1
          if (wfi%io_s<= io2 .and. io2 <= wfi%io_e) then
            call axpy_wf( &
              & coeff(io2), wf%rwf(:, :, :, ispin, io2, ik, im), &
              & wf_exc_tmp)
          end if
        end do
        if (wfi%if_divide_orbit) then
          call comm_summation(wf_exc_tmp, wf_exc, nsize_rg, wfi%icomm_o)
        else
          call copy_data(wf_exc_tmp, wf_exc)
        end if

        if (wfi%io_s<= io1 .and. io1 <= wfi%io_e) then
          ! Exclude non-orthonormal component:
          call axpy_wf(-1d0, wf_exc, wf_io1)
          ! Normalization:
          norm2_tmp = dot_wf(wf_io1, wf_io1)
          if (wfi%if_divide_rspace) then
            call comm_summation(norm2_tmp, norm2, wfi%icomm_r)
          else
            norm2 = norm2_tmp
          endif
          call scal_wf(1d0 / sqrt(norm2), wf_io1)
          ! Write back to "rwf":
          call copy_data( &
            & wf_io1, &
            & wf%rwf(:, :, :, ispin, io1, ik, im))
        end if
      end do !io1

    end do !ispin
    end do !ik
    end do !im

    return
  contains

  ! Dot product of two wavefunctions:
  real(8) function dot_wf(x, y) result(p)
    implicit none
    real(8), intent(in) :: x( &
      & rg%is_array(1):rg%ie_array(1), &
      & rg%is_array(2):rg%ie_array(2), &
      & rg%is_array(3):rg%ie_array(3))
    real(8), intent(in) :: y( &
      & rg%is_array(1):rg%ie_array(1), &
      & rg%is_array(2):rg%ie_array(2), &
      & rg%is_array(3):rg%ie_array(3))
    integer :: i1, i2, i3
    p = 0d0
    !$omp parallel do collapse(2) default(shared) private(i1,i2,i3) reduction(+:p)
    do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
        do i1 = rg%is(1), rg%ie(1)
          p = p + x(i1, i2, i3) * y(i1, i2, i3)
        end do
      end do
    end do
    !$omp end parallel do
    p = p * sys%hvol
    return
  end function dot_wf

  ! Constant times a wavefunction plus a wavefunction:
  subroutine axpy_wf(a, x, y)
    implicit none
    real(8), intent(in) :: a
    real(8), intent(in) :: x( &
      & rg%is_array(1):rg%ie_array(1), &
      & rg%is_array(2):rg%ie_array(2), &
      & rg%is_array(3):rg%ie_array(3))
    real(8), intent(inout) :: y( &
      & rg%is_array(1):rg%ie_array(1), &
      & rg%is_array(2):rg%ie_array(2), &
      & rg%is_array(3):rg%ie_array(3))
    integer :: i1, i2, i3
    !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
    do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
        do i1 = rg%is(1), rg%ie(1)
          y(i1, i2, i3) = a * x(i1, i2, i3) + y(i1, i2, i3)
        end do
      end do
    end do
    !$omp end parallel do
    return
  end subroutine axpy_wf


  ! Scales a wavefunction by a constant
  subroutine scal_wf(a, x)
    implicit none
    real(8), intent(in) :: a
    real(8), intent(inout) :: x( &
      & rg%is_array(1):rg%ie_array(1), &
      & rg%is_array(2):rg%ie_array(2), &
      & rg%is_array(3):rg%ie_array(3))
    integer :: i1, i2, i3
    !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
    do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
        do i1 = rg%is(1), rg%ie(1)
          x(i1, i2, i3) = a * x(i1, i2, i3)
        end do
      end do
    end do
    !$omp end parallel do
    return
  end subroutine scal_wf

  end subroutine gram_schmidt_col_real8


!=======================================================================



  subroutine gram_schmidt_col_complex8_cblas(sys, rg, wfi, wf, pinfo)
    ! Only for the colinear L(S)DA:
    use timer
    use communication, only: comm_bcast, comm_summation
    implicit none
    type(s_dft_system),       intent(in)    :: sys
    type(s_rgrid),        intent(in)    :: rg
    type(s_orbital_parallel),      intent(in)    :: wfi
    type(s_orbital), intent(inout) :: wf
    type(s_process_info) :: pinfo

    complex(8), parameter :: zero = 0d0
    complex(8), parameter :: one = 1d0
    integer, parameter :: n_one = 1
    character(1),parameter :: TRANSA='C', TRANSB='N'

    integer :: nsize_rg
    integer :: ik, im, ispin, m
    integer :: io, jo, jo1, jo2
    complex(8) :: coeff(wfi%numo), coeff_tmp(wfi%numo)
    real(8) :: norm2, norm2_tmp
    complex(8) :: wf_block(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), wfi%numo)
    complex(8) :: wf_block_send(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), wfi%numo_max)
    complex(8) :: umat(wfi%numo_max,wfi%numo), umat_tmp(wfi%numo_max,wfi%numo)
    complex(8) :: ZDOTC

    nsize_rg = (rg%ie(1)-rg%is(1)+1)*(rg%ie(2)-rg%is(2)+1)*(rg%ie(3)-rg%is(3)+1)

    do im = wfi%im_s, wfi%im_e
    do ik = wfi%ik_s, wfi%ik_e
    do ispin = 1, sys%nspin

      ! Copy wave function
      do io = wfi%io_s, wfi%io_e
        jo = io - wfi%io_s + 1
        call copy_data( &
          & wf%zwf(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), ispin, io, ik, im), &
          & wf_block(:, :, :, jo))
      end do

      ! Loop for all:
      do m = 0, pinfo%nporbital-1
        if(wfi%id_o==m)then
        ! Loop for orbit #io1 in my rank:
          do jo1 = 1, wfi%numo

            ! normalize orbital jo1
            norm2_tmp = real( ZDOTC( &
             &      nsize_rg, wf_block(:,:,:,jo1), n_one, &
             &                wf_block(:,:,:,jo1), n_one )) &
             &     * sys%hvol
            if (wfi%if_divide_rspace) then
              call comm_summation(norm2_tmp, norm2, wfi%icomm_r)
            else
              norm2 = norm2_tmp
            endif
            call ZDSCAL(nsize_rg, one/sqrt(norm2), wf_block(:,:,:,jo1), n_one)

            ! Calculate overlap coefficients:
            coeff_tmp = 0d0
            do jo2 = jo1+1, wfi%numo
              coeff_tmp(jo2) = real( ZDOTC( &
               &      nsize_rg, wf_block(:,:,:,jo1), n_one, &
               &                wf_block(:,:,:,jo2), n_one )) &
               &     * sys%hvol
            end do
            if (wfi%if_divide_rspace) then
              call comm_summation(coeff_tmp, coeff, wfi%numo, wfi%icomm_r)
            else
              coeff = coeff_tmp
            endif

            ! Exclude non-orthonormal component:
            do jo2 = jo1+1, wfi%numo
              call ZAXPY( &
                &  nsize_rg, - coeff(jo2), wf_block(:,:,:,jo1), n_one, &
                &                          wf_block(:,:,:,jo2), n_one)
            end do

          end do !jo1

        end if !m==wfi%id_o

        if (wfi%if_divide_orbit) then
          call copy_data( wf_block(:,:,:,:), wf_block_send(:,:,:,1:wfi%numo) )
          wf_block_send(:,:,:,wfi%numo+1:wfi%numo_max) = 0d0
          call comm_bcast( wf_block_send, wfi%icomm_o, wfi%irank_io(wfi%io_s_all(m)))

          umat_tmp=0.d0
          if( wfi%id_o > m )then
            call zgemm(TRANSA, TRANSB, wfi%numo_max, wfi%numo, nsize_rg,  &
              &   dcmplx(sys%hvol), wf_block_send(:,:,:,1), nsize_rg,  &
              &                wf_block(:,:,:,1), nsize_rg,  &
              &          zero, umat_tmp, wfi%numo_max )

            call comm_summation(umat_tmp, umat, wfi%numo_max*wfi%numo, wfi%icomm_r)

            call zgemm(TRANSB, TRANSB, nsize_rg, wfi%numo, wfi%numo_max,  &
              &         - one, wf_block_send(:,:,:,1), nsize_rg,  &
              &                umat, wfi%numo_max,  &
              &           one, wf_block(:,:,:,1), nsize_rg)
          end if
        end if ! wfi%if_divide_orbit

      end do !m

      do io = wfi%io_s, wfi%io_e
        jo = io - wfi%io_s + 1
        call copy_data( &
          & wf_block(:, :, :, jo), &
          & wf%zwf(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), ispin, io, ik, im))
      end do

    end do !ispin
    end do !ik
    end do !im

    return

  end subroutine gram_schmidt_col_complex8_cblas

  !=======================================================================


    subroutine gram_schmidt_col_rblas(sys, rg, wfi, wf, pinfo)
      ! Only for the colinear L(S)DA:
      use timer
      use communication, only: comm_bcast, comm_summation
      implicit none
      type(s_dft_system),       intent(in)    :: sys
      type(s_rgrid),        intent(in)    :: rg
      type(s_orbital_parallel),      intent(in)    :: wfi
      type(s_orbital), intent(inout) :: wf
      type(s_process_info) :: pinfo

      real(8), parameter :: zero = 0d0
      real(8), parameter :: one = 1d0
      integer, parameter :: n_one = 1
      character(1),parameter :: TRANSA='T', TRANSB='N'

      integer :: nsize_rg
      integer :: ik, im, ispin, m
      integer :: io, jo, jo1, jo2
      real(8) :: coeff(wfi%numo), coeff_tmp(wfi%numo)
      real(8) :: norm2, norm2_tmp
      real(8) :: wf_block(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), wfi%numo)
      real(8) :: wf_block_send(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), wfi%numo_max)
      real(8) :: umat(wfi%numo_max,wfi%numo), umat_tmp(wfi%numo_max,wfi%numo)
      real(8) :: DDOT

      nsize_rg = (rg%ie(1)-rg%is(1)+1)*(rg%ie(2)-rg%is(2)+1)*(rg%ie(3)-rg%is(3)+1)

      do im = wfi%im_s, wfi%im_e
      do ik = wfi%ik_s, wfi%ik_e
      do ispin = 1, sys%nspin

        ! Copy wave function
        do io = wfi%io_s, wfi%io_e
          jo = io - wfi%io_s + 1
          call copy_data( &
            &  wf%rwf(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), ispin, io, ik, im) , &
            & wf_block(:, :, :, jo))
        end do

        ! Loop for all:
        do m = 0, pinfo%nporbital-1
          if(wfi%id_o==m)then
          ! Loop for orbit #jo1 in my rank:
            do jo1 = 1, wfi%numo

              ! normaliza the orbital jo1
              norm2_tmp = DDOT( &
               &      nsize_rg, wf_block(:,:,:,jo1), n_one, &
               &                wf_block(:,:,:,jo1), n_one ) &
               &     * sys%hvol
              if (wfi%if_divide_rspace) then
                call comm_summation(norm2_tmp, norm2, wfi%icomm_r)
              else
                norm2 = norm2_tmp
              endif
              call DSCAL(nsize_rg, one/sqrt(norm2), wf_block(:,:,:,jo1), n_one)

              ! Calculate overlap coefficients:
              coeff_tmp = 0d0
              do jo2 = jo1+1, wfi%numo
                coeff_tmp(jo2) = DDOT( &
                 &      nsize_rg, wf_block(:,:,:,jo1), n_one, &
                 &                wf_block(:,:,:,jo2), n_one ) &
                 &     * sys%hvol
              end do
              if (wfi%if_divide_rspace) then
                call comm_summation(coeff_tmp, coeff, wfi%numo, wfi%icomm_r)
              else
                coeff = coeff_tmp
              endif

              ! Exclude non-orthonormal component:              !$omp parallel do private(jo2)
              do jo2 = jo1+1, wfi%numo
                call DAXPY( &
                  &  nsize_rg, - coeff(jo2), wf_block(:,:,:,jo1), n_one, &
                  &                          wf_block(:,:,:,jo2), n_one)
              end do

            end do !jo1

          end if !m==wfi%id_o

          if (wfi%if_divide_orbit) then
            call copy_data( wf_block(:,:,:,:), wf_block_send(:,:,:,1:wfi%numo) )
            wf_block_send(:,:,:,wfi%numo+1:wfi%numo_max) = 0d0
            call comm_bcast( wf_block_send, wfi%icomm_o, wfi%irank_io(wfi%io_s_all(m)))

            umat_tmp=0.d0
            if( wfi%id_o > m )then
              call dgemm(TRANSA, TRANSB, wfi%numo_max, wfi%numo, nsize_rg,  &
                &      sys%hvol, wf_block_send(:,:,:,1), nsize_rg,  &
                &                wf_block(:,:,:,1), nsize_rg,  &
                &          zero, umat_tmp, wfi%numo_max )

              call comm_summation(umat_tmp, umat, wfi%numo_max*wfi%numo, wfi%icomm_r)

              call dgemm(TRANSB, TRANSB, nsize_rg, wfi%numo, wfi%numo_max,  &
                &         - one, wf_block_send(:,:,:,1), nsize_rg,  &
                &                umat, wfi%numo_max,  &
                &           one, wf_block(:,:,:,1), nsize_rg)
            end if
          end if ! wfi%if_divide_orbit

        end do !m

        do io = wfi%io_s, wfi%io_e
          jo = io - wfi%io_s + 1
          call copy_data( &
            & wf_block(:, :, :, jo), &
            & wf%rwf(rg%is(1):rg%ie(1), rg%is(2):rg%ie(2), rg%is(3):rg%ie(3), ispin, io, ik, im))
        end do

      end do !ispin
      end do !ik
      end do !im

      return

    end subroutine gram_schmidt_col_rblas

    !=======================================================================



    subroutine gram_schmidt_col_complex8_org(sys, rg, wfi, wf)
      ! Only for the colinear L(S)DA:
      use timer
      use communication, only: comm_bcast, comm_summation
      implicit none
      type(s_dft_system),       intent(in)    :: sys
      type(s_rgrid),        intent(in)    :: rg
      type(s_orbital_parallel),      intent(in)    :: wfi
      type(s_orbital), intent(inout) :: wf

      integer :: nsize_rg
      integer :: ik, im, ispin
      integer :: io1, io2
      complex(8) :: coeff(1:sys%no), coeff_tmp(1:sys%no)
      real(8) :: norm2, norm2_tmp
      complex(8), dimension( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3)) &
        & :: wf_io1, wf_exc, wf_exc_tmp

      complex(8), parameter :: one = 1d0

      nsize_rg =  (rg%ie_array(1) - rg%is_array(1) + 1) &
        & * (rg%ie_array(2) - rg%is_array(2) + 1) &
        & * (rg%ie_array(3) - rg%is_array(3) + 1)

      do im = wfi%im_s, wfi%im_e
      do ik = wfi%ik_s, wfi%ik_e
      do ispin = 1, sys%nspin

        ! Loop for all orbit #io1:
        do io1 = 1, sys%no

          ! Retrieve orbit #io1 into "wf_io1":
          if (wfi%io_s<= io1 .and. io1 <= wfi%io_e) then
            call copy_data( &
              & wf%zwf(:, :, :, ispin, io1, ik, im), &
              & wf_io1)
          end if
          if (wfi%if_divide_orbit) &
            & call comm_bcast(wf_io1, wfi%icomm_o, wfi%irank_io(io1))

          ! Calculate overlap coefficients:
          coeff_tmp = 0d0
          do io2 = 1, io1 - 1
            if (wfi%io_s<= io2 .and. io2 <= wfi%io_e) then
              coeff_tmp(io2) = dot_wf( &
                & wf%zwf(:, :, :, ispin, io2, ik, im), &
                & wf_io1)
            end if
          end do
          if (wfi%if_divide_rspace .or. wfi%if_divide_orbit) then
            call comm_summation(coeff_tmp, coeff, sys%no, wfi%icomm_ro)
          else
            coeff = coeff_tmp
          endif

          ! Calculate exclusion term "wf_exc":
          wf_exc_tmp = 0d0
          do io2 = 1, io1 - 1
            if (wfi%io_s<= io2 .and. io2 <= wfi%io_e) then
              call axpy_wf( &
                & coeff(io2), wf%zwf(:, :, :, ispin, io2, ik, im), &
                & wf_exc_tmp)
            end if
          end do
          if (wfi%if_divide_orbit) then
            call comm_summation(wf_exc_tmp, wf_exc, nsize_rg, wfi%icomm_o)
          else
            call copy_data(wf_exc_tmp, wf_exc)
          endif

          if (wfi%io_s<= io1 .and. io1 <= wfi%io_e) then
            ! Exclude non-orthonormal component:
            call axpy_wf(-one, wf_exc, wf_io1)
            ! Normalization:
            norm2_tmp = real(dot_wf(wf_io1, wf_io1))
            if (wfi%if_divide_rspace) then
              call comm_summation(norm2_tmp, norm2, wfi%icomm_r)
            else
              norm2 = norm2_tmp
            endif
            call scal_wf(one / sqrt(norm2), wf_io1)
            ! Write back to "zwf":
            call copy_data( &
              & wf_io1, &
              & wf%zwf(:, :, :, ispin, io1, ik, im))
          end if
        end do !io1

      end do !ispin
      end do !ik
      end do !im

      return
    contains

    ! Dot product of two wavefunctions:
    complex(8) function dot_wf(x, y) result(p)
      implicit none
      complex(8), intent(in) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      complex(8), intent(in) :: y( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3
      p = 0d0
      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3) reduction(+:p)
      do i3 = rg%is(3), rg%ie(3)
        do i2 = rg%is(2), rg%ie(2)
          do i1 = rg%is(1), rg%ie(1)
            p = p + conjg(x(i1, i2, i3)) * y(i1, i2, i3)
          end do
        end do
      end do
      !$omp end parallel do
      p = p * sys%hvol
      return
    end function dot_wf

    ! Constant times a wavefunction plus a wavefunction:
    subroutine axpy_wf(a, x, y)
      implicit none
      complex(8), intent(in) :: a
      complex(8), intent(in) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      complex(8), intent(inout) :: y( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3
      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
      do i3 = rg%is(3), rg%ie(3)
        do i2 = rg%is(2), rg%ie(2)
          do i1 = rg%is(1), rg%ie(1)
            y(i1, i2, i3) = a * x(i1, i2, i3) + y(i1, i2, i3)
          end do
        end do
      end do
      !$omp end parallel do
      return
    end subroutine axpy_wf


    ! Scales a wavefunction by a constant
    subroutine scal_wf(a, x)
      implicit none
      complex(8), intent(in) :: a
      complex(8), intent(inout) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3
      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
      do i3 = rg%is(3), rg%ie(3)
        do i2 = rg%is(2), rg%ie(2)
          do i1 = rg%is(1), rg%ie(1)
            x(i1, i2, i3) = a * x(i1, i2, i3)
          end do
        end do
      end do
      !$omp end parallel do
      return
    end subroutine scal_wf

  end subroutine gram_schmidt_col_complex8_org

  !=======================================================================

    subroutine gbp_gram_schmidt_col_complex8(sys, rg, wfi, wf)
      ! Only for the colinear L(S)DA:
      use timer
      use communication, only: comm_bcast, comm_summation
      implicit none
      type(s_dft_system),       intent(in)    :: sys
      type(s_rgrid),            intent(in)    :: rg
      type(s_orbital_parallel), intent(in)    :: wfi
      type(s_orbital),          intent(inout) :: wf

      integer :: nsize_rg
      integer :: ik, im, ispin
      integer :: io1, io2
      real(8) :: coeff(1:sys%no), coeff_tmp(1:sys%no)
      real(8) :: norm2, norm2_tmp
      real(8), dimension( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3)) &
        & :: wf_io1, wf_exc, wf_exc_tmp

      real(8), parameter :: one = 1d0

      nsize_rg =  (rg%ie_array(1) - rg%is_array(1) + 1) &
              & * (rg%ie_array(2) - rg%is_array(2) + 1) &
              & * (rg%ie_array(3) - rg%is_array(3) + 1)

      do im = wfi%im_s, wfi%im_e
      do ik = wfi%ik_s, wfi%ik_e
      do ispin = 1, sys%nspin

        ! Loop for all orbit #io1:
        do io1 = 1, sys%no

          ! Retrieve orbit #io1 into "wf_io1":
          if (wfi%io_s<= io1 .and. io1 <= wfi%io_e) then
            call copy_data_3d_complex8_real8( &
              & wf%zwf(:, :, :, ispin, io1, ik, im), &
              & wf_io1)
          end if
          if (wfi%if_divide_orbit) &
            & call comm_bcast(wf_io1, wfi%icomm_o, wfi%irank_io(io1))

          ! Calculate overlap coefficients:
          coeff_tmp = 0d0
          do io2 = 1, io1 - 1
            if (wfi%io_s<= io2 .and. io2 <= wfi%io_e) then
              coeff_tmp(io2) = dot_wf_complex8_real8( &
                & wf%zwf(:, :, :, ispin, io2, ik, im), &
                & wf_io1)
            end if
          end do
          if (wfi%if_divide_rspace .or. wfi%if_divide_orbit) then
            call comm_summation(coeff_tmp, coeff, sys%no, wfi%icomm_ro)
          else
            coeff = coeff_tmp
          endif

          ! Calculate exclusion term "wf_exc":
          wf_exc_tmp = 0d0
          do io2 = 1, io1 - 1
            if (wfi%io_s<= io2 .and. io2 <= wfi%io_e) then
              call axpy_wf_real8_complex8( &
                & coeff(io2), wf%zwf(:, :, :, ispin, io2, ik, im), &
                & wf_exc_tmp)
            end if
          end do
          if (wfi%if_divide_orbit) then
            call comm_summation(wf_exc_tmp, wf_exc, nsize_rg, wfi%icomm_o)
          else
            call copy_data(wf_exc_tmp, wf_exc)  ! real8 -> real8
          endif

          if (wfi%io_s<= io1 .and. io1 <= wfi%io_e) then
            ! Exclude non-orthonormal component:
            call axpy_wf_real8_real8(-one, wf_exc, wf_io1)
            ! Normalization:
            norm2_tmp = dot_wf_real8_real8(wf_io1, wf_io1)
            if (wfi%if_divide_rspace) then
              call comm_summation(norm2_tmp, norm2, wfi%icomm_r)
            else
              norm2 = norm2_tmp
            endif
            call scal_wf_real8(one/sqrt(norm2), wf_io1)
            ! Write back to "zwf":
            call copy_data_3d_real8_complex8( &
              & wf_io1, &
              & wf%zwf(:, :, :, ispin, io1, ik, im))
          end if
        end do !io1

      end do !ispin
      end do !ik
      end do !im

      return
    contains

    subroutine copy_data_3d_complex8_real8(src,dst)
      implicit none
      complex(8), intent(in)  :: src(:,:,:)
      real(8),    intent(out) :: dst(:,:,:)
      integer :: ix,iy,iz
      integer :: nx,ny,nz

      nz = size(src,3)
      ny = size(src,2)
      nx = size(src,1)

!$omp parallel do collapse(2) default(none) &
!$omp          private(ix,iy,iz) &
!$omp          firstprivate(nx,ny,nz) &
!$omp          shared(src,dst)
      do iz=1,nz
      do iy=1,ny
      do ix=1,nx
         dst(ix,iy,iz) = real(src(ix,iy,iz))
      end do
      end do
      end do
!$omp end parallel do
    end subroutine copy_data_3d_complex8_real8

    subroutine copy_data_3d_real8_complex8(src,dst)
      implicit none
      real(8),   intent(in)  :: src(:,:,:)
      complex(8),intent(out) :: dst(:,:,:)
      integer :: ix,iy,iz
      integer :: nx,ny,nz

      nz = size(src,3)
      ny = size(src,2)
      nx = size(src,1)

!$omp parallel do collapse(2) default(none) &
!$omp          private(ix,iy,iz) &
!$omp          firstprivate(nx,ny,nz) &
!$omp          shared(src,dst)
      do iz=1,nz
      do iy=1,ny
      do ix=1,nx
         dst(ix,iy,iz) = src(ix,iy,iz)
      end do
      end do
      end do
!$omp end parallel do
    end subroutine copy_data_3d_real8_complex8


    ! Dot product of two wavefunctions:
    real(8) function dot_wf_complex8_real8(x, y) result(p)
      implicit none
      complex(8), intent(in) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      real(8), intent(in) :: y( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3

      p=0d0
      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3) reduction(+:p)
      do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
      do i1 = rg%is(1), rg%ie(1)
         p = p + real(x(i1, i2, i3))*y(i1, i2, i3)
      end do
      end do
      end do
      !$omp end parallel do
      p = p * sys%hvol
      return
    end function dot_wf_complex8_real8

    real(8) function dot_wf_real8_real8(x, y) result(p)
      implicit none
      real(8), intent(in) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      real(8), intent(in) :: y( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3

      p=0d0
      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3) reduction(+:p)
      do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
      do i1 = rg%is(1), rg%ie(1)
         p = p + x(i1, i2, i3) * y(i1, i2, i3)
      end do
      end do
      end do
      !$omp end parallel do
      p = p * sys%hvol
      return
    end function dot_wf_real8_real8

    ! Constant times a wavefunction plus a wavefunction:
    subroutine axpy_wf_real8_complex8(a, x, y)
      implicit none
      real(8),    intent(in) :: a
      complex(8), intent(in) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      real(8), intent(inout) :: y( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3

      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
      do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
      do i1 = rg%is(1), rg%ie(1)
         y(i1, i2, i3) = a * real(x(i1, i2, i3)) + y(i1, i2, i3)
      end do
      end do
      end do
      !$omp end parallel do
      return
    end subroutine axpy_wf_real8_complex8

    subroutine axpy_wf_real8_real8(a, x, y)
      implicit none
      real(8), intent(in) :: a
      real(8), intent(in) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      real(8), intent(inout) :: y( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3

      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
      do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
      do i1 = rg%is(1), rg%ie(1)
         y(i1, i2, i3) = a * x(i1, i2, i3) + y(i1, i2, i3)
      end do
      end do
      end do
      !$omp end parallel do
      return
    end subroutine axpy_wf_real8_real8


    ! Scales a wavefunction by a constant
    subroutine scal_wf_real8(a, x)
      implicit none
      real(8), intent(in) :: a
      real(8), intent(inout) :: x( &
        & rg%is_array(1):rg%ie_array(1), &
        & rg%is_array(2):rg%ie_array(2), &
        & rg%is_array(3):rg%ie_array(3))
      integer :: i1, i2, i3

      !$omp parallel do collapse(2) default(shared) private(i1,i2,i3)
      do i3 = rg%is(3), rg%ie(3)
      do i2 = rg%is(2), rg%ie(2)
      do i1 = rg%is(1), rg%ie(1)
         x(i1, i2, i3) = a * x(i1, i2, i3)
      end do
      end do
      end do
      !$omp end parallel do
      return
    end subroutine scal_wf_real8

    end subroutine gbp_gram_schmidt_col_complex8




end module gram_schmidt_orth
