#!/usr/bin/env wish

# tkload - Tcl/Tk clone of xload system load monitor for Linux

package require Tk

set ::width 700
set ::height 375
set ::graph_data {}
set ::marks {}
set ::show_marks 1
set ::max_time 3600
set ::update_interval 1000
set ::start_time [clock seconds]
set ::show_1m 1
set ::show_5m 1
set ::show_15m 1
# Exponent applied to the log time scale; >1 pushes recent times farther right.
# TODO: expose as a configuration parameter.
set ::time_scale_exp 2.0
set ::font_size 16
set ::font_family "Helvetica"

# Assign argv to given names
# A: Associative-array: map option to value
# P: Positional parameters: indexed from 0
# opts: Options string e.g., "hc:p"
# V: e.g., $argv
proc getopts { A_name P_name opts V } {
  upvar $A_name A
  upvar $P_name P
  upvar optind count
  # Colons
  array set C {}
  _getopts_parse_opt_string C $opts
  set i 0
  set count 0
  set q 0
  set N [ llength $V ]
  set dash_found false
  while { $i < $N } {
    set t [ lindex $V $i ]
    set c [ string range $t 0 0 ]
    if { $c eq "-" && ! $dash_found} {
      set c [ string range $t 1 1 ]
    } else {
      set P($q) $t
      incr q
      incr i
      continue
    }
    if { $c eq "-" } { # Found --
      set dash_found true
      incr i
      incr count
      continue
    }
    if { ! [ info exists C($c) ] } {
      error "getopts: invalid flag: $c"
    }
    if { [ string equal $C($c) ":" ] } {
      incr i
      incr count
      set t [ lindex $V $i ]
      lappend A($c) $t
    } else {
      lappend A($c) {}
    }
    incr i
    incr count
  }
}

proc _getopts_parse_opt_string { C_name opts } {
  upvar $C_name C
  set i 0
  set N [ string length $opts ]
  while { $i < $N } {
    set c     [ string range $opts $i $i ]
    incr i
    set colon [ string range $opts $i $i ]
    if { [ string equal $colon ":" ] } {
      set C($c) ":"
      incr i
    } else {
      set C($c) "_"
    }
  }
}

# Find and load rc file. Searches, in order:
#   $TKLOADRC, $XDG_CONFIG_HOME/tkload/settings.cfg,
#   ~/.config/tkload/settings.cfg, ~/.tkloadrc
# File format: key=value per line, '#' starts a comment. Recognized keys:
#   max_time (seconds), font_size, update_interval (seconds, float),
#   time_scale_exp, show_1m, show_5m, show_15m, width, height
proc load_rc {} {
  set candidates {}
  if {[info exists ::opt_settings] && $::opt_settings ne ""} {
    lappend candidates $::opt_settings
  }
  if {[info exists ::env(TKLOADRC)] && $::env(TKLOADRC) ne ""} {
    lappend candidates $::env(TKLOADRC)
  }
  if {[info exists ::env(XDG_CONFIG_HOME)] && $::env(XDG_CONFIG_HOME) ne ""} {
    lappend candidates [file join $::env(XDG_CONFIG_HOME) tkload settings.cfg]
  }
  lappend candidates [file join $::env(HOME) .config tkload settings.cfg]
  lappend candidates [file join $::env(HOME) .tkloadrc]

  set valid {max_time font_size font_family update_interval time_scale_exp \
             show_1m show_5m show_15m width height}

  foreach path $candidates {
    if {![file readable $path]} continue
    try {
      set f [open $path r]
    } on error {} {
      continue
    }
    while {[gets $f line] >= 0} {
      set line [string trim $line]
      if {$line eq "" || [string index $line 0] eq "#"} continue
      set eq [string first "=" $line]
      if {$eq < 0} continue
      set key [string trim [string range $line 0 [expr {$eq - 1}]]]
      set val [string trim [string range $line [expr {$eq + 1}] end]]
      if {[lsearch -exact $valid $key] >= 0} {
        if {$key eq "update_interval"} {
          if {[string is double -strict $val] && $val > 0} {
            set ::update_interval [expr {int($val * 1000)}]
          }
        } else {
          set ::$key $val
        }
      }
    }
    close $f
    return $path
  }
  return ""
}

array set _opts {}
array set _pos {}
try {
  getopts _opts _pos "s:" $argv
} on error {err} {
  puts stderr "tkload: $err"
  puts stderr "usage: tkload \[-s settings.cfg\]"
  exit 2
}
if {[info exists _opts(s)]} {
  set ::opt_settings [lindex $_opts(s) end]
}
load_rc

# Get current load average from /proc/loadavg
proc get_load {} {
  try {
    set f [open "/proc/loadavg" r]
  } on error {} {
    return {0 0 0}
  }
  gets $f line
  close $f
  set loads [split $line]
  return [list [lindex $loads 0] [lindex $loads 1] [lindex $loads 2]]
}

# Update graph with new load data
proc update_graph {} {
  set loads [get_load]
  set load1 [lindex $loads 0]
  set load5 [lindex $loads 1]
  set load15 [lindex $loads 2]
  set now [clock seconds]

  # Store all three loads with timestamp
  lappend ::graph_data [list $now $load1 $load5 $load15]

  # Remove old data (older than max_time)
  set cutoff [expr {$now - $::max_time}]
  set new_data {}
  foreach point $::graph_data {
    if {[lindex $point 0] >= $cutoff} {
      lappend new_data $point
    }
  }
  set ::graph_data $new_data

  # Update display
  .canvas delete all
  draw_graph $load1 $load5 $load15

  after $::update_interval update_graph
}

# Load and display initial data without waiting
proc initial_update {} {
  set loads [get_load]
  set load1 [lindex $loads 0]
  set load5 [lindex $loads 1]
  set load15 [lindex $loads 2]
  set now [clock seconds]
  lappend ::graph_data [list $now $load1 $load5 $load15]
  .canvas delete all
  draw_graph $load1 $load5 $load15
}

# Draw the load graph
proc draw_graph {load1 load5 load15} {
  set c .canvas
  set w [winfo width $c]
  set h [winfo height $c]
  set pad 30
  set left_pad 60
  set bottom_pad 60
  set menu_h 40
  set top_pad [expr {$pad + $menu_h}]

  # Draw background
  $c create rect 0 0 $w $h -fill white

  # Draw scale and grid - compute max from visible data
  set max_load 1.0
  foreach point $::graph_data {
    if {$::show_1m && [lindex $point 1] > $max_load} {set max_load [lindex $point 1]}
    if {$::show_5m && [lindex $point 2] > $max_load} {set max_load [lindex $point 2]}
    if {$::show_15m && [lindex $point 3] > $max_load} {set max_load [lindex $point 3]}
  }
  # Round up to a nice value
  set max_load [expr {ceil($max_load * 1.1)}]
  if {$max_load < 1.0} {set max_load 1.0}

  # Horizontal grid lines
  set plot_height [expr {$h - $top_pad - $bottom_pad}]
  set n_lines 4
  for {set i 0} {$i <= $n_lines} {incr i} {
    set y [expr {$h - $bottom_pad - ($i * $plot_height / $n_lines)}]
    set val [expr {$i * $max_load / $n_lines}]
    $c create line $left_pad $y $w $y -fill lightgray -dash {2 2}
    $c create text [expr {$left_pad - 5}] $y -text [format "%.1f" $val] -anchor e -font [list $::font_family $::font_size]
  }

  # Draw axes
  $c create line $left_pad $top_pad $left_pad [expr {$h - $bottom_pad}] -fill black -width 2
  $c create line $left_pad [expr {$h - $bottom_pad}] $w [expr {$h - $bottom_pad}] -fill black -width 2

  set now [clock seconds]
  set scale [expr {$plot_height / $max_load}]

  # Convert time to log scale x position
  proc time_to_x {time_ago w pad left_pad} {
    if {$time_ago <= 0} {
      return [expr {$w - $pad}]
    }
    set log_scale [expr {pow(log($time_ago + 1) / log($::max_time + 1.0), $::time_scale_exp)}]
    return [expr {$left_pad + (($w - $pad - $left_pad) * (1.0 - $log_scale))}]
  }

  # Draw x-axis labels (positioned to avoid legend)
  set label_times {60 300 900 3600}
  set label_names {"1m ago" "5m ago" "15m ago" "1h ago"}

  foreach time $label_times name $label_names {
    set x [time_to_x $time $w $pad $left_pad]
    $c create line $x [expr {$h - $bottom_pad}] $x [expr {$h - $bottom_pad + 5}] -fill black
    $c create text $x [expr {$h - $bottom_pad + 20}] -text $name -anchor n -font [list $::font_family [expr {$::font_size - 2}]]
  }

  # Draw load line graphs for 1m, 5m, 15m
  set prev_x1 ""
  set prev_y1 ""
  set prev_x5 ""
  set prev_y5 ""
  set prev_x15 ""
  set prev_y15 ""

  foreach point $::graph_data {
    set timestamp [lindex $point 0]
    set load1_val [lindex $point 1]
    set load5_val [lindex $point 2]
    set load15_val [lindex $point 3]
    set time_ago [expr {$now - $timestamp}]
    set x [time_to_x $time_ago $w $pad $left_pad]

    # 1-minute load (red)
    if {$::show_1m} {
      set y1 [expr {$h - $bottom_pad - ($load1_val * $scale)}]
      if {$prev_x1 ne ""} {
        $c create line $prev_x1 $prev_y1 $x $y1 -fill red -width 2
      }
      set prev_x1 $x
      set prev_y1 $y1
    }

    # 5-minute load (green)
    if {$::show_5m} {
      set y5 [expr {$h - $bottom_pad - ($load5_val * $scale)}]
      if {$prev_x5 ne ""} {
        $c create line $prev_x5 $prev_y5 $x $y5 -fill green -width 2
      }
      set prev_x5 $x
      set prev_y5 $y5
    }

    # 15-minute load (blue)
    if {$::show_15m} {
      set y15 [expr {$h - $bottom_pad - ($load15_val * $scale)}]
      if {$prev_x15 ne ""} {
        $c create line $prev_x15 $prev_y15 $x $y15 -fill blue -width 2
      }
      set prev_x15 $x
      set prev_y15 $y15
    }
  }

  # Draw marks if enabled
  if {$::show_marks} {
    foreach point $::graph_data {
      set timestamp [lindex $point 0]
      if {[lsearch -exact $::marks $timestamp] >= 0} {
        set load1_val [lindex $point 1]
        set load5_val [lindex $point 2]
        set load15_val [lindex $point 3]
        set time_ago [expr {$now - $timestamp}]
        set x [time_to_x $time_ago $w $pad $left_pad]

        if {$::show_1m} {
          set y1 [expr {$h - $bottom_pad - ($load1_val * $scale)}]
          $c create oval [expr {$x - 5}] [expr {$y1 - 3}] [expr {$x + 5}] [expr {$y1 + 3}] \
            -fill red -outline red
        }
        if {$::show_5m} {
          set y5 [expr {$h - $bottom_pad - ($load5_val * $scale)}]
          $c create oval [expr {$x - 5}] [expr {$y5 - 3}] [expr {$x + 5}] [expr {$y5 + 3}] \
            -fill green -outline green
        }
        if {$::show_15m} {
          set y15 [expr {$h - $bottom_pad - ($load15_val * $scale)}]
          $c create oval [expr {$x - 5}] [expr {$y15 - 3}] [expr {$x + 5}] [expr {$y15 + 3}] \
            -fill blue -outline blue
        }
      }
    }
  }

  # Draw current load indicators (at right edge)
  set x_now [expr {$w - $pad}]
  set y1 [expr {$h - $bottom_pad - ($load1 * $scale)}]
  set y5 [expr {$h - $bottom_pad - ($load5 * $scale)}]
  set y15 [expr {$h - $bottom_pad - ($load15 * $scale)}]

  $c create oval [expr {$x_now - 5}] [expr {$y1 - 3}] [expr {$x_now + 5}] [expr {$y1 + 3}] \
    -fill red -outline red
  $c create oval [expr {$x_now - 5}] [expr {$y5 - 3}] [expr {$x_now + 5}] [expr {$y5 + 3}] \
    -fill green -outline green
  $c create oval [expr {$x_now - 5}] [expr {$y15 - 3}] [expr {$x_now + 5}] [expr {$y15 + 3}] \
    -fill blue -outline blue

  # Menu area background
  $c create rect 0 0 $w $menu_h -fill #eeeeee -outline ""
  $c create line 0 $menu_h $w $menu_h -fill gray

  # Draw labels in menu area
  $c create text 10 [expr {$menu_h/2}] -text "Load: 15m:$load15  5m:$load5  1m:$load1" \
    -anchor w -font [list $::font_family $::font_size bold]

  # Draw legend with clickable rectangles in menu area
  set legend_font [list $::font_family $::font_size]
  set legend_pad 6
  set legend_y [expr {$menu_h/2}]

  # Create text first to measure, then size rectangles around them
  set tmp1 [$c create text 0 0 -text "R:1m" -anchor center -font $legend_font]
  set tmp5 [$c create text 0 0 -text "G:5m" -anchor center -font $legend_font]
  set tmp15 [$c create text 0 0 -text "B:15m" -anchor center -font $legend_font]
  set bb1 [$c bbox $tmp1]
  set bb5 [$c bbox $tmp5]
  set bb15 [$c bbox $tmp15]
  $c delete $tmp1 $tmp5 $tmp15

  set w1 [expr {[lindex $bb1 2] - [lindex $bb1 0] + 2*$legend_pad}]
  set w5 [expr {[lindex $bb5 2] - [lindex $bb5 0] + 2*$legend_pad}]
  set w15 [expr {[lindex $bb15 2] - [lindex $bb15 0] + 2*$legend_pad}]
  set rect_h [expr {[lindex $bb1 3] - [lindex $bb1 1] + 2*$legend_pad}]
  set gap 5

  set total [expr {$w1 + $w5 + $w15 + 2*$gap}]
  set x15_left [expr {$w - 10 - $total}]
  set x5_left [expr {$x15_left + $w15 + $gap}]
  set x1_left [expr {$x5_left + $w5 + $gap}]
  set y_top [expr {$legend_y - $rect_h/2}]
  set y_bot [expr {$legend_y + $rect_h/2}]

  set rect1 [$c create rect $x1_left $y_top [expr {$x1_left + $w1}] $y_bot \
    -fill white -outline black -width 1]
  set text1 [$c create text [expr {$x1_left + $w1/2}] $legend_y -text "R:1m" \
    -anchor center -font $legend_font -fill black]

  set rect5 [$c create rect $x5_left $y_top [expr {$x5_left + $w5}] $y_bot \
    -fill white -outline black -width 1]
  set text5 [$c create text [expr {$x5_left + $w5/2}] $legend_y -text "G:5m" \
    -anchor center -font $legend_font -fill black]

  set rect15 [$c create rect $x15_left $y_top [expr {$x15_left + $w15}] $y_bot \
    -fill white -outline black -width 1]
  set text15 [$c create text [expr {$x15_left + $w15/2}] $legend_y -text "B:15m" \
    -anchor center -font $legend_font -fill black]

  # Change border color and text color if curves are hidden
  if {!$::show_1m} {
    $c itemconfig $rect1 -outline gray
    $c itemconfig $text1 -fill gray
  }
  if {!$::show_5m} {
    $c itemconfig $rect5 -outline gray
    $c itemconfig $text5 -fill gray
  }
  if {!$::show_15m} {
    $c itemconfig $rect15 -outline gray
    $c itemconfig $text15 -fill gray
  }

  # Store tags for click handlers (add to all items with this tag)
  $c addtag clickable withtag $rect1
  $c addtag clickable withtag $text1
  $c addtag clickable withtag $rect5
  $c addtag clickable withtag $text5
  $c addtag clickable withtag $rect15
  $c addtag clickable withtag $text15
  $c addtag legend_1m withtag $rect1
  $c addtag legend_1m withtag $text1
  $c addtag legend_5m withtag $rect5
  $c addtag legend_5m withtag $text5
  $c addtag legend_15m withtag $rect15
  $c addtag legend_15m withtag $text15
}

# Create main window
wm title . "tkload"
wm geometry . "${::width}x${::height}"

# Create canvas
canvas .canvas -bg white
pack .canvas -fill both -expand 1

# Update canvas size when window resizes
bind . <Configure> {
  .canvas config -width [winfo width .]
  .canvas config -height [winfo height .]
}

# Click handlers for legend
.canvas bind legend_1m <Button-1> {
  set ::show_1m [expr {!$::show_1m}]
  .canvas delete all
  set now [clock seconds]
  set cutoff [expr {$now - $::max_time}]
  set new_data {}
  foreach point $::graph_data {
    if {[lindex $point 0] >= $cutoff} {
      lappend new_data $point
    }
  }
  set ::graph_data $new_data
  draw_graph [lindex [get_load] 0] [lindex [get_load] 1] [lindex [get_load] 2]
}
.canvas bind legend_5m <Button-1> {
  set ::show_5m [expr {!$::show_5m}]
  .canvas delete all
  set now [clock seconds]
  set cutoff [expr {$now - $::max_time}]
  set new_data {}
  foreach point $::graph_data {
    if {[lindex $point 0] >= $cutoff} {
      lappend new_data $point
    }
  }
  set ::graph_data $new_data
  draw_graph [lindex [get_load] 0] [lindex [get_load] 1] [lindex [get_load] 2]
}
.canvas bind legend_15m <Button-1> {
  set ::show_15m [expr {!$::show_15m}]
  .canvas delete all
  set now [clock seconds]
  set cutoff [expr {$now - $::max_time}]
  set new_data {}
  foreach point $::graph_data {
    if {[lindex $point 0] >= $cutoff} {
      lappend new_data $point
    }
  }
  set ::graph_data $new_data
  draw_graph [lindex [get_load] 0] [lindex [get_load] 1] [lindex [get_load] 2]
}

proc mark_time {} {
  lappend ::marks [clock seconds]
  update_graph
}

proc toggle_marks {} {
  set ::show_marks [expr {!$::show_marks}]
  set now [clock seconds]
  set loads [get_load]
  set cutoff [expr {$now - $::max_time}]
  set new_data {}
  foreach point $::graph_data {
    if {[lindex $point 0] >= $cutoff} {
      lappend new_data $point
    }
  }
  set ::graph_data $new_data
  .canvas delete all
  draw_graph [lindex $loads 0] [lindex $loads 1] [lindex $loads 2]
}

bind . <Key-q> {exit}
bind . <space> {mark_time}
bind . <Key-m> {toggle_marks}

proc show_config {} {
  set t .config
  if {[winfo exists $t]} {
    wm deiconify $t
    raise $t
    return
  }
  toplevel $t
  wm title $t "Configuration"
  wm transient $t .

  label $t.l_range -text "X-axis range (hours):" -anchor w
  entry $t.e_range -width 10
  $t.e_range insert 0 [expr {$::max_time / 3600.0}]

  grid $t.l_range -row 0 -column 0 -sticky w -padx 8 -pady 6
  grid $t.e_range -row 0 -column 1 -sticky w -padx 8 -pady 6

  label $t.l_family -text "Font family:" -anchor w
  ttk::combobox $t.c_family -width 24 -state readonly \
    -values [lsort -dictionary [font families]]
  $t.c_family set $::font_family
  grid $t.l_family -row 1 -column 0 -sticky w -padx 8 -pady 6
  grid $t.c_family -row 1 -column 1 -sticky w -padx 8 -pady 6

  label $t.l_font -text "Font size:" -anchor w
  ttk::combobox $t.c_font -width 8 -state readonly \
    -values {8 9 10 11 12 13 14 15 16 17 18 19 20}
  $t.c_font set $::font_size
  grid $t.l_font -row 2 -column 0 -sticky w -padx 8 -pady 6
  grid $t.c_font -row 2 -column 1 -sticky w -padx 8 -pady 6

  label $t.l_interval -text "Update interval (seconds):" -anchor w
  entry $t.e_interval -width 10
  $t.e_interval insert 0 [expr {$::update_interval / 1000.0}]
  grid $t.l_interval -row 3 -column 0 -sticky w -padx 8 -pady 6
  grid $t.e_interval -row 3 -column 1 -sticky w -padx 8 -pady 6

  label $t.l_curves -text "Curves shown:" -anchor w
  frame $t.f_curves
  set ::cfg_show_1m $::show_1m
  set ::cfg_show_5m $::show_5m
  set ::cfg_show_15m $::show_15m
  checkbutton $t.f_curves.c1 -text "1m" -variable ::cfg_show_1m
  checkbutton $t.f_curves.c5 -text "5m" -variable ::cfg_show_5m
  checkbutton $t.f_curves.c15 -text "15m" -variable ::cfg_show_15m
  pack $t.f_curves.c1 $t.f_curves.c5 $t.f_curves.c15 -side left
  grid $t.l_curves -row 4 -column 0 -sticky w -padx 8 -pady 6
  grid $t.f_curves -row 4 -column 1 -sticky w -padx 8 -pady 6

  frame $t.btns
  button $t.btns.ok -text "OK" -command {
    set v [.config.e_range get]
    if {[string is double -strict $v] && $v > 0} {
      set ::max_time [expr {int($v * 3600)}]
    }
    set fs [.config.c_font get]
    if {[string is integer -strict $fs] && $fs >= 8 && $fs <= 20} {
      set ::font_size $fs
    }
    set ff [.config.c_family get]
    if {$ff ne ""} {
      set ::font_family $ff
    }
    set iv [.config.e_interval get]
    if {[string is double -strict $iv] && $iv > 0} {
      set ::update_interval [expr {int($iv * 1000)}]
    }
    set ::show_1m $::cfg_show_1m
    set ::show_5m $::cfg_show_5m
    set ::show_15m $::cfg_show_15m
    destroy .config
  }
  button $t.btns.cancel -text "Cancel" -command {destroy .config}
  button $t.btns.save   -text "Save"   -command {save_config_dialog}
  button $t.btns.load   -text "Load"   -command {load_config_dialog}
  pack $t.btns.ok $t.btns.cancel $t.btns.save $t.btns.load -side left -padx 4
  grid $t.btns -row 5 -column 0 -columnspan 2 -pady 8
}

proc save_config_dialog {} {
  set path [tk_getSaveFile -parent .config -title "Save settings" \
    -initialfile "settings.cfg"]
  if {$path eq ""} return
  set range_hours [.config.e_range get]
  set fs [.config.c_font get]
  try {
    set f [open $path w]
  } on error {msg} {
    tk_messageBox -parent .config -icon error -message "Cannot write: $msg"
    return
  }
  if {[string is double -strict $range_hours] && $range_hours > 0} {
    puts $f "max_time=[expr {int($range_hours * 3600)}]"
  }
  if {[string is integer -strict $fs] && $fs >= 8 && $fs <= 20} {
    puts $f "font_size=$fs"
  }
  set ff [.config.c_family get]
  if {$ff ne ""} {
    puts $f "font_family=$ff"
  }
  set iv [.config.e_interval get]
  if {[string is double -strict $iv] && $iv > 0} {
    puts $f "update_interval=$iv"
  }
  puts $f "show_1m=$::cfg_show_1m"
  puts $f "show_5m=$::cfg_show_5m"
  puts $f "show_15m=$::cfg_show_15m"
  close $f
}

proc load_config_dialog {} {
  set path [tk_getOpenFile -parent .config -title "Load settings"]
  if {$path eq ""} return
  try {
    set f [open $path r]
  } on error {msg} {
    tk_messageBox -parent .config -icon error -message "Cannot read: $msg"
    return
  }
  array set vals {}
  while {[gets $f line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} continue
    set eq [string first "=" $line]
    if {$eq < 0} continue
    set k [string trim [string range $line 0 [expr {$eq - 1}]]]
    set v [string trim [string range $line [expr {$eq + 1}] end]]
    set vals($k) $v
  }
  close $f
  if {[info exists vals(max_time)] && [string is double -strict $vals(max_time)]} {
    .config.e_range delete 0 end
    .config.e_range insert 0 [expr {$vals(max_time) / 3600.0}]
  }
  if {[info exists vals(font_size)] && [string is integer -strict $vals(font_size)] \
      && $vals(font_size) >= 8 && $vals(font_size) <= 20} {
    .config.c_font set $vals(font_size)
  }
  if {[info exists vals(font_family)] && $vals(font_family) ne ""} {
    .config.c_family set $vals(font_family)
  }
  if {[info exists vals(update_interval)] && [string is double -strict $vals(update_interval)] \
      && $vals(update_interval) > 0} {
    .config.e_interval delete 0 end
    .config.e_interval insert 0 $vals(update_interval)
  }
  foreach {k var} {show_1m ::cfg_show_1m show_5m ::cfg_show_5m show_15m ::cfg_show_15m} {
    if {[info exists vals($k)] && [string is boolean -strict $vals($k)]} {
      set $var [expr {$vals($k) ? 1 : 0}]
    }
  }
}

bind .canvas <Button-3> {show_config}

# Force window to render, then load initial data
update
initial_update
after $::update_interval update_graph

# Local Variables:
# tcl-indent-level: 2
# End:
