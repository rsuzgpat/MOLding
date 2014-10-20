#
# $Id: fftk_GenZMatrix.tcl,v 1.3 2012/01/26 22:10:18 johns Exp $
#

#======================================================
namespace eval ::ForceFieldToolKit::GenZMatrix:: {

    variable psfPath
    variable pdbPath
    variable outFolderPath
    variable basename
    
    variable donList
    variable accList
    variable atomLabels
    variable vizSpheresDon
    variable vizSpheresAcc
    
    variable qmProc
    variable qmMem
    variable qmRoute
    variable qmCharge
    variable qmMult

}
#======================================================
proc ::ForceFieldToolKit::GenZMatrix::init {} {

    # IO variables
    variable psfPath
    variable pdbPath
    variable outFolderPath
    variable basename

    # Hydrogen Bonding Variables    
    variable donList
    variable accList

    # QM Input File Variables   
    variable qmProc
    variable qmMem
    variable qmRoute
    variable qmCharge
    variable qmMult
    
    # Initialize
    set psfPath {}
    set pdbPath {}
    set outFolderPath {}
    set basename {}
    set donList {}
    set accList {}
    set qmProc 1
    set qmMem 1
    set qmCharge 0
    set qmMult 1
    set qmRoute "# RHF/6-31G* Opt=(Z-matrix,MaxCycles=100)"


}
#======================================================
proc ::ForceFieldToolKit::GenZMatrix::sanityCheck {} {
    # checks to see that appropriate information is set prior to running
    
    # returns 1 if all input is sane
    # returns 0 if there is a problem
    
    # localize relevant GenZMatrix variables
    variable psfPath
    variable pdbPath
    variable outFolderPath
    variable basename
    
    variable donList
    variable accList
    
    variable qmProc
    variable qmMem
    variable qmRoute
    variable qmCharge
    variable qmMult
    
    # local variables
    set errorList {}
    set errorText ""
    
    # checks
    # make sure that psfPath is entered and exists
    if { $psfPath eq "" } {
        lappend errorList "No PSF file was specified."
    } else {
        if { ![file exists $psfPath] } { lappend errorList "Cannot find PSF file." }
    }
    
    # make sure that pdbPath is entered and exists
    if { $pdbPath eq "" } {
        lappend errorList "No PDB file was specified."
    } else {
        if { ![file exists $pdbPath] } { lappend errorList "Cannot find PDB file." }
    }
    
    # make sure that outFolderPath is specified and writable
    if { $outFolderPath eq "" } {
        lappend errorList "No output path was specified."
    } else {
        if { ![file writable $outFolderPath] } { lappend errorList "Cannot write to output path." }
    }
    
    # make sure that basename is not empty
    if { $basename eq "" } { lappend errorList "No basename was specified." }
    
    # it's OK if donor and/or acceptor lists are emtpy, nothing will be written
    
    # validate gaussian settings (not particularly vigorous validation)
    # qmProc (processors)
    if { $qmProc eq "" } { lappend errorList "No processors were specified." }
    if { $qmProc <= 0 || $qmProc != [expr int($qmProc)] } { lappend errorList "Number of processors must be a positive integer." }
    # qmMem (memory)
    if { $qmMem eq "" } { lappend errorList "No memory was specified." }
    if { $qmMem <= 0 || $qmMem != [expr int($qmMem)]} { lappend errorList "Memory must be a postive integer." }
    # qmCharge (charge)
    if { $qmCharge eq "" } { lappend errorList "No charge was specified." }
    if { $qmCharge != [expr int($qmCharge)] } { lappend errorList "Charge must be an integer." }
    # qmMult (multiplicity)
    if { $qmMult eq "" } { lappend errorList "No multiplicity was specified." }
    if { $qmMult < 0 || $qmMult != [expr int($qmMult)] } { lappend errorList "Multiplicity must be a positive integer." }
    # qmRoute (route card for gaussian; just make sure it isn't empty)
    if { $qmRoute eq "" } { lappend errorList "Route card is empty." }
    

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
proc ::ForceFieldToolKit::GenZMatrix::genZmatrix {} {
    # writes Gaussian input files for calculating water interaction energies

    # initialize some variables
    variable outFolderPath
    variable basename
    variable donList
    variable accList
    variable qmProc
    variable qmMem
    variable qmRoute
    variable qmCharge
    variable qmMult
    
    # run sanity check
    if { ![::ForceFieldToolKit::GenZMatrix::sanityCheck] } { return }
    
    
    # assign Gaussian atom names and gather x,y,z for output com file
    set Gnames {}
    set atom_info {}
    for {set i 0} {$i < [molinfo top get numatoms]} {incr i} {
        set temp [atomselect top "index $i"]
        lappend atom_info [list [$temp get element][expr $i+1] [$temp get x] [$temp get y] [$temp get z]]
        lappend Gnames [$temp get element][expr $i+1]
        $temp delete
    }
    
    
    # donors
    foreach ind $donList {
        # NOTE: in previous versions, donors were hydrogens only
        #       this version now accepts any atom type
        
        # make the donor selection (A)
        set donorA [atomselect top "index $ind"]
        
        # open output file
        set outname "${outFolderPath}/${basename}-DON-[$donorA get name].gau"
        set outfile [open $outname w]
        
        # write the header
        puts $outfile "%chk=${basename}-DON-[$donorA get name].chk"
        puts $outfile "%nproc=$qmProc"
        puts $outfile "%mem=${qmMem}GB"
        puts $outfile "$qmRoute"
        puts $outfile ""
        puts $outfile "<qmtool> simtype=\"Geometry optimization\" </qmtool>"
        puts $outfile "${basename}-DON-[$donorA get name]"
        puts $outfile ""
        puts $outfile "$qmCharge $qmMult"
        # write the cartesian coords
        foreach atom_entry $atom_info {
           puts $outfile "[lindex $atom_entry 0] [lindex $atom_entry 1] [lindex $atom_entry 2] [lindex $atom_entry 3]"
        }
        
        
        # if the donor is a hydrogen
        if { [$donorA get element] eq "H" } {
            
            set bondlistA [lindex [$donorA getbonds] 0]
    
            # validation
            if { [llength $bondlistA] != 1 } {
                tk_messageBox -type ok -icon warning \
                    -message "Application Halting due to error!"
                    -detail "Donor hydrogen $ind has more than one bond."
                close $outfile
                return
            }
            
            # determine some information about the hydrogen-bearing atom (B)
            set donorB [atomselect top "index $bondlistA"]
            set bondlistB [lindex [$donorB getbonds] 0]
            # select an atom to form the angle (C)
            if { [lindex $bondlistB 0] != $ind } {
                set donorC [atomselect top "index [lindex $bondlistB 0]"]
            } else {
                set donorC [atomselect top "index [lindex $bondlistB 1]"]
            }
            
            set donorAname [lindex $Gnames [$donorA get index]]
            set donorBname [lindex $Gnames [$donorB get index]]
            set donorCname [lindex $Gnames [$donorC get index]]
            
            # write the zmatrix
            puts $outfile "  x [format %4s $donorAname]  1.0 [format %7s $donorBname]  90.0 [format %5s $donorCname]   dih"
            puts $outfile " Ow [format %4s $donorAname]  rAH      x   90.0 [format %5s $donorBname]  180.0"
            puts $outfile "H1w   Ow  0.9572 [format %4s $donorAname] 127.74    x    0.0"
            puts $outfile "H2w   Ow  0.9572 [format %4s $donorAname] 127.74    x  180.0\n"
            puts $outfile "rAH 2.0"
            puts $outfile "dih 0.0"        
            
            # wrap up
            close $outfile
            continue
        } else {
            # the donor is not a hydrogen, which requires a different zmatrix
            
            # find information regarding donor (A)
            set donorAname [lindex $Gnames [$donorA get index]]
            set bondlistA [lindex [$donorA getbonds] 0]
    
            # find information regarding atom connected to the donor (B)
            set donorB [atomselect top "index [lindex $bondlistA 0]"]
            set donorBname [lindex $Gnames [$donorB get index]]
    
            # find cartesian coordinate for water oxygen placement
            set watOxyz [::ForceFieldToolKit::GenZMatrix::getWatXYZ $donorA]
            
            # several tests to determine the bonding connectivity and appropriate zmat values
            # one atom connected to donor (i.e. linear diatomic?)
            if { [llength $bondlistA] == 1 } {
                tk_messageBox -type ok -icon warning \
                    -message "Application halting due to error!"
                    -detail "Unsupported geometry for hydrogen bond donor $ind."
                close $outfile
                return
            }
            
            # two atoms connected to donor (i.e. linear)
            if { [llength $bondlistA] == 2 } {
                tk_messageBox -type ok -icon warning \
                    -message "Application halting due to error!"
                    -detail "Unsupported geometry for hydrogen bond donor $ind."
                close $outfile
                return
            }
            
            # more than two atoms connected to donor (e.g. planar)
            if { [llength $bondlistA] > 2 } {
                set ang [::QMtool::bond_angle $watOxyz [measure center $donorA] [measure center $donorB]]
                set donorC [atomselect top "index [lindex $bondlistA 1]"]
                set donorCname [lindex $Gnames [$donorC get index]]
                set dihed [::QMtool::dihed_angle $watOxyz [measure center $donorA] [measure center $donorB] [measure center $donorC]]
                puts $outfile " Ow [format %4s $donorAname]  rAH [format %7s $donorBname] [format %7s [format %3.2f $ang]] [format %4s $donorCname] [format %7s [format %3.2f $dihed]]"
            }
            
            puts $outfile "  x   Ow  1.0    [format %4s $donorAname]   90.0 [format %5s $donorBname]    dih"
            puts $outfile "H1w   Ow  0.9572 [format %4s $donorAname]  127.75    x    0.0"
            puts $outfile "H2w   Ow  0.9572 [format %4s $donorAname]  127.75    x  180.0"
            puts $outfile ""        
            puts $outfile "rAH 2.0"
            puts $outfile "dih 0.0"
            
            # wrap up
            close $outfile
            continue
    
        }
    }

    
    #acceptor
    
    foreach ind $accList {
    
       set acc [atomselect top "index $ind"]
       set bondlist [lindex [$acc getbonds] 0]
       set donorH [::ForceFieldToolKit::GenZMatrix::getWatXYZ $acc]
    
       set Aname [lindex $Gnames [$acc get index]]   
       set AM1 [atomselect top "index [lindex $bondlist 0]"]
       set AM1name [lindex $Gnames [$AM1 get index]]

       # open output file   
       set outname "${outFolderPath}/${basename}-ACC-[$acc get name].gau"
       set outfile [open $outname w]
       # write the header
       puts $outfile "%chk=${basename}-ACC-[$acc get name].chk"
       puts $outfile "%nproc=$qmProc"
       puts $outfile "%mem=${qmMem}GB"
       puts $outfile "$qmRoute"
       puts $outfile ""
       puts $outfile "<qmtool> simtype=\"Geometry optimization\" </qmtool>"
       puts $outfile "${basename}-ACC-[$acc get name]"
       puts $outfile ""
       puts $outfile "$qmCharge $qmMult"
       # write coords
       foreach atom_entry $atom_info {
           puts $outfile "[lindex $atom_entry 0] [lindex $atom_entry 1] [lindex $atom_entry 2] [lindex $atom_entry 3]"
       }
    
        
       if { [llength $bondlist] == 1 } {
          set bondlist2 [lindex [$AM1 getbonds] 0]
          if { [llength $bondlist2] == 1 } {
             puts "YOU ONLY HAVE TWO ATOMS!!!  DO IT BY HAND!!!"
             #quit
             return -1
          }
          if { [lindex $bondlist2 0] != $ind } {
             set AM1M1 [atomselect top "index [lindex $bondlist2 0]"]
          } else {
             set AM1M1 [atomselect top "index [lindex $bondlist2 1]"]
          }
          set AM1M1name [lindex $Gnames [$AM1M1 get index]]
          set ang [::QMtool::bond_angle $donorH [measure center $acc] [measure center $AM1M1] ]
          set dihed 180.0
          # Gaussian doesn't like angles of 180 degrees
          puts $outfile "H1w [format %4s $Aname]  rAH [format %7s $AM1M1name] [format %7s [format %3.2f $ang]] [format %4s $AM1name] [format %7s [format %3.2f $dihed]]"
    
       }
    
       if { [llength $bondlist] == 2 } {
          set ang [::QMtool::bond_angle $donorH [measure center $acc] [measure center $AM1] ]
          set AM2 [atomselect top "index [lindex $bondlist 1]"]
          set AM2name [lindex $Gnames [$AM2 get index]]
          set dihed 180.0
          puts $outfile "H1w [format %4s $Aname]  rAH [format %7s $AM1name] [format %7s [format %3.2f $ang]] [format %4s $AM2name] [format %7s [format %3.2f $dihed]]"
       }
          
       if {[llength $bondlist] > 2} {
          set ang [::QMtool::bond_angle $donorH [measure center $acc] [measure center $AM1] ]
          set AM2 [atomselect top "index [lindex $bondlist 1]"]
          set AM2name [lindex $Gnames [$AM2 get index]]
          set dihed [::QMtool::dihed_angle $donorH [measure center $acc] [measure center $AM1] [measure center $AM2] ]
          puts $outfile "H1w [format %4s $Aname]  rAH [format %7s $AM1name] [format %7s [format %3.2f $ang]] [format %4s $AM2name] [format %7s [format %3.2f $dihed]]"
    
       }
    
       puts $outfile "  x  H1w  1.0 [format %7s $Aname]   90.0 [format %5s $AM1name]    0.0"
       puts $outfile " Ow  H1w  0.9572    x   90.0 [format %5s $Aname]  180.0"
       puts $outfile "H2w   Ow  0.9572  H1w  104.52    x   dih\n"
       puts $outfile "rAH 2.0"
       puts $outfile "dih 0.0"
    
       close $outfile
       #lappend filelist $outfile


       ## is it a carbonyl?
       if { [string index $Aname 0] == "O" && [string index $AM1name 0] == "C" && [llength $bondlist] == 1 } {
          foreach pm {"p" "m"} dihed {180.0 0.0} {
             # open output file 
             set outname "${outFolderPath}/${basename}-ACC-[$acc get name]-${pm}120.gau"
             set outfile [open $outname w]
             # write the header
             puts $outfile "%chk=${basename}-ACC-[$acc get name]-${pm}120.chk"
             puts $outfile "%nproc=$qmProc"
             puts $outfile "%mem=${qmMem}GB"
             puts $outfile "$qmRoute"
             puts $outfile ""
             puts $outfile "<qmtool> simtype=\"Geometry optimization\" </qmtool>"
             puts $outfile "${basename}-ACC-[$acc get name]-${pm}120"
             puts $outfile ""
             puts $outfile "$qmCharge $qmMult"
             # write coords
             foreach atom_entry $atom_info {
                 puts $outfile "[lindex $atom_entry 0] [lindex $atom_entry 1] [lindex $atom_entry 2] [lindex $atom_entry 3]"
             }
             # other position for water with carbonyl
             set ang 120.0
             # Gaussian doesn't like angles of 180 degrees
             puts $outfile "H1w [format %4s $Aname]  rAH [format %7s $AM1name] [format %7s [format %3.2f $ang]] [format %4s $AM1M1name] [format %7s [format %3.2f $dihed]]"
             puts $outfile "  x  H1w  1.0 [format %7s $Aname]   90.0 [format %5s $AM1name]    0.0"
             puts $outfile " Ow  H1w  0.9572    x   90.0 [format %5s $Aname]  180.0"
             puts $outfile "H2w   Ow  0.9572  H1w  104.52    x   dih\n"
             puts $outfile "rAH 2.0"
             puts $outfile "dih 0.0"
             close $outfile
          }
       }

    }
    

}
#======================================================
proc ::ForceFieldToolKit::GenZMatrix::getWatXYZ { accsel } {
    # helper function for genZmatrix
    # returns xyz coordinates for interacting water atom

    set mol [$accsel molid]
    set aCent [measure center $accsel]
    
    set bonded [lindex [$accsel getbonds] 0]
    set numBonded [llength $bonded]
    
    set count 0
    set normavg {0 0 0}
    
    if { $numBonded == 1 } {
       set temp1 [atomselect $mol "index [lindex $bonded 0]"]
       set normavg [vecsub $aCent [measure center $temp1]]
       incr count
       $temp1 delete
    }
    
    if { $numBonded == 2 } {
       set temp1 [atomselect $mol "index [lindex $bonded 0]"]
       set bondvec1 [vecnorm [vecsub $aCent [measure center $temp1]]]
       set temp2 [atomselect $mol "index [lindex $bonded 1]"]
       set bondvec2 [vecnorm [vecsub $aCent [measure center $temp2]]]
       set normavg [vecadd $bondvec1 $bondvec2]
       incr count
       $temp1 delete
       $temp2 delete
    }
    
    
    #for all combinations of 3 atoms
    
    if { $numBonded > 2 } {
     for {set i 0} {$i <= [expr $numBonded-3]} {incr i} {
    
       set temp1 [atomselect $mol "index [lindex $bonded $i]"]
       #normalize bond vectors first
       set normPos1 [vecadd $aCent [vecnorm [vecsub [measure center $temp1] $aCent]]]
    
       for {set j [expr $i+1]} {$j <= [expr $numBonded-2]} {incr j} {
          set temp2 [atomselect $mol "index [lindex $bonded $j]"]
          set normPos2 [vecadd $aCent [vecnorm [vecsub [measure center $temp2] $aCent]]]
    
          for {set k [expr $j+1]} {$k <= [expr $numBonded-1]} {incr k} {
             set temp3 [atomselect $mol "index [lindex $bonded $k]"]
             set normPos3 [vecadd $aCent [vecnorm [vecsub [measure center $temp3] $aCent]]]
    
             #get the normal vector to the plane formed by the three atoms
             set vec1 [vecnorm [vecsub $normPos1 $normPos2]]
             set vec2 [vecnorm [vecsub $normPos2 $normPos3]]
             set norm [veccross $vec1 $vec2]
    
             #check that the normal vector and atom of interest are on the same side of the plane
             set d [expr -1.0*[vecdot $norm $normPos1]]
             if { [expr $d + [vecdot $norm $aCent]] < 0 } {
                set norm [veccross $vec2 $vec1]
             }
    
             #will average normal vectors at end
             set normavg [vecadd $normavg $norm]
             incr count
             $temp3 delete
          }
          $temp2 delete
       }
       $temp1 delete
     }
    }
    
    set normavg [vecscale [expr 1.0/$count] $normavg]
    
    set donorH [vecadd $aCent [vecscale 2.0 [vecnorm $normavg]]]
    
    return $donorH

}
#======================================================

