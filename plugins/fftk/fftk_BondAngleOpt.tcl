#
# $Id: fftk_BondAngleOpt.tcl,v 1.3 2012/01/26 22:10:17 johns Exp $
#

#======================================================
namespace eval ::ForceFieldToolKit::BondAngleOpt {
    # variables to declare

    variable psf
    variable pdb
    
    variable name
    variable namdbin
    variable outFile
    variable outFileName

    variable parlist
    variable tempParName
    #variable parFileOpt

    variable bondtypelist
    variable angtypelist
    variable allbondlist
    variable allanglelist
    variable optBondLength
    variable optAngleLength

    variable bondangFCs
    variable bondEqs
    variable angEqs

    variable lbfactor
    variable ubfactor
    variable lbabs
    variable ubabs
    
    variable bondtol
    variable bondscale
    variable angtol
    variable angscale
    
    variable tol
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    
    variable debug
    variable debugLog
    variable guiMode
    variable optCount


}

#======================================================
proc ::ForceFieldToolKit::BondAngleOpt::init {} {
    # localize variables
    variable name
    variable namdbin
    variable outFile
    variable outFileName
    
    variable psf
    variable pdb

    variable parlist
    variable tempParName
    #variable parFileOpt

    variable bondtypelist
    variable angtypelist
    variable allbondlist
    variable allanglelist
    variable optBondLength
    variable optAngleLength

    variable bondangFCs
    variable bondEqs
    variable angEqs

    variable lbfactor
    variable ubfactor
    variable lbabs
    variable ubabs
    
    variable bondtol
    variable bondscale
    variable angtol
    variable angscale
    
    variable tol
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    
    variable debug
    variable debugLog
    variable guiMode
    variable optCount

    
    #==================
    # initialize variables
    set name "min-bondangles"
    set namdbin "namd2"
    set parlist {}
    set tempParName "OPTTEMP.par"
    set outFile {}
    set outFileName "BondAngleOpt.log"
    
    set psf {}
    set pdb {}
    
    #set parFileOpt {}
    set bondtypelist {}
    set angletypelist {}
    set allbondlist {}
    set allanglelist {}
    set optBondLength {}
    set optAngleLength {}
    set bondangFCs {}
    set bondEqs {}
    set angEqs {}
    
    set lbfactor 0.5
    set ubfactor 5.0
    set lbabs 1.0
    set ubabs 600.0
    
    set bondtol 0.02
    set angtol 2.0
    set bondscale 0.03
    set angscale 3.0
    
    set tol 0.001
    set mode "downhill"
    set saT 25
    set saTSteps 20
    set saIter 15
    
    set debug 0
    set debugLog {}
    set guiMode 1
    set optCount 0

}
#======================================================
proc ::ForceFieldToolKit::BondAngleOpt::sanityCheck {} {
    # runs a sanity check on the input information prior to launching optimizatino
    
    # returns 1 if all input is sane
    # returns 0 if there are problems
    
    # localize relevant BondAngleOpt variables
    variable psf
    variable pdb
    variable namdbin
    variable parlist
    
    variable outFileName

    variable bondangFCs
    variable bondEqs
    variable angEqs
    
    variable bondtypelist
    variable angtypelist

    variable lbfactor
    variable ubfactor
    variable lbabs
    variable ubabs
    
    variable tol
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    
    # local variables
    set errorList {}
    set errorText ""
    
    # make sure psf is entered and exists
    if { $psf eq "" } { lappend errorList "No PSF file was specified." } \
    else { if { ![file exists $psf] } { lappend errorList "Cannot find PSF file." } }
    
    # make sure pdb is entered and exists
    if { $pdb eq "" } { lappend errorList "No PDB file was specified." } \
    else { if { ![file exists $pdb] } { lappend errorList "Cannot find PDB file." } }
    
    # make sure namd2 command and/or file exists
    if { $namdbin eq "" } {
        lappend errorList "NAMD binary file (or command if in PATH) was not specified."
    } else { if { [::ExecTool::find $namdbin] eq "" } { lappend errorList "Cannot find NAMD binary file." } }
    
    # make sure that output log name is not empty and directory is writable
    if { $outFileName eq "" } { lappend errorList "Output LOF file was not specified." } \
    else { if { ![file writable [file dirname $outFileName]] } { lappend errorList "Cannot write to output LOG file directory." } }
    
    # make sure there is a parameter file and that it/they exists
    if { [llength $parlist] == 0 } { lappend errorList "No parameter files were specified." } \
    else {
        foreach parFile $parlist {
            if { ![file exists $parFile] } { lappend errorList "Cannot open prm file: $parFile." }
        }
    }
    
    # PARAMETERS
    # make sure that there are force constants (indicative of overall parameter set)
    if { [llength $bondangFCs] == 0 } { lappend errorList "No parameters to optimize." } \
    else {
        # check each force constant
        foreach fc $bondangFCs {
            if { $fc eq "" || $fc < 0 || ![string is double $fc] } { lappend errorList "Found inappropriate force constant." }
        }
        
        # check bond types
        foreach bond $bondtypelist {
            if { [llength $bond] != 2 || [lindex $bond 0] eq "" || [lindex $bond 1] eq "" } { lappend errorList "Found inappropriate bond definition." }
        }

        # check the bond eqs
        foreach beq $bondEqs {
            if { $beq eq "" || $beq < 0 || ![string is double $beq] } { lappend errorList "Found inappropriate b\u2080." }
        }
        
        # check angle types
        foreach angle $angtypelist {
            if { [llength $angle] != 3 || [lindex $angle 0] eq "" || [lindex $angle 1] eq "" || [lindex $angle 2] eq "" } { lappend errorList "Found inappropriate angle definition." }
        }
        
        # check the angle eqs
        foreach aeq $angEqs {
            if { $aeq eq "" || ![string is double $aeq] } { lappend errorList "Found inappropriate \u03F4." }
        }
    }
    
    # check bounds
    if { $lbabs eq "" || $lbabs < 0 || ![string is double $lbabs] } { lappend errorList "Found inappropriate lower absolute bound." }
    if { $ubabs eq "" || $ubabs < 0 || ![string is double $ubabs] } { lappend errorList "Found inappropriate upper absolute bound." }
    if { $lbfactor eq "" || $lbfactor < 0 || ![string is double $lbfactor] } { lappend errorList "Found inappropriate lower relative bound." }
    if { $ubfactor eq "" || $ubfactor < 0 || ![string is double $ubfactor] } { lappend errorList "Found inappropriate upper relative bound." }
    
    # ADVANCED SETTINGS
    # optimizer settings
    if { [lsearch -exact {downhill {simulated annealing}} $mode] == -1 } { lappend errorList "Unsupported optimization mode." } \
    else {
        # check tol
        if { $tol eq "" || $tol < 0 || ![string is double $tol] } { lappend errorList "Found inappropriate optimization tolerance setting." }
        # check simulated annealing parameters
        if { $mode eq "simulated annealing" } {
            if { $saT eq "" || ![string is double $saT] } { lappend errorList "Found inappropriate saT setting." }
            if { $saTSteps eq "" || $saTSteps < 0 || ![string is integer $saTSteps] } { lappend errorList "Found inappropriate saTSteps setting." }
            if { $saIter eq "" || $saTSteps < 0 || ![string is integer $saIter] } { lappend errorList "Found inappropriate saIter setting." }
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
proc ::ForceFieldToolKit::BondAngleOpt::optimize {} {
    # localize some variables (only the necessary ones)
    variable outFile
    variable outFileName
    variable name
    
    variable psf
    variable pdb

    variable bondtypelist
    variable angtypelist
    variable bondangFCs
    variable bondEqs
    variable angEqs
    variable allbondlist
    variable allanglelist
    variable optBondLength
    variable optAngleLength
    
    variable lbfactor
    variable ubfactor
    variable lbabs
    variable ubabs
 
    variable parlist
    variable tempParName

    variable tol
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    
    variable debug
    variable debugLog
    variable guiMode
    variable optCount


    #----------------------------------------
    
    if { $guiMode } {
        # run a sanity check
        if { ![::ForceFieldToolKit::BondAngleOpt::sanityCheck] } { return }
    }
    
    # open the log file
    set outFile [open $outFileName w]
    
    # if in debugging mode, open output file
    if { $debug } {
        set debugLog [open "[file rootname [file tail $outFileName]].debug.log" w]
        # run a proc to print settings
        ::ForceFieldToolKit::BondAngleOpt::printSettings $debugLog
    }
    
    # name for NAMD minimization (arbitrary)
    set name min-bondangles
    
    if { $debug } {
        puts $debugLog ""
        #puts $debugLog "Parameters Read In from $parFileOpt:\n$params"
        puts $debugLog ""
        puts $debugLog "bondtypelist:\n$bondtypelist"
        puts $debugLog "angtypelist:\n$angtypelist"
        puts $debugLog "bondangFCs:\n$bondangFCs"
        puts $debugLog "bondEqs:\n$bondEqs"
        puts $debugLog "angEqs:\n$angEqs"
        puts $debugLog ""
        flush $debugLog
    }
    

    # build initial values and bounds lists for force constants (FC)
    set init {}
    set bounds {}
    foreach ele $bondangFCs {
       lappend init $ele
       if {$lbabs > [expr $lbfactor*$ele]} {
          set lb $lbabs
       } else {
          set lb [expr $lbfactor*$ele]
       }
       if {$ubabs < [expr $ubfactor*$ele]} {
          set ub $ubabs
       } else {
          set ub [expr $ubfactor*$ele]
       }
       lappend bounds "$lb $ub"
    }
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "init:\n$init"
        puts $debugLog "bounds:\n$bounds"
        puts $debugLog ""
        flush $debugLog
    }
    
    
    # ?
    set scale 2.0
    
    # write some info to log
    puts $outFile "init: $init"
    puts $outFile "bounds: $bounds"
    puts $outFile "scale: $scale"
    
    # need a list of all bonds and angles and the QM optimized
    # values for each to compare against during optimization
    mol new $psf
    mol addfile $pdb
    set sel [atomselect top all]
    
    set allbondlist [topo -sel $sel getbondlist]
    foreach bond $allbondlist {
       lappend optBondLength [measure bond "[lindex $bond 0] [lindex $bond 1]"]
    }
    
    set allanglelist [topo -sel $sel getanglelist]
    foreach angle $allanglelist {
       lappend optAngleLength [measure angle "[lindex $angle 1] [lindex $angle 2] [lindex $angle 3]"]
    }
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "allbondlist:\n$allbondlist"
        puts $debugLog "allanglelist:\n$allanglelist"
        puts $debugLog ""
        flush $debugLog
    }
    
    # NO LONGER NECESSARY; to ensure that additional parameters (e.g., LJ) make it in, include in parlist box
    # add the parFileOpt to the parlist to make sure that LJ parameters make it in
    #lappend parlist $parFileOpt

    # also need to include the prm filename that the optimize routine will modify on the fly
    # however, the file itself will actually be written from inside the optimization routine
    set tempParName "OPTTEMP.par"
    lappend parlist $tempParName
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "Final parlist:\n$parlist"
        puts $debugLog ""
        flush $debugLog
    }
    
    # write a namd configuration file used for minimization
    # note that this proc is currently in the ChargeOpt namespace
    # consider moving to ::ForceFieldToolKit::shared::
    ::ForceFieldToolKit::ChargeOpt::writeMinConf $name $psf $pdb $parlist
    
    # reset the optCount, used to update the GUI on the status of the optimization
    if { $guiMode } {
        set optCount 0
        set ::ForceFieldToolKit::gui::baoptStatus "Running...Optimizing(iter:$optCount)"
        update idletasks
    }
    
    ## can do simple downhill optimization or simulated annealing
    # will set this up as an option from GUI later (much like chargeopt)
    if { $mode eq "downhill" } {
        set opt [optimization -downhill -tol $tol -function ::ForceFieldToolKit::BondAngleOpt::optBondsAngles]
    } elseif { $mode eq "simulated annealing" } {
        set opt [optimization -annealing -tol $tol -T $saT -iter $saIter -Tsteps $saTSteps -function ::ForceFieldToolKit::BondAngleOpt::optBondsAngles]
    } else {
        puts "ERROR - Unknown optimization mode.\nDownhill and Simulated Annealing are only currently supported modes"
        puts $outFile "ERROR - Unknown optimization mode.\nDownhill and Simulated Annealing are only currently supported modes"
        if { $debug } {
            puts $debugLog "ERROR - Unknown optimization mode."
            puts $debugLog "Only Downhill and Simulated Annealing are currently supported"
            puts $debugLog "Current mode set to: $mode"
        }
        return -1
    }
    
    $opt configure -bounds $bounds
    $opt initsimplex $init $scale

    if { $debug } {
        puts $debugLog ""
        puts $debugLog "optimization setup:"
        puts $debugLog "optimization -downhill -tol $tol -function ::ForceFieldToolKit::optBondsAngles"
        puts $debugLog ""
        flush $debugLog
    }

    # run
    set result [$opt start]
    # write output to log file
    puts $outFile "Raw Result:\n$result"

    # write clearly formatted output to the log file (for import into BuildPar)
    puts $outFile "\nFINAL PARAMETERS"
    # write bonds
    for {set i 0} {$i < [llength $bondtypelist]} {incr i} {
        puts $outFile "[list bond [lindex $bondtypelist $i] [lindex $result 0 $i] [lindex $bondEqs $i]]"
    }
    # write angles
    for {set i 0} {$i < [llength $angtypelist]} {incr i} {
        puts $outFile "[list angle [lindex $angtypelist $i] [lindex $result 0 [expr {[llength $bondtypelist] + $i}]] [lindex $angEqs $i]]"
    }
    puts $outFile "END\n"
    
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "Opt Result:\n$result"
        puts $debugLog ""
        flush $debugLog
    }
    
    # provide some results
    # NEED SOMETHING HERE
    # for the time being,
    puts $result
    
    # cleanup
    file delete $tempParName
    file delete $name.conf
    file delete $name.log
    foreach out {coor vel xsc} {
       file delete $name.$out
       file delete $name.$out.BAK
       file delete $name.restart.$out
       file delete $name.restart.$out.old
    }
    close $outFile
    mol delete top
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "DONE"
        puts $debugLog ""
        flush $debugLog
        close $debugLog
    }

}
#======================================================
proc ::ForceFieldToolKit::BondAngleOpt::optBondsAngles { bondangleFCs } {
    # localize necessary variables
    variable tempParName
    variable outFile
    variable name
    variable namdbin
    
    variable bondtypelist
    variable angtypelist
    variable bondangFCs
    variable bondEqs
    variable angEqs
    variable allbondlist
    variable allanglelist
    variable optBondLength
    variable optAngleLength
    
    variable bondscale
    variable angscale
    variable bondtol
    variable angtol
    
    variable debug
    variable debugLog
    variable guiMode
    variable optCount

    #-------------------------------------------------------
    #have to write the parameter file in optimize function
    #opt function takes two lists containing bond FCs and angle FCs
    #pass bondEqs, angEqs, bondangFCs, tempParName, name 
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "OptInput:\n$bondangleFCs"
        puts $debugLog ""
        flush $debugLog
    }
    
    # writeParamFile for the current set of bond/angle parameters
    set outParam [open "$tempParName" w]
    puts $outParam "BONDS"
    for {set i 0} {$i < [llength $bondtypelist]} {incr i} {
       set curFC [lindex $bondangleFCs $i]
       puts $outParam "[lindex $bondtypelist $i] $curFC [lindex $bondEqs $i]"
    }
    puts $outParam "\nANGLES"
    for {set i 0} {$i < [llength $angtypelist]} {incr i} {
       set curFC [lindex $bondangleFCs [expr $i + [llength $bondtypelist]]]
       puts $outParam "[lindex $angtypelist $i] $curFC [lindex $angEqs $i]"
    }
    puts $outParam "\nEND"
    close $outParam
    
    # a system call is bad.  removed until alternative.
    #if { $debug } {
    #    puts $debugLog ""
    #    puts $debugLog "Parameter file written:"
    #    puts $debugLog "[exec cat $tempParName]"
    #    puts $debugLog ""
    #    flush $debugLog
    #}

    # write the current bond/angle parameters to log file    
    puts -nonewline $outFile "Current bond force constants: "
    for {set i 0} {$i < [llength $bondtypelist]} {incr i} {
       puts -nonewline $outFile [format "[lindex $bondtypelist $i] %2.3f   " [lindex $bondangleFCs $i]]
    }
    puts -nonewline $outFile "\nCurrent angle force constants: "
    for {set i 0} {$i < [llength $angtypelist]} {incr i} {
       puts -nonewline $outFile [format "[lindex $angtypelist $i] %2.3f   " [lindex $bondangleFCs [expr $i + [llength $bondtypelist]]]]
    }
    puts $outFile ""

    #run namd min
    ::ExecTool::exec $namdbin $name.conf > $name.log
    mol addfile $name.coor
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "NAMD run complete"
        puts $debugLog ""
        flush $debugLog
    }

    #measure bonds, angles, compare to frame 0 (QM length)   
    set Obj 0

    for {set i 0} {$i < [llength $allbondlist]} {incr i} {
       set curbond [lindex $allbondlist $i]
       set length [measure bond "[lindex $curbond 0] [lindex $curbond 1]" last]
       set optL [lindex $optBondLength $i]
       puts $outFile [format "Bond: $curbond  QM: %1.3f  MM: %1.3f  delta: %1.3f" $optL $length [expr $length - $optL]]
       if { [expr abs($length - $optL)] > $bondtol } {
          set Obj [expr $Obj + 1*pow(($length - $optL)/$bondscale,2)]
       }
    }

    for {set i 0} {$i < [llength $allanglelist]} {incr i} {
       set curangle [lindex $allanglelist $i]
       set length [measure angle "[lindex $curangle 1] [lindex $curangle 2] [lindex $curangle 3]" last]
       set optL [lindex $optAngleLength $i]
       puts $outFile [format "Angle: [lrange $curangle 1 4] QM: %1.3f  MM: %1.3f  delta: %1.3f" $optL $length [expr $length - $optL]]
       if { [expr abs($length - $optL)] > $angtol } {
          set Obj [expr $Obj + 1*pow(($length - $optL)/$angscale,2)]
       }
    }
    puts $outFile "Current objective value: $Obj\n\n\n"
    
    if { $debug } {
        puts $debugLog ""
        puts $debugLog "Current objective value: $Obj"
        puts $debugLog ""
        flush $debugLog
    }

    animate delete beg 1 end 1
    
    # update the status in the gui
    if { $guiMode } {
        incr optCount
        set ::ForceFieldToolKit::gui::baoptStatus "Running...Optimizing(iter:$optCount)"
        update idletasks
    }

    return $Obj

}
#======================================================
proc ::ForceFieldToolKit::BondAngleOpt::buildScript { scriptFilename } {

    # localize variables
    #--------------------------
    variable outFile
    variable outFileName
    variable name
    variable psf
    variable pdb
    variable bondtypelist
    variable angtypelist
    variable bondangFCs
    variable bondEqs
    variable angEqs
    variable allbondlist
    variable allanglelist
    variable optBondLength
    variable optAngleLength   
    variable lbfactor
    variable ubfactor
    variable lbabs
    variable ubabs
    variable parlist
    variable tempParName
    variable tol
    variable mode
    variable saT
    variable saTSteps
    variable saIter
    variable bondtol
    variable bondscale
    variable angtol
    variable angscale
    variable debug
    variable debugLog
    variable guiMode
    variable optCount
    
    #--------------------------
    
    set scriptFile [open $scriptFilename w]
    # load required packages
    puts $scriptFile "\# Load required packages"
    puts $scriptFile "package require namdenergy"
    puts $scriptFile "package require optimization"
    puts $scriptFile "package require topotools"
    
    # this will need to change once ParaToolExt is officially named
    puts $scriptFile "package require ParaToolExt"
    
    # Variables to set
    puts $scriptFile "\n\# Setup the Environment"
    # outFile is hardcoded
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::outFileName $outFileName"
    # name is hardcoded
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::psf $psf"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::pdb $pdb"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::bondtypelist $bondtypelist"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::angtypelist $angtypelist"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::bondangFCs $bondangFCs"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::bondEqs $bondEqs"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::angEqs $angEqs"
    # allbondlist is set internally
    # allanglelist is set internally
    # optBondLength is set internally
    # optAngleLength is set internally
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::lbfactor $lbfactor"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::ubfactor $ubfactor"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::lbabs $lbabs"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::ubabs $ubabs"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::parlist $parlist"
    # tempParName is hardcoded
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::tol $tol"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::mode $mode"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::saT $saT"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::saTSteps $saTSteps"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::saIter $saIter"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::bondtol $bondtol"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::bondscale $bondscale"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::angtol $angtol"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::angscale $angscale"
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::debug $debug"
    # debugLog is hardcoded
    puts $scriptFile "set ::ForceFieldToolKit::BondAngleOpt::guiMode 0"
    # optCount is irrelevant when guiMode = 0

    #--------------------------
    
    # launch the optimization
    puts $scriptFile "\n\# Run the Optimization"
    puts $scriptFile "::ForceFieldToolKit::BondAngleOpt::optimize"
    puts $scriptFile "\n\# Return gracefully"
    puts $scriptFile "return 1"
    
    # wrap up
    close $scriptFile
    return
}
#======================================================
proc ::ForceFieldToolKit::BondAngleOpt::printSettings { outfile } {
    # a tool to print all settings passsed to the bonds/angles
    # optimization routine, and any relevant settings in the 
    # BondAngleOpt namespace that will be accessed during the
    # optimization
    
    puts $outfile "=================================="
    puts $outfile " Bond/Angle Optimization Settings "
    puts $outfile "=================================="
    puts $outfile ""
    
    puts $outfile "INPUT"
    puts $outfile "psf: $::ForceFieldToolKit::BondAngleOpt::psf"
    puts $outfile "pdb: $::ForceFieldToolKit::BondAngleOpt::pdb"
    puts $outfile "Parameter Files:"
    foreach par $::ForceFieldToolKit::BondAngleOpt::parlist { puts $outfile "\t$par" }
    puts $outfile "namdbin: $::ForceFieldToolKit::BondAngleOpt::namdbin"
    puts $outfile "outFileName: $::ForceFieldToolKit::BondAngleOpt::outFileName"
    puts $outfile "----------------------------------"
    puts $outfile ""
    
    puts $outfile "PARAMETERS TO OPTIMIZE SECTION"
    puts $outfile "bondtypelist: $::ForceFieldToolKit::BondAngleOpt::bondtypelist"
    puts $outfile "angletypelist: $::ForceFieldToolKit::BondAngleOpt::angtypelist"
    puts $outfile "bondangFCs: $::ForceFieldToolKit::BondAngleOpt::bondangFCs"
    puts $outfile "bondEqs: $::ForceFieldToolKit::BondAngleOpt::bondEqs"
    puts $outfile "angEqs: $::ForceFieldToolKit::BondAngleOpt::angEqs"
    puts $outfile "lbfactor: $::ForceFieldToolKit::BondAngleOpt::lbfactor"
    puts $outfile "ubfactor: $::ForceFieldToolKit::BondAngleOpt::ubfactor"
    puts $outfile "lbabs: $::ForceFieldToolKit::BondAngleOpt::lbabs"
    puts $outfile "ubabs: $::ForceFieldToolKit::BondAngleOpt::ubabs"
    puts $outfile "----------------------------------"
    puts $outfile ""
    
    puts $outfile "ADVANCED SETTINGS"
    puts $outfile "tol: $::ForceFieldToolKit::BondAngleOpt::tol"
    puts $outfile "optimization mode: $::ForceFieldToolKit::BondAngleOpt::mode"
    puts $outfile "Simulated Annealing settings: Temp-$::ForceFieldToolKit::BondAngleOpt::saT, Steps-$::ForceFieldToolKit::BondAngleOpt::saTSteps, Iterations-$::ForceFieldToolKit::BondAngleOpt::saIter"
    puts $outfile "bondtol: $::ForceFieldToolKit::BondAngleOpt::bondtol"
    puts $outfile "bondscale: $::ForceFieldToolKit::BondAngleOpt::bondscale"
    puts $outfile "angtol: $::ForceFieldToolKit::BondAngleOpt::angtol"
    puts $outfile "angscale: $::ForceFieldToolKit::BondAngleOpt::angscale"
    puts $outfile "debugging: $::ForceFieldToolKit::BondAngleOpt::debug"
    puts $outfile "----------------------------------"
    puts $outfile ""
    
    puts $outfile "HARDCODED SETTINGS (set by init)"
    puts $outfile "name: $::ForceFieldToolKit::BondAngleOpt::name"
    puts $outfile "tempParName: $::ForceFieldToolKit::BondAngleOpt::tempParName"
    puts $outfile "----------------------------------"    
    
    flush $outfile
    
}
#======================================================

