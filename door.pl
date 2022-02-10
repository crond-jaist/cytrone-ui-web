#!/usr/bin/perl
#
# Door - a UI server for CyTrONE
#       by k-chinen, CROND, JAIST, 2017-2018
#
# This program was tested with ...
#   - C&S Safari 11.0 and perl 5.18.2 over MacOS 10.11.6 
#   - C&S FireFox 52.6.0 and perl 5.10.1 over CentOS 6.9
#   - C   FireFox 52.7.2 over CentOS 6.9
#   - S   perl 5.22 over Ubuntu 16.04.4
#
#
# Requirements: (except CyRIS installation)
#   install perl
#   install Net::WebSocket::Server
#           # cpan install Net::WebSocket::Server
#   install Sys::Virt
#           # cpan install Sys::Virt
#   
#   install YAML::Tiny, Data:dumper, Data:Dump
#       Ubuntu:
#           % sudo apt-get install libyaml-tiny-perl 
#           % sudo apt-get install libdata-dump-perl
#       CentOS:
#           % sudo yum install perl-YAML-tiny
#           % sudo yum install perl-DATA-dump
# 
use Config;
$Config{useithreads} or \
    die('Recompile Perl with threads to run this program.');

use strict;
my  $versionstr = "version 0.3 <2018-Apr>";

use Getopt::Std;
use Sys::Syslog qw(:standard :macros);
use Net::WebSocket::Server;
use URI::Escape;
use threads;
use threads::shared;
use Thread::Queue;
use YAML::Tiny;
use Data::Dumper;
use Data::Dump;
use Digest::MD5 qw(md5_hex);

local $Data::Dumper::Indent = 1;
local $Data::Dumper::Terse  = 1;

BEGIN {
    unshift @INC, ".";
}

our $trngsrv_proto : shared;
our $trngsrv_host : shared;
our $trngsrv_port : shared;
our $trngsrv_lang : shared;
our $trngsrv_user : shared;
#our $trngsrv_pass : shared;

$trngsrv_proto = "http";
$trngsrv_host = "127.0.0.1";
$trngsrv_port = "8082";
$trngsrv_lang = "en";
$trngsrv_user = "alice";
#$trngsrv_pass = "rabbit";

use cy1;

use httpd;
import httpd;

use h32id;
import h32id;

my $sysid = `hostname`.'_'.&h32iden(time, "r2yrmrdeHMS");
$sysid =~ s#\n##g;

my $wsd_port : shared;
my $wsd_addr : shared;
my $wsd_url  : shared;
$wsd_port    = 12345;
$wsd_addr    = "127.0.0.1";
$wsd_url     = "ws://". $wsd_addr .":". $wsd_port ."/";


my $cnt_flush : shared;

my $debug_httpd : shared;
$debug_httpd = 0;

my $debug_mask = '';
my $debug_main = 0;

my $quiet : shared;
$quiet = 0;

my $msgtrace : shared;
$msgtrace = 0;

my $waitclient=0;

my $httpd_droot="htmldoc";

select STDOUT;
$| = 1;

sub printversion {
print <<EOM;
door.pl $versionstr
EOM
}

sub usage {
print <<EOM;
door.pl - A UI server for CyTrONE by k-chinen, CROND, JAIST. 2017-2018.
usage: $0 [-f <file>] [options]
option:                                         ; default value
    -h          print this message              ;
    -v          print version                   ;
    -V          print parameters                ;
    -f file     read cofiguration file          ; 
    -p port     HTTP service port number        ; $httpd_port
    -a addr     HTTP service address            ; $httpd_addr
                        URL $httpd_url
    -c dirs     HTTP document root directories  ; $httpd_droot
    -P port     WS service port number          ; $wsd_port
    -A addr     WS service address              ; $wsd_addr
                        URL $wsd_url
    -d          debug mode                      ; $debug_httpd
    -D string   debug-masking of module,protocol; $debug_mask
    -q          quiet mode                      ; $quiet
    -m          trace messages intro syslog     ; $msgtrace
    -z          sleep until client access       ;

example:
    % $0 -p 4989 -P 3213 -c docroot
    % $0 -f door.conf 

EOM
}

sub verify {
    printf "parameters ---\n";
    printf "system:\n";
    printf "    sysid         |$sysid|\n";
    printf "debugging and logging:\n";
    printf "    debug_main    $debug_main\n";
    printf "    debug_httpd   $debug_httpd\n";
#    printf "  debug_httpd_auth     $debug_httpd_auth\n";
    printf "    quiet  $quiet\n";
    printf "    debug_mask    |$debug_mask|\n";
    printf "front services:\n";
    printf "    proto  %-15s %-5s %s\n", "addr", "port", "URL";
    printf "    ---------------------------------------------------------\n";
    printf "    HTTP   %-15s %-5s %s\n", $httpd_addr, $httpd_port, $httpd_url;
    printf "    WS     %-15s %-5s %s\n", $wsd_addr, $wsd_port, $wsd_url;
    printf "    httpd_droot   |$httpd_droot|\n";
    printf "back service:\n";
    printf "    trngsrv_proto $trngsrv_proto\n";
    printf "    trngsrv_host  $trngsrv_host\n";
    printf "    trngsrv_port  $trngsrv_port\n";
    printf "    trngsrv_lang  $trngsrv_lang\n";
    printf "    trngsrv_user  $trngsrv_user\n";

    printf "others:\n";

    my $place="unknown";

    if(($httpd_addr eq '127.0.0.1') && ($wsd_addr eq '127.0.0.1')
        && ($trngsrv_host eq '127.0.0.1')) {
        $place = "local";
    }
    else {
        $place = "remote";
    }
    printf "    running place                |$place|\n";

    my $nu = &uptbl_numusers;
    printf "    the number of registed user: %d\n", $nu;

 }

sub readconfigfile {
    my ($fn) = @_;
    my @f;
    if($debug_httpd) {
        print STDERR "read config-file $fn\n";
    }
    if(-f $fn) {
        open(F, "<$fn") || die "exist but cannot read file $fn";
        while(<F>) {
            chomp;
            if(/^\s*#/) {
                next;
            }
            if(/^\s*$/) {
                next;
            }
            @f = split(/[ \t]+/, $_);
            if($f[0] eq 'debug_httpd') {
                $debug_httpd++;
            }
            elsif($f[0] eq 'debug_mask') {
                $debug_mask = $f[1];
            }
            elsif($f[0] eq 'quiet') {
                $quiet++;
            }
            elsif($f[0] eq 'msgtrace') {
                $msgtrace++;
            }
            #####
            elsif($f[0] eq 'httpd_addr') {
                $httpd_addr = $f[1];
            }
            elsif($f[0] eq 'httpd_port') {
                $httpd_port = $f[1];
            }
            elsif($f[0] eq 'httpd_droot') {
                $httpd_droot = $f[1];
            }
            elsif($f[0] eq 'sweep_contfiles') {
                &sweep_contfiles($f[1]);
            }
            elsif($f[0] eq 'sweep_HTMLcontfiles') {
                &sweep_HTMLcontfiles($f[1]);
            }
            elsif($f[0] eq 'set_maincontfile') {
                &set_maincontfile($f[1]);
            }
            elsif($f[0] eq 'add_contfile') {
                &add_contfile($f[1]);
            }
            elsif($f[0] eq 'httpd_userpasswd') {
                &uptbl_setpair($f[1], $f[2]);
            }
            elsif($f[0] eq 'httpd_userfile') {
                &uptbl_loadfile($f[1]);
            }
            #####
            elsif($f[0] eq 'wsd_addr') {
                $wsd_addr = $f[1];
            }
            elsif($f[0] eq 'wsd_port') {
                $wsd_port = $f[1];
            }
            #####
            elsif($f[0] eq 'trngsrv_proto') {
                $trngsrv_proto = $f[1];
            }
            elsif($f[0] eq 'trngsrv_host') {
                $trngsrv_host = $f[1];
            }
            elsif($f[0] eq 'trngsrv_port') {
                $trngsrv_port = $f[1];
            }
            elsif($f[0] eq 'trngsrv_lang') {
                $trngsrv_lang = $f[1];
            }
            elsif($f[0] eq 'trngsrv_user') {
                $trngsrv_user = $f[1];
            }
            #####
            else {
                print "ERROR: miss understanding |$_|\n";
            }
        }
        close(F);
    }
}

sub resolve {
    $httpd_url = "http://" . $httpd_addr .":". $httpd_port ."/";
    $wsd_url = "ws://". $wsd_addr .":". $wsd_port ."/junk";
    &set_wsd_url($wsd_url);
}


my %opt;
getopts('vhVD:dqmf:p:a:c:P:A:r:z', \%opt);

&httpd_nodebug;
&httpd_noauthdebug;
&cy1_nodebug;
&cy1_openlog;


if(defined $opt{'f'}) {
    &readconfigfile($opt{'f'});
}

if(defined $opt{'d'}) {
    $debug_httpd++;
}

if(defined $opt{'D'}) {
    $debug_mask .= $opt{'D'};
}
if($debug_mask eq 'all') {
    $debug_mask = "main,http,httpauth,cy1,door";
}


if(defined $opt{'q'}) {
    $quiet++;
}
if(defined $opt{'m'}) {
    $msgtrace = 1;
}

if(defined $opt{'p'}) {
    $httpd_port = $opt{'p'};
}
if(defined $opt{'a'}) {
    $httpd_addr = $opt{'a'};
}

if(defined $opt{'c'}) {
    $httpd_droot = $opt{'c'};
}


if(defined $opt{'P'}) {
    $wsd_port = $opt{'P'};
}
if(defined $opt{'A'}) {
    $wsd_addr = $opt{'A'};
}


&resolve;


if(defined $opt{'z'}) {
    $waitclient++;
}

if(defined $opt{'h'}) {
    &usage();
    exit 0;
}

if(defined $opt{'v'}) {
    &printversion();
    exit 0;
}

if(defined $opt{'V'}) {
    &verify();
    exit 0;
}


my @f=split(/,/, $debug_mask);
foreach my $x (@f) {
print STDERR "debug_httpd target '$x'\n";
    if($x eq 'main')    { $debug_httpd++; }
    if($x eq 'door')    { $debug_main++; }
    if($x eq 'cy1')     { &cy1_debug; }
    if($x eq 'http')    { &httpd_debug; }
    if($x eq 'httpauth'){ &httpd_authdebug; }
}
if($debug_httpd) {
    &httpd_debug;
}
if($quiet>0) {
    &httpd_nodebug;
}

if($trngsrv_proto =~ /\bHTTPS\b/i) {
    cy1_useHTTPS;
}
elsif($trngsrv_proto =~ /\bHTTP\b/i) {
    cy1_useHTTP;
}
else
{
}

openlog("door", "nowait,pid", LOG_USER);
syslog(LOG_INFO, "ACTION");

my @mq : shared;
@mq = ();

my $actconn: shared;
$actconn = 0;

my $__junkrange;
for(' ','+','%','0'..'9', 'a'..'z', 'A'..'Z') { $__junkrange .= $_;} 
#print "__junkrange |$__junkrange|\n";

sub gen_junktext {
    my $x;
    my $t;
    $x = '';
    for(my $i = 0; $i < 24 ; $i++) {
        $t = int(rand(100));
        if($t>90) {
            $x .= ' ';
        }
        else {
            $x .= substr($__junkrange, int(rand(length($__junkrange))), 1);
        }
    }
#print "x     |$x|\n";
    return $x;
}


my $aid = 0;
sub dummytrans_aclist {
    my $x;
    my $y;
    my $label;
    my $th;

    $aid++;

    $th = 999;
    if($aid<9) {
        $th=500;
    }
    elsif($aid<99) {
        $th=900;
    }
    elsif($aid>199) {
        return;
    }

    $x = int(rand(1000));
    if($x>=$th) {
#       $label = uri_escape("item $aid it includes space");
        $label = uri_escape(&gen_junktext);
        push(@mq, "ACLIST ADD ac$aid $label");
    }
    elsif($x>=$th/2) {
        $y = int(rand($aid));
        push(@mq, "ACLIST DEL ac$y");
    }
}

my $tid = 0;
sub dummytrans_trlist {
    my $x;
    my $y;
    my $label;
    my $th;

    $tid++;

    $th = 1000;
    if($tid<9) {
        $th = 500;
    }
    elsif($tid<99) {
        $th = 900;
    }
    elsif($tid>199) {
        return;
    }

    $x = int(rand(1000));
    if($x>=$th) {
#       $label = uri_escape("space included item $tid");
        $label = uri_escape(&gen_junktext);
        push(@mq, "TRLIST ADD tr$tid $label");
    }
    elsif($x>=$th/2) {
        $y = int(rand($tid));
        push(@mq, "TRLIST DEL tr$y");
    }
}

sub dummytrans {
    &dummytrans_trlist;
    &dummytrans_aclist;
}

sub send_trlist {
    my ($conn) = @_;
    my $ct;

#print STDERR "httpd_candidate_username $httpd_candidate_username\n";
#print STDERR "httpd_username $httpd_username\n";

#    $ct = cy1_trlist($trngsrv_host, $trngsrv_port, $trngsrv_lang, $trngsrv_user);
    my ($u, $p) = httpd_current_uppair();
    if($debug_httpd) {
	print "DEBUG: send_trlist(): Request params: $trngsrv_host, $trngsrv_port, $trngsrv_lang, $u, $p\n";
    }
    $ct = cy1_trlist($trngsrv_host, $trngsrv_port, $trngsrv_lang, $u, $p);
    $conn->send_utf8("TRLIST CONT ".$ct->content);
    if($debug_httpd) {
	print "DEBUG: send_trlist(): Response content: " . $ct->content . "\n";
    }
}

sub send_aclist {
    my ($conn) = @_;
    my $ct;
#    $ct = cy1_aclist($trngsrv_host, $trngsrv_port, $trngsrv_lang, $trngsrv_user);
    my ($u, $p) = httpd_current_uppair();
    if($debug_httpd) {
	print "DEBUG: send_aclist(): Request params: $trngsrv_host, $trngsrv_port, $trngsrv_lang, $u, $p\n";
    }
    $ct = cy1_aclist($trngsrv_host, $trngsrv_port, $trngsrv_lang, $u, $p);
    $conn->send_utf8("ACLIST CONT ".$ct->content);
    if($debug_httpd) {
	print "DEBUG: send_aclist(): Response content: " . $ct->content . "\n";
    }
}

sub run_training {
    my ($conn, $qid, $msg, $nins) = @_;
    my $chunk = uri_unescape($msg);
    if($debug_main) {
        print "chunk <".$chunk.">\n";
    }
    my @tup = split(/\|/, $chunk);
    my $ct;

    if($debug_main) {
        print "run_training: qid '$qid'\n";
    }

    if($nins<=0) {
        $nins = 1;
    }

    my ($u, $p) = httpd_current_uppair();
    $ct = cy1_create($conn, "RUN START-ACK $qid", $qid,
            $trngsrv_host, $trngsrv_port, $trngsrv_lang, $u, $p,
            $tup[0], $tup[1], $tup[2], $nins);
}

sub stop_training {
    my ($conn, $qid, $xxxid) = @_;
    my $ct;

    if($debug_main) {
        print "stop_training: qid '$qid' xxxid '$xxxid'\n";
    }

    my ($u, $p) = httpd_current_uppair();
    $ct = cy1_end($conn, "RUN STOP-ACK $qid", $qid,
            $trngsrv_host, $trngsrv_port, $trngsrv_lang, $u, $p,
            $xxxid);

}

my $ws;

$ws = Net::WebSocket::Server->new(
    listen => $wsd_port,
    on_connect => sub {
        my ($serv, $conn) = @_;
        $conn->on(
            handshake => sub {
                my ($conn, $handshake, $q) = @_;
                if($debug_httpd) {
                    print "connect:(addr:" . 
                        $conn->socket->peerhost(). ":".
                        $conn->socket->peerport() . ", query:" . $q . ")\n";
                }
#                $_->send_utf8("HELO") for $conn->server->connections;
#                $_->send_utf8("SYSID $sysid") for $conn->server->connections;
                push(@mq, "HELO");
                push(@mq, "SYSID $sysid");
                $actconn++;
            },
            utf8 => sub {
                my ($conn, $msg) = @_;
                if($debug_main) {
                    print "utf8 |$msg|\n";
                }

                if( $msg eq 'PING') {
                    push(@mq, "PONG");
                }
                if( $msg eq 'NOP') {
                }

                if( $msg eq 'TRLIST') {
                    &send_trlist($conn);
                }

                if( $msg eq 'ACLIST') {
                    &send_aclist($conn);
                }

                if( $msg =~ /^RUN\s+/) {
                    my @fs = split(/\s+/, $msg);
                    my $qid;
                    my $subcmd;
                    my $xid;
                    my $xic;
                    $subcmd = $fs[1];
                    $qid = $fs[2];
                    $xid = $fs[3];
                    $xic = $fs[4];
                    if($debug_main) {
                        print "subcmd |$subcmd|\n";
                        print "qid    |$qid|\n";
                        print "xid    |$xid|\n";
                        print "xic    |$xic|\n";
                    }
                    if($subcmd eq 'START') {
                        &run_training($conn, $qid, $xid, $xic);
                    }
                    elsif($subcmd eq 'STOP') {
                        &stop_training($conn, $qid, $xid);
                    }
                }

                if( $msg eq 'RESET') {
                    $cnt_flush++;
                }
#               $_->send_utf8($msg) for $conn->server->connections;
            },
            disconnect => sub {
                my ($conn, $code, $reason) = @_;
                if($debug_httpd) {
                    print "disconnect:(" . $conn->socket->peerhost(). ":".
                        $conn->socket->peerport(). ", code:" . $code . ")\n";
                }
            },
        );
    },
    tick_period => 1,
    on_tick => sub {
        my($serv) = @_;
        my $cq = $_;
#       print "len $#mq\n";
#        &dummytrans();
        #####
        ##### send message when somethings are found in queue
        #####
        while($#mq>=0) {
            my $x;
            $x = shift(@mq);
            $_->send_utf8($x) for $serv->connections;
            if($msgtrace) {
                syslog(LOG_INFO, "WSD MSG |$x|");
            }
        }
    }
);

syslog(LOG_INFO, "WSD UP");


sub wsth {
    $ws->start;
}




my $Qsep='#';
my $Msep=' ';
my $Asep=';';


my @curr_es;
my @curr_rs;





my $fsprobetick = 5;
my $healthprobeinterval = 10;
my $last_health = -1;
my $health_elap = -1;
my $ref_time;

my @curr_fs;
my @last_fs;
my $ref_add;
my $ref_del;
my $zzc;
my $tmark_thre=6;


sub sighand {
    $cnt_flush++;
}

$SIG{'USR1'} = \&sighand;

if(!$quiet) {
    print "START\n";
    syslog(LOG_INFO, "MAIN");
}
if($debug_httpd) {
    print "wsd_port         $wsd_port\n";
}

my $dmyth1 = threads->create(\&httpd::httpd_mainbody);
my $dmyth2 = threads->create(\&wsth);

sleep 1;

push(@mq, "TIME".$Msep.(time));

sleep 1;

if($waitclient>0) {
    while(1) {
        if($actconn>0) {
            last;
        }
        # explicit message --- I am sleeping.
        print "zzz\n";
        sleep(1);
    }
}

select STDOUT; $| = 1;

&digest_setpolicy('all');
#&uptbl_setpair('abc', 'ajapa');
#&uptbl_setpair('xyz', 'xeon');

$zzc = 0;
while(1) {
#    print "@@@".time."\n";

    $ref_time = time;
    $health_elap = $ref_time - $last_health;
    if($health_elap >= $healthprobeinterval) {
#       &health_main;
        $last_health = $ref_time;
    }

#   printf "EQ  %2d: ", $#cy1_eq;
#   if($#cy1_eq>=0) {
#   }
    while($cy1_eq->pending>0) {
        print "cy1_eq pending\n";
        my $x = $cy1_eq->dequeue;
    }

    if(0) {
        print "- - -\n";
        foreach my $thr (threads->list()) {
            print "threads ".$thr." running\n";
        }
    }

    if($cnt_flush) {
#       &flush_rs();
        $cnt_flush = 0;
        goto NEXT2;
    }

NEXT2:
    if($debug_httpd) {
#        printf "MQ  %2d: ", $#mq;
#        print join(" ", @mq);
#        print "\n";
    }

NEXT:
    @last_fs = @curr_fs;
    sleep $fsprobetick;
    $zzc++;
}
