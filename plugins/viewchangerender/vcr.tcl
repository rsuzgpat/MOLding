# view_change_render.tcl
#
# Johan Strumpfer, Barry Isralewitz, Jordi Cohen
# Oct 2003; updated Feb 2007; updated Feb 2011
# johanstr@ks.uiuc.edu
#
# A script to save current viewpoints and animate
# a smooth 'camera move' between them. Can also
# rendering each frame to a numbered .rgb file
#
# Usage:
# The following commands are provided in the ::VCR:: namespace:
#   write_vps filename              -  write all saved viewpoints to file
#   renum_vp n1 n2                  -  renumber viewpoint n1 -> n2
#   save_vp n                       -  save current viewpoint in position n   
#   remove_vp n                     -  remove viewpoint in position n
#   insert_vp                       -  insert the current viewpoint into 
#                                      position n, shifting positions of 
#                                      viewpoints >= n by 1 if needed.
#   clear_vps                       -  remove all stored viewpoints
#   load_vps filename               -  source the tcl script with saved
#                                      viewpoints                        
#   list_vps                        -  list all currently stored viewpoints
#   retrieve_vp n                   -  load viewpoint at position n
#   play_vp n1 n2                   -  play through the list of current
#                                      viewpoints starting at n1 and ending at
#                                      n2, loading each in turn
#   initialise_movevp n1 n2         -  initialisation routine called by move_vp
#                                      that sets up the interpolation from
#                                      viewpoint n1 to n2. 
#                                      required for move_vp_increment
#   move_vp_increment               -  move the camera and increment length
#                                      ::VCR::stepsize along path set up in
#                                      initialse_movevp
#   movetime_vp n1 n2 t             -  move the camera from viewpoint n1 to
#                                      viewpoint n2 in t seconds
#   move_vp n1 n2 N                 -  move the camera from viewpoint n1 to
#                                      viewpoint n2 in N steps
#
# Notes:
# + move_vp can take ad additional argument smooth or sharp, e.g.,
#   move_vp n1 n2 N smooth 
#          or 
#   move_vp n1 n2 N sharp
#   Adding the smooth keyword uses a constant acceleration and then deceleration
#   to move the camera from start to finish. Adding the keyword sharp uses a 
#   constant velocity to move the camera from start to finish.
# + the position n1 or n2 in movetime_vp or move_vp can be given as "here" to
#   move to/from the current camera position

package provide viewchangerender 1.6

namespace eval ::VCR:: {
}

proc ::VCR::scale_mat {mat scaling} {
  set bigger ""
  set outmat ""
  for {set i 0} {$i<=3} {incr i} {
    set r ""
    for {set j 0} {$j<=3} {incr j} {            
      lappend r  [expr $scaling * [lindex [lindex [lindex $mat 0] $i] $j] ]
    }
    lappend outmat  $r
  }
  lappend bigger $outmat
  return $bigger
}


proc ::VCR::sub_mat {mat1 mat2} {
  set bigger ""
  set outmat ""
  for {set i 0} {$i<=3} {incr i} {
    set r ""
    for {set j 0} {$j<=3} {incr j} {            
      lappend r  [expr  (0.0 + [lindex [lindex [lindex $mat1 0] $i] $j]) - ( [lindex [lindex [lindex $mat2 0] $i] $j] )]

    }
    lappend outmat  $r
  }
  lappend bigger $outmat
  return $bigger
}


proc ::VCR::add_mat {mat1 mat2} {
  set bigger ""
  set outmat ""
  for {set i 0} {$i<=3} {incr i} {
    set r ""
    for {set j 0} {$j<=3} {incr j} {            
      lappend r  [expr  (0.0 + [lindex [lindex [lindex $mat1 0] $i] $j]) + [lindex [lindex [lindex $mat2 0] $i] $j] ]
    }
    lappend outmat  $r
  }
  lappend bigger $outmat
  return $bigger
}


proc ::VCR::matrix_to_euler {mat} {
  set pi 3.1415926535
  set R31 [lindex $mat 0 2 0]
  
  if {$R31 == 1} {
    set phi1 0.
    set psi1 [expr atan2([lindex $mat 0 0 1],[lindex $mat 0 0 2]) ]
    set theta1 [expr -$pi/2]
  } elseif {$R31 == -1} {
    set phi1 0.
    set psi1 [expr atan2([lindex $mat 0 0 1],[lindex $mat 0 0 2]) ]
    set theta1 [expr $pi/2]
  } else {
    set theta1 [expr -asin($R31)]
    # Alternate correct solution with a different trajectory:
    # set theta1 [expr $pi + asin($R31)]
    set cosT [expr cos($theta1)]
    set psi1 [expr  atan2([lindex $mat 0 2 1]/$cosT,[lindex $mat 0 2 2]/$cosT) ]
    set phi1 [expr  atan2([lindex $mat 0 1 0]/$cosT,[lindex $mat 0 0 0]/$cosT) ]
  }

  return "$theta1 $phi1 $psi1"
}


proc ::VCR::euler_to_matrix {euler} {
  set theta [lindex $euler 0]
  set phi [lindex $euler 1]
  set psi [lindex $euler 2]
    
  set mat {}
  lappend mat [list [expr cos($theta)*cos($phi)] [expr sin($psi)*sin($theta)*cos($phi) - cos($psi)*sin($phi)] [expr cos($psi)*sin($theta)*cos($phi) + sin($psi)*sin($phi)] 0. ]

  lappend mat [list [expr cos($theta)*sin($phi)] [expr sin($psi)*sin($theta)*sin($phi) + cos($psi)*cos($phi)] [expr cos($psi)*sin($theta)*sin($phi) - sin($psi)*cos($phi)] 0. ]
  
  lappend mat [list [expr -sin($theta)] [expr sin($psi)*cos($theta)] [expr cos($psi)*cos($theta)] 0. ]
    
  lappend mat [list 0. 0. 0. 1. ]
       
  return [list $mat]
}


proc ::VCR::write_vps {filename} {
  variable viewpoints

  set myfile [open $filename w]
  puts $myfile "\#This file contains viewpoints for a VMD script, view_change.tcl.\n\#Type 'source $filename' from the VMD command window to load these viewpoints.\n"
  puts $myfile "\nvariable ::VCR::viewpoints\n"
  
  foreach v [array names viewpoints] {
    if [string equal -length 5 $v "here,"] {continue}
    puts $myfile "set ::VCR::viewpoints($v) { $viewpoints($v) }\n "
  }
  puts $myfile "global PrevScreenSize"
  puts $myfile "set PrevScreenSize \[display get size\]"
  puts $myfile "proc RestoreScreenSize \{\} \{ global PrevScreenSize; display resize \[lindex \$PrevScreenSize 0\] \[lindex \$PrevScreenSize 1\] \}"
  puts $myfile "display resize [display get size]"
  puts $myfile "puts \"\\nLoaded viewpoints file $filename \\n\"\n"
  puts $myfile "puts \"Note: The screen size has been changed to that stored in the viewpoints file.\\n To restore it to change it type\\n  RestoreScreenSize\\ninto the Tk/Tcl console.\n\""
  close $myfile
}


proc ::VCR::renum_vp {view_num viewnumNew} {
  variable viewpoints
  if { ([info exists viewpoints($view_num,0)]) && !([info exists viewpoints($viewnumNew,0)]) } { 
    set viewpoints($viewnumNew,0) $viewpoints($view_num,0)
    set viewpoints($viewnumNew,1) $viewpoints($view_num,1)
    set viewpoints($viewnumNew,2) $viewpoints($view_num,2)
    set viewpoints($viewnumNew,3) $viewpoints($view_num,3)
    set viewpoints($viewnumNew,4) $viewpoints($view_num,4)
    ::VCR::remove_vp $view_num
   }
} 


proc ::VCR::save_vp {view_num {mol top}} {
  variable viewpoints
  if { !([molinfo $mol get drawn]) } {
      error "Molecule $mol is not drawn. Please specify currently drawn molecule with\n   save_vp view_num molid"
  }
  if [info exists viewpoints($view_num,0)] { unset viewpoints($view_num,0) }
  if [info exists viewpoints($view_num,1)] { unset viewpoints($view_num,1) }
  if [info exists viewpoints($view_num,2)] { unset viewpoints($view_num,2) }
  if [info exists viewpoints($view_num,3)] { unset viewpoints($view_num,3) }
  if [info exists viewpoints($view_num,4)] { unset viewpoints($view_num,4) }
  set viewpoints($view_num,0) [molinfo $mol get rotate_matrix]
  set viewpoints($view_num,1) [molinfo $mol get center_matrix]
  set viewpoints($view_num,2) [molinfo $mol get scale_matrix]
  set viewpoints($view_num,3) [molinfo $mol get global_matrix]
  set viewpoints($view_num,4) [molinfo $mol get frame]

} 


proc ::VCR::remove_vp {view_num} {
  variable viewpoints
  if [info exists viewpoints($view_num,0)] { unset viewpoints($view_num,0) }
  if [info exists viewpoints($view_num,1)] { unset viewpoints($view_num,1) }
  if [info exists viewpoints($view_num,2)] { unset viewpoints($view_num,2) }
  if [info exists viewpoints($view_num,3)] { unset viewpoints($view_num,3) }
  if [info exists viewpoints($view_num,4)] { unset viewpoints($view_num,4) }
}


proc ::VCR::insert_vp {view_num {mol top}} {
    variable viewpoints
    if [info exists viewpoints($view_num,0)] {
        set vp [expr $view_num + 1]
        while { [info exists viewpoints($vp,0)] } {
            incr vp
        }
        while { $vp > $view_num} {
            set viewpoints($vp,0) $viewpoints([expr $vp-1],0)
            set viewpoints($vp,1) $viewpoints([expr $vp-1],1)
            set viewpoints($vp,2) $viewpoints([expr $vp-1],2)
            set viewpoints($vp,3) $viewpoints([expr $vp-1],3)
            set viewpoints($vp,4) $viewpoints([expr $vp-1],4)
            incr vp -1
        }
    }
    ::VCR::remove_vp $view_num
    set viewpoints($view_num,0) [molinfo $mol get rotate_matrix]
    set viewpoints($view_num,1) [molinfo $mol get center_matrix]
    set viewpoints($view_num,2) [molinfo $mol get scale_matrix]
    set viewpoints($view_num,3) [molinfo $mol get global_matrix]
    set viewpoints($view_num,4) [molinfo $mol get frame]
}


proc ::VCR::clear_vps {} {
    variable viewpoints
    set listed {}
    foreach v [array names viewpoints] {
        unset viewpoints($v)
    }
}


proc ::VCR::load_vps { fname } {
    variable viewpoints
    source $fname
}


proc ::VCR::list_vps {} {
    variable viewpoints
    set listed {}
    foreach v [array names viewpoints] {
        set v0 [lindex [split $v ","] 0]
        if {[lsearch -exact $listed $v0] == -1 && $v0 != "here"} {
            lappend listed $v0
        }
    }
    return [lsort -integer $listed]
}


proc ::VCR::play_vp { first last {morph_frames 50} args} { 
    variable viewpoints
    puts "first: $first    last: $last"
    if { !([info exists viewpoints($first,0)]) } {
        puts "Starting view $first was not saved" 
    }
    if { !([info exists viewpoints($last,0)]) } {
        puts "Ending view $last was not saved" 
    }
    if {!([info exists viewpoints($first,0)] && [info exists viewpoints($last,0)])} {
        error "play_vp failed, don't have both start and end viewpoints"
    }

    set inc 1
    if { $first > $last } {set inc -1}
    ::VCR::retrieve_vp $first
    set cur $first
    while { $cur != $last } {
        set next [expr $cur+$inc]
        set allthere 1
        if { !([info exists viewpoints($next,0)]) } {
                set allthere 0
        }
        if { $allthere == 1 } {
            ::VCR::move_vp $cur $next $morph_frames sharp
            set cur $next
        } else {
            puts "Viewpoint $next does not seem to exist, moving in to next one in list."
        }
    }
}

#### Move the one step further


proc ::VCR::initialise_movevp { start end args } {
  variable viewpoints 
  variable smooth
  variable tumble
  variable ninja
  variable render
  variable move
  variable stepsize
  variable beginvp
  variable finalvp 
  variable framestep
  variable tracking 1

  set pi 3.1415926535
  
  set smooth 0
  set tumble 0
  set ninja  0
  set render 0
  if {[lsearch $args "smooth"] > -1}  {set smooth 1} 
  if {[lsearch $args "sharp"] > -1 }  {set smooth 0} ;#default
#  if {[lsearch $args "tumble"] > -1}  {set tumble 1}
  if {[lsearch $args "ninja"] > -1 }  {set ninja 1}
  if {[lsearch $args "-render"] > -1} {set render 1}  ;# only for use by move_vp_render
  

#  if {$render} {set framenum $::VCR::first_frame_num}
  
  if {$start == "here" || $end == "here"} {save_vp "here"}

  # Make sure that we aren't trying to access something that doesn't exist            
    if { !([info exists viewpoints($start,0)]) } {
    error "Starting view $start was not saved" 
  }

  if { !([info exists viewpoints($end,0)]) } {
    error "Ending view $end was not saved" 
  }
  set beginvp {}
  set finalvp {}
  for {set i 0} {$i < 5} {incr i} {
    lappend beginvp $viewpoints($start,$i)
    lappend finalvp $viewpoints($end,$i)
  }
  set begin_euler [::VCR::matrix_to_euler [lindex $beginvp 0] ]
  set final_euler [::VCR::matrix_to_euler [lindex $finalvp 0] ]
  # Make sure to take the quickest path!
  set diff [vecsub $final_euler $begin_euler]
  for {set i 0} {$i < 3} {incr i} {
    if  {[lindex $diff $i] > $pi} {
      set final_euler [lreplace $final_euler $i $i [expr [lindex $final_euler $i] -2.*$pi]]
    } elseif {[lindex $diff $i] < [expr -$pi]} {
      set final_euler [lreplace $final_euler $i $i [expr 2.*$pi + [lindex $final_euler $i]]]
    }
  }
  # Check done
  set framestep 1
  # ninja rotates the camera the long way around
  if {$ninja} {
    set final_euler [lreplace $final_euler 2 2 [expr 2.*$pi + [lindex $final_euler 2]]]
  }
  set rotate_diff [vecsub $final_euler $begin_euler]
  set center_diff  [::VCR::sub_mat [lindex $finalvp 1]   [lindex $beginvp 1]]
  set scale_diff   [::VCR::sub_mat [lindex $finalvp 2]   [lindex $beginvp 2]]
  set global_diff  [::VCR::sub_mat [lindex $finalvp 3]   [lindex $beginvp 3]]
  set finalframe   [lindex $finalvp 4]
  set beginframe   [lindex $beginvp 4]
  set frame_diff   [expr $finalframe - $beginframe]
  set ::VCR::finalframe $finalframe
  set move {}
  lappend move $rotate_diff
  lappend move $center_diff
  lappend move $scale_diff
  lappend move $global_diff
  lappend move $frame_diff
  set stepsize 0
}


proc ::VCR::retrieve_vp {view_num} {
  variable viewpoints
  foreach mol [molinfo list] {
    if [info exists viewpoints($view_num,0)] {
      molinfo $mol set rotate_matrix   $viewpoints($view_num,0)
      molinfo $mol set center_matrix   $viewpoints($view_num,1)
      molinfo $mol set scale_matrix    $viewpoints($view_num,2)
      molinfo $mol set global_matrix   $viewpoints($view_num,3)
      animate goto  [expr int($viewpoints($view_num,4))]
    } else {
      puts "View $view_num was not saved"}
  }
}


# MOVE FROM VIEWPOINT start TO end IN runtime SECONDS
# NOTE: SMOOTH ACCELERATE AND DECELERATE NOT IMPLEMENTED
# looks to be accurate to about 0.01 seconds
proc ::VCR::movetime_vp {start end runtime {framestep 1}} {
   if {$start != $end} {
       variable tracking
      ::VCR::initialise_movevp $start $end
      set ::VCR::framestep $framestep
      set t [time { ::VCR::retrieve_vp $start }]
      set t2 [time {set runtime [expr $runtime*1000000]}]
      set t2 [expr [lindex [split $t2] 0]+0.0]
      set Ttot $runtime
      set tracking 1.0
      set j 1
      set spf 0.0
      while { $tracking > 0 } {
            set t [expr [lindex [split $t] 0] + $t2*10]
            set runtime [expr 0.0 + $runtime - $t]
            set spf [expr ($spf*($j-1)+$t)/$j]  
            set ::VCR::stepsize [expr $tracking/$runtime*$spf]
            set diff [expr $tracking - $::VCR::stepsize]
            if { $diff < 0 || $::VCR::stepsize < 0} {
                set ::VCR::stepsize $tracking
                set tracking 0
            } else {
                set tracking $diff
            }
            incr j
            set t [time { ::VCR::move_vp_increment }]
         } 
    }


    proc ::VCR::move_vp {start end {morph_frames -1} {framestep 1} args} {
      ::VCR::initialise_movevp $start $end $args

      set ::VCR::framestep $framestep
      if {$morph_frames == -1 && $framestep == 1} {
        set morph_frames [lindex $::VCR::move 4]
      } elseif {$morph_frames == -1} {
        set morph_frames 50
      }
      if { $morph_frames == 0 } {
        set morph_frames 50
      }

      set ::VCR::stepsize [expr 1.0/$morph_frames]
     
      if {$start != "here"} {
            puts "Going to first viewpoint"
            ::VCR::retrieve_vp $start
      }
      set tracking 1
      set j 0
      
      while { $tracking > 0 } {
          #set scaling to apply for this individual frame
          if {$::VCR::smooth} {
            #accelerate smoothly to start and stop 
            set theta [expr 3.1415927*(1.0 +$j)/($morph_frames+1)] 
            set ::VCR::stepsize [expr (1. - cos($theta))*0.5-(1-$tracking)]
            if { $::VCR::stepsize == 0 } { set ::VCR::stepsize 0.0001 }
            #puts "   $theta $VCR::stepsize $tracking"
          }

          if { $tracking < $::VCR::stepsize || $::VCR::stepsize < 0 } { 
               set ::VCR::stepsize [expr $tracking] 
               set tracking 0
          } else {
            set tracking [expr $tracking - $::VCR::stepsize]
          }
          ::VCR::move_vp_increment
          incr j
              
    #      RENDER FUNCTIONALITY DISABLED - THIS WILL BE INCORPORATED VIA MOVIEMAKER
    #      if {$::VCR::render} {
    #        set frametext [format "%06d" $framenum]
    #        render snapshot [file join $::VCR::dirName $::VCR::filePrefixName.$frametext.rgb]  
    #        puts "Rendering frame [file join $::VCR::dirName $::VCR::filePrefixName.$frametext.rgb]"
    #        incr framenum
    #      }
      }
    }
}


proc ::VCR::init_move_vp_Movie { vplist frameskip {framestep 1} args} {
  set start [lindex $vplist 0]
  set end [lindex $vplist 1]
  set ::VCR::movieList $vplist
  ::VCR::initialise_movevp $start $end $args
  set ::VCR::movieListPos 1
  set nVP [llength $vplist]
  set totFrames 0
  for { set n 1 } { $n < $nVP } {incr n} {
    set m1 [lindex $vplist [expr $n-1]]
    set m2 [lindex $vplist $n]
    set totFrames [expr $totFrames + abs($::VCR::viewpoints($m2,4)-$::VCR::viewpoints($m1,4))]
 }

  set ::VCR::framestep $framestep
  set morph_frames 1
  if { [lindex $::VCR::move 4] != 0 } {
    set morph_frames [expr double(abs([lindex $::VCR::move 4]))/$frameskip]
  }

  set ::VCR::stepsize [expr 1.0/$morph_frames]
 
  if {$start != "here"} {
        puts "Going to first viewpoint"
        ::VCR::retrieve_vp $start
  }
  set ::VCR::tracking 1
  set ::VCR::CurMovieMakerFrame 0
  return $totFrames
}

  
# PROC WILL MOVE THE VIEWPOINT as a fraction $::VCR::stepsize along the
# direction $::VCR::move
proc ::VCR::move_vp_increment {} {
    set topmol [molinfo top]
    foreach mol [molinfo list] {
      set random {}
      if {$::VCR::tumble} {
         set randscale 0.1
      } else {
         set randscale 0.0
      }
      lappend random [expr  $randscale*rand()]
      lappend random [expr  $randscale*rand()]
      lappend random [expr  $randscale*rand()]
      set ::VCR::current {}
      lappend ::VCR::current [molinfo $mol get rotate_matrix]
      lappend ::VCR::current [molinfo $mol get center_matrix] 
      lappend ::VCR::current [molinfo $mol get scale_matrix ]
      lappend ::VCR::current [molinfo $mol get global_matrix]
      lappend ::VCR::current [molinfo $mol get frame]
      set euler [matrix_to_euler [lindex $::VCR::current 0]]
      for {set i 0} {$i < 4} {incr i} {
          if {$i == 0} {      
             set euler [vecadd [vecadd $euler [vecscale $::VCR::stepsize [lindex $::VCR::move 0]]] $random]
             lset ::VCR::current 0 [euler_to_matrix $euler ]
          } else {
             lset ::VCR::current $i [add_mat [lindex $::VCR::current $i] [scale_mat [lindex $::VCR::move $i] $::VCR::stepsize]]
          }    
      }
      
      molinfo $mol set rotate_matrix [lindex $::VCR::current 0]
      molinfo $mol set center_matrix [lindex $::VCR::current 1]
      molinfo $mol set scale_matrix  [lindex $::VCR::current 2]
      molinfo $mol set global_matrix [lindex $::VCR::current 3]
      if {$::VCR::framestep == 1 && $mol == $topmol} {
        set f [expr $::VCR::finalframe - ([lindex $::VCR::move 4] * $::VCR::tracking) ]
        #set f [expr int(round([lindex $::VCR::current 4] + [lindex $::VCR::move 4] * $::VCR::stepsize)) ]
        #if { [lindex $::VCR::move 4] < 0 } {
        #    set f [expr floor([$f)]
        #} else {
        #    set f [expr ceil($f)]
        #}
        #puts "$f"
        if { $f > 0 } {
            animate goto [expr $f]           
        } else {
            animate goto 0
        }
      }
    }
    display update 
}


proc ::VCR::moviecallback { args } {
  if {$::MovieMaker::userframe == 0 } { 
        set ::VCR::tracking 0
        set ::VCR::movieListPos 0
        set totFrames 0
        set nVP [llength $::VCR::movieList]

        for { set n 1 } { $n < $nVP } {incr n} {
            set m1 [lindex $::VCR::movieList [expr $n-1]]
            set m2 [lindex $::VCR::movieList $n]
            set totFrames [expr $totFrames + abs($::VCR::viewpoints($m2,4)-$::VCR::viewpoints($m1,4))]

        }
        set ::VCR::totFrames $totFrames
        set ::VCR::framestep $::MovieMaker::trjstep
        set ::VCR::CurMovieMakerFrame -1
  }
  if {$::MovieMaker::userframe < $::MovieMaker::numframes && $::MovieMaker::userframe > $::VCR::CurMovieMakerFrame} {
      if {$::VCR::tracking == 0} {
            if { $::VCR::movieListPos == 0 } { 
                puts "Generating frames with View-Change-Render."
                puts "Movie Maker settings:"
                puts "\tframerate=$::MovieMaker::framerate fps"
                puts "\tduration=$::MovieMaker::movieduration sec" 
                puts "\tframeskip=$::MovieMaker::trjstep"
                puts "\ttotal animation frames=$::MovieMaker::numframes"
                puts "View-Change-Render settings:"
                puts "\ttotal trajectory frames=$::VCR::totFrames"
                puts "\ttotal time=[expr $::VCR::movieTime*$::vcr_gui::timescale]"
                puts "\tRetrieving first viewpoint"
                ::VCR::retrieve_vp [lindex $::VCR::movieList 0]
            }
            set start [lindex $::VCR::movieList $::VCR::movieListPos]
            set T [lindex $::VCR::movieTimeList $::VCR::movieListPos]
            incr ::VCR::movieListPos
            if { $::VCR::movieListPos < [llength $::VCR::movieList] } {
                set end [lindex $::VCR::movieList $::VCR::movieListPos]
                puts -nonewline "Reached viewpoint $start proceeding to viewpoint $end"
                ::VCR::initialise_movevp $start $end 
                set morph_frames [expr $T/$::VCR::movieTime]
                set morph_frames [expr floor($morph_frames*$::MovieMaker::numframes)]
                set ::VCR::stepsize [expr 1.0/$morph_frames]
                set ::VCR::tracking 1
                puts " in ${morph_frames} frames."
            } else {
                set ::MovieMaker::userframe $::MovieMaker::numframes
            }
      }
      if {$::VCR::tracking > 0} {
          incr ::VCR::CurMovieMakerFrame 
          if { $::VCR::tracking < $::VCR::stepsize || $::VCR::stepsize < 0 } { 
               set ::VCR::stepsize [expr $::VCR::tracking] 
               set ::VCR::tracking 0
          } else {
            set ::VCR::tracking [expr $::VCR::tracking - $::VCR::stepsize]
          }
          ::VCR::move_vp_increment
       }
   } 
}

proc ::VCR::setmovieTime { val } {
    set ::VCR::movieTime $val
}

proc ::VCR::getmovieTimeList {} {
    return $::VCR::movieTimeList
}

proc ::VCR::getmovieList {} {
    return $::VCR::movieList
}

proc ::VCR::createMovieVars { {force 0} } {
    if { $force == 1 } {
      set ::VCR::movieTimeList {}
      set ::VCR::movieList {}
      set ::VCR::movieTime 0.0
    } else {
      if { ![info exists ::VCR::movieTimeList] } {
        set ::VCR::movieTimeList {}
      }
      if { ![info exists ::VCR::movieList] } {
        set ::VCR::movieList {}
      }
      if { ![info exists ::VCR::movieTime] } {
        set ::VCR::movieTime 0.0
      }
    }
    return
}
