# remote is a vmd plugin that provides a GUI for remote access
#
# Copyright (c) 2011 The Board of Trustees of the University of Illinois
#

package provide remote 0.1

namespace eval ::remote:: {
# define all namespace vars here
  # window handle
  variable w                                          

  variable currentUserList
  variable userListMenu

  variable portValue
  variable modeChoice
  variable userMenuText

  namespace export updateData
# list all exported proc names
#  namespace export name1 name2
}

# -------------------------------------------------------------------------
#
# Create the window and initialize data structures
#
proc ::remote::remote {} {

  variable w
  variable userListMenu
  variable userMenuText
  variable portValue
  variable modeChoice

# If already initialized, just turn on
  if { [winfo exists .remote] } {
    wm deiconify $w
    return
  }

  set w [toplevel ".remote"]
  wm title $w "Mobile Device Remote Control"

  #Add a menubar
  frame $w.menubar -relief raised -bd 2
  #grid  $w.menubar -padx 1 -column 0 -columnspan 5 -row 0 -sticky ew
  pack $w.menubar -padx 1 -fill x

  menubutton $w.menubar.help -text "Help" -underline 0 \
    -menu $w.menubar.help.menu
  $w.menubar.help config -width 5
  pack $w.menubar.help -side right

  ## help menu
  menu $w.menubar.help.menu -tearoff no
  $w.menubar.help.menu add command -label "About" \
    -command {tk_messageBox -type ok -title "About VMD Remote" \
              -message "Remote Control Gui."}
  $w.menubar.help.menu add command -label "Help..." \
    -command "vmd_open_url [string trimright [vmdinfo www]]plugins/remote"

# now, let's define the gooey

## ---------------------------------------------------------------------------
## ---------------------- START main FRAME ---------------------------
  set win [frame $w.win]
  set row 0

  # -----------------------------------------------
  # intro text
  grid [label $win.introText -text "Mobile Device Remote Control"] \
     -row $row -column 0 -columnspan 2 
  incr row

#  # -----------------------------------------------
#  # host name, to help people out
#  grid [label $win.hostlabel -text "Host Name: "] \
#    -row $row -column 0 -sticky w
#  grid [label $win.hostvalue -text [info hostname]] \
#    -row $row -column 1 -sticky ew
#  incr row

  # -----------------------------------------------
  # Incoming port number
  grid [label $win.portlabel -text "Port Number: "] \
    -row $row -column 0 -sticky w
  grid [entry $win.portValue -width 5 -textvariable \
       [namespace current]::portValue  ] \
    -row $row -column 1 -sticky ew
  incr row

  bind $win.portValue <Return> {::remote::setPort}

  # -----------------------------------------------
  grid [labelframe $win.mode -bd 2 -relief ridge \
            -text "Mode" \
            -padx 1m -pady 1m] -row $row -column 0 -columnspan 2 -sticky nsew
  incr row

  # ---
     grid [radiobutton $win.mode.off -text "Off" \
                   -variable [namespace current]::modeChoice -value 0 -command \
                   "[namespace current]::setMode" ] \
        -row 0 -column 0 -sticky w

     grid [radiobutton $win.mode.move -text "Move" \
                   -variable [namespace current]::modeChoice -value 1 -command \
                   "[namespace current]::setMode" ] \
        -row 0 -column 1 -sticky w

     grid [radiobutton $win.mode.anim -text "Animate" \
                   -variable [namespace current]::modeChoice -value 2 -command \
                   "[namespace current]::setMode" ] \
        -row 0 -column 2 -sticky w

     grid [radiobutton $win.mode.track -text "Tracker" \
                   -variable [namespace current]::modeChoice -value 3 -command \
                   "[namespace current]::setMode" ] \
        -row 0 -column 3 -sticky w

     grid [radiobutton $win.mode.user -text "User" \
                   -variable [namespace current]::modeChoice -value 4 -command \
                   "[namespace current]::setMode" ] \
        -row 0 -column 4 -sticky w

  # -----------------------------------------------
  # Current User List
  grid [labelframe $win.userFrame -bd 2 -text "User In Control"       \
                                              -padx 1m -pady 1m]      \
                   -row $row -column 0 -columnspan 2 -sticky nsew
    # -----
    variable listBox
    set listBox [listbox $win.userFrame.userList -activestyle none -yscroll "$win.userFrame.s set" -width 35] 

    bind $listBox <ButtonRelease-1> { ::remote::processClick %W}

    grid $listBox -row 0 -column 0 -sticky news 
    grid [scrollbar $win.userFrame.s -command "$win.userFrame.userList yview"] \
                                -row 0 -column 1 -sticky news
    # -----

  incr row
#
  # -----------------------------------------------
  updateData
  global vmd_mobile_state_changed
  trace add variable vmd_mobile_state_changed write "::remote::updateData"

  pack $win 

}

# -------------------------------------------------------------------------
proc ::remote::processClick {W} {
   variable currentUserList
# XXX add processing code here to select controller
#   puts "clicked row [$W curselection]"

# we only care about this someone is connected....
   if { [llength $currentUserList] > 0} {

      set userClicked [lindex $currentUserList [$W curselection]]

      # if they were already active, we don't need to do anything
      if { [lindex $userClicked 2] != 1} {
#         puts "sending ::mobile set activeClient $userClicked"
         ::mobile set activeClient [lindex $userClicked 0] [lindex $userClicked 1]
  
         updateData
      }
   }
}

# -------------------------------------------------------------------------
proc ::remote::setPort {args} {
   variable portValue
   ::mobile port $portValue
}


# -------------------------------------------------------------------------
proc remotegui_tk {} {
  ::remote::remote
  return $::remote::w
}

# -------------------------------------------------------------------------
proc ::remote::updateData {args} {
  variable currentUserList
  variable listBox
  variable portValue
  variable modeChoice

  # get the current list of clients....
  set currentUserList [::mobile get clientList]
  set newMode [::mobile get mode]

   # list is a list of lists.  
# user 0
   # user name
   # user IP
   # Is user in control? 1 for yes, 0 for no
# user 1
   # user name
   # user IP
   # Is user in control? 1 for yes, 0 for no
# etc

  $listBox delete 0 end

  if { $newMode == "off" } {
    $listBox insert 0 "  Mode Is Currently Off"
  } else {

    if {[llength $currentUserList] == 0} {
      $listBox insert 0 "No Connected User In Control"
    } else {
      foreach client $currentUserList {
         $listBox insert end "[lindex $client 0] ([lindex $client 1])"
      }

# xxx: do we need to set them active?  index 2 will be 1 if yes, 0 if no
      set lbIndex 0
      set anyActive 0
      foreach client $currentUserList {
#         puts "client is $client and lbIndex is $lbIndex"
         if { [lindex $client 2] == 1} {
            set anyActive 1
#            puts "activating"
#            $listBox activate $lbIndex
            $listBox selection set $lbIndex $lbIndex
         }
         incr lbIndex
      }
      if { $anyActive == 0} {
         puts "none active"
      }
    }
  }

  set portValue [::mobile get port]

  switch $newMode {
     off { set modeChoice 0 }
     move { set modeChoice 1 }
     animate { set modeChoice 2 }
     tracker { set modeChoice 3 }
     user { set modeChoice 4 }
  }
}   ;# end of remote::updateData 

# -------------------------------------------------------------------------
proc ::remote::setMode {} {
   variable modeChoice
   switch $modeChoice {
     0 { ::mobile mode off }
     1 { ::mobile mode move }
     2 { ::mobile mode animate }
     3 { ::mobile mode tracker }
     4 { ::mobile mode user }
  }
}

# -------------------------------------------------------------------------


