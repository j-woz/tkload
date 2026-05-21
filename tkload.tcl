#!/usr/bin/env wish

# tload - Tcl/Tk clone of xload system load monitor for Linux

package require Tk

set ::width 300
set ::height 340
set ::graph_data {}
set ::max_time 3600
set ::update_interval 1000
set ::start_time [clock seconds]
set ::show_1m 1
set ::show_5m 1
set ::show_15m 1

# Get current load average from /proc/loadavg
proc get_load {} {
  if {[catch {open "/proc/loadavg" r} f]} {
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

# Draw the load graph
proc draw_graph {load1 load5 load15} {
  set c .canvas
  set w [winfo width $c]
  set h [winfo height $c]
  set pad 30
  set bottom_pad 60

  # Draw background
  $c create rect 0 0 $w $h -fill white

  # Draw scale and grid
  set max_load 4.0

  # Horizontal grid lines
  set plot_height [expr {$h - $pad - $bottom_pad}]
  for {set i 0} {$i <= 4} {incr i} {
    set y [expr {$h - $bottom_pad - ($i * $plot_height / 4)}]
    $c create line $pad $y $w $y -fill lightgray -dash {2 2}
    $c create text [expr {$pad - 5}] $y -text "$i.0" -anchor e -font "TkDefaultFont 8"
  }

  # Draw axes
  $c create line $pad $pad $pad [expr {$h - $bottom_pad}] -fill black -width 2
  $c create line $pad [expr {$h - $bottom_pad}] $w [expr {$h - $bottom_pad}] -fill black -width 2

  set now [clock seconds]
  set scale [expr {$plot_height / $max_load}]

  # Convert time to log scale x position
  proc time_to_x {time_ago w pad} {
    if {$time_ago <= 0} {
      return [expr {$w - $pad}]
    }
    set log_scale [expr {log($time_ago + 1) / log(3601.0)}]
    return [expr {$pad + (($w - 2*$pad) * (1.0 - $log_scale))}]
  }

  # Draw x-axis labels (positioned to avoid legend)
  set label_times {60 300 3600}
  set label_names {"1m ago" "5m ago" "1h ago"}

  foreach time $label_times name $label_names {
    set x [time_to_x $time $w $pad]
    $c create line $x [expr {$h - $bottom_pad}] $x [expr {$h - $bottom_pad + 5}] -fill black
    $c create text $x [expr {$h - $bottom_pad + 20}] -text $name -anchor n -font "TkDefaultFont 7"
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
    set x [time_to_x $time_ago $w $pad]

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

  # Draw labels
  $c create text 10 10 -text "Load: 1m:$load1  5m:$load5  15m:$load15" \
    -anchor nw -font "TkDefaultFont 10 bold"

  # Draw legend with clickable rectangles at the top
  set legend_x [expr {$w - 120}]
  set legend_y 30

  # Draw rectangles around legend items (white fill for clickability)
  set rect1 [$c create rect [expr {$legend_x - 55}] [expr {$legend_y - 10}] \
    [expr {$legend_x - 25}] [expr {$legend_y + 10}] -fill white -outline black -width 1]
  set text1 [$c create text [expr {$legend_x - 40}] $legend_y -text "R:1m" \
    -anchor center -font "TkDefaultFont 8" -fill black]

  set rect5 [$c create rect [expr {$legend_x - 20}] [expr {$legend_y - 10}] \
    [expr {$legend_x + 10}] [expr {$legend_y + 10}] -fill white -outline black -width 1]
  set text5 [$c create text [expr {$legend_x - 5}] $legend_y -text "G:5m" \
    -anchor center -font "TkDefaultFont 8" -fill black]

  set rect15 [$c create rect [expr {$legend_x + 15}] [expr {$legend_y - 10}] \
    [expr {$legend_x + 45}] [expr {$legend_y + 10}] -fill white -outline black -width 1]
  set text15 [$c create text [expr {$legend_x + 30}] $legend_y -text "B:15m" \
    -anchor center -font "TkDefaultFont 8" -fill black]

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
wm title . "tload"
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

# Start updating
update_graph

# Local Variables:
# tcl-indent-level: 2
# End:
