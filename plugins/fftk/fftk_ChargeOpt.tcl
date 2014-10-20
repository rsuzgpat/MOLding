#
# $Id: fftk_ChargeOpt.tcl,v 1.4 2012/01/27 20:57:02 johns Exp $
#

#======================================================
namespace eval ::ForceFieldToolKit::ChargeOpt {

    # Input Variables
    
    # Need to Manually Set
    variable psfPath
    variable pdbPath
    variable resName
    variable parList
    variable logFileList
    variable atomList
    variable indWeights
    variable namdbin
    
    variable chargeGroups
    variable chargeInit
    variable chargeBounds
    variable chargeSum
    
    variable baseLog
    variable watLog
    
    variable outFile
    variable outFileName
    
    variable start
    variable end
    variable delta
    variable offset
    variable scale
    
    variable tol
    variable dWeight


    # Set in Procs
    variable QMEn
    variable QMDist
    variable molid
    
    variable simtype
    variable debug
    
    variable reChargeOverride
    variable reChargeOverrideCharges
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    
    variable guiMode
    variable optCount
    variable mmCount
    
    variable returnFinalCharges

}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::init {} {

    # GUI Input
    variable psfPath
    variable pdbPath
    variable resName
    variable parList
    variable namdbin
    variable outFileName
    
    set psfPath {}
    set pdbPath {}
    set resName {}
    set parList {}
    set namdbin "namd2"
    set outFileName "ChargeOpt.log"

    # GUI Charge Constraints
    variable chargeGroups
    variable chargeInit
    variable chargeBounds
    variable chargeSum

    set chargeGroups {}
    set chargeInit {}
    set chargeBounds {}
    set chargeSum {}

    # GUI QM Target Data    
    variable baseLog
    variable watLog
    variable logFileList
    variable atomList
    variable indWeights
    
    set baseLog {}
    set watLog {}
    set logFileList {}
    set atomList {}
    set indWeights {}   

    # ADV Settings  
    variable start
    variable end
    variable delta
    variable offset
    variable scale
    variable tol
    variable dWeight

    set start -0.4
    set end 0.4
    set delta 0.05
    set offset -0.2
    set scale 1.16
    set tol 0.005
    set dWeight 1.0
    
    # Other
    variable outFile
    variable QMEn
    variable QMDist
    variable molid
    variable simtype
    variable debug
    variable reChargeOverride
    variable reChargeOverrideCharges
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    variable guiMode
    variable optCount
    variable mmCount
    variable returnFinalCharges

    set outFile {}
    set QMEn {}
    set QMDist {}
    set molid {}
    
    set simtype ""
    set debug 0
    set reChargeOverride 0
    set reChargeOverrideCharges {}
    set mode downhill
    set saT 25
    set saTSteps 20
    set saIter 15
    
    set guiMode 1
    set optCount 0
    set mmCount 0
    
    set returnFinalCharges {}

}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::sanityCheck {} {
    # checks to see that appropriate information is set
    # prior to running the charge optimization
    
    # returns 1 if all input is sane
    # returns 0 if there is an error
    
    # localize relevant ChargeOpt variables
    variable psfPath
    variable pdbPath
    variable resName
    variable parList
    variable namdbin
    variable outFileName

    variable chargeGroups
    variable chargeInit
    variable chargeBounds
    variable chargeSum
    
    variable baseLog
    variable watLog
    variable logFileList
    variable atomList
    variable indWeights
    
    variable start
    variable end
    variable delta
    variable offset
    variable scale

    variable mode
    variable tol
    #variable dWeight ; not yet in GUI
    variable saT
    variable saTSteps
    variable saIter
    
    # local variables
    set errorList {}
    set errorText ""
    
    # build the error list based on what proc is checked (opt or psf rewrite)
    # INPUT
    # make sure psf is entered and exists
    if { $psfPath eq "" } { lappend errorList "No PSF file was specified." } \
    else { if { ![file exists $psfPath] } { lappend errorList "Cannot find PSF file." } }
    
    # make sure the pdb is entered and exists
    if { $pdbPath eq "" } { lappend errorList "No PDB file was specified." } \
    else { if { ![file exists $pdbPath] } { lappend errorList "Cannot find PDB file." } }

    # make sure residue name isn't empty
    if { $resName eq "" } { lappend errorList "Residue name was not specified." }
    
    # make sure there is a parameter file (init and one with at least TIP3 water)
    # and that they exist
    if { [llength $parList] == 0 } { lappend errorList "No parameter files were specified." } \
    else {
        foreach parFile $parList {
            if { ![file exists $parFile] } { lappend errorList "Cannot open prm file: $parFile." }
        }
    }
    
    # make sure namd2 command and/or file exists
    if { $namdbin eq "" } {
        lappend errorList "NAMD binary file (or command if in PATH) was not specified."
    } else { if { [::ExecTool::find $namdbin] eq "" } { lappend errorList "Cannot find NAMD binary file." } }
    
    # make sure output file name (outFileName) isn't blank, and user can write to output dir
    if { $outFileName eq "" } { lappend errorList "Output LOG file was not specified." } \
    else { if { ![file writable [file dirname $outFileName]] } { lappend errorList "Cannot write to output LOG directory." } }
    
    
    # CHARGE CONSTRAINTS
    # may need some work, although there may only be so much we can do here
    # charge groups
    # check that charge groups isn't empty
    if { [llength $chargeGroups] == 0 } {
        lappend errorList "Charge groups aren't set."
    } else {
        # check that each group contains at least one atom name
        foreach group $chargeGroups {
            if { $group eq "" } { lappend errorList "Found a charge group without an atom definition." }
        }
        
        # check initial charge
        foreach charge $chargeInit {
            if { $charge eq "" || ![string is double $charge] } { lappend errorList "Found inappropriate initial charge." }
            if { $charge == 0.0 } { lappend errorList "Initial charge should not be 0.0." }
        }
        
        # check bounds
        foreach bound $chargeBounds {
            if { [llength $bound] != 2 } { lappend errorList "Found Unbalanced bounds element." }
            if { [lindex $bound 0] eq "" || ![string is double [lindex $bound 0]] } { lappend errorList "Found inappropriate lower bound." }
            if { [lindex $bound 1] eq "" || ![string is double [lindex $bound 1]] } { lappend errorList "Found inappropriate upper bound." }
        }
        
        # check charge sum
        if { $chargeSum eq "" || ![string is double $chargeSum] } { lappend errorList "Found inappropriate charge sum." }
    }
    
    
    # QM TARGET DATA
    # may also need some work.
    # check cmpd QM single point energy log file is entered and exists
    if { $baseLog eq "" } { lappend errorLog "QM single point energy log file for the compound was not specified." } \
    else { if { ![file exists $baseLog] } { lappend errorLog "Cannot find QM single point energy log file for compound." } }
    
    # check wat QM single point energy log file is entered and exists
    if { $watLog eq "" } { lappend errorLog "QM single point energy log file for water was not specified." } \
    else { if { ![file exists $watLog] } { lappend errorLog "Cannot find QM single point energy log file for water." } }
    
    # check that log file list isn't empty
    if { [llength $logFileList] == 0 } { lappend errorList "No QM water-interaction energy log files loaded." } \
    else {
        # check atom names
        # consider loading the psf/pdb and checking atom names against loaded molecule
        foreach atom $atomList {
            if { $atom eq "" } { lappend errorList "Found inappropriate atom name in QM water-interaction log list." }
        }
        
        # check weights
        foreach weight $indWeights {
            if { $weight < 0 || ![string is double $weight] } { lappend errorList "Found inappropriate weight in QM water-interaction log list." }
        }
    }
    
    
    # ADVANCED SETTINGS
    # water shift settings - check that they are not empty and are numbers
    # start
    if { $start eq "" } { lappend errorList "Water shift start is not set." } \
    else { if { ![string is double $start] } { lappend errorList "Found inappropriate water shift start value." } }
    # end
    if { $end eq "" } { lappend errorList "Water shift end is not set." } \
    else { if { ![string is double $end] } { lappend errorList "Found inappropriate water shift end value." } }
    # delta
    if { $delta eq "" } { lappend errorList "Water shift delta is not set." } \
    else { if { ![string is double $delta] } { lappend errorList "Found inappropriate water shift delta value." } }
    # offset
    if { $offset eq "" } { lappend errorList "Water shift offset is not set." } \
    else { if { ![string is double $offset] } { lappend errorList "Found inappropriate water shift offset value." } }
    # scale
    if { $scale eq "" } { lappend errorList "Water shift scale is not set." } \
    else { if { ![string is double $scale] } { lappend errorList "Found inappropriate water shift scale value." } }

    # optimizer settings
    if { [lsearch -exact {downhill {simulated annealing}} $mode] == -1 } { lappend errorList "Unsupported optimization mode." } \
    else {
        # check tol
        if { $tol eq "" || $tol < 0 || ![string is double $tol] } { lappend errorList "Found inappropriate optimization tolerance setting." }
        # check simulated annealing parameters
        if { $mode eq "simulated annealing" } {
            if { $saT eq "" || ![string is double $saT] } { lappend errorList "Found inappropriate saT setting." }
            if { $saTSteps eq "" || $saTSteps < 0 || ![string is integer $saTSteps] } { lappend errorList "Found inappropriate saTSteps setting." }
            if { $saIter eq "" || $saIter < 0 || ![string is integer $saIter] } { lappend errorList "Found inappropriate saIter setting." }
        }
    }
    
    # LOG FILE
    # make sure that the user can write to CWD
    if { ![file writable ./] } { lappend errorList "Cannot write log file to CWD." }

    # if there is an error, tell the user about it
    # return -1 to tell the calling proc that there is a problem
    if { [llength $errorList] > 0 } {
        foreach ele $errorList {
            set errorText [concat $errorText\n$ele]
        }
        tk_messageBox \
            -type ok \
            -icon warning \
            -message "Application halting due to the following errors:" \
            -detail $errorText
        
        # there are errors, return the error response
        return 0
    }

    # if you've made it this far, there are no errors
    return 1    
    
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::optimize {} {
    # need to localize all variables
    variable psfPath
    variable pdbPath
    variable resName
    variable parList
    variable namdbin
    variable outFileName
    variable chargeGroups
    variable chargeInit
    variable chargeBounds
    variable chargeSum
    variable baseLog
    variable watLog
    variable logFileList
    variable atomList
    variable indWeights
    variable start
    variable end
    variable delta
    variable offset
    variable scale
    variable tol
    variable dWeight
    variable outFile
    variable QMEn
    variable QMDist
    variable molid
    variable simtype
    variable debug
    variable reChargeOverride
    variable reChargeOverrideCharges
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    variable guiMode
    variable optCount
    variable mmCout
    variable returnFinalCharges

    # run a sanity check
    if { ![::ForceFieldToolKit::ChargeOpt::sanityCheck] } { return }

    
    set outFile [open $outFileName w]
    if { $debug } {
        set debugLog [open "[file rootname [file tail $outFileName]].debug.log" w]
        ::ForceFieldToolKit::ChargeOpt::printSettings $debugLog
    }
    
    if { $guiMode } {
        set ::ForceFieldToolKit::gui::coptStatus "Running...Loading QM Data"
        update idletasks
    }
    
    set simtype "single point"
    
    mol delete all
    
    # Parse Compound and Water Single Point Energy Calculations for QM Energy
    set Enwat [lindex [lindex [::ForceFieldToolKit::ChargeOpt::getscf $watLog] end] 1]
    set Enbase [lindex [lindex [::ForceFieldToolKit::ChargeOpt::getscf $baseLog] end] 1]
    
    if { $debug } {
        puts $debugLog "Single Point Energies Parsed.  QME(water): $Enwat\tQME(cmpd): $Enbase"; flush $debugLog
    }

    # Build the necessary psf/pdb for a water molecule from a library/proc
    ::ForceFieldToolKit::ChargeOpt::writeWatPSF
    ::ForceFieldToolKit::ChargeOpt::writeWatPDB
        
    # Construct a psf/pdb pair for Compound + Water
    resetpsf
    readpsf $psfPath
    coordpdb $pdbPath
    readpsf wat.psf
    coordpdb wat.pdb
    writepsf base-wat.psf
    writepdb base-wat.pdb
        
    mol new base-wat.psf
    set molid [molinfo top]
    
    ## Parse energies and optimal water positions from QM Log files
    set QMEn {}
    foreach log $logFileList {
        # Parse energy, calculate interaction energy (QMEn)
       set Entot [lindex [lindex [::ForceFieldToolKit::ChargeOpt::getscf $log] end] 1]
       lappend QMEn [expr $scale*($Entot - $Enbase - $Enwat)]
       mol addfile base-wat.pdb
    
       ## very conservative here, do not assume coordinates in
       ## pdb match those in water-interaction log file

       # Parse Compound coordinates and move VMD atoms into position    
       set sel [atomselect top "resname $resName"]
       set molCoords [::ForceFieldToolKit::ChargeOpt::getMolCoords $log [$sel num]]
       for {set i 0} {$i < [$sel num]} {incr i} {
          set temp [atomselect top "index $i"]
          $temp set x [lindex [lindex $molCoords $i] 0]
          $temp set y [lindex [lindex $molCoords $i] 1]
          $temp set z [lindex [lindex $molCoords $i] 2]
          $temp delete
       }
       $sel delete

       # Parse Water coordinates and move VMD atoms into position
       ## don't want to assume water atoms are always in the same order
       set watCoords [::ForceFieldToolKit::ChargeOpt::getWatCoords $log]
       set sel [atomselect top "water and name OH2"]
       $sel moveto [lindex $watCoords 0]
       $sel delete
       set sel [atomselect top "water and name H1"]
       $sel moveto [lindex $watCoords 1]
       $sel delete
       set sel [atomselect top "water and name H2"]
       $sel moveto [lindex $watCoords 2]
       $sel delete
    }
    

    # Clean up temporary files used to load atoms into VMD
    file delete base-wat.psf
    file delete base-wat.pdb
    file delete wat.psf
    file delete wat.pdb

    
    ## retyping and re-charging
    ::ForceFieldToolKit::SharedFcns::reTypeFromPSF $psfPath $molid
    ::ForceFieldToolKit::SharedFcns::reChargeFromPSF $psfPath $molid
    # check to see if recharge is overridden in advanced settings
    if { $reChargeOverride } {
        foreach ovr $reChargeOverrideCharges {
            set temp [atomselect $molid "name [lindex $ovr 0]"]
            $temp set charge [lindex $ovr 1]
            $temp delete
        }
    }


    if { $debug } {
        puts $debugLog "Cmpd atoms retyped to: [[atomselect $molid "resname $resName"] get type]"; flush $debugLog
        puts $debugLog "Cmpd atoms recharged to: [[atomselect $molid "resname $resName"] get charge]"; flush $debugLog
    }
    
    
    ## get QM distances
    set QMDist {}
    for {set i 0} {$i < [llength $atomList]} {incr i} {
       set temp1 [atomselect top "name [lindex $atomList $i] and resname $resName" frame $i]
       set temp2 [atomselect top "water and name OH2" frame $i]   
       lappend QMDist [measure bond "[$temp1 get index] [$temp2 get index]" frame $i]
       $temp1 delete
       $temp2 delete
    }
    
    if { $debug } {
        puts $debugLog "QM data loaded into VMD frames"; flush $debugLog
        puts $debugLog "\tFrame\tQMEn\t\t\tQMDist"; flush $debugLog
        for {set i 0} {$i < [llength $QMEn]} {incr i} {
            puts $debugLog "\t$i\t[lindex $QMEn $i]\t[lindex $QMDist $i]"; flush $debugLog
        }
    }
    
    ## set up and run optimization

    # reset counter to keep track of optimization iterations
    set optCount 0
    # if running from gui, update the status
    if { $guiMode } {
        set ::ForceFieldToolKit::gui::coptStatus "Running...Optimizing(iter:$optCount)"
        update idletasks
    }
    
    ## can do simple downhill optimization or simulated annealing
    if { $mode eq "downhill" } {
        set opt [optimization -downhill -tol $tol -function ::ForceFieldToolKit::ChargeOpt::optCharges]
    } elseif { $mode eq "simulated annealing" } {
        set opt [optimization -annealing -tol $tol -T $saT -iter $saIter -Tsteps $saTSteps -function ::ForceFieldToolKit::ChargeOpt::optCharges]  
    }

    # configure bounds and initialize
    $opt configure -bound [lrange $chargeBounds 0 [expr [llength $chargeBounds] - 2]]
    $opt initsimplex [lrange $chargeInit 0 [expr [llength $chargeInit] - 2]]

    if { $debug } {
        puts $debugLog "Beginning Optimization"; flush $debugLog
        puts $debugLog "\topt setup line: optimization -downhill -tol $tol -function ::ForceFieldToolKit::ChargeOpt::optCharges"; flush $debugLog
        puts $debugLog "\topt configure line: configure -bound [lrange $chargeBounds 0 [expr [llength $chargeBounds] - 2]]"; flush $debugLog
        puts $debugLog "\topt initsimplex line: initsimplex [lrange $chargeInit 0 [expr [llength $chargeInit] - 2]]"; flush $debugLog
        update idletasks
    }
    
    set result [$opt start]
    
    set finalCharges [lindex $result 0]

    # used to load optimization results into the gui
    set returnFinalCharges {}   

    set curChargeSum 0
    #puts -nonewline $outFile "FINAL CHARGES: "
    puts $outFile "FINAL CHARGES"
    for {set i 0} {$i < [expr [llength $chargeGroups] - 1]} {incr i} {
       set charge [format %1.3f [lindex $finalCharges $i]]
       set curChargeSum [expr $curChargeSum + [llength [lindex $chargeGroups $i]]*$charge]
       #puts -nonewline $outFile "[lindex $chargeGroups $i] $charge  "
       puts $outFile "[list [lindex $chargeGroups $i] $charge]"
       lappend returnFinalCharges [list [lindex $chargeGroups $i] $charge]
    }
         
    set leftover [expr ($chargeSum - $curChargeSum)*1.0/[llength [lindex $chargeGroups end]]]
    #puts $outFile [format "[lindex $chargeGroups end] %1.3f " $leftover]
    puts $outFile "[list [lindex $chargeGroups end] [format "%1.3f" $leftover]]"
    lappend returnFinalCharges [list [lindex $chargeGroups end] [format "%1.3f" $leftover]]
    
    puts $outFile "END"
    puts $outFile "\n Be sure to check sum of charges for rounding errors!"

    # some cleanup  
    mol delete all
    close $outFile
    
    if { $debug } {
        puts $debugLog "Optimization result:"; flush $debugLog
        puts $debugLog "$result"; flush $debugLog
        close $debugLog
    }
    
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::shiftWat {name1 molid dist {offset -0.2}} {

   set tempsel1 [atomselect $molid "not water and name $name1"]
   set tempsel2 [atomselect $molid "water and name OH2"]

   foreach let {x y z} {
     lappend v1 [$tempsel1 get $let]
   }

   foreach let {x y z} {
     lappend v2 [$tempsel2 get $let]
   }

   set unitV [vecnorm [vecsub $v2 $v1]]

   set tempsel3 [atomselect top "water"]

   foreach ind [$tempsel3 get index] {
     set temp [atomselect $molid "index $ind"]
     foreach let {x y z} {
       lappend p [$temp get $let]
     }
     set pnew [vecadd $p [vecscale [expr $offset + $dist] $unitV]]
     $temp set x [lindex $pnew 0]
     $temp set y [lindex $pnew 1]
     $temp set z [lindex $pnew 2]
     unset p
     $temp delete
   }

   $tempsel1 delete
   $tempsel2 delete
   $tempsel3 delete
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::MMmin { psf pdb resname molAtomName start end delta offset namdbin parlist} {

   mol new $psf

   for {set d $start} {$d <= $end} {set d [expr $d+$delta]} {
     mol addfile $pdb
     ::ForceFieldToolKit::ChargeOpt::shiftWat $molAtomName [molinfo top] $d $offset
   }

   set molec [atomselect top "resname $resname"]
   set wat [atomselect top "water"]

   set namdEn "namdenergy -silent -nonb -sel \$molec \$wat -exe $namdbin -cutoff 1000"
   foreach par $parlist {
     set namdEn [concat $namdEn "-par $par"]
   }
   set energiesout [eval $namdEn]

   set dMin 0.0
   set enMin 10000000000.0
   for {set i 0} {$i < [llength $energiesout]} {incr i} {
      set d [expr $start + $i*$delta]
      set en [lindex [lindex $energiesout $i] 5]
      lappend DistEnlist "$d $en"
      if {$en < $enMin} {
         set dMin $d
         set enMin $en
##         break
      }
##      set dOLD $d
##      set enOLD $en
   }

   mol delete top

   return "$enMin $dMin $DistEnlist"


}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::optCharges { charges } {

    variable QMEn
    variable QMDist
    variable atomList
    variable dWeight
    variable chargeSum
    variable outFile
    variable chargeGroups
    variable molid
    variable namdbin
    variable parList
    variable resName
    variable start
    variable end
    variable delta
    variable offset
    variable indWeights
    variable debug
    variable guiMode
    variable optCount

#   global QMEn QMDist atomList dWeight chargeSum outFile chargeGroups molid namdbin parList
#   global res start end delta offset indWeights

   set curChargeSum 0

   puts -nonewline $outFile "Current test charges: "
   for {set i 0} {$i < [expr [llength $chargeGroups] - 1]} {incr i} {
      set temp [atomselect $molid "resname $resName and name [lindex $chargeGroups $i]"]
      $temp set charge [lindex $charges $i]
      $temp delete
      set curChargeSum [expr $curChargeSum + [llength [lindex $chargeGroups $i]]*[lindex $charges $i]]
      puts -nonewline $outFile [format "[lindex $chargeGroups $i] %2.3f   " [lindex $charges $i]]
   }

   set temp [atomselect $molid "name [lindex $chargeGroups end]"]
   set leftover [expr ($chargeSum - $curChargeSum)*1.0/[llength [lindex $chargeGroups end]]]
   $temp set charge $leftover
   puts $outFile [format "[lindex $chargeGroups end] %2.3f " $leftover]
   $temp delete

   set all [atomselect $molid all]
   $all writepsf tempOpt.psf

   set MMEn { }
   set MMDistdelta { }
   for {set i 0} {$i < [llength $atomList]} {incr i} {
      animate goto $i
      $all writepdb tempOpt.pdb
      set MMEnDist [::ForceFieldToolKit::ChargeOpt::MMmin tempOpt.psf tempOpt.pdb $resName [lindex $atomList $i] $start $end $delta $offset $namdbin $parList]
      lappend MMEn [lindex $MMEnDist 0]
      lappend MMDistdelta [lindex $MMEnDist 1]
   }

   set Obj 0

   for {set i 0} {$i < [llength $atomList]} {incr i} {
     puts $outFile [format "[lindex $atomList $i] QME: %1.3f MME: %1.3f" [lindex $QMEn $i] [lindex $MMEn $i]]
     puts $outFile [format "QMD: %1.3f MMDistDelta: %1.3f" [lindex $QMDist $i] [lindex $MMDistdelta $i]]
     set Obj [expr $Obj + [lindex $indWeights $i]*pow([expr [lindex $QMEn $i] - [lindex $MMEn $i]],2)/0.2]
##     set Obj [expr $Obj + pow([expr [lindex $QMEn $i] - [lindex $MMEn $i]],2)/abs([lindex $QMEn $i])]
     set Obj [expr $Obj + [lindex $indWeights $i]*$dWeight*pow([lindex $MMDistdelta $i],2)/0.1]
##     set Obj [expr $Obj + $dWeight*pow([lindex $MMDistdelta $i],2)/[lindex $QMDist $i]]
   }

   puts $outFile "Current objective value: $Obj\n\n\n"
 
   file delete tempOpt.pdb
   file delete tempOpt.psf
   
   # if running from gui, update the status menu
   incr optCount
   if { $guiMode } {
    set ::ForceFieldToolKit::gui::coptStatus "Running...Optimizing(iter:$optCount)"
    update idletasks
   }

   
   return $Obj
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::getscf { file } {
    variable simtype

   set scfenergies {}

   set fid [open $file r]

   set hart_kcal 1.041308e-21; # hartree in kcal
   set mol 6.02214e23;

   set num 0
   set ori 0
   set tmpscf {}
   set optstep 0
   set scanpoint 0
   
   while {![eof $fid]} {
      set line [string trim [gets $fid]]

      # Stop reading on errors
      if {[string match "Error termination*" $line]} { puts $line; return $scfenergies }

      # We only read Link0
      if {[string match "Normal termination of Gaussian*" $line]} { variable normalterm 1; break }
            
      if {$simtype=="Relaxed potential scan"} {
         if {[string match "Step number * out of a maximum of * on scan point * out of *" $line]} {
            set optstep   [lindex $line 2]
            set scanpoint [lindex $line 12]
            set scansteps [lindex $line 15]
            puts "SCAN: optstep $optstep on scan point $scanpoint out of $scansteps"
         }
      }
            
     if {[string match "SCF Done:*" $line] || [string match "Energy=* NIter=*" $line]} {
         if {[string match "SCF Done:*" $line]} {
            set scf [lindex $line 4]
         } else {
            set scf [lindex $line 1]
         }
         set scfkcal [expr {$scf*$hart_kcal*$mol}]
         if {$num==0} { set ori $scf }
         set scfkcalori [expr {($scf-$ori)*$hart_kcal*$mol}]
         # In case of a relaxed potential scan we replace the previous energy of the same scanstep,
         # otherwise we just append all new scf energies
         if {$optstep==1 || !($simtype=="Relaxed potential scan")} {
            if {[llength $tmpscf]} { lappend scfenergies $tmpscf; set tmpscf {} }
            puts [format "%i: SCF = %f hart = %f kcal/mol; rel = %10.4f kcal/mol" $num $scf $scfkcal $scfkcalori]
         }
         set tmpscf [list $num $scfkcal]

         incr num
      }

   }
   close $fid
   if {[llength $tmpscf]} { lappend scfenergies $tmpscf }

   return $scfenergies
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::getMolCoords { file numMolAtoms } {

   set fid [open $file r]
   ::QMtool::init_variables ::QMtool

   ::QMtool::read_gaussian_cartesians $fid qmtooltemppdb.pdb last
   file delete qmtooltemppdb.pdb
   set coordlist [lindex [::QMtool::get_cartesian_coordinates] 0]
    
   close $fid

   return [lrange $coordlist 0 [expr $numMolAtoms - 1]]
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::getWatCoords { file } {
   
   set fid [open $file r]
   ::QMtool::init_variables ::QMtool

   ::QMtool::read_gaussian_cartesians $fid qmtooltemppdb.pdb last
   file delete qmtooltemppdb.pdb
   set coordlist [lindex [::QMtool::get_cartesian_coordinates] 0]
   set atomlist [::QMtool::get_atomproplist]
   set numAtoms [llength $atomlist]

   set Hcount 0
   for {set i [expr $numAtoms - 4]} {$i < $numAtoms} {incr i} {
      set name [lindex [lindex $atomlist $i] 1]
      if { [string match "O*" $name] } {
         set Ocoord [lindex $coordlist $i]
      } elseif { [string match "H*" $name] && $Hcount == 1} {
         set H2coord [lindex $coordlist $i]
         set Hcount 2
      } elseif { [string match "H*" $name] && $Hcount == 0} {
         set H1coord [lindex $coordlist $i]
         set Hcount 1
      }
   }

   close $fid

   set coords [list $Ocoord $H1coord $H2coord]
   return $coords

}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::writeMinConf { name psf pdb parlist {extrabFile ""} } {

   set conf [open "$name.conf" w]
   puts $conf "structure          $psf"    
   puts $conf "coordinates        $pdb"
   puts $conf "paraTypeCharmm     on"
   foreach par $parlist {
      puts $conf "parameters       $par"
   }
   puts $conf "temperature         310"
   puts $conf "exclude             scaled1-4"
   puts $conf "1-4scaling          1.0"
   puts $conf "cutoff              1000.0"
   puts $conf "switching           on"
   puts $conf "switchdist          1000.0"
   puts $conf "pairlistdist        1000.0"
   puts $conf "timestep            1.0 "
   puts $conf "nonbondedFreq       2"
   puts $conf "fullElectFrequency  4 "
   puts $conf "stepspercycle       20"
   puts $conf "outputName          $name"
   puts $conf "restartfreq         1000"
   if { $extrabFile != "" } {
      puts $conf "extraBonds          yes"
      puts $conf "extraBondsFile $extrabFile"
   }
   puts $conf "minimize            1000"
   puts $conf "reinitvels          310"
   puts $conf "run 0"
   close $conf

}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::writeWatPSF {} {

    set outfile [open wat.psf w]
set contents {PSF

       3 !NTITLE
 REMARKS original generated structure x-plor psf file
 REMARKS topology top_tip3p.inp
 REMARKS segment WT { first NONE; last NONE; auto none  }

       3 !NATOM
       1 WT   1    TIP3 OH2  OT    -0.834000       15.9994           0
       2 WT   1    TIP3 H1   HT     0.417000        1.0080           0
       3 WT   1    TIP3 H2   HT     0.417000        1.0080           0

       2 !NBOND: bonds
       1       2       1       3

       1 !NTHETA: angles
       2       1       3

       0 !NPHI: dihedrals


       0 !NIMPHI: impropers


       0 !NDON: donors


       0 !NACC: acceptors


       0 !NNB

       0       0       0

       1       0 !NGRP
       0       0       0
}

    puts $outfile "$contents"
    close $outfile
    
    #return wat.psf

}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::writeWatPDB {} {

    set outfile [open wat.pdb w]
    
    set contents {REMARK original generated coordinate pdb file
ATOM      1  OH2 TIP3X   1       0.353   0.997   3.995  1.00  0.00      WT   O
ATOM      2  H1  TIP3X   1       1.170   0.722   4.411  1.00  0.00      WT   H
ATOM      3  H2  TIP3X   1      -0.261   1.107   4.721  1.00  0.00      WT   H
END 
}
    puts $outfile "$contents"
    close $outfile
    
    #return wat.pdb
}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::printSettings { debugLog } {
    # a tool to print all settings passed to the charge optimization routine
    # and relevant settings in the ChargeOpt namespace that will be accessed
    # by the charge optimization routing
    

    puts $debugLog "=========================================="
    puts $debugLog " Charge Optimization GUI Debugging Output "
    puts $debugLog "=========================================="
    
    puts $debugLog "INPUT SECTION"
    puts $debugLog "psfPath: $::ForceFieldToolKit::ChargeOpt::psfPath"
    puts $debugLog "pdbPath: $::ForceFieldToolKit::ChargeOpt::pdbPath"
    puts $debugLog "resName: $::ForceFieldToolKit::ChargeOpt::resName"
    puts $debugLog "parList:"
    foreach item $::ForceFieldToolKit::ChargeOpt::parList {puts $debugLog "\t$item"}
    puts $debugLog "namdbin: $::ForceFieldToolKit::ChargeOpt::namdbin"
    puts $debugLog "log file: $::ForceFieldToolKit::ChargeOpt::outFileName"
    puts $debugLog "-------------------------------------------"
    puts $debugLog "CHARGE CONSTRAINTS SECTION"
    #puts $debugLog "chargeGroups:"
    #foreach item $::ForceFieldToolKit::ChargeOpt::chargeGroups {puts $debugLog "\t$item"}
    puts $debugLog "chargeGroups: $::ForceFieldToolKit::ChargeOpt::chargeGroups"
    #puts $debugLog "chargeInit:"
    #foreach item $::ForceFieldToolKit::ChargeOpt::chargeInit {puts $debugLog "\t$item"}
    puts $debugLog "chargeInit: $::ForceFieldToolKit::ChargeOpt::chargeInit"
    #puts $debugLog "chargeBounds:"
    #foreach item $::ForceFieldToolKit::ChargeOpt::chargeBounds {puts $debugLog "\t$item"}
    puts $debugLog "chargeBounds: $::ForceFieldToolKit::ChargeOpt::chargeBounds"
    puts $debugLog "chargeSum: $::ForceFieldToolKit::ChargeOpt::chargeSum"
    puts $debugLog "-------------------------------------------"
    puts $debugLog "QM TARGET DATA SECTION"
    puts $debugLog "baseLog: $::ForceFieldToolKit::ChargeOpt::baseLog"
    puts $debugLog "watLog: $::ForceFieldToolKit::ChargeOpt::watLog"
    puts $debugLog "logFileList:"
    foreach item $::ForceFieldToolKit::ChargeOpt::logFileList {puts $debugLog "\t$item"}
    #puts $debugLog "atomList:"
    #foreach item $::ForceFieldToolKit::ChargeOpt::atomList {puts $debugLog "\t$item"}
    puts $debugLog "atomList: $::ForceFieldToolKit::ChargeOpt::atomList"
    #puts $debugLog "indWeights:"
    #foreach item $::ForceFieldToolKit::ChargeOpt::indWeights {puts $debugLog "\t$item"}
    puts $debugLog "indWeights: $::ForceFieldToolKit::ChargeOpt::indWeights"
    puts $debugLog "-------------------------------------------"
    puts $debugLog "ADVANCED SETTINGS SECTION"
    puts $debugLog "start: $::ForceFieldToolKit::ChargeOpt::start"
    puts $debugLog "end: $::ForceFieldToolKit::ChargeOpt::end"
    puts $debugLog "delta: $::ForceFieldToolKit::ChargeOpt::delta"
    puts $debugLog "end: $::ForceFieldToolKit::ChargeOpt::end"
    puts $debugLog "offset: $::ForceFieldToolKit::ChargeOpt::offset"
    puts $debugLog "scale: $::ForceFieldToolKit::ChargeOpt::scale"
    puts $debugLog "tol: $::ForceFieldToolKit::ChargeOpt::tol"
    puts $debugLog "dWeight: $::ForceFieldToolKit::ChargeOpt::dWeight"
    puts $debugLog "Optimization mode: $::ForceFieldToolKit::ChargeOpt::mode"
    puts $debugLog "Simulated Annealing Parameters: Temp. $::ForceFieldToolKit::ChargeOpt::saT, Steps $::ForceFieldToolKit::ChargeOpt::saTSteps, Iterations $::ForceFieldToolKit::ChargeOpt::saIter"
    puts $debugLog "Override ReChargeFromPSF: $::ForceFieldToolKit::ChargeOpt::reChargeOverride"
    puts $debugLog "Override Charges: $::ForceFieldToolKit::ChargeOpt::reChargeOverrideCharges"
    puts $debugLog "debug: $::ForceFieldToolKit::ChargeOpt::debug"
    puts $debugLog "=========================================="
    puts $debugLog ""
    flush $debugLog

}
#======================================================
proc ::ForceFieldToolKit::ChargeOpt::buildScript { scriptFileName } {
    # need to localize all variables
    variable psfPath
    variable pdbPath
    variable resName
    variable parList
    variable namdbin
    variable chargeGroups
    variable chargeInit
    variable chargeBounds
    variable chargeSum
    variable baseLog
    variable watLog
    variable logFileList
    variable atomList
    variable indWeights
    variable start
    variable end
    variable delta
    variable offset
    variable scale
    variable tol
    variable dWeight
    variable outFile
    variable outFileName
    variable QMEn
    variable QMDist
    variable molid
    variable simtype
    variable debug
    variable reChargeOverride
    variable reChargeOverrideCharges
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    #variable guiMode

    
    set scriptFile [open $scriptFileName w]
    # load required packages
    puts $scriptFile "\# Load required packages"
    puts $scriptFile "package require forcefieldtoolkit"
    
    # set all chargeOpt variables
    puts $scriptFile "\n\# Set ChargeOpt Variables"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::psfPath $psfPath"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::pdbPath $pdbPath"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::resName $resName"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::parList {$parList}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::namdbin $namdbin"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::outFileName $outFileName"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::chargeGroups {$chargeGroups}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::chargeInit {$chargeInit}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::chargeBounds {$chargeBounds}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::chargeSum $chargeSum"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::baseLog $baseLog"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::watLog $watLog"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::logFileList {$logFileList}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::atomList {$atomList}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::indWeights {$indWeights}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::start $start"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::end $end"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::delta $delta"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::offset $offset"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::scale $scale"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::tol $tol"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::dWeight $dWeight"
    #puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::outFile $outFile"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::QMEn {$QMEn}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::QMDist {$QMDist}"
    #puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::molid $molid"
    #puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::simtype $simtype"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::debug $debug"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::reChargeOverride $reChargeOverride"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::reChargeOverrideCharges {$reChargeOverrideCharges}"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::mode $mode"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::saT $saT"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::saIter $saIter"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::saTSteps $saTSteps"
    puts $scriptFile "set ::ForceFieldToolKit::ChargeOpt::guiMode 0"
        
    # launch the optimization
    puts $scriptFile "\n\# Run the Optimization"
    puts $scriptFile "::ForceFieldToolKit::ChargeOpt::optimize"
    puts $scriptFile "\n\# Return gracefully"
    puts $scriptFile "return 1"
 
    # wrap up
    close $scriptFile
    return
}
#======================================================
