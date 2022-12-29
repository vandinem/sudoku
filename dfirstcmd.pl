use strict;

# working with code developed for newsuduko.pl (originals on Google Drive) 1520

# 2015-11-21 Command-line (single board) adaptation of depthfirst.pl

# http://search.cpan.org/~jlmorel/Win32-Console-ANSI-1.10/lib/Win32/Console/ANSI.pm

# THE DEFAULT SETTINGS do not provide the animated grid showing the algo working through
# possible solutions.  This looks cool, but VERY slow (a few minutes vs a few seconds on
# the solution of a difficult board). But -V will set 'verbose' and show this if wanted.
# The -G option will display the non-verbose solution(s) as a simple grid (easier to read)
# while the default will sent the solution to STDOUT in a single line.

use Win32::Console::ANSI;
use Win32::Console::ANSI qw/ Title Cls /;
use Term::ANSIScreen qw/:color :cursor :screen /;

our $r_offset = 3;
our $c_offset = 3;

our $grid_color = "white";
our $orig_color = "bold yellow";
our $std_color  = "yellow";
              
our @original   = ();

our $verbose   = 0;
our $grid      = 0;

our $sctr      = 0; # counts solutions
our $cctr      = 0; # counts # of times the recursive function 'solve_board' is called
our $actr      = 0; # counts #of unique boards we have solved

our $answer;
our @answers   = ();

# +-----------------------------------------------------------------------+
# | sub draw_grid                                                         |
# +-----------------------------------------------------------------------+
sub draw_grid {
    my ( $color ) = @_;
    my ( $r, $c, $y );
    
    Cls();

    locate( $r_offset, 1 );
    
    savepos;
        
    for $y ( 0 .. 8 ) {
        
        if ( ( $y % 3 ) == 0 ) {
          
            print " " x $c_offset;
            
            print colored [ $color ], "+---------+---------+---------+\n";
            
        }
          
        print " " x $c_offset;
        
        print colored [ $color ], "|         |         |         |\n";
        
    }
 
    print " " x $c_offset;
    
    print colored [ $color ], "+---------+---------+---------+";
        
    print "\n";
    
}

# +-----------------------------------------------------------------------+
# | sub display_progress                                                  |
# +-----------------------------------------------------------------------+
sub display_progress {
    my   @a = @_;
    my ( $x, $y, $z );
    my ( $r, $c );
    my ( $rlines, $clines );
    my   $ind_original;
    
    for $x ( 0 .. 8 ) {
        
        for $y ( 0 .. 8 ) {
          
            # print STDERR "y[$y]\n";
          
            # Besides the absolute row offset, need to account for the border rows we add between minor grids
            
            $rlines = ( $x < 3 ) ? 1 : ( $x < 6 ) ? 2 : 3 ;
          
            # Besides the absolute col offset, need to account for the border cols we add between minor grids
            
            $clines = ( $y < 3 ) ? 1 : ( $y < 6 ) ? 2 : 3 ;
          
            $r = $r_offset + $rlines + $x;
            $c = $c_offset + $clines + ( $y * 3 ) + 2;
            
            # print STDERR "o[$c_offset], l[$clines], y[$y], c[$c]\n";
            
            $ind_original = ( $original[$x][$y] eq "0" ) ? 0 : 1;
            
            $z = $a[$x][$y];
            
            locate( $r, $c );
            
            if ( $ind_original == 1 ) {
                
                print colored [$orig_color], ( $z == 0 ) ? " " : $z;
                # print colored [ "white" ], ( $z == 0 ) ? " " : $z;
                
            }
            else {
                
                print colored [$std_color],  ( $z == 0 ) ? " " : $z;
                # print colored [ "blue" ],  ( $z == 0 ) ? " " : $z;
              
            }
            
        }
        
    }
        
    locate( 18, 4 );
    
    print "sctr: [$sctr], cctr: [$cctr]\n";

}

# +-----------------------------------------------------------------------+
# | sub load_board                                                        |
# +-----------------------------------------------------------------------+
sub load_board {
    my ( $s ) = @_;
    my   @a;
    my ( $x, $y );
    
    
    for $x ( 0 .. 8 ) {
        
        for $y ( 0 .. 8 ) {
            
            $a[$x][$y] = substr( $s, ( $x * 9 ) + $y , 1 );
            
        }
        
    }
    
    return( @a );
    
}

# +-----------------------------------------------------------------------+
# | sub next_gap: where is the first open cell on the board?              |
# +-----------------------------------------------------------------------+
sub next_gap {
    my   @board = @_;
    my ( $z, $r, $c );
    
    $r = $c = 0;
    
    while ( $r < 9 ) {
        
        $z = $board[$r][$c];
        
        if ( $z == 0 ) {
            
            return( $r, $c );
            
        }
        
        $c++;
        
        if ( $c == 9 ) {
            
            $c = 0;
            
            $r++;
            
        }
        
    }
    
    return( -1, -1 );
    
}

# +-----------------------------------------------------------------------+
# | sub col_values: for identified cell, list numbers already in column   |
# +-----------------------------------------------------------------------+
sub col_values {
    my ( $r, $c, @board ) = @_;
    my ( $i, $val, $n );
    my   @a = ();
    
    for ( $i = 0; $i < 9; $i++ ) {
        
        $val = $board[ $i ][ $c ];
        
        if ( $val == 0 ) {
            
            next;
            
        }
        
        push( @a, $val );
        
    }
    
    show_found( "Column", sort( @a ) );
    
    return( @a );
    
}

# +-----------------------------------------------------------------------+
# | sub row_values: for identified cell, list numbers already in row      |
# +-----------------------------------------------------------------------+
sub row_values {
    my ( $r, $c, @board ) = @_;
    my ( $i, $val, $n );
    my   @a = ();
    
    for ( $i = 0; $i < 9; $i++ ) {
        
        $val = $board[ $r ][ $i ];
        
        if ( $val == 0 ) {
            
            next;
            
        }
        
        push( @a, $val );
        
    }
    
    show_found( "Row", sort( @a ) );
    
    return( @a );
    
}

# +-----------------------------------------------------------------------+
# | sub grid_values: for given cell, list numbers already in local grid   |
# +-----------------------------------------------------------------------+
sub grid_values {
    my ( $r, $c, @board ) = @_;
    my ( $i, $val, $n, $start_r, $start_c, $rr, $cc );
    my   @a = ();
    
    # Identify which columns and which rows define the grid
    
    $start_r = ( $r < 3 ? 0 : ( $r < 6 ? 3 : 6 ) );
    $start_c = ( $c < 3 ? 0 : ( $c < 6 ? 3 : 6 ) );
    
    for ( $rr = $start_r; $rr < $start_r + 3; $rr++ ) {
        
        for ( $cc = $start_c; $cc < $start_c + 3; $cc++ ) {
            
            $val = $board[ $rr ][ $cc ];
            
            if ( $val == 0 ) {
                
                next;
                
            }
            
            push( @a, $val );
            
        }
        
    }
    
    show_found( "Local Grid", sort( @a ) );
    
    return( @a );
    
}

# +-----------------------------------------------------------------------+
# | sub show_found: display the numbers found                             |
# +-----------------------------------------------------------------------+
sub show_found {
    
    my ( $locale, @a ) = @_;
    my ( $n, $i );
    
    if ( $verbose == 1 ) {
        
        $n = @a;
        
        # print STDERR "Values already in this [$locale]:\n";
        
        for ($i = 0; $i < $n; $i++ ) {
            
            # print STDERR "[" . $a[ $i ] . "]\n";
            
        }
        
    }
    
}

# +-----------------------------------------------------------------------+
# | sub candidates: for identified cell, what numbers are still available |
# +-----------------------------------------------------------------------+
sub candidates {
    my ( $r, $c, @board ) = @_;

    my   @cvalues;
    my   @rvalues;
    my   @gvalues;
    my ( $x, $i );
    my   @map = ( 0 ) x 10; # We'll only need slots 1..9
    my   @a;
   
    # Look at the row, column, and local grid to figure out which numbers
    # are worth trying.
    
    @cvalues = col_values ( $r, $c, @board );
    @rvalues = row_values ( $r, $c, @board );
    @gvalues = grid_values( $r, $c, @board );
    
    foreach $x ( @cvalues, @rvalues, @gvalues ) {
        
        $map[ $x ] = 1;
        
    }
    
    foreach ( $i = 1; $i < 10; $i++ ) {
        
        # print STDERR "$i [" . $map[ $i ] . "]\n";
        
        if ( $map[ $i ] != 1 ) {
            
            push( @a, $i );
            
        }
        
    }
    
    show_found( "Candidates", sort( @a ) );
    
    return( @a );
    
}

# +-----------------------------------------------------------------------+
# | sub unwind: Convert board array into a string                         |
# +-----------------------------------------------------------------------+
sub unwind {
    my @board = @_;
    my ( $i, $j, $t );
    
    $t = "";
    
    for ( $i = 0; $i < 9; $i++ ) {
        
        for ( $j = 0; $j < 9; $j++ ) {
            
            $t .= $board[ $i ][ $j ];
            
        }
        
    }
    
    return( $t );
    
}

# +-----------------------------------------------------------------------+
# | sub windup: print string as a simple board                            |
# +-----------------------------------------------------------------------+
sub windup {
    my ( $s ) = @_;
    my ( $i, $t, $x );
    
    $x = "";
    
    for ( $i = 0; $i < 9; $i++ ) {
        
        if ( ( $i > 0 ) && ( ( $i % 3 ) == 0 ) ) {
            
            $x .= "---+---+---\n";
            
        }
        
        
        $t  = substr( $s, ( $i * 9 ) + 0, 3) . "|" . substr( $s, ( $i * 9 ) + 3, 3) . "|" . substr( $s, ( $i * 9 ) + 6, 3);
        
        $x .= "$t\n";
        
    }
    
    return( $x );
    
}

# +-----------------------------------------------------------------------+
# | sub solve_board: look for a solution                                  |
# +-----------------------------------------------------------------------+
sub solve_board {
    my ( $level,  @a ) = @_;
    my   @b;
    my   @c;
    my ( $r, $c, $n, $i, $val );
    
    $cctr++; # Counts each call of this function
    
    ( $r, $c ) = next_gap( @a );
    
    if ( $r == -1 ) {
        
        # No gaps remain on the board!  Record and save this solution:
        
        $sctr++;
        
        $answer = unwind( @a );
        
        push( @answers, $answer );
        
        # ... and then push on to find any others.  Fist clear the board:
        
        $cctr = 0;
        
        if ( $verbose == 1 ) {
            
            Cls();
            
            draw_grid( $grid_color );
            
        }
    
        return( 1 );
        
    }
        
    # print STDERR "\n\nNext gap found row [$r] and column [$c]\n\n";
    
    # An open space was found.  Get the list of available choices and try each one:
    
    $n = @b = candidates( $r, $c, @a );
    
    if ( $n == 0 ) {
        
        # No available numberrs are found to try in this gap!
        
        return( 0 );
        
    }
    else {
        
        for ( $i = 0;$i < $n; $i++ ) {
            
            $a[ $r ][ $c ] = $b[ $i ];
            
            if ( $verbose == 1 ) {
                
                display_progress( @a );
                
            }
            
            $val = solve_board( $level + 1, @a );
            
            # Return the cell value to 0!
            
            $a[ $r ][ $c ] = 0;
            
        }
        
    }
    
    return( 0 );
    
}

# +-----------------------------------------------------------------------+
# |  check_args:  set variables based on command-line arguments           |
# +-----------------------------------------------------------------------+
sub check_args {
    my  @a = @_;
    my ( $s, $tag, $fname, $ctr );
    
    $fname = "";
    
    $ctr   = 0;
    
    foreach $s ( @a ) {
        
        # Remove any extra quote delimiters
        $s =~ s/'//g;
        
        $tag = uc( substr( $s, 0, 2 ) );
        
        if ( $tag eq "-F" ) {
            
            $fname = substr( $s, 2, length( $s ) - 2 );
            
        }
        elsif ( $tag eq "-V")  {
            
            # Show output to screen
            
            $verbose = 1;
            
        }
        elsif ( $tag eq "-G")  {
            
            # If NOT verbose, show simple output as a grid
            
            $grid    = 1;
            
        }
        
        $ctr++;
        
    }
    
    return( $ctr );
    
}


# +-----------------------------------------------------------------------+
# | M A I N   Program                                                     |
# +-----------------------------------------------------------------------+

my ( $n, $s, $t, $val, $ctr );
my   @a;

$val = check_args( @ARGV );

# Read in the string representing the board from STDIN:

while ( $s = <STDIN> ) {
    
    chomp( $s );
    
    if ( substr( $s, 0, 1 ) eq "#" ) {
        
        next;
        
    }
    
    if ( length( $s ) != 81 ) {
        
        next;
        
    }
    
    if ( $verbose == 1 ) {
        
        # Prepare the console box display
        
        printf("\e[?25l"); # hide the cursor
        
        Cls();
        
        draw_grid( $grid_color );
    
    }
    
    # Load and Solve the puzzle:
        
    $cctr = $sctr = 0;
        
    @original = load_board( $s );
    
    @a        = load_board( $s );
    
    $val = solve_board( 0, @a );
    
    if ( $verbose == 1 ) {
        
        printf("\e[?25h"); # show the cursor
        
    }
    
    # All answers are stored in the @answers array.  Display and write these strings to STDERR
    
    if ( $verbose == 1 ) {
        
        Cls();
        
        foreach $s ( @answers ) {
            
            @a = load_board( $s );
                
            draw_grid( $grid_color );
            
            display_progress( @a );
            
            $r_offset += 20;
            
        }
        
    }
    else {
        
        $ctr = 0;
        
        foreach $s ( @answers ) {
            
            $ctr++;
            
            if ( $grid == 1 ) {
                
                print "\n$ctr\n\n";
                
                print windup( $s );
                
                print "\n";
                
            }
            else {
                
                print "$ctr\t$s\n";
                
            }
            
        }
        
    }

}