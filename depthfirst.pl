#!/usr/bin/perl -w
use strict;

# working with code developed for newsuduko.pl (originals on Google Drive) 1520

use DBI;

# http://search.cpan.org/~jlmorel/Win32-Console-ANSI-1.10/lib/Win32/Console/ANSI.pm

use Win32::Console::ANSI;
use Win32::Console::ANSI qw/ Title Cls /;
use Term::ANSIScreen qw/:color :cursor :screen /;

our $r_offset = 3;
our $c_offset = 3;

our $grid_color = "white";
our $orig_color = "bold yellow";
our $std_color  = "yellow";
              
our @original   = ();

our $sqlitestr = "dbi:SQLite:mcvsudoku.sqlite";

our $verbose   = 0;

our $sctr      = 0; # counts solutions
our $cctr      = 0; # counts # of times the recursive function 'solve_board' is called
our $actr      = 0; # counts #of unique boards we have solved

our $answer;
our @answers   = ();

our $outfile   = 'answers.tab';

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
    
    # locate 1, 1; print "@ This is (1,1)", savepos; 
    # print locate(24,60), "@ This is (24,60)"; loadpos;
    # print down(2), clline, "@ This is (3,16)\n";
    # color 'black on white'; clline;
    # print "This line is black on white.\n";
    # print color 'reset'; print "This text is normal.\n";
    # print colored ("This text is bold blue.\n", 'bold blue');
    # print "This text is normal.\n";
    # print colored ['bold blue'], "This text is bold blue.\n";
    # print "This text is normal.\n";

}

# +-----------------------------------------------------------------------+
# | sub get_library: get current set of boards from the sqlite database   |
# +-----------------------------------------------------------------------+
sub get_library {
    my ($dbh, $sth, $sql);
    my  $table = "sudokuboards";
    my ($board, $n);
    my  @a = ();
    
    
    $dbh = DBI -> connect($sqlitestr, "", "", {RaiseError => 1, AutoCommit => 1}) or
        die("Unable to connect to database: $DBI::errstr\n\n");
        
    $sql  = "SELECT Board FROM $table WHERE rotation = 0";
    
    $sth = $dbh -> prepare($sql) or
        die("Unable to prepare SQL: $DBI::errstr [$sql]\n\n");
    
    $sth -> execute() or
        die("Failed executing SQL: $DBI::errstr [$sql]\n\n");
    
    # Assign field to variables, and go get the data.
    $sth -> bind_columns(\$board);
    
    while ($sth -> fetch()) {
        
        push(@a,$board);
        
    }
    
    $sth -> finish();
    
    # disconnect from database
    $dbh -> disconnect;
    
    $n = @a;
    
    print STDERR "\n$n sudoku boards loaded from the sqlite database.\n\n";
    
    return( @a );
    
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
# | sub display_board                                                        |
# +-----------------------------------------------------------------------+
sub display_board {
    my @a = @_;
    my ( $x, $y, $z );
    
    for $x ( 0 .. 8 ) {
        
        for $y ( 0 .. 8 ) { 
            
            $z = $a[$x][$y];
            
            print STDERR "[" . ( $z == 0 ? "_" : $z ) . "]"
            
        }
        
        print STDERR "\n";
        
    }
        
    print STDERR "\n";

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
        
        print STDERR "Values already in this [$locale]:\n";
        
        for ($i = 0; $i < $n; $i++ ) {
            
            print STDERR "[" . $a[ $i ] . "]\n";
            
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
        
        # No gaps remain on the board!
        
        $sctr++;
        
        # print STDERR "\nSolution $sctr found! [level = $level]:\n";
        
        $answer = unwind( @a );
        
        push( @answers, $answer );
        
        # display_board( @a );
        
        display_progress( @a );
        
        $cctr = 0;

        print "\n\n\n\nSOLUTION [$sctr]: Enter QUIT to exit:";
        
        $val = <STDIN>;
        
        Cls();
        
        if ( lc( substr( $val, 0, 1 ) eq "q" ) ) {
            
            printf("\e[?25h"); # show the cursor
            
            exit( 1 );
            
        }
        
        draw_grid( $grid_color );
    
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
            
            # print STDERR "[$level] Insert [" . $b[ $i ] . "] at ($r, $c )\n";
            
            display_progress( @a );
            
            $val = solve_board( $level + 1, @a );
            
            # Return the cell value to 0!
            
            $a[ $r ][ $c ] = 0;
            
        }
        
    }
    
    return( 0 );
    
}


# +-----------------------------------------------------------------------+
# | sub save_answer: Write an answer to a file                            |
# +-----------------------------------------------------------------------+
sub save_answer {
    my ( $difficulty, $board, $answer ) = @_;
    my ( $fh );
    
    $actr++;
    
    open( $fh, ( $actr == 1 ? '>' : '>>' ), $outfile ) or die "Could not open file [$outfile]\n";
    
    print $fh "$difficulty\t$board\t$answer\n";
    
    close $fh;

}

# +-----------------------------------------------------------------------+
# | M A I N   Program                                                     |
# +-----------------------------------------------------------------------+

my ( $n, $s, $i, $t, $val );
my   @a;

my @boards = (
  '000400000020800105070001600007500000310000079000003800002300040105008060000006000'  # 00 Very difficult[6][57]
, '200000080000060500043805000068500270000000000034007960000106750006090000020000003'  # 01 Boston Globe [Sunday][0][55]
, '000004000603200005950100000004010070002806900070040100000009061700008302000500000'  # 02 2012-06-10 Boston Globe [Sunday][1][55]
, '003000600200306001010908050060080090908000106030010040070401080600705002009000700'  # 03 2012-06-11 Boston Globe [Monday][0][51]
, '090107080050306020007000600023040710700000004045030860009000200010608040060209070'  # 04 2012-06-12 Boston Globe [Tuesday][0][49]
, '090030004007000000050462000008000400270806035003000800000324090000000500300090010'  # 05 2012-06-13 Boston Globe [Wednesday][0][55]
, '000000000187050000365120009000040083020000060810070000700019846000060391000000000'  # 06 2012-06-14 Boston Globe [Thursday][0][53]
, '400050002000900060902030001007000039000040000230000800100020905070005000300070006'  # 07 2012-06-15 Boston Globe [Friday][0][56]
, '000000010700006200804005000000009020320804091050100000000400603008300007060000000'  # 08 2012-06-16 Boston Globe [Saturday][2][57]
, '000200140010090000864300000300000007020030060100000005000009873000040090038006000'  # 09 2012-06-17 Boston Globe [Sunday][2][57]
, '350080900200509000000000710080003052000108000510200080038000000000401006002030097'  # 10 2012-06-18 Boston Globe [Monday][0][53]
, '000401000150000036040608090702306509000000000305102807080503020670000053000907000'  # 11 2012-06-19 Boston Globe [Tuesday][0][49]
, '900620008070000005050080040000800000100030004000007000010040030200000080600051002'  # 12
, '000000000900836001081000520008702100000090000003408200015000690200145007000000000'  # 13
, '700000805020500970000071000000000218000000000953000000000850000018007090406000007'  # 14
);

# $n = @boards = get_library();

$n = @boards;

print STDERR "\nThere are [$n] boards in the array.\n\n";

printf("\e[?25l"); # hide the cursor

Cls();

draw_grid( $grid_color );

for ( $i = 0; $i < $n; $i++ ) {
    
    if ( !( $i == 13 ) ) {
        
        next;
        
    }
    
    $cctr = $sctr = 0;

    $s = $boards[ $i ]; # 2 and 9 take some processing
        
    @original = load_board( $s );

    @a        = load_board( $s );
    
    # display_board( @a );
    
    $val = solve_board( 0, @a );
    
    # We only want boards with unique solutions ( $sctr = 1 )
    
    if ( $sctr == 1 ) {
        
        save_answer( $cctr, $s, $answer );
        
    }
    
    if ( ( $i % 10 ) == 0 ) {
        
        print STDERR "==> Checked [$i] of [$n]\n";
        
    }
    

}

printf("\e[?25h"); # show the cursor

Cls();

foreach $s ( @answers ) {
    
    @a = load_board( $s );
    
    draw_grid( $grid_color );
    
    display_progress( @a );
    
    $r_offset += 20;
    
}