##!/usr/bin/perl -w

#!/Users/markvandine/perl5/perlbrew/perls/perl-5.14.2/bin/perl -w
use strict;
use Term::ANSIColor;
use List::MoreUtils qw/ uniq /; # <--- need to point shebang to the right perlbrew location.  see testpdf.pl, also use cpanm to install 
use DBI;

our $host = "www.vandine.biz";
our $db   = "vandineb_PuzzleTools";
our $usr  = "vandineb_root";
our $pwd  = "brainiac5";

our $sqlitestr = "dbi:SQLite:mcvsudoku.sqlite";

# Sudoku boards are received as 81 character strings representing a concatenation
# of 9 rows of 9 cells each.
#
# These are arranged into a 9x9 matrix (rxc)
#
# The 9x9 matrix is itself a 3x3 meta-matrix of 3x3 matrices (RxC of rxc)
#
# The original solver had a very simple brute force approach to solving boards.
# This approach attempts to be a little more intelligent, with a goal of
# scoring solutions to get an accurate measurment of difficulty.

our $strlen     = 81;
our @log        = ();
our $nposers    =  0;

# +-----------------------------------------------------------------------+
# | sub test_board: checks for a well-formed game                         |
# +-----------------------------------------------------------------------+
sub test_board {
    my ($s) = @_;
    my ($i, $c);
    
    if (length($s) != $strlen) {
        
        print STDERR "String for board was not 81 characters in length.\n";
        
        return 0;
        
    }
    
    for ($i = 0;$i < $strlen;$i++) {
        
        $c = substr($s,$i,1);
        
        if (index("0123456789",$c) < 0) {
            
            print STDERR "String for board contains invalid character [$c] in position [$i]\n";
            
            return 0;
            
        }
        
    }
    
    return 1;
    
}


# +-----------------------------------------------------------------------+
# | sub count_open: How many open spaces on the board?                    |
# +-----------------------------------------------------------------------+
sub count_open {
    my ($s) = @_;
    my  @a;
    my  $ctr = 0;
    my  $cell;
    
    @a= split(//,$s);
    
    foreach $cell (@a) {
        
        if ($cell eq "0") {
            
            $ctr++;
            
        }
        
    }
    
    return $ctr;
    
}

# +-----------------------------------------------------------------------+
# | sub create_mask                                                       |
# +-----------------------------------------------------------------------+
sub create_mask {
    my ($board, $num) = @_;
    my  $mask = "0" x $strlen;
    my ($r, $c, $cstr, $i, $R, $C, $localgrid, $offset); 
    
    # Mask out rows:
    
    for ($r = 0;$r < 9;$r++) {
        
        if (index(substr($board,$r * 9,9),$num) >= 0) {
            
            substr($mask,$r * 9,9) = "X" x 9;
            
        }
        
    }
    
    # Mask out columns.  This is a little trickier:
    
    for ($c = 0; $c < 9;$c++) {
        
        # Creat a synthetic string of the board values in column c
        $cstr = "";
        for ($i = 0;$i < 9;$i++) {
            
            $cstr .= substr($board,($i * 9) + $c,1);
            
        }
        
        # see if $num is here, and if so, update the mask
        if (index($cstr,$num) >= 0) {
            
            for ($i = 0;$i < 9;$i++) {
                
                substr($mask,($i * 9) + $c,1) = 'X';
                
            }
            
        }
        
    }
    
    # ... and now local grids.  This is similar to our approach with
    # columns: create a synthetic representation of the cells, and update
    # the mask if $num is found there.
    
    for ($R = 0;$R < 3;$R++) {
        
        for ($C = 0;$C < 3;$C++) {
            
            $r = $R * 3;
            $c = $C * 3;
            
            $localgrid = "";
            for ($i = 0;$i < 3;$i++) {
                
                $offset = (($r + $i) * 9) + $c;
                
                $localgrid .= substr($board, $offset, 3);
                
            }
            
            # if (($R == 1) && ($C == 0)) { print STDERR "num: [$num], local: [$localgrid]\n" }
            
            # see if $num is here, and if so, update the mask
            if (index($localgrid,$num) >= 0) {
                
                for ($i = 0;$i < 3;$i++) {
                    
                    $offset = (($r + $i) * 9) + $c;
                    
                    # if (($R == 1) && ($C == 0)) { print STDERR "r[$r], i[$i], c[$c], o[$offset],\n$mask\n"; }
                    
                    substr($mask, $offset, 3) = "XXX";
                    
                }
                
            }
        }
        
    }
    
    # Finally, make sure any cell in the board that has a value already is masked out ...
    for ($i = 0;$i < $strlen;$i++) {
        
        if (substr($board,$i,1) ne "0") {
            
            substr($mask,$i,1) = "X";
            
        }
        
    }
    
    return($mask);
    
}

# +-----------------------------------------------------------------------+
# | sub check_local: row and column of single open cell in local grid     |
# +-----------------------------------------------------------------------+
sub check_local {
    my ($mask, $R, $C) = @_;
    my ($r, $c, $localgrid, $i, $offset, $pos);
    
    $r = $R * 3;
    $c = $C * 3;
    
    $localgrid = "";
    for ($i = 0;$i < 3;$i++) {
        
        $offset = (($r + $i) * 9) + $c;
        
        $localgrid .= substr($mask, $offset, 3);
        
    }
    
    # if (($R == 2) && ($C == 2)) { print STDERR "local[$localgrid]\n"; }
    
    if (count_open($localgrid) == 1) {
        
        # If just one cell in the local grid is open, figure out its offset
        # in the 81 character string that defines the board.
        
        $pos = index($localgrid,"0");
        
        $offset = (($r + int($pos / 3)) * 9) + ($c + ($pos % 3));
        
        return($offset);
        
    }
    else {
        
        return(-1);
        
    }
    
}

# +-----------------------------------------------------------------------+
# | sub test_rcintersect                                                  |
# +-----------------------------------------------------------------------+
sub test_rcintersect {
    my ($board, $ntest) = @_;
    my ($num, $mask, $R, $C, $r, $c, $i, $localgrid, $offset);
    my  @a = ();
    
    # For each number, create a mask of the board that marks where it CAN'T
    # go (because it is already present in the row, column or local grid).
    # From that mask, you can quickly identify any local grid where there is
    # a single gap remaining where the number can be placed.
    
    for ($num = 1;$num <= 9;$num++) {
        
        $mask = create_mask($board,$num);
        
        # Now we check the mask.  We want to keep track of all the changes we
        # can make [it helps to determine puzzle difficulty].
        
        for ($R = 0;$R < 3;$R++) {
            
            for ($C = 0;$C < 3;$C++) {
                
                $offset = check_local($mask,$R,$C);
                
                # if (($R == 2) && ($C == 2) && ($num == 6)) { print_board($mask,$mask); }
                
                if ($offset >= 0) {
                    
                    # An answer! Record the number and offset (where it goes) in the board:
                    push(@a,[($num, $offset, $ntest)]);
                    
                    substr($board,$offset,1) = $num;
                    
                }
                
            }
            
        }
        
    }
    
    return($board, @a);
    
}

# +-----------------------------------------------------------------------+
# | sub test_coltest                                                      |
# +-----------------------------------------------------------------------+
sub test_coltest {
    my ($board, $ntest) = @_;
    my ($num, $c, $r, $mask, $val, $cstr, $rstr, $offset, $pos);
    my  @a = ();
    
    # Checks each column to see if intersecting rows isolate a single cell
    # where a given number can go:
    
    for ($num = 1;$num <= 9;$num++) {
        
        for ($c = 0;$c < 9;$c++) {
            
            # Create a string that represents the whole column
            $cstr = "";
            for ($r = 0;$r < 9;$r++) {
                
                $cstr .= substr($board,($r * 9) + $c,1);
                
            }
            
            # If $num is here already, we don't need to check further:
            if (index($cstr,$num) >= 0) {
                
                next;
                
            }
            
            # Create a mask of the column
            
            $mask = "";
            
            for ($r = 0;$r < 9;$r++) {
                
                $val = substr($cstr,$r,1);
                
                if ($val eq "0") {
                    
                    # Cell looks open ... is $num somewhere else on this row already?
                    $rstr = substr($board,$r * 9,9);
                    if (index($rstr,$num) >= 0) {
                        
                        # Yes! So this cell isn't viable:
                        
                        $mask .= "X";
                        
                    }
                    else {
                        
                        # No! So $num might be valid here:
                        
                        $mask .= "0";
                        
                    }
                    
                }
                else {
                    
                    $mask .= "X";
                    
                }
                
            }
            
            # The mask is complete.  If there is only one open position, we have a solution:
            if (count_open($mask) == 1) {
                
                #$pos will tell us which row the single open cell is:
                
                $pos    = index($mask,"0");
                
                $offset = ($pos * 9) + $c;
                
                push(@a,[($num, $offset, $ntest)]);
                
                substr($board,$offset,1) = $num;
                
            }
            
        }
        
    }
    
    return($board, @a);
    
}

# +-----------------------------------------------------------------------+
# | sub test_rowtest                                                      |
# +-----------------------------------------------------------------------+
sub test_rowtest {
    my ($board, $ntest) = @_;
    my ($num, $r, $rstr, $mask, $c, $val, $cstr, $i, $offset, $pos);
    my  @a = ();
    
    # Checks each column to see if intersecting rows isolate a single cell
    # where a given number can go:
    
    for ($num = 1;$num <= 9;$num++) {
        
        for ($r = 0;$r < 9;$r++) {
            
            # Create a string that represents the whole column
            $rstr = substr($board,$r * 9,9);
            
            # If $num is here already, we don't need to check further:
            if (index($rstr,$num) >= 0) {
                
                next;
                
            }
            
            # Create a mask of the row
            
            $mask = "";
            
            for ($c = 0;$c < 9;$c++) {
                
                $val = substr($rstr,$c,1);
                
                if ($val eq "0") {
                    
                    # Cell looks open ... is $num somewhere else on this column already?
                    
                    $cstr = "";
                    for ($i = 0;$i < 9;$i++) {
                        
                        $cstr .= substr($board,($i * 9) + $c,1);
                        
                    }
                    
                    if (index($cstr,$num) >= 0) {
                        
                        # Yes! So this cell isn't viable:
                        
                        $mask .= "X";
                        
                    }
                    else {
                        
                        # No! So $num might be valid here:
                        
                        $mask .= "0";
                        
                    }
                    
                }
                else {
                    
                    $mask .= "X";
                    
                }
                
            }
            
            # The mask is complete.  If there is only one open position, we have a solution:
            if (count_open($mask) == 1) {
                
                #$pos will tell us which row the single open cell is:
                
                $pos    = index($mask,"0");
                
                $offset = ($r * 9) + $pos;
                
                push(@a,[($num, $offset, $ntest)]);
                
                substr($board,$offset,1) = $num;
                
            }
            
        }
        
    }
    
    return($board, @a);
    
}

# +-----------------------------------------------------------------------+
# | sub missing_value                                                     |
# +-----------------------------------------------------------------------+
sub missing_value {
    my ($s) = @_;
    my ($i, $t);
    my  $val;
    
    # print STDERR "missing_value: s[$s]\n";
    
    $t = join("",sort split(//,$s));
    
    for ($i = 0;$i <= 9;$i++) {
        
        if ($i ne substr($t,$i,1)) {
            
            $val = $i;
            
            last;
            
        }
        
    }
    
    # print STDERR "missing value: s[$s], t[$t], val[$val]\n";
    
    return($val);
    
}

# +-----------------------------------------------------------------------+
# | sub test_intersect                                                    |
# +-----------------------------------------------------------------------+
sub test_intersect {
    my ($board, $ntest,$complex) = @_;
    my ($i, $j, $r, $c, $rr, $cc, $rstr, $cstr, $localgrid, $val, $nctr, $vstr, $mask);
    my  @answers = ();
    my  @a;
    
    # For each blank cell on the board, create a reference string for its
    # row, column, and local grid.
    
    do {
        
        $nctr = 0;
        
        for ($i = 0;$i < $strlen;$i++) {
            
            if (substr($board,$i,1) ne "0") {
                
                next;
                
            }
            
            $r  = int($i / 9);
            $c  = $i % 9;
            
            $rr = 3 * int($r / 3);
            $cc = 3 * int($c / 3);
            
            $rstr = substr($board, $r * 9,9);
            
            $cstr = "";
            for ($j = 0;$j < 9;$j++) {
                
                $cstr .= substr($board,($j * 9) + $c,1);
                
            }
            
            $localgrid = "";
            for ($j = 0;$j < 3;$j++) {
                
                $localgrid .= substr($board,(($rr + $j) * 9) + $cc,3);
                
            }
            
            if ($complex == 0) {
                
                # resolve situations where all but one value in a row, column, or
                # local grid has been identified.
                
                if (count_open($rstr) == 1) {
                    
                    $val = missing_value($rstr);
                    
                    push(@answers,[($val, $i, $ntest)]);
                    
                    substr($board,$i,1) = $val;
                    
                    $nctr++;
                    
                }
                
                if (count_open($cstr) == 1) {
                    
                    $val = missing_value($cstr);
                    
                    push(@answers,[($val, $i, $ntest)]);
                    
                    substr($board,$i,1) = $val;
                    
                    $nctr++;
                    
                }
                
                if (count_open($localgrid) == 1) {
                    
                    $val = missing_value($localgrid);
                    
                    push(@answers,[($val, $i, $ntest)]);
                    
                    substr($board,$i,1) = $val;
                    
                    $nctr++;
                    
                }
                
            }
            else {
                
                $vstr = $rstr . $cstr . $localgrid . "0";
                
                @a = uniq split(//,$vstr);
                
                $mask = join("",@a);
                
                # We know that the cell we are looking at is '0', so if we have
                # "0" and all but one of the nine integers, then $mask will be
                # 9 characters in length:
                
                if (length($mask) != 9) {
                    
                    next;
                    
                }
                
                $val = missing_value($mask);
                
                push(@answers,[($val, $i, $ntest)]);
                
                substr($board,$i,1) = $val;
                
                $nctr++;
                
            }
            
        }
        
    } while ($nctr > 0);
    
    return($board, @answers);
    
}

# +-----------------------------------------------------------------------+
# | sub check_board: makes sure a completed board is correct              |
# +-----------------------------------------------------------------------+
sub check_board {
    my ($board) = @_;
    my ($rstr, $cstr, $i, $j);
    my ($r, $c, $R, $C, $localgrid, $unique, $offset);
    my  @a;
    
    # Check each row and column
    for ($i = 0;$i < 9;$i++) {
        
        $r = $c = $i;
        
        $rstr = substr($board, $r * 9,9);
        
        $cstr = "";
        for ($j = 0;$j < 9;$j++) {
            
            $cstr .= substr($board,($j * 9) + $c,1);
            
        }
        
        @a = uniq split(//,$rstr);
        $unique = join("",sort @a);
        
        if ($unique ne "123456789") {
            
            # print STDERR "check_board, row [$i], [$rstr, $unique]\n";
            
            return 0;
            
        }
        
        @a = uniq split(//,$cstr);
        $unique = join("",sort @a);
        
        if ($unique ne "123456789") {
            
            # print STDERR "check_board, column [$i], [$cstr, $unique]\n";
            
            return 0;
            
        }
        
    }
    
    # Now check the 9 local grids:
    
    for ($R = 0;$R < 3;$R++) {
        
        for ($C = 0;$C < 3;$C++) {
            
            $r = $R * 3;
            $c = $C * 3;
            
            $localgrid = "";
            for ($i = 0;$i < 3;$i++) {
                
                $offset = (($r + $i) * 9) + $c;
                
                $localgrid .= substr($board, $offset, 3);
                
            }
            
            @a = uniq split(//,$localgrid);
            $unique = join("",sort @a);
            
            if ($unique ne "123456789") {
                
                # print STDERR "check_board, localgrid [" . ($R + 1) . ", " . ($C + 1) . "], [$localgrid, $unique]\n";
                # die "ERROR: Bad board?  [$board]]n";
                
                return 0;
                
            }
            
        }
        
    }
    
    return 1;

}

# +-----------------------------------------------------------------------+
# | sub solve_board: applies a series of strategies to solve the game.    |
# +-----------------------------------------------------------------------+
sub solve_board {
    my ($board, $difficulty) = @_;
    my ($n, $i, $num, $offset, $testnum, $r, $c, $ntest, $well_formed, $nmin, $ibest);
    my  @a;
    my  @b;
    my ($state, $newboard, $diff);
    
    if (count_open($board) == 0) {
        
        # No blank spaces left ... we're done!
        
        return ($board);
        
    }
    
    # Now run through our Phase I deterministic (no guessing!) tests ...
    
    while (1) {
        
        # Step through tests.  @log will hold a record of each cell we update.
        
        # When a test finds some cells to fill in, update the board, then go back
        # and repeat starting with the simplest test again.  When a test does
        # not find any cells to update, move on to the next test.
        
        
        # This used to be the final test, but since each board should generally end
        # with it, I've moved it up.  When only one cell is empty in the row,
        # column, or local grid, and we fill that with the missing value.
        
        $testnum = 5;
        
        @a     = test_intersect($board,$testnum + $difficulty * 100,0);
        $board = shift @a;
        $n     = @a;
        
        if ($n) {
            
            push(@log,@a);
            
            next;
            
        }
        
        # The 'mask' is the test I do where intersecting rows and columns
        # identify the only place a single number can go in a local grid (because
        # the number is in a row or column intersecting any other cell in the local grid):
        
        $testnum = 1;
        
        @a     = test_rcintersect($board,$testnum + $difficulty * 100);
        $board = shift @a;
        $n     = @a;
        
        if ($n) {
            
            push(@log,@a);
            
            next;
            
        }
        
        # The second test looks at open spaces in each column to see if intersecting
        # rows eliminate all but one possible place for a given number.
        
        $testnum = 2;
        
        @a     = test_coltest($board,$testnum + $difficulty * 100);
        $board = shift @a;
        $n     = @a;
        
        if ($n) {
            
            push(@log,@a);
            
            next;
            
        }
        
        # The third test is like the second, but instead looks at open spaces in
        # each ROW to see if intersecting COLUMNS eliminate all but one possible
        # place for a given number.
        
        $testnum = 3;
        
        @a     = test_rowtest($board,$testnum + $difficulty * 100);
        $board = shift @a;
        $n     = @a;
        
        if ($n) {
            
            push(@log,@a);
            
            next;
            
        }
        
        # The fourth test is deterministic, but it took me a while to figure out so
        # I consider it a little less obvious.  It's an 'intersection' test: for each
        # open space we look to see if we can eliminate all but one possible value
        # based on the contents of the row, column, and local grid.
        #
        # In the more complex situation, 8 of the 9 possible values for the empty
        # cell can be found in the intersecting row, column, or local grid.
        
        $testnum = 4;
        
        @a     = test_intersect($board,$testnum + $difficulty * 100,1);
        $board = shift @a;
        $n     = @a;
        
        if ($n) {
            
            push(@log,@a);
            
            next;
            
        }
        
        last;
        
    }
    
    # So by this point, we've done all we can with our various deterministic
    # strategies.  We can be in one of three states:
    
    #     1  The board is complete, but badly formed (at least one of the row,
    #     column, or local grids does not have the correct 1..9 members)
    #
    #     2  The board is complete and correct
    #
    #     3  The board is incomplete ... there are still blanks.  Because of our
    #     existing strategies, this means that any blank space can support two
    #     or more possible values based on what we know ... in other words, to
    #     move forward we will have to make a guess.
    
    if (count_open($board) == 0) {
        
        # Scenario 1 or 2.  Return the board and a flag for success or failure
        
        $well_formed = check_board($board);
        
        return($well_formed, $difficulty, $board);
        
    }
    else {
        
        # Scenario 3.  In this situation we're going to have to guess if
        # we are to move forward:
        #
        #     -  Identify a cell with the lowest number of alternative values M
        #
        #     -  Increment the global $difficulty with the value of M.  This will
        #        ultimately help us distinguish wholly deterministic puzzles
        #        (difficulty = 0) from more challenging scenarios.
        #
        #     -  Loop through the possible values, updating the board and recursing
        #        into solve_board to see if a guess moves us along:
        
        print_board($board, $board);
        $nposers++;       
        return(0, $difficulty, $board); 
        
        $nmin = 10;
        
        for ($i = 0;$i < 81;$i++) {
            
            if (substr($board,$i,1) ne '0') {
                
                next;
                
            }
            
            $r = int($i / 9) + 1;
            $c = ($i % 9) + 1;
            
            $n = @a = possible_values($board, $i);
            
            if ($n < $nmin) {
                
                $ibest = $i;
                @b     = @a;
                $nmin  = $n
                
            }
            
            # print STDERR sprintf("%02d [%2d,%2d]: %d", $i, $r, $c, $a[0]);
            # for ($j = 1;$j < $n;$j++) { print STDERR ", " . $a[$j]; } print STDERR "\n";
            
        }
        
        foreach $c (@b) {
            
            substr($board,$ibest,1) = $c;
            
            ($state, $diff, $newboard) = solve_board($board,$difficulty + 1);
            
            if ($state) {
                
                $difficulty = $diff;
                
                return ($state, $difficulty, $newboard);
                
            }
            
        }
        
        # If we are here, we never found a solution
        return(0, $difficulty, $board);
        
    }
    
}

# +-----------------------------------------------------------------------+
# | sub print_board                                                       |
# +-----------------------------------------------------------------------+
sub print_board {
    my ($sboard, $board) = @_;
    my ($r, $c, $i, $sval, $val);
    
    for ($r = 0;$r < 9; $r++) {
        
        if (($r % 3) == 0) {
            
            print "-------------------------------\n";
        }
        
        for ($c = 0;$c < 9;$c++) {
            
            if (($c % 3) == 0) {
                
                print "|";
                
            }
            
            $sval = substr($sboard,($r * 9) + $c,1);
            $val  = substr($board, ($r * 9) + $c,1);
            
            if ($sval ne $val) {
                
                # print color 'bold blue';
                print color 'bold white';
                
            }
            
            print ($val eq "0" ? "   " : " $val ");
            
            if ($sval ne $val) {
                
                print color 'reset';
                
            }
            
        }
        
        print "|\n";
        
    }
    
    print "-------------------------------\n\n\n";
}

# +-----------------------------------------------------------------------+
# | sub possible_values                                                   |
# +-----------------------------------------------------------------------+
sub possible_values {
    my ($board,$offset) = @_;
    my ($r, $c, $rstr, $cstr, $i, $j, $localgrid, $rr, $cc, $vstr, $unique);
    my  @a;
    my  @b = ();
    
    $r = int($offset / 9);
    $c = $offset % 9;
    
    $rr = 3 * int($r / 3);
    $cc = 3 * int($c / 3);
    
    $rstr = substr($board, $r * 9,9);
    
    $cstr = "";
    for ($j = 0;$j < 9;$j++) {
        
        $cstr .= substr($board,($j * 9) + $c,1);
        
    }
    
    $localgrid = "";
    for ($j = 0;$j < 3;$j++) {
        
        $localgrid .= substr($board,(($rr + $j) * 9) + $cc,3);
        
    }
    
    $vstr = $rstr . $cstr . $localgrid;
    
    @a = uniq split(//,$vstr);

    $unique = join("",@a);
    
    for ($i = 1; $i <= 9;$i++) {
        
        if (index($unique,$i) < 0) {
            
            push(@b,$i);
            
        }
        
    }
    
    return(sort @b);
    
}

# +-----------------------------------------------------------------------+
# | display_log                                                           |
# +-----------------------------------------------------------------------+
sub display_log {
    my  @log = @_;
    my ($ctr, $x, $r, $c);
    my ($num, $offset, $ntest);
    
    $ctr = 0;
    
    foreach $x (@log) {
        
        $ctr++;
        
        ($num, $offset, $ntest) = @$x;
        
        print STDERR "$ctr\t";
        
        $r = int($offset / 9) + 1;
        $c = ($offset % 9) + 1;
        
        print STDERR "Place [$num] in row [$r] col [$c] according to test [$ntest]\n";
        
    }
    
    return($ctr);
    
}

# +-----------------------------------------------------------------------+
# | sub filled_cells: count the non-blank cells in a board                |
# +-----------------------------------------------------------------------+
sub filled_cells {
    my ($s) = @_;
    my ($c, $ctr, $n, $i);
    
    $n = length($s);
    
    $ctr = 0;
    
    for ($i = 0; $i < $n;$i++) {
        
        $c = substr($s,$i,1);
        
        if ($c ne "0") {
            
            $ctr++;
            
        }
        
    }
    
    
    return($ctr);
    
}

# +-----------------------------------------------------------------------+
# | sub get_originallist: put the original set of boards into a list      |
# +-----------------------------------------------------------------------+
sub get_originallist {
    my ($dbh, $sth, $sql);
    my  $table = "sudokuboards";
    my ($board, $n);
    my  @a = ();
    
    # Connect to the database
    $dbh = DBI -> connect("dbi:mysql:$db:$host",$usr,$pwd) or
        die("Unable to connect to database: $DBI::errstr\n\n");
    
    $sql  = "SELECT Board FROM $table";
    
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
    
    print STDERR "\n$n sudoku boards loaded from the original database.\n\n";
    
    return(@a);
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
        
    $sql  = "SELECT Board FROM $table";
    
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
    
    return(@a);
    
}

# +-----------------------------------------------------------------------+
# | sub rotate_board: rotates a board one quarter turn                    |
# +-----------------------------------------------------------------------+
sub rotate_board {
    my ($board) = @_;
    my  @rows = ();
    my ($i, $j, $s, $t);
    my  @newrows = ();
    
    for ($i = 0;$i < 9;$i++) {
        
        $rows[$i] = substr($board,$i * 9,9);
        
    }
    
    for ($i = 0;$i < 9;$i++) {
        
        $t = "";
        for ($j = 8;$j >= 0;$j--) {
            
            $t .= substr($rows[$j],$i,1);
            
        }
        
        push(@newrows,$t);
        
    }
    
    $t = "";
    for ($i = 0;$i < 9;$i++) {
        
        $t .= $newrows[$i];
        
    }
    
    return($t);
    
}

# +-----------------------------------------------------------------------+
# | sub board_id: identifies the location of the board in the DB          |
# +-----------------------------------------------------------------------+
sub board_id {
    my ($board) = @_;
    my ($dbh, $sth, $sql);
    my ($id);
    
    $dbh = DBI -> connect($sqlitestr, "", "", {RaiseError => 1, AutoCommit => 1});
    
    $sql = "SELECT ID FROM sudokuboards WHERE board = '$board'";
    
    $sth =  $dbh -> prepare($sql);
    $sth ->  execute();
    
    $sth -> bind_columns(\$id);
    
    if (!$sth -> fetch()) {
        
        $id = 0;
        
    }
    
    $sth -> finish();
    
    $dbh -> disconnect();
    
    return($id);
    
}

# +-----------------------------------------------------------------------+
# | sub get_board: retrieves a specific board based on ID                 |
# +-----------------------------------------------------------------------+
sub get_board {
    my ($id) = @_;
    my ($dbh, $sth, $sql);
    my ($board);
    
    $dbh = DBI -> connect($sqlitestr, "", "", {RaiseError => 1, AutoCommit => 1});
    
    $sql = "SELECT board FROM sudokuboards WHERE ID = '$id'";
    
    $sth =  $dbh -> prepare($sql);
    $sth ->  execute();
    
    $sth -> bind_columns(\$board);
    
    if (!$sth -> fetch()) {
        
        $id = 0;
        
    }
    
    $sth -> finish();
    
    $dbh -> disconnect();
    
    return($board);
    
}

# +-----------------------------------------------------------------------+
# | sub add_board: adds a board to our database table                     |
# +-----------------------------------------------------------------------+
sub add_board {
    my ($board, $sboard, $difficulty, $parent_id, $rotation) = @_;
    my ($dbh, $sth, $sql);
    my ($nfilled, $id);
    
    # Add the board to the table.  If the parent_id provided is 0, then also
    # retrieve the ID assigned to the board so it can be identified as a
    # parent to subsequent rotations:
    
    $nfilled = filled_cells($board);
    
    $dbh = DBI -> connect($sqlitestr, "", "", {RaiseError => 1, AutoCommit => 1}) or
        die("Unable to connect to database: $DBI::errstr\n\n");
    
    $sql  = "INSERT INTO sudokuboards (board, solution, difficulty, parentid, rotation, nfilled) ";
    $sql .= "VALUES ('$board', '$sboard', $difficulty, $parent_id, $rotation, $nfilled)";
    
    # print STDERR "[$sql]\nb[$board]\ns[$sboard]\nd[$difficulty]\np[$parent_id]\nr[$rotation]\nf[$nfilled]\n";
    
    $sth =  $dbh -> prepare($sql) or
        die("Failed preparing SQL: $DBI::errstr [$sql]\nb[$board]\ns[$sboard]\nd[$difficulty]\np[$parent_id]\nr[$rotation]\nf[$nfilled]\n");
        
    $sth ->  execute() or
        die("Failed executing SQL: $DBI::errstr [$sql]\nb[$board]\ns[$sboard]\nd[$difficulty]\np[$parent_id]\nr[$rotation]\nf[$nfilled]\n");
    
    $sth -> finish();
    
    $dbh -> disconnect();
    
    if ($parent_id == 0) {
        
        $parent_id = board_id($board);
        
    }
    
    return($parent_id);
    
}

# +-----------------------------------------------------------------------+
# | sub evaluate_board: takes a proposed board and adds it to our table   |
# +-----------------------------------------------------------------------+
sub evaluate_board {
    my ($board) = @_;
    my ($rotation, $id);
    my  $parent_id = 0;
    my ($state, $difficulty, $sboard, $nfilled);
    my  $ctr = 0;
    
    # Any board suggested is actually 4 boards, since each can be rotated
    # through 0, 1, 2, or 3 quarter turns to create new starting arrangements
    # of cells.
    
    # For each rotaion, we check whether the board is already in the table.
    # If so, move to the next.  If not, and if the board can be solved,
    # add the board, its solution, degree of difficulty, etc, to the table.
    
    for ($rotation = 0;$rotation < 4; $rotation++) {
        
        if ($rotation) {
            
            # After the initial board ($rotation == 0), we will make three
            # quarter-turns of the board for new starting arrangements.
            
            $board = rotate_board($board);
            
        }
        
        $id = board_id($board);
        
        if ($id) {
            
            # This one is already in the table, so we can skip to the next one
            
            if ($rotation == 0) {
                
                $parent_id = $id;
                
            }
            
            next;
            
        }
        
        # Get the board's solution:
        
        ($state, $difficulty, $sboard) = solve_board($board,0);
        
        if (!$state) {
            
            # if unsolvable, skip to the next one
            print STDERR "Unsolvable? rotation [$rotation], board:\n$board\n";
            
            next;
            
        }
        
        if (!defined($sboard)) {
            
            # The odd case where a completed board is submitted, so the solver kicks out before trying to solve
            # (because there is nothing to do).  We don't want to keep this anyway, so just skip to the next.
            
            print STDERR "Skipping\n";
            
            next;
            
        }
        
        $parent_id = add_board($board, $sboard, $difficulty, $parent_id, $rotation);
        
        $ctr++;
        
    }
    
    return($ctr);
    
}

# +-----------------------------------------------------------------------+
# | sub convert_oldtable: moves the Puzzle site mysql table to sqlite     |
# +-----------------------------------------------------------------------+
sub convert_oldtable {
    my ($n, $ctr, $nboards, $board);
    my @a;
    
    
    $n = @a = get_originallist();
    
    print STDERR "Looking at a starting list of [$n] boards:\n\n";
    
    $ctr = 0;
    $nboards = 0;
    
    foreach $board (@a) {
        
        # In the original table, there is some junk, so some test cases to step past:
        
        if (length($board) != $strlen) {
            
            print STDERR "Skipping: bad length\n";
            next;
            
        }
        
        # there are sometimes spaces instead of zeros for blanks?
        
        if (index($board," ") >= 0) {
            
            print STDERR "Applying fixup for:\n[$board]\n";
            
            $board =~ s/ /0/g;
            
        }
        
        $n = filled_cells($board);
        
        if ($n == $strlen) {
            
            print STDERR "Skipping: completed board, nothing to solve!\n";
            next;
            
        }
        
        # OK, at least we now have something worth trying:
        
        # print STDERR "trying: $board\n";
        
        $n = evaluate_board($board);
        
        $ctr += $n;
        
        $nboards++;
        
        print STDERR "$nboards: [$ctr] records in the table\n";
        
    }
    
    print STDERR "[$ctr] boards have been filed.\n\n";
    
}

# +-----------------------------------------------------------------------+
# | sub check_log: evaluates the log file                                 |
# +-----------------------------------------------------------------------+
sub check_log {
    my @a = (0, 0, 0, 0, 0);
    my ($num, $offset, $ntest);
    my ($ctr, $i);
    my $x;
    
    foreach $x (@log) {
        
        ($num, $offset, $ntest) = @$x;
        
        $a[$ntest - 1] = 1;
        
    }
    
    $ctr = 0;
    foreach ($i = 0;$i < 5;$i++) {
        $ctr += $a[$i];
    }
    
    return($ctr);
    
}

# +-----------------------------------------------------------------------+
# | M A I N   Program                                                     |
# +-----------------------------------------------------------------------+

my ($s, $test, $n);
my ($state, $difficulty, $board, $id, $ntests, $ctr);
my @boards = (
  '000400000020800105070001600007500000310000079000003800002300040105008060000006000' # Very difficult[6][57]
, '200000080000060500043805000068500270000000000034007960000106750006090000020000003' # Boston Globe [Sunday][0][55]
, '000004000603200005950100000004010070002806900070040100000009061700008302000500000' # 2012-06-10 Boston Globe [Sunday][1][55]
, '003000600200306001010908050060080090908000106030010040070401080600705002009000700' # 2012-06-11 Boston Globe [Monday][0][51]
, '090107080050306020007000600023040710700000004045030860009000200010608040060209070' # 2012-06-12 Boston Globe [Tuesday][0][49]
, '090030004007000000050462000008000400270806035003000800000324090000000500300090010' # 2012-06-13 Boston Globe [Wednesday][0][55]
, '000000000187050000365120009000040083020000060810070000700019846000060391000000000' # 2012-06-14 Boston Globe [Thursday][0][53]
, '400050002000900060902030001007000039000040000230000800100020905070005000300070006' # 2012-06-15 Boston Globe [Friday][0][56]
, '000000010700006200804005000000009020320804091050100000000400603008300007060000000' # 2012-06-16 Boston Globe [Saturday][2][57]
, '000200140010090000864300000300000007020030060100000005000009873000040090038006000'  # 2012-06-17 Boston Globe [Sunday][2][57]
, '350080900200509000000000710080003052000108000510200080038000000000401006002030097'  # 2012-06-18 Boston Globe [Monday][0][53]
, '000401000150000036040608090702306509000000000305102807080503020670000053000907000'  # 2012-06-19 Boston Globe [Tuesday][0][49]
, '900620008070000005050080040000800000100030004000007000010040030200000080600051002'
);

# delete from sqlite_sequence where name='sudokuboards'; -- resets autoincrement counter to 1

# @boards = get_originallist();

@boards = get_library();

# $s = get_board(1586); # Requires a guess after step 22
# $s = get_board(197);
# @boards = ($s);

$ctr = 0;
foreach $s (@boards) {
    
    # Following block used when converting old library:
    # $id = board_id($s);
    # if ($id) {
    #     # Already did this one.  Skip to the next.
    #     print STDERR "[" . substr($s,0,18) . " ...] Already done.  Next!\n";
    #     next;
    # }
    # $test = test_board($s);
    # if ($test == 0) {
    #     print STDERR "ERROR: Badly formed Sudoku board.\n\n";
    #     next;
    # }
    
    @log   = ();
    
    $n = filled_cells($s);
    
    if (($n == 81) || ($n < 5)) {
        
        print STDERR "ERROR: Bad number of starting cells [$n]\n\n";
        
        next;
        
    }
    
    # print STDERR "[$ctr] Solving board with [$n] cells filled in at the outset ...\n";
    
    ($state, $difficulty, $board) = solve_board($s,0);
    
    # display_log(@log);
    $ntests = check_log(@log);
    
    # if (($difficulty == 0) && ($ntests == 5)) { # One of each type of test was used
    #     $id = board_id($s);
    #     display_log(@log);
    #     print_board($s, $board);
    #     print STDERR "This is board [$id]\n";
    #     last;
    # }
    
    if ($nposers == 10) {
        
        exit;
        
    }
    
    # if ($state) {
    #     print STDERR "\nSolved! [$difficulty][$n]\n-----------\n\n";
    #     $n = evaluate_board($s);
    #     print STDERR "Added [$n] records to the sqlite table\n\n"
    # }
    # else {
    #     print "\nNo solution found!\n------------------\n\n";
    # }
    
    # print_board($s, $board);
    
    $ctr++;
    
}

