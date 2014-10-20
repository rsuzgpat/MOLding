#
# $Id: fftk_GenBonded.tcl,v 1.3 2012/01/26 22:10:18 johns Exp $
#

#======================================================
namespace eval ::ForceFieldToolKit::GenBonded:: {

    variable geomCHK
    variable com
    variable qmProc
    variable qmMem
    variable qmRoute
    
    variable psf
    variable pdb
    variable templateParFile
    variable glog
    variable blog
    
}
#======================================================
proc ::ForceFieldToolKit::GenBonded::init {} {

    # localize variables
    variable geomCHK
    variable com
    variable qmProc
    variable qmMem
    variable qmRoute
    
    variable psf
    variable pdb
    variable templateParFile
    variable glog
    variable blog
    
    # set variables to initial state
    set geomCHK {}
    set com "hess.gau"
    set qmProc 1
    set qmMem 1
    set qmRoute "\# MP2/6-31G* Geom=(AllCheck,NewRedundant) Freq NoSymm Pop=(ESP,NPA) IOp(6/33=2,7/33=1) SCF=Tight"
    
    set psf {}
    set pdb {}
    set templateParFile {}
    set glog {}
    set blog "BondedCalc.log"
    
}
#======================================================
proc ::ForceFieldToolKit::GenBonded::sanityCheck { procType } {
    # checks to make sure that input is sane
    
    # returns 1 if everything looks OK
    # returns 0 if there is a problem
    
    # localize GenBonded variables
    variable geomCHK
    variable com
    variable qmProc
    variable qmMem
    variable qmRoute
    
    variable psf
    variable pdb
    variable templateParFile
    variable glog
    variable blog

    # local variables
    set errorList {}
    set errorText ""
    
    # build the error list based on what proc is checked
    switch -exact $procType {
        writeComFile {
            # validate gaussian settings (not particularly vigorous validation)
            # qmProc (processors)
            if { $qmProc eq "" } { lappend errorList "No processors were specified." }
            if { $qmProc <= 0 || $qmProc != [expr int($qmProc)] } { lappend errorList "Number of processors must be a positive integer." }
            # qmMem (memory)
            if { $qmMem eq "" } { lappend errorList "No memory was specified." }
            if { $qmMem <= 0 || $qmMem != [expr int($qmMem)]} { lappend errorList "Memory must be a postive integer." }
            # qmRoute (route card for gaussian; just make sure it isn't empty)
            if { $qmRoute eq "" } { lappend errorList "Route card is empty." }

            # make sure that geometry CHK is specified and exists
            if { $geomCHK eq "" } {
                lappend errorList "Checkpoint file from geometry optimization was not specified."
            } else {
                if { ![file exists $geomCHK] } { lappend errorList "Cannot find geometry optimization checkpoint file." }
            }
            
            # make sure that com file is specified and output dir is writable
            if { $com eq "" } {
                lappend errorList "Output COM file was not specified."
            } else {
                if { ![file writable [file dirname $com]] } { lappend errorList "Cannot write to output directory." }
            }
            
        }
        
        calcBonded {
            # make sure that psf is entered and exists
            if { $psf eq "" } {
                lappend errorList "No PSF file was specified."
            } else {
                if { ![file exists $psf] } { lappend errorList "Cannot find PSF file." }
            }
            
            # make sure that pdb is entered and exists
            if { $pdb eq "" } {
                lappend errorList "No PDB file was specified."
            } else {
                if { ![file exists $pdb] } { lappend errorList "Cannot find PDB file." }
            }
            
            # make sure that template par file is entered and exists
            if { $templateParFile eq "" } {
                lappend errorList "No template parameter file was specified."
            } else {
                if { ![file exists $templateParFile] } { lappend errorList "Cannot find template parameter file." }
            }

            # make sure that gaussian log file is enetered and exists
            if { $glog eq "" } {
                lappend errorList "No Gaussian log file was specified."
            } else {
                if { ![file exists $glog] } { lappend errorList "Cannot find Gaussian log file." }
            }
            
            # make sure that output file is specified and output dir is writable
            if { $blog eq "" } {
                lappend errorList "Output file was not specified."
            } else {
                if { ![file writable [file dirname $blog]] } { lappend errorList "Cannot write to output directory." }
            }

        }
    }

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
proc ::ForceFieldToolKit::GenBonded::writeComFile {} {
    # writes the gaussian input file for the hessian calculation
    
    # localize necessary variables
    variable geomCHK
    variable com
    variable qmProc
    variable qmMem
    variable qmRoute
    
    # sanity check should go here
    if { ![::ForceFieldToolKit::GenBonded::sanityCheck writeComFile] } { return }
    
    # make a copy of the CHK file
    set newCHKname "[file rootname $com].chk"
    file copy $geomCHK $newCHKname
    
    # write the com file
    set outfile [open $com w]
    puts $outfile "%chk=$newCHKname"
    puts $outfile "%nproc=$qmProc"
    puts $outfile "%mem=$qmMem"
    puts $outfile "$qmRoute"
    puts $outfile "\n"
    close $outfile
    
}
#======================================================
proc ::ForceFieldToolKit::GenBonded::calcBonded {} {
    # averages bond and angle parameters from internal coordinates (hess)
    # for bonds and angles in template parameter file
    
    # localize variables
    variable psf
    variable pdb
    variable templateParFile
    variable glog
    variable blog
    
    # sanity check should go here
    if { ![::ForceFieldToolKit::GenBonded::sanityCheck calcBonded] } { return }
    
    ::ForceFieldToolKit::gui::consoleMessage "Bonded parameters calculation started"
    
    # open the log file for output
    set outfile [open $blog w]
    puts $outfile "Bonded Parameters from Hessian Transformation\n"
    puts $outfile "FINAL PARAMETERS"
    flush $outfile
    
    # setup the template parameters based on init file
    # read in the template parameter file
    set templatePars [::ForceFieldToolKit::SharedFcns::readParFile $templateParFile]
    
    # build an array for bonds and angles
    array set templateBonds {}
    foreach bond [lindex $templatePars 0] {
        #                    {type def}                {k  b0}          {comment}
        set templateBonds([lindex $bond 0]) [list [lindex $bond 1] [lindex $bond 2]]
    }
    array set templateAngles {}
    foreach angle [lindex $templatePars 1] {
        #                       {type def}              {k  theta}       {ksub   s}         {comment}
        set templateAngles([lindex $angle 0]) [list [lindex $angle 1] [lindex $angle 2] [lindex $angle 3]]
    }

    
    # load the typed molecule
    mol new $psf
    mol addfile $pdb
    set moleculeID [molinfo top]
    
    # load the Gaussian Log files from the hessian calculation
    set logID [mol new]
    ::QMtool::use_vmd_molecule $logID
    ::QMtool::load_gaussian_log $glog $logID
        
    # grab the internal coords, which contains the parameters of interest
    set internal_coords [::QMtool::get_internal_coordinates]
    
    # build a bonds prm section from internal coordinates
    set bonds {}
    foreach entry [lsearch -inline -all -index 1 $internal_coords "bond"] {
        set inds [lindex $entry 2]
        set pars [lindex $entry 4]
        set temp [atomselect $moleculeID "index $inds"]
        set typeDef [$temp get type]
        
        # {                  {type def} {k b} {comment}   }
        lappend bonds [list $typeDef $pars {}]
        
        $temp delete
    }
    
    # build an angles prm section from internal coordinates
    set angles {}
    foreach entry [lsearch -inline -all -index 1 $internal_coords "angle"] {
        set inds [lindex $entry 2]
        set pars [lindex $entry 4]
        set temp [atomselect $moleculeID "index $inds"]
        set typeDef [$temp get type]
        
        #                 {   {typeDef} {k theta} {comment}    }
        lappend angles [list $typeDef $pars {}]
        
        $temp delete
    }
    

    # Now average duplicate parameters and update only those
    # found in the template parameter file
    
    # BONDS
    # initialize some variables
    set b_list {}
    set b_rts {}
    # cycle through each bond definition
    foreach bondEntry $bonds {
        # parse out parameter data
        # { {bond type def} {k b} {comment} }
        set typeDef [lindex $bondEntry 0]
        set k [lindex $bondEntry 1 0]
        set b [lindex $bondEntry 1 1]
        
        # test (forward and reverse)
        set testfwd [lsearch -exact $b_list $typeDef]
        set testrev [lsearch -exact $b_list [lreverse $typeDef]]
        
        if { $testfwd == -1 && $testrev == -1 } {
            # new bond type definition, append all values
            lappend b_list $typeDef
            lappend b_rts [list $k $b 1]
        } else {
            if { $testfwd > -1 } {
                set ind $testfwd
            } else {
                set ind $testreb
            }
            # repeat type definition found, add to running totals
            lset b_rts $ind 0 [expr {[lindex $b_rts $ind 0] + $k}]
            lset b_rts $ind 1 [expr {[lindex $b_rts $ind 1] + $b}]
            lset b_rts $ind 2 [expr {[lindex $b_rts $ind 2] + 1}]
        }
    }

    # update the bonds array
    for {set i 0} {$i < [llength $b_list]} {incr i} {
        # if the paratool bond is present in the template, update the k and b0 values
        if { [info exists templateBonds([lindex $b_list $i])] } {
            # calc the avg values from running totals data (b_rts)
            set avgK [expr {[lindex $b_rts $i 0]/[lindex $b_rts $i 2]}]
            set avgB0 [expr {[lindex $b_rts $i 1]/[lindex $b_rts $i 2]}]
            # update the value in the templateBonds array
            lset templateBonds([lindex $b_list $i]) 0 [list $avgK $avgB0]     
        }
        # else, we don't really care
    }    
    

    # write the relevent updated bonds to the log file
    foreach key [array names templateBonds] {
        puts $outfile "[list bond $key [lindex $templateBonds($key) 0 0] [lindex $templateBonds($key) 0 1]]"
        #puts $outfile "[list bond $key [lindex $templateBonds($key) 0] [lindex $templateBonds($key) 1]]"
    }

    # DONE with BONDS


    # ANGLES
    # initialize some variables
    set a_list {}
    set a_rts {}
    set a_rtsub {}
    
    # cycle through each angle definition
    foreach angleEntry $angles {
        # parse out parameter data
        set typeDef [lindex $angleEntry 0]
        set k [lindex $angleEntry 1 0]
        set theta [lindex $angleEntry 1 1]
        set kub [lindex $angleEntry 2 0]
        set s [lindex $angleEntry 2 1]
        
        # test (forward and reverse)
        set testfwd [lsearch -exact $a_list $typeDef]
        set testrev [lsearch -exact $a_list [lreverse $typeDef]]
        if { $testfwd == -1 && $testrev == -1 } {
            # new angle definition, append all data
            lappend a_list $typeDef
            lappend a_rts [list $k $theta 1]
            # handle angle UB term, empty or not
            if { $kub ne "" } {
                lappend a_rtsub [list $kub $s 1]
            } else {
                lappend a_rtsub [list {} {} 0]
            }
        } else {
            # duplicate definition, update running totals and count
            if { $testfwd > -1 } {
                set ind $testfwd
            } else {
                set ind $testrev
            }
            # update angle totals and count
            lset a_rts $ind 0 [expr {[lindex $a_rts $ind 0] + $k}]
            lset a_rts $ind 1 [expr {[lindex $a_rts $ind 1] + $theta}]
            lset a_rts $ind 2 [expr {[lindex $a_rts $ind 2] + 1}]
            # for UB term, update if not empty string (just ignore empty strings)
            if { $kub ne "" } {
                # how the term is updated depends on whether there are any UB terms stored already
                # i.e., if the count is above 0 we need to update, otherwise, just replace
                if { [lindex $a_rtsub $ind 2] > 0 } {
                    lset a_rtsub $ind 0 [expr {[lindex $a_rtsub $ind 0] + $kub}]
                    lset a_rtsub $ind 1 [expr {[lindex $a_rtsub $ind 1] + $s}]
                    lset a_rtsub $ind 2 [expr {[lindex $a_rtsub $ind 2] + 1}]
                } else {
                    lset a_rtsub $ind 0 $kub
                    lset a_rtsub $ind 1 $s
                    lset a_rtsub $ind 2 1
                }
            }; # end of UB term if
        }; # end of angles test
    }; # end of angles loop
    
    # update the angles array
    for {set i 0} {$i < [llength $a_list]} {incr i} {
        # if the paratool angle is present in the template, update the values
        if { [info exists templateAngles([lindex $a_list $i])] } {
            # calc the avg values from angle running totals
            set avgK [expr {[lindex $a_rts $i 0]/[lindex $a_rts $i 2]}]
            set avgTheta [expr {[lindex $a_rts $i 1]/[lindex $a_rts $i 2]}]
            # update the angles data in the angles array
            lset templateAngles([lindex $a_list $i]) 0 [list $avgK $avgTheta]
            
            # if kub and s are defined (count greater than zero), average them
            # otherwise set as undefined
            if { [lindex $a_rtsub $i 2] > 0 } {
                set avgKub [expr {[lindex $a_rtsub $i 0]/[lindex $a_rtsub $i 2]}]
                set avgS [expr {[lindex $a_rtsub $i 1]/[lindex $a_rtsub $i 2]}]
                # update with value
                lset templateAngles([lindex $a_list $i]) 1 [list $avgKub $avgS]
            } else {
                # update as undefined
                lset templateAngles([lindex $a_list $i]) 1 [list {} {}]
            }
        }
        # else, we don't care about the values
    }
    
    # write the relevant angles to the log file
    foreach key [array names templateAngles] {
        puts $outfile "[list angle $key [lindex $templateAngles($key) 0 0] [lindex $templateAngles($key) 0 1]]"
        #puts $outfile "[list angle $key [lindex $templateAngles($key) 0] {} {}]"
        #puts $outfile "[list angle $key [lindex $templateAngles($key) 0] [lindex $templateAngles($key) 1] [lindex $templateAngles($key) 2]]"
    }
    
    # DONE with ANGLES


    puts $outfile "END\n"
    
    # clean up
    mol delete $moleculeID
    mol delete $logID
    close $outfile
    
    ::ForceFieldToolKit::gui::consoleMessage "Bonded parameters calculation finished"

}
#======================================================
