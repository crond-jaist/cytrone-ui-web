#!/usr/bin/perl
#
# human readable ID generation with 32 charactors.
#       because md5sum, sha1, UUID like ID is not suit to human,
#       I designe yet another ID generation method.
#       This is one-way conversion.  Do not expect reverse conversion.
#       To keep width, this program fills "Z" as padding.
#       Since 32 charactors are "0" to "Y", maximum is "YYYYY".
#       "Z" does not appear.
#
#	by k-chinen, CROND, JAIST.
#
package h32id;

use Exporter qw(import);

use strict;
use POSIX qw(strftime);

our @EXPORT = qw(h32iden);


            #          abcdefghijlkmnopqrstuvwxyz
            #012345678901234567890123456789012"
my $dh2base="0123456789ABCDEFGHJKMNPQRSTUVWXYZ"; # skip I L O

sub h32iden {
    my($t, $sin) = @_;
    my $ps;
    my %fm;
    my %fc;
    my $sout;
    my $verb=0;

    if($t<0) {
        $t = time;
    }

    %fm = ();
    %fc = ();

#printf "sin  %-20s %2d\n", "|".$sin."|", (length $sin);

    while($sin ne "") {
#print  "---\n";
#printf "sin  %-20s %2d\n", "|".$sin."|", (length $sin);
        if( $sin =~ /^([rzce]+[124]*)([ymdHMSs]+)/) {
            my $ex = $1;
            my $tg = $2;
            my $tk = $ex.$tg;

#printf "tk   %-20s %2d\n", "|".$tk."|", (length $tk);

            if($tk eq $sin) {
#               print "\t\tREMOVE\n";
                $sin = "";
            }
            else {
#               print "\t\tCUT\n";
                $sin = substr($sin, length $tk);
            }
#printf "sin* %-20s %2d\n", "|".$sin."|", (length $sin);
    
#           print "\ttk |$tk| ; ex |$ex| tg |$tg|\n";
            foreach my $x (split(//, $tg)) {
#               print "\t\tx  |$x|\n";
                if(defined  $fm{$x} ) {
                    print "WARN already $fm{$x} overwrite\n";
                }
                $fm{$x} = $ex;
                $fc{$x}++;
            }
        }
        else {
            print "ERROR ignore pattern\n";
            last;
        }
    }

    my $ec=0;

    $ec = 1;
    if($fc{"y"}==1 && $fc{"m"}==1 && $fc{"d"}==1 &&
        $fc{"H"}==1 && $fc{"M"}==1 && $fc{"S"}==1) {
        $ec = 0;
    }
    if($ec>0) {
        print "ERROR over and/or under appearance format\n";
        $verb++;
    }

    if($verb) {
    printf "%3s %3s %3s %3s %3s %3s\n", "y", "m", "d", "H", "M", "S";
    printf "%3s %3s %3s %3s %3s %3s\n", $fm{"y"}, $fm{"m"}, $fm{"d"},   
            $fm{"H"}, $fm{"M"}, $fm{"S"};
    printf "%3d %3d %3d %3d %3d %3d\n", $fc{"y"}, $fc{"m"}, $fc{"d"},   
            $fc{"H"}, $fc{"M"}, $fc{"S"};
    }

    my @ltm = localtime($t);
    my @gtm = gmtime($t);
    my $lref = strftime("%Y-%m-%d %H:%M:%S", @ltm);
    my $gref = strftime("%Y-%m-%d %H:%M:%S", @gtm);
#   print "lref |$lref|\n";
#   print "gref |$gref|\n";

    my $q;
    my $domain;
    
    $q = -1;
    $domain = -1;
    if($fm{"m"} eq "e" && $fm{"d"} eq "e" &&
        $fm{"H"} eq "e" && $fm{"M"} eq "e" && $fm{"S"} eq "e" ) {
#print "emdHMS 5\n";
        $domain = 12*31*24*60*60;
                    $q = $ltm[4];
        $q *= 31;   $q += $ltm[3];
        $q *= 24;   $q += $ltm[2];
        $q *= 60;   $q += $ltm[1];
        $q *= 60;   $q += $ltm[0];
    }
    elsif($fm{"d"} eq "e" &&
        $fm{"H"} eq "e" && $fm{"M"} eq "e" && $fm{"S"} eq "e" ) {
#print "edHMS 4\n";
        $domain = 31*24*60*60;
                    $q = $ltm[3];
        $q *= 24;   $q += $ltm[2];
        $q *= 60;   $q += $ltm[1];
        $q *= 60;   $q += $ltm[0];
    }
    elsif($fm{"H"} eq "e" && $fm{"M"} eq "e" && $fm{"S"} eq "e") {
#print "eHMS 3\n";
        $domain = 24*60*60;
                    $q = $ltm[2];
        $q *= 60;   $q += $ltm[1];
        $q *= 60;   $q += $ltm[0];
    }

#print "q $q\n";

    $sout = "";

    if($q>=0) {
        my $d;
        my $m;
        my $w;

        $w = 0;
        while(1) {
            $d = int($domain / 32);
            $m = $domain % 32;
#            print "domain $domain ; d $d m $m ".substr($dh2base, $m, 1)."\n";
            $w++;
            if($d<=0) {
                last;
            }
            $domain = $d;
        }
#print "domain $domain w $w\n";

        while(1) {
            $d = int($q / 32);
            $m = $q % 32;
#           print "q $q ; d $d m $m ".substr($dh2base, $m, 1)."\n";
            $sout = substr($dh2base, $m, 1) . $sout;
            if($d<=0) {
                last;
            }
            $q = $d;
        }

        if(length($sout)>$w) {
            print "ERROR overflow $sout vs w $w\n";
            exit 9;
        }
        else {
#           print "MID $sout vs w $w\n";
        }

#print "sout b $sout\n";
       $sout = substr("ZZZZZZZZ".$sout, -$w);
#        $sout = substr("________".$sout, -$w);
#print "sout a $sout\n";

    }

    if($fm{"d"} eq "r") {
        my $tp = sprintf("%02d", $ltm[3]);
        $sout = $tp . $sout;
    }
    elsif($fm{"d"} eq "c") {
        my $tp = substr($dh2base, $ltm[3], 1);
        $sout = $tp . $sout;
    }
    else {
    }

    if($fm{"m"} eq "r") {
        my $tp = sprintf("%02d", $ltm[4]+1);
        $sout = $tp . $sout;
    }
    elsif($fm{"m"} eq "c") {
        my $tp = substr($dh2base, $ltm[4], 1);
        $sout = $tp . $sout;
    }
    else {
    }

    if($fm{"y"} eq "r4") {
        my $tp = sprintf("%04d", $ltm[5]+1900);
        $sout = $tp . $sout;
    }
    elsif($fm{"y"} eq "r2") {
        my $tp = sprintf("%02d", ($ltm[5]+1900)%100);
        $sout = $tp . $sout;
    }
    elsif($fm{"y"} eq "z" || $fm{"y"} eq "z1") {
        my $tp = sprintf("%d", $ltm[5]);
        $sout = $tp . $sout;
    }
    elsif($fm{"y"} eq "z2") {
        my $tp = sprintf("%d", $ltm[5]+1900-1970);
        $sout = $tp . $sout;
    }

#   print "sout |$sout|\n";

    return $sout;
}

1;
