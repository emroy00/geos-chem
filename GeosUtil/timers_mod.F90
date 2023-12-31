!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !MODULE: timers_mod.F90
!
! !DESCRIPTION: Module TIMERS\_MOD is used to track and time how long
! specified parts of GEOS-Chem take to run.
!\\
!\\
! !INTERFACE:
!
MODULE Timers_Mod
!
! !USES:
!
  USE Precision_Mod

  IMPLICIT NONE
  PRIVATE
!
! !PUBLIC MEMBER FUNCTIONS:
!
  PUBLIC  :: Timer_Setup          ! Setup timers
  PUBLIC  :: Timer_Add            ! Adds a timer
  PUBLIC  :: Timer_Start          ! Starts a timer ticking
  PUBLIC  :: Timer_End            ! Stops a timer ticking
  PUBLIC  :: Timer_Sum_Loop       ! Sums the timers within a loop
  PUBLIC  :: Timer_Print          ! Prints the specified timer
  PUBLIC  :: Timer_PrintAll       ! Prints all timers
  PUBLIC  :: Timer_StopAll        ! Stops all currently running timers
!
! !PRIVATE MEMBER FUNCTIONS:
!
  PRIVATE :: Timer_Find           ! Finds the specified timer
  PRIVATE :: Timer_PrintNum       ! Prints the timer by number
  PRIVATE :: Timer_PrintHeaders   ! Writes headers for logfile & JSON output
  PRIVATE :: Timer_TheTime        ! Returns the current time in milliseconds
  PRIVATE :: Timer_TimePrint      ! Formats the seconds when printing
  PRIVATE :: Timer_TimePrint_JSON ! Prints the timer to JSON format
!
! !REMARKS:
!  This module helps track valuable timing information.
!
! !REVISION HISTORY:
!  23 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!-----------------------------------------------------------------------------
!BOC
!
! !PRIVATE TYPES:
!
  ! What mode the timers should be in. Defaults to 1.
  ! 1: CPU Time
  ! 2: Real Time
  ! 3: MPI time
  INTEGER                                   :: TimerMode = 1

  ! Current number of timers. Starts at 0.
  INTEGER                                   :: TimerCurrentSize = 0

  ! Maximum Supported Timers. Increasing will increase memory footprint.
  INTEGER, PARAMETER                        :: TimerMaxSize = 35

  ! Number of threads for parallel loops
  INTEGER                                   :: nThreads   = 1
  REAL(f8)                                  :: d_nThreads = 1.0_f8

  ! The definition of the GC_Timer type.
  TYPE GC_Timer
     LOGICAL                                :: ENABLED
     CHARACTER(LEN=30)                      :: TIMER_NAME
     REAL(f8)                               :: TOTAL_TIME
     REAL(f8), ALLOCATABLE                  :: TOTAL_TIME_LOOP(:)
     REAL(f8)                               :: START_TIME
     REAL(f8), ALLOCATABLE                  :: START_TIME_LOOP(:)
     REAL(f8)                               :: END_TIME
     REAL(f8), ALLOCATABLE                  :: END_TIME_LOOP(:)
  END TYPE GC_Timer

  ! The array of timers. Determined by TimerMaxSize.
  TYPE(GC_Timer), DIMENSION(TimerMaxSize) :: SavedTimers

CONTAINS
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_Setup
!
! !DESCRIPTION: Set up the Timer for first use.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_Setup( TheMode )
!
! !USES:
!
    USE ErrCode_Mod
!
! !INPUT PARAMETERS:
!
    INTEGER, INTENT(IN)  :: TheMode     ! Timer mode
                                        ! 1:CPU time, 2:Real time, 3:MPI time
!
! !REMARKS:
!  This currently only needs to run if you want to manually set the mode.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    INTEGER            :: RC
#ifdef MODEL_CLASSIC
#ifndef NO_OMP
    INTEGER, EXTERNAL  :: OMP_GET_NUM_THREADS
#endif
#endif

    ! Strings
    CHARACTER(LEN=255) :: WarnMsg, ThisLoc

    !=======================================================================
    ! Timer_Setup begins here
    !=======================================================================

    ! Initialize
    RC      = GC_SUCCESS
    WarnMsg = ''
    ThisLoc = ' -> at Timer_Setup (in module GeosUtil/timers_mod.F90)'

    ! Warning if timer mode is incorrect
    IF ( TheMode .lt. 1 ) THEN
       WarnMsg = 'INVALID TIMER TYPE! '                                   // &
                  'The following timer modes are supported: '             // &
                  '(1) CPU time, (2) Real time, or (3) MPI time.'
       CALL GC_Warning( WarnMsg, RC, ThisLoc )
       RETURN
    ENDIF

    TimerMode = TheMode

#ifdef MODEL_CLASSIC
#ifndef NO_OMP
    ! Determine the number of threads available for parallel loops
    !$OMP PARALLEL
    nThreads   = OMP_GET_NUM_THREADS()
    d_nThreads = DBLE( nThreads )
    !$OMP END PARALLEL
#endif
#endif

    ! Debug
    !PRINT*, "Timer_Setup: Done setting up GEOS-Chem timers"

  END SUBROUTINE Timer_Setup
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_Add
!
! !DESCRIPTION: Adds a new timer to the timer list. Returns status of success.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_Add( TimerName, RC )
!
! !USES:
!
    USE ErrCode_Mod
!
! !INPUT PARAMETERS:
!
    CHARACTER(LEN=*), INTENT(IN)    :: TimerName   ! Name for timer
!
! !INPUT/OUTPUT PARAMETERS:
!
    INTEGER,          INTENT(INOUT) :: RC          ! Success / Failure
!
! !REMARKS:
!  This only fails if the timers are full.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_Add begins here!
    !=======================================================================

    ! Initialize
    RC       = GC_SUCCESS
    ErrMsg   = ''
    ThisLoc  = ' -> at Timer_Add (in module GeosUtil/timers_mod.F90)'

    ! Now we are sure that timers are enabled
    ! We need to check if the timers are full
    IF (TimerCurrentSize < TimerMaxSize) THEN         ! There's room

       ! Increase the timer current size by one
       TimerCurrentSize = TimerCurrentSize + 1

       ! Set the defaults of the new Timer
       SavedTimers(TimerCurrentSize)%ENABLED    = .false.
       SavedTimers(TimerCurrentSize)%TIMER_NAME = TimerName
       SavedTimers(TimerCurrentSize)%TOTAL_TIME = 0.0_f8
       SavedTimers(TimerCurrentSize)%START_TIME = 0.0_f8
       SavedTimers(TimerCurrentSize)%END_TIME   = 0.0_f8

       ! Setup arrays for timers called within parallel loops
       ALLOCATE( SavedTimers(TimerCurrentSize)%START_TIME_LOOP(nThreads), &
                 STAT=RC )
       IF ( RC /= GC_SUCCESS ) RETURN
       SavedTimers(TimerCurrentSize)%START_TIME_LOOP = 0.0_f8

       ALLOCATE( SavedTimers(TimerCurrentSize)%END_TIME_LOOP(nThreads), &
                 STAT=RC )
       IF ( RC /= GC_SUCCESS ) RETURN
       SavedTimers(TimerCurrentSize)%END_TIME_LOOP = 0.0_f8

       ALLOCATE( SavedTimers(TimerCurrentSize)%TOTAL_TIME_LOOP(nThreads), &
                 STAT=RC )
       IF ( RC /= GC_SUCCESS ) RETURN
       SavedTimers(TimerCurrentSize)%TOTAL_TIME_LOOP = 0.0_f8

       ! Debug
       !PRINT*, TimerName, "timer added at slot ", TimerCurrentSize

       ! Success.
       RC = GC_SUCCESS

    ELSE                                             ! There's not room

       ! Exit with error
       PRINT*,"    TimerCurrentSize = ", TimerCurrentSize
       PRINT*,"    TimerMaxSize     = ", TimerMaxSize
       ErrMsg = 'Maximum number of timers is reached!'
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN

    ENDIF

  END SUBROUTINE Timer_Add
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_Start
!
! !DESCRIPTION: Starts a timer ticking.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_Start( TimerName, RC, InLoop, ThreadNum )
!
! !USES:
!
    USE ErrCode_Mod
!
! !INPUT PARAMETERS:
!
    CHARACTER(LEN=*),  INTENT(IN)    :: TimerName   ! Name for timer
    LOGICAL, OPTIONAL, INTENT(IN)    :: InLoop      ! Called within a loop?
    INTEGER, OPTIONAL, INTENT(IN)    :: ThreadNum   ! Current thread number
!
! !INPUT/OUTPUT PARAMETERS:
!
    INTEGER,           INTENT(INOUT) :: RC          ! Success / Failure
!
! !REMARKS:
!  This must be called to start a timer ticking.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    LOGICAL            :: LoopTimer          ! Is this a timer in a DO loop?
    INTEGER            :: TimerLoc           ! Timer number
    REAL(f8)           :: TheTime            ! Returned Time from method

    ! Strings
    CHARACTER(LEN=30)  :: TempTimerName
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_Start begins here!
    !=======================================================================

    ! Initialize
    RC        = GC_SUCCESS
    ErrMsg    = ''
    ThisLoc   = ' -> at Timer_Start (in module GeosUtil/timers_mod.F90)'

    ! Is this timer in a parallel loop?
    LoopTimer = .FALSE.
    IF ( PRESENT(InLoop) ) LoopTimer = .TRUE.

    ! Determine the timer index
    TempTimerName = TimerName
    TimerLoc      = Timer_Find( TempTimerName )

    ! Exit if timer is not found
    IF (TimerLoc .eq. 0) THEN
       ErrMsg = 'Timer not found: ' // TRIM( TimerName )
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN
    ENDIF

    IF ( .not. LoopTimer ) THEN
       ! Now we do some minor error checking
       IF ( SavedTimers(TimerLoc)%ENABLED ) THEN
          ErrMsg = 'Timer already running: ' // TRIM( TimerName )
          CALL GC_Warning( ErrMsg, RC, ThisLoc )
          RETURN
       ENDIF

       ! Timer isn't enabled, it's been found, so we enable it
       SavedTimers(TimerLoc)%ENABLED = .true.
    ENDIF

    ! And we note the current time
    ! 1: CPU Time
    ! 2: Real Time
    ! 3: MPI time
    IF ( TimerMode .eq. 1 ) THEN
       TheTime = Timer_TheTime()
    ENDIF

    IF ( LoopTimer ) THEN
       ! Debug
       !PRINT*, TRIM(TempTimerName), ": Thread=", ThreadNum, ", Start=", TheTime

       ! Get the start time
       SavedTimers(TimerLoc)%START_TIME_LOOP(ThreadNum) = TheTime
    ELSE
       ! Debug
       !PRINT*, TRIM(TempTimerName), ": Start=", TheTime

       ! Get the start time
       SavedTimers(TimerLoc)%START_TIME = TheTime
    ENDIF

  END SUBROUTINE Timer_Start
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_End
!
! !DESCRIPTION: Stops a timer ticking. Adds elapsed time to total.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_End( TimerName, RC, InLoop, ThreadNum )
!
! !USES:
!
    USE ErrCode_Mod
!
! !INPUT PARAMETERS:
!
    CHARACTER(LEN=*),  INTENT(IN)    :: TimerName   ! Name for timer
    LOGICAL, OPTIONAL, INTENT(IN)    :: InLoop      ! Called within a loop?
    INTEGER, OPTIONAL, INTENT(IN)    :: ThreadNum   ! Current thread number
!
! !INPUT/OUTPUT PARAMETERS:
!
    INTEGER,           INTENT(INOUT) :: RC          ! Success / Failure
!
! !REMARKS:
!  Without this routine being called, a timer will not add to its total.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    LOGICAL            :: LoopTimer          ! Is this a timer in a DO loop?
    INTEGER            :: TimerLoc           ! Timer number
    REAL(f8)           :: TheTime            ! Returned Time from method
    REAL(f8)           :: Diff               ! Difference in times

    ! Strings
    CHARACTER(LEN=30)  :: TempTimerName
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_End begins here!
    !=======================================================================

    ! Initialize
    RC       = GC_SUCCESS
    ErrMsg   = ''
    ThisLoc  = ' -> at Timer_End (in module GeosUtil/timers_mod.F90)'

    ! Is this timer in a parallel loop?
    LoopTimer = .FALSE.
    IF ( PRESENT(InLoop) ) LoopTimer = .TRUE.

    ! Determine timer index
    TempTimerName = TimerName
    TimerLoc      = Timer_Find( TempTimerName )

    ! Exit if timer is not found
    IF (TimerLoc .eq. 0) THEN
       ErrMsg = 'Timer not found: ' // TRIM( TimerName )
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN
    ENDIF

    IF ( .not. LoopTimer ) THEN
       ! Now we do some minor error checking
       IF ( .not. SavedTimers(TimerLoc)%ENABLED ) THEN
          ErrMsg = 'Timer is not running: ' // TRIM( TimerName )
          CALL GC_Warning( ErrMsg, RC, ThisLoc )
          RETURN
       ENDIF
    ENDIF

    ! And we note the current time
    ! 1: CPU Time
    ! 2: Real Time
    ! 3: MPI time
    IF ( TimerMode .eq. 1 ) THEN
       TheTime = Timer_TheTime()
    ENDIF

    IF ( LoopTimer ) THEN
       ! Debug
       !PRINT*, TRIM(TempTimerName), ": Thread=", ThreadNum, ", End  =", TheTime

       ! Get the end time
       SavedTimers(TimerLoc)%END_TIME_LOOP(ThreadNum) = TheTime

       ! Get the difference in stard and end times for this thread
       Diff = SavedTimers(TimerLoc)%END_TIME_LOOP(ThreadNum) - &
              SavedTimers(TimerLoc)%START_TIME_LOOP(ThreadNum)

       ! Error check...
       IF ( Diff .lt. 0 ) THEN
          ErrMsg = 'Timer returned invalid value: ' // TRIM( TimerName )
          CALL GC_Warning( ErrMsg, RC, ThisLoc )
          Diff = 0
       ENDIF

       ! Asd difference to current value of total time
       SavedTimers(TimerLoc)%TOTAL_TIME_LOOP(ThreadNum) = &
              SavedTimers(TimerLoc)%TOTAL_TIME_LOOP(ThreadNum) + Diff

       ! Debug
       !Print*, TRIM(TempTimerName), ": Thread=", ThreadNum, ", Diff=", Diff, ", TotalTime=", SavedTimers(TimerLoc)%TOTAL_TIME_LOOP(ThreadNum)

    ELSE
       ! Timer is enabled, it's been found, so we disable it
       SavedTimers(TimerLoc)%ENABLED = .false.

       ! Debug
       !PRINT*, TRIM(TempTimerName), ": End  =", TheTime

       ! Get the end time
       SavedTimers(TimerLoc)%END_TIME = TheTime

       ! Get the difference in start and end times
       Diff = SavedTimers(TimerLoc)%END_TIME - SavedTimers(TimerLoc)%START_TIME

       ! Error check...
       IF ( Diff .lt. 0 ) THEN
          ErrMsg = 'Timer returned invalid value: ' // TRIM( TimerName )
          CALL GC_Warning( ErrMsg, RC, ThisLoc )
          Diff = 0
       ENDIF

       ! Add difference to current value of total time
       SavedTimers(TimerLoc)%TOTAL_TIME = SavedTimers(TimerLoc)%TOTAL_TIME + &
                                          Diff
    ENDIF

  END SUBROUTINE Timer_End
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_Sum_Loop
!
! !DESCRIPTION: Sums elapsed time across parallel threads to obtain the total.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_Sum_Loop( TimerName, RC )
!
! !USES:
!
    USE ErrCode_Mod
!
! !INPUT PARAMETERS:
!
    CHARACTER(LEN=*),  INTENT(IN)    :: TimerName   ! Name for timer
!
! !INPUT/OUTPUT PARAMETERS:
!
    INTEGER,           INTENT(INOUT) :: RC          ! Success / Failure
!
! !REMARKS:
!  Without this routine being called, a timer will not add to its total.
!
! !REVISION HISTORY:
!  30 Apr 2020 - M. Sulprizio- Initial version
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    INTEGER            :: N
    INTEGER            :: TimerLoc       ! Timer number
    REAL(f8)           :: TheTime        ! Returned Time from method
    REAL(f8)           :: Diff           ! Difference in times for each thread
    REAL(f8)           :: TotalDiff      ! Total difference in times

    ! Strings
    CHARACTER(LEN=30)  :: TempTimerName
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_Sum_Loop begins here!
    !=======================================================================

    ! Initialize
    RC       = GC_SUCCESS
    ErrMsg   = ''
    ThisLoc  = ' -> at Timer_Sum_Loop (in module GeosUtil/timers_mod.F90)'
    TotalDiff= 0.0

    ! Determine timer index
    TempTimerName = TimerName
    TimerLoc      = Timer_Find( TempTimerName )

    ! Exit if timer is not found
    IF (TimerLoc .eq. 0) THEN
       ErrMsg = 'Timer not found: ' // TRIM( TimerName )
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN
    ENDIF

    ! Sum the total time across threads
    SavedTimers(TimerLoc)%TOTAL_TIME =                                       &
         SUM(SavedTimers(TimerLoc)%TOTAL_TIME_LOOP) / d_nThreads

    ! Debug
    !Print*, 'Timer:', TRIM(TimerName)
    !Print*, 'Thread totals:', SavedTimers(TimerLoc)%TOTAL_TIME_LOOP
    !Print*, 'Total time', SavedTimers(TimerLoc)%TOTAL_TIME

  END SUBROUTINE Timer_Sum_Loop
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_Print
!
! !DESCRIPTION: Prints the specified Timer by name.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_Print( TimerName, RC, LunJson )
!
! !USES:
!
    USE ErrCode_Mod
!
! !INPUT PARAMETERS:
!
    CHARACTER(LEN=*), INTENT(IN)    :: TimerName   ! Name for timer
    INTEGER,          OPTIONAL      :: LunJson     ! Logical unit for JSON
!
! !INPUT/OUTPUT PARAMETERS:
!
    INTEGER,          INTENT(INOUT) :: RC          ! Success / Failure
!
! !REMARKS:
!  This is useful if you only want to print a single timer.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    INTEGER            :: TimerLoc           ! Timer number

    ! Strings
    CHARACTER(LEN=30)  :: TempTimerName
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_Print begins here!
    !=======================================================================

    ! Initialize
    RC       = GC_SUCCESS
    ErrMsg   = ''
    ThisLoc  = ' -> at Timer_Print (in module GeosUtil/timers_mod.F90)'

    TempTimerName = TimerName

    TimerLoc = Timer_Find( TempTimerName )

    ! Exit if timer is not found
    IF ( TimerLoc == 0 ) THEN
       ErrMsg = 'Timer not found: ' // TRIM( TimerName )
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN
    ENDIF

    ! Print the timer output; write to JSON if LunJson is passed
    IF ( PRESENT( LunJson ) ) THEN
       CALL Timer_PrintNum( TimerLoc, LunJson )
    ELSE
       CALL Timer_PrintNum( TimerLoc          )
    ENDIF

  END SUBROUTINE Timer_Print
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_PrintAll
!
! !DESCRIPTION: Prints all Timers to log file.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_PrintAll( Input_Opt, RC )
!
! !USES:
!
    USE ErrCode_Mod
    USE Input_Opt_Mod, ONLY : OptInput
    USE inquireMod,    ONLY : findFreeLun
!
! !OUTPUT PARAMETERS:
!
    TYPE(OptInput), INTENT(IN) :: Input_Opt   ! Input Options object
!
! !OUTPUT PARAMETERS:
!
    INTEGER, INTENT(OUT)       :: RC          ! Success / Failure
!
! !REMARKS:
!  This prints all timers in the order added.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    INTEGER            :: I,      LunJson

    ! Strings
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_PrintAll begins here!
    !=======================================================================

    ! Initialize
    RC       = GC_SUCCESS
    ErrMsg   = ''
    ThisLoc  = ' -> at Timer_PrintAll (in module GeosUtil/timers_mod.F90)'

    ! Exit if no timers were turned on
    IF ( TimerCurrentSize < 1 ) THEN
       ErrMsg = 'No timers are defined!'
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN
    ENDIF

    ! Print header info
    IF ( Input_Opt%amIRoot ) THEN

       ! Find LUN and open a file for JSON output
       LunJson = findFreeLun()
       OPEN( LunJson, FILE='gcclassic_timers.json', FORM='formatted' )

       ! Print headers for both logfile and JSON output
       CALL Timer_PrintHeaders( LunJson )

       ! Print formatted output to stdout and to a JSON file
       DO I = 1, TimerCurrentSize
          CALL Timer_PrintNum( I, LunJson )

          ! Deallocate loop timer arrays
          IF ( ALLOCATED( SavedTimers(I)%START_TIME_LOOP ) ) THEN
             DEALLOCATE(  SavedTimers(I)%START_TIME_LOOP, STAT=RC )
             IF ( RC /= GC_SUCCESS ) RETURN
          ENDIF
          IF ( ALLOCATED( SavedTimers(I)%END_TIME_LOOP ) ) THEN
             DEALLOCATE(  SavedTimers(I)%END_TIME_LOOP, STAT=RC )
             IF ( RC /= GC_SUCCESS ) RETURN
          ENDIF
          IF ( ALLOCATED( SavedTimers(I)%TOTAL_TIME_LOOP ) ) THEN
             DEALLOCATE(  SavedTimers(I)%TOTAL_TIME_LOOP, STAT=RC )
             IF ( RC /= GC_SUCCESS ) RETURN
          ENDIF

       ENDDO

       ! Close the JSON file
       WRITE( LunJson, '(a)' ) '    }'
       WRITE( LunJson, '(a)' ) '}'
       CLOSE( LunJson        )
    ENDIF

  END SUBROUTINE Timer_PrintAll
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_StopAll
!
! !DESCRIPTION: Stops all Timers.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_StopAll( RC )
!
! !USES:
!
    USE ErrCode_Mod
!
! !OUTPUT PARAMETERS:
!
    INTEGER, INTENT(OUT) :: RC          ! Success / Failure
!
! !REMARKS:
!  This stops all currently running timers. Used during crashes.
!
! !REVISION HISTORY:
!  11 Aug 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    ! Scalars
    INTEGER :: I

    ! Strings
    CHARACTER(LEN=255) :: ErrMsg, ThisLoc

    !=======================================================================
    ! Timer_StopAll begins here!
    !=======================================================================

    ! Initialize
    RC       = GC_SUCCESS
    ErrMsg   = ''
    ThisLoc  = ' -> at Timer_StopAll  (in module GeosUtil/timers_mod.F90)'

    ! Exit if no timers are defined
    IF ( TimerCurrentSize < 1 ) THEN
       ErrMsg = 'No timers are defined!'
       CALL GC_Error( ErrMsg, RC, ThisLoc )
       RETURN
    ENDIF

    ! Stop all of the timers
    DO I = 1, TimerCurrentSize
       IF ( (SavedTimers(I)%ENABLED) ) THEN
          PRINT*, "Timer forced to stop due to error: ",                     &
               SavedTimers(I)%TIMER_NAME

          ! Yes, this is inefficient. Should have another function
          ! written eventually to replace using the normal one.
          CALL Timer_End( SavedTimers(I)%TIMER_NAME, RC )
       ENDIF
    ENDDO

  END SUBROUTINE Timer_StopAll
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_PrintNum
!
! !DESCRIPTION: Prints Timer by number.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_PrintNum( SlotNumber, LunJson )
!
! !INPUT PARAMETERS:
!
    INTEGER, INTENT(IN) :: SlotNumber  ! The slot of the timer
    INTEGER, OPTIONAL   :: LunJson     ! Logical unit # for JSON file
!
! !REMARKS:
!  This actually does the printing, and is called by other print
!  routines.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC

    IF ( TimerCurrentSize < 1 ) THEN  ! Return if it's empty
       RETURN
    ENDIF

    IF ( (SavedTimers(SlotNumber)%ENABLED) ) THEN
       PRINT*, "** WARNING: Timer still enabled! "
    ENDIF

    ! Print the timer info; write to JSON if LunJson is passed
    IF ( PRESENT( LunJson ) ) THEN
       CALL Timer_TimePrint( SlotNumber, LunJson )
    ELSE
       CALL Timer_TimePrint( SlotNumber          )
    ENDIF

  END SUBROUTINE Timer_PrintNum
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_Find
!
! !DESCRIPTION: Finds the number of the specified Timer.
!\\
!\\
! !INTERFACE:
!
  FUNCTION Timer_Find( TimerName ) RESULT ( SlotNumber )
!
! !INPUT PARAMETERS:
!
    CHARACTER(LEN=30), INTENT(IN) :: TimerName   ! Name for timer.
!
! !RETURN VALUE:
!
    INTEGER                       :: SlotNumber  ! The slot of the timer.
!
! !REMARKS:
!  This is a private routine.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    INTEGER :: I

    SlotNumber = 0

    IF(TimerCurrentSize .lt. 1) THEN  ! Return 0 if it's empty
       RETURN
    ENDIF

    DO I = 1, TimerCurrentSize, 1
       IF( TRIM((SavedTimers(I)%TIMER_NAME)) .eq. TRIM(TimerName)) THEN
          SlotNumber = I
       ENDIF
    ENDDO

  END FUNCTION Timer_Find
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_TheTime
!
! !DESCRIPTION: Returns the current time in milliseconds.
!\\
!\\
! !INTERFACE:
!
  FUNCTION Timer_TheTime() RESULT ( TotalTime )
!
! !RETURN VALUE:
!
    REAL(f8) :: TotalTime  ! The current calculated time.
!
! !REMARKS:
!  This is a private routine.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    INTEGER        :: TIME_VALUE            ! For the function
    INTEGER        :: TIME_CLOCK            ! For the function

    ! Let's call the intrinsic function...
    CALL SYSTEM_CLOCK(TIME_VALUE, TIME_CLOCK)

    ! Debug
    !PRINT*, "TIME_VALUE: ", TIME_VALUE
    !PRINT*, "TIME_CLOCK: ", TIME_CLOCK
    !CALL FLUSH(6)

    TotalTime = REAL(TIME_VALUE) / REAL(TIME_CLOCK)

  END FUNCTION Timer_TheTime
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_TimePrint
!
! !DESCRIPTION: Formats the time and writes it out to the log file.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_TimePrint( SlotNumber, LunJson )
!
! !INPUT PARAMETERS:
!
    INTEGER, INTENT(IN) :: SlotNumber  ! The slot of the timer
    INTEGER, OPTIONAL   :: LunJson    ! File unit for Json write
!
! !REMARKS:
!  This is a private subroutine.
!
! !REVISION HISTORY:
!  24 Jul 2015 - M. Yannetti - Initial version.
!  See https://github.com/geoschem/geos-chem for complete history
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
    REAL(f8)           :: InputSecs       ! Real value of secones
    REAL(f8)           :: SecsLeft        ! How many seconds are 'left'
    INTEGER            :: IntSecs         ! Same as above, but integer
    INTEGER            :: TotalMS         ! Total Milliseconds
    INTEGER            :: TotalSecs       ! Total Seconds
    INTEGER            :: TotalMins       ! Total Minutes
    INTEGER            :: TotalHours      ! Total Hours
    INTEGER            :: TotalDays       ! Total Days


    ! Strings
    CHARACTER(LEN=100) :: OutputStr       ! Combined output string
    CHARACTER(LEN=15)  :: JsonDhms
    CHARACTER(LEN=14)  :: JsonSecs
    CHARACTER(LEN=10)  :: TempStr         ! Needed to remove whitespace.
    CHARACTER(LEN=2)   :: DD, HH, MM, SS
    CHARACTER(LEN=3)   :: MS

    !=======================================================================
    ! Timer_TimePrint begins here!
    !=======================================================================

    ! Initialize
    InputSecs  = 0.0_f8
    SecsLeft   = 0.0_f8
    TotalMS    = 0
    TotalSecs  = 0
    TotalMins  = 0
    TotalHours = 0
    TotalDays  = 0

    ! Copy the timer value
    InputSecs = SavedTimers(SlotNumber)%TOTAL_TIME
    IntSecs   = INT(InputSecs)
    SecsLeft  = InputSecs - REAL(IntSecs)

    IF ( InputSecs < 0 ) THEN ! Invalid time
       WRITE( 6, 110 ) SavedTimers(SlotNumber)%TIMER_NAME
110    FORMAT(2x,a30,': Invalid run time - negative value')
       RETURN
    ELSEIF ( InputSecs .eq. 0 ) THEN ! Zero timer
       WRITE( 6, 120 ) SavedTimers(SlotNumber)%TIMER_NAME
120    FORMAT(2x,a30,':  >>>>> THE TIMER DID NOT RUN <<<<<')
       RETURN
    ENDIF

    ! Debug
    !PRINT*, "INT   : ", IntSecs
    !PRINT*, "REAL  : ", InputSecs
    !PRINT*, "REMAIN: ", SecsLeft

    !-----------------------------------------------------------------------
    ! Calculate hours
    !-----------------------------------------------------------------------
    TotalHours = FLOOR(REAL(IntSecs)/3600.0)
    IntSecs    = IntSecs - (TotalHours*3600)

    !-----------------------------------------------------------------------
    ! Calculate days (if needed)
    !-----------------------------------------------------------------------
    IF ( TotalHours > 24 ) THEN
       TotalDays  = FLOOR(REAL(TotalHours)/24.0)
       TotalHours = TotalHours - (TotalDays*24)
    ENDIF

    !-----------------------------------------------------------------------
    ! Calculate minutes
    !-----------------------------------------------------------------------
    TotalMins  = FLOOR(REAL(IntSecs)/60.0)
    IntSecs    = IntSecs - (TotalMins*60)

    !-----------------------------------------------------------------------
    ! Calculate seconds
    !-----------------------------------------------------------------------
    TotalSecs  = IntSecs

    !-----------------------------------------------------------------------
    ! Calculate milliseconds
    !-----------------------------------------------------------------------
    SecsLeft = SecsLeft * 1000
    TotalMS = INT(SecsLeft)

    !-----------------------------------------------------------------------
    ! Write timers to log file in DD-hh:mm:ss.SSS format
    ! and also write the total number of seconds for convenience
    !-----------------------------------------------------------------------
    WRITE( DD, '(i2.2)' ) TotalDays
    WRITE( HH, '(i2.2)' ) TotalHours
    WRITE( MM, '(i2.2)' ) TotalMins
    WRITE( SS, '(i2.2)' ) TotalSecs
    WRITE( MS, '(i3.3)' ) TotalMS

    WRITE( 6, 130 ) SavedTimers(SlotNumber)%TIMER_NAME,                      &
                    DD, HH, MM, SS, MS, InputSecs
130 FORMAT( 2x,a30,':',2x,a2,'-',a2,':',a2,':',a2,'.',a3, 4x, f14.3    )

    !-----------------------------------------------------------------------
    ! Also write to JSON format
    !-----------------------------------------------------------------------
    IF ( PRESENT( LunJson ) ) THEN
       WRITE( JsonDhms, 140      ) DD, HH, MM, SS, MS
       WRITE( JsonSecs, '(f14.3)') InputSecs
140    FORMAT( a2,'-',a2,':',a2,':',a2,'.',a3 )

       ! Write to JSON file
       CALL Timer_TimePrint_JSON(                                            &
            lun        = LunJson,                                            &
            slot       = SlotNumber,                                         &
            timer_name = TRIM( SavedTimers(SlotNumber)%TIMER_NAME ),         &
            d_hms      = TRIM( ADJUSTL( JsonDhms )               ),          &
            seconds    = TRIM( ADJUSTL( JsonSecs )               )          )
    ENDIF

  END SUBROUTINE Timer_TimePrint
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_TimePrint_JSON
!
! !DESCRIPTION: Writes each timer to JSON output
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_TimePrint_JSON( lun, slot, timer_name, d_hms, seconds )
!
! !INPUT PARAMETERS:
!
    INTEGER,          INTENT(IN) :: lun
    INTEGER,          INTENT(IN) :: slot
    CHARACTER(LEN=*), INTENT(IN) :: timer_name
    CHARACTER(LEN=*), INTENT(IN) :: d_hms
    CHARACTER(LEN=*), INTENT(IN) :: seconds

!
! !REMARKS:
!  This is a private subroutine.
!EOP
!------------------------------------------------------------------------------
!BOC

    !=======================================================================
    ! Timer_TimePrint begins here!
    !=======================================================================

    ! Write timer info
    ! Skip trailing comma if we are on the last timer
    WRITE( lun, 100 ) timer_name
    WRITE( lun, 110 )
    WRITE( lun, 120 ) d_hms
    WRITE( lun, 130 ) seconds
    IF ( slot == TimerCurrentSize ) THEN
       WRITE( lun, 140 )
    ELSE
       WRITE( lun, 150 )
    ENDIF

    ! FORMAT statements
100 FORMAT( '        "', a, '":'                                            )
110 FORMAT( '        {'                                                     )
120 FORMAT( '            "d_hms":',   1x, '"', a, '",'                      )
130 FORMAT( '            "seconds":', 1x, a                                 )
140 FORMAT( '        }'                                                     )
150 FORMAT( '        },'                                                    )

  END SUBROUTINE Timer_TimePrint_JSON
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: Timer_WriteHeaders
!
! !DESCRIPTION: Writes headers for logfile output to stdout
!  as well for JSON file format.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE Timer_PrintHeaders( lun )
!
! !INPUT PARAMETERS:
!
    INTEGER, INTENT(IN) :: lun   ! Logical unit number for JSON
!EOP
!------------------------------------------------------------------------------
!BOC

    !=======================================================================
    ! Write header for log file output to stdout
    !=======================================================================
    WRITE( 6, *     ) ''
    WRITE( 6, '(a)' ) REPEAT( '=', 79 )
    WRITE( 6, '(a)' ) 'G E O S - C H E M   T I M E R S'
    WRITE( 6, *     ) ''
    WRITE( 6, 100   ) 'Timer name','DD-hh:mm:ss.SSS','Total Seconds'
    WRITE( 6, '(a)' ) REPEAT( '-', 79 )
100 FORMAT( 2x, a10, 23x, a15, 5x, a13 )

    !=======================================================================
    ! Write header for JSON output
    !=======================================================================
    WRITE( lun, 200 )
    WRITE( lun, 210 )
    WRITE( lun, 220 )
    WRITE( lun, 230 )
    WRITE( lun, 240 )
    WRITE( lun, 250 )
    WRITE( lun, 260 )
    WRITE( lun, 270 )
    WRITE( lun, 220 )
200 FORMAT( '{'                                                             )
210 FORMAT( '    "description":'                                            )
220 FORMAT( '    {'                                                         )
230 FORMAT( '        "name": "GEOS-Chem Classic timers output",'            )
240 FORMAT( '        "author": "The International GEOS-Chem Community",'    )
250 FORMAT( '        "reference": "https://geos-chem.readthedocs.io"'       )
260 FORMAT( '    },'                                                         )
270 FORMAT( '    "GEOS-Chem Classic timers":'                               )

  END SUBROUTINE Timer_PrintHeaders
!EOC
END MODULE Timers_Mod
